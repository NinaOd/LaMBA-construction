#!/bin/bash

################################################################################
# Sheep Anatomical Priors Creation Script
# Author: NinaOd & Claude Code AI
# Date: 2026-03-12
# Description: Creates probabilistic anatomical priors from individual subject
#              labels transformed to template space. Compares FSL mean,
#              c3d mean, and c3d STAPLE methods.
################################################################################

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

################################################################################
# EXPECTED DIRECTORY STRUCTURE
################################################################################
#
# Main_dir/
# ├── labels_combined/                    (input: combined labelmaps in native space)
# │   ├── Sub_A/
# │   │   └── Sub_A_T2w-SR_annotation_combined.nii.gz
# │   ├── Sub_B/
# │   │   └── Sub_B_T2w-SR_annotation_combined.nii.gz
# │   └── ...
# ├── warps/                              (from register_syn_batch.py or register_rigid_batch.py)
# │   ├── tpl_A_1Warp.nii.gz             (SyN mode only)
# │   ├── tpl_A_0GenericAffine.mat
# │   ├── tpl_B_1Warp.nii.gz
# │   ├── tpl_B_0GenericAffine.mat
# │   └── ...
# └── results/                            (will be created)
#     ├── transformed/                    (combined labelmaps in template space)
#     ├── split/                          (binary masks per label in template space)
#     ├── organized/                      (split masks grouped by region)
#     ├── priors_fsl/                     (FSL mean priors)
#     └── priors_c3d/                     (c3d mean and STAPLE priors)
#
# REQUIRED INPUTS:
# - Template: path to reference template (e.g., tpl_template0.nii.gz)
# - Warp files: output of register_syn_batch.py (SyN) or register_rigid_batch.py (rigid)
#   Naming convention: tpl_{NAME}_0GenericAffine.mat  and  tpl_{NAME}_1Warp.nii.gz
# - Combined labelmaps: one per subject, all labels merged into one NIfTI (integer 1-7)
#
# NOTE: Subjects used for priors do NOT need to be the same as those used
#       for template creation. Additional subjects can be registered to the
#       template and their labels included in prior creation.
################################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# USAGE
################################################################################

usage() {
    cat << EOF
Usage: $0 -i <labels_combined_dir> -w <warps_dir> -t <template> -o <output_dir> [--rigid]

Create probabilistic anatomical priors from combined subject labelmaps.

The script transforms the combined labelmap to template space first (preserving label
boundaries), then splits into per-label binary masks, and finally computes priors.

Required arguments:
  -i, --input       Directory containing Sub_* subject folders, each holding a
                    combined labelmap (*_T2w-SR_annotation_combined.nii.gz)
  -w, --warps       Directory containing warp files from register_syn_batch.py or
                    register_rigid_batch.py (naming: tpl_{NAME}_0GenericAffine.mat)
  -t, --template    Path to template image (e.g., tpl_template0.nii.gz)
  -o, --output      Output directory (will be created if it doesn't exist)

Optional arguments:
  --rigid           Use rigid-only registration (affine .mat only, no warp field).
                    Use this when creating priors for nnUNet training.
                    Default (without flag): SyN registration (warp + affine).
                    Use SyN when creating the probabilistic atlas.
  -h, --help        Show this help message

Example (SyN priors for atlas):
  $0 -i /path/to/labels_combined -w /path/to/warps_syn -t /path/to/template.nii.gz -o /path/to/results_syn

Example (rigid priors for nnUNet):
  $0 -i /path/to/labels_combined -w /path/to/warps_rigid -t /path/to/template.nii.gz -o /path/to/results_rigid --rigid

Expected input structure:
  labels_combined/
    ├── Sub_A/
    │   └── Sub_A_T2w-SR_annotation_combined.nii.gz
    ├── Sub_B/
    │   └── Sub_B_T2w-SR_annotation_combined.nii.gz
    └── ...

EOF
    exit 1
}

################################################################################
# PARSE COMMAND LINE ARGUMENTS
################################################################################

TEMPLATE=""
LABEL_BASE_DIR=""
OUTPUT_DIR=""
WARP_DIR=""
RIGID_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--input)
            LABEL_BASE_DIR="$2"
            shift 2
            ;;
        -w|--warps)
            WARP_DIR="$2"
            shift 2
            ;;
        -t|--template)
            TEMPLATE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --rigid)
            RIGID_MODE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option: $1"
            usage
            ;;
    esac
done

# Check required arguments
if [[ -z "$TEMPLATE" ]] || [[ -z "$LABEL_BASE_DIR" ]] || [[ -z "$OUTPUT_DIR" ]] || [[ -z "$WARP_DIR" ]]; then
    echo "Error: Missing required arguments"
    echo ""
    usage
fi

# Label definitions
LABELS=(1 2 3 4 5 6 7)
REGION_NAMES=("ic" "gm" "wm" "ven" "cb" "dp" "bs")
REGION_FULL_NAMES=(
    "Intracranial Space"
    "Grey Matter"
    "White Matter"
    "Ventricles"
    "Cerebellum"
    "Deep Grey Matter"
    "Brainstem"
)

################################################################################
# HELPER FUNCTIONS
################################################################################

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
}

check_file() {
    if [[ ! -f "$1" ]]; then
        print_error "Required file not found: $1"
        exit 1
    fi
}

check_dir() {
    if [[ ! -d "$1" ]]; then
        print_error "Required directory not found: $1"
        exit 1
    fi
}

################################################################################
# VALIDATION
################################################################################

if [[ "$RIGID_MODE" == true ]]; then
    echo -e "${YELLOW}Registration mode: RIGID-ONLY (for nnUNet priors)${NC}"
else
    echo -e "${YELLOW}Registration mode: SyN (for atlas/anatomical priors)${NC}"
fi

print_header "Validating Environment and Inputs"

# Check if FSL is available
if ! command -v fslmerge &> /dev/null; then
    print_error "FSL not found. Please install FSL or add it to PATH."
    exit 1
fi
print_success "FSL found"

# Check if c3d is available
if ! command -v c3d &> /dev/null; then
    print_error "c3d (Convert3D) not found. Please install or add to PATH."
    exit 1
fi
print_success "c3d found"

# Check if ANTs is available
if ! command -v antsApplyTransforms &> /dev/null; then
    print_error "ANTs not found. Please install ANTs or add to PATH."
    exit 1
fi
print_success "ANTs found"

# Check template exists
check_file "$TEMPLATE"
print_success "Template found: $TEMPLATE"

# Check directories exist
check_dir "$LABEL_BASE_DIR"
check_dir "$WARP_DIR"
print_success "Input directories validated"

# Find subjects
SUBJECT_DIRS=($(find "$LABEL_BASE_DIR" -maxdepth 1 -name "Sub_*" -type d | sort))

if [[ ${#SUBJECT_DIRS[@]} -eq 0 ]]; then
    print_error "No subject directories found in $LABEL_BASE_DIR"
    print_error "Expected pattern: Sub_* (e.g., Sub_A, Sub_B, etc.)"
    exit 1
fi

echo "Found ${#SUBJECT_DIRS[@]} subjects:"
for dir in "${SUBJECT_DIRS[@]}"; do
    echo "  - $(basename "$dir")"
done

################################################################################
# SETUP OUTPUT DIRECTORIES
################################################################################

print_header "Creating Output Directories"

# Create output directory if it doesn't exist
if [[ ! -d "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
    print_success "Created output directory: $OUTPUT_DIR"
fi

TRANSFORMED_DIR="$OUTPUT_DIR/transformed"
SPLIT_DIR="$OUTPUT_DIR/split"
ORGANIZED_DIR="$OUTPUT_DIR/organized"
PRIORS_FSL_DIR="$OUTPUT_DIR/priors_fsl"
PRIORS_C3D_DIR="$OUTPUT_DIR/priors_c3d"

mkdir -p "$TRANSFORMED_DIR"
mkdir -p "$SPLIT_DIR"
mkdir -p "$ORGANIZED_DIR"
mkdir -p "$PRIORS_FSL_DIR"
mkdir -p "$PRIORS_C3D_DIR"

for region in "${REGION_NAMES[@]}"; do
    mkdir -p "$ORGANIZED_DIR/$region"
done

print_success "Output directories created"

# Record start time
START_TIME=$(date +%s)

################################################################################
# STEP 1: Transform Combined Labelmaps to Template Space
################################################################################

print_header "STEP 1: Transforming Combined Labelmaps to Template Space"

echo "Transforming the full combined labelmap per subject (NearestNeighbor)."
echo "This preserves label boundaries with no gaps or overlaps."
echo ""

successful_subjects=0
failed_subjects=0

for subject_dir in "${SUBJECT_DIRS[@]}"; do
    subject=$(basename "$subject_dir")
    # Derive tpl_ name: strip "Sub_" prefix, add "tpl_" prefix
    # e.g. Sub_A → tpl_A, Sub_B → tpl_B
    tpl_name="tpl_${subject#Sub_}"
    echo ""
    echo "Processing: $subject (output: $tpl_name)"

    # Find combined labelmap
    combined_file="$subject_dir/${subject}_T2w-SR_annotation_combined.nii.gz"
    if [[ ! -f "$combined_file" ]]; then
        print_error "Combined labelmap not found: $combined_file"
        ((failed_subjects++)) || true
        continue
    fi
    echo "  Input: $(basename "$combined_file")"

    # Find affine file (required for both modes)
    affine_files=("$WARP_DIR"/${tpl_name}*0GenericAffine.mat)
    if [[ ! -f "${affine_files[0]}" ]]; then
        print_error "No affine file found for $tpl_name"
        ((failed_subjects++)) || true
        continue
    fi
    affine_file="${affine_files[0]}"
    echo "  Using: $(basename "$affine_file")"

    # Find warp file (SyN mode only)
    warp_file=""
    if [[ "$RIGID_MODE" == false ]]; then
        warp_files=("$WARP_DIR"/${tpl_name}*1Warp.nii.gz)
        if [[ ! -f "${warp_files[0]}" ]]; then
            print_error "No warp file found for $tpl_name (required for SyN mode)"
            ((failed_subjects++)) || true
            continue
        fi
        warp_file="${warp_files[0]}"
        echo "  Using: $(basename "$warp_file")"
    fi

    # Build transform arguments: warp first (if SyN), then affine
    transform_args=()
    if [[ "$RIGID_MODE" == false ]]; then
        transform_args+=(-t "$warp_file")
    fi
    transform_args+=(-t "$affine_file")

    output_combined="$TRANSFORMED_DIR/${tpl_name}_combined_toTemplate.nii.gz"

    if antsApplyTransforms \
        -d 3 \
        -i "$combined_file" \
        -r "$TEMPLATE" \
        "${transform_args[@]}" \
        -o "$output_combined" \
        -n NearestNeighbor \
        --verbose 0 2>/dev/null; then
        print_success "$subject: combined labelmap transformed"
        ((successful_subjects++)) || true
    else
        print_error "$subject: transformation failed"
        ((failed_subjects++)) || true
    fi
done

echo ""
echo "Transformation summary:"
echo "  Successful: $successful_subjects"
echo "  Failed: $failed_subjects"

if [[ $successful_subjects -eq 0 ]]; then
    print_error "No subjects were successfully processed. Cannot continue."
    exit 1
fi

################################################################################
# STEP 2: Split Combined Labelmaps into Per-Label Binary Masks
################################################################################

print_header "STEP 2: Splitting Combined Labelmaps into Binary Masks"

echo "Splitting each template-space combined labelmap into one binary mask per label."
echo ""

split_success=0

for combined_file in "$TRANSFORMED_DIR"/*_combined_toTemplate.nii.gz; do
    if [[ ! -f "$combined_file" ]]; then
        print_error "No transformed combined labelmaps found in $TRANSFORMED_DIR"
        exit 1
    fi

    filename=$(basename "$combined_file")
    tpl_name="${filename%_combined_toTemplate.nii.gz}"
    echo "Splitting: $filename"

    labels_split=0
    for i in "${!LABELS[@]}"; do
        label="${LABELS[$i]}"
        region="${REGION_NAMES[$i]}"
        output_mask="$SPLIT_DIR/${tpl_name}_label${label}_toTemplate.nii.gz"

        if fslmaths "$combined_file" -thr "$label" -uthr "$label" -bin "$output_mask" 2>/dev/null; then
            ((labels_split++)) || true
        else
            print_error "  Failed to split label $label ($region) from $tpl_name"
        fi
    done

    if [[ $labels_split -eq ${#LABELS[@]} ]]; then
        print_success "$tpl_name: all ${#LABELS[@]} labels split"
        ((split_success++)) || true
    else
        print_warning "$tpl_name: only $labels_split/${#LABELS[@]} labels split"
    fi
done

echo ""
echo "Split summary: $split_success subjects fully split"

################################################################################
# STEP 3: Organize Labels by Region
################################################################################

print_header "STEP 3: Organizing Labels by Region"

for i in "${!LABELS[@]}"; do
    label="${LABELS[$i]}"
    region="${REGION_NAMES[$i]}"
    region_full="${REGION_FULL_NAMES[$i]}"

    cp "$SPLIT_DIR"/*_label${label}_toTemplate.nii.gz "$ORGANIZED_DIR/$region/" 2>/dev/null || true
    
    file_count=$(find "$ORGANIZED_DIR/$region" -name "*.nii.gz" | wc -l)
    
    if [[ $file_count -gt 0 ]]; then
        print_success "Label $label ($region_full): $file_count files"
    else
        print_warning "Label $label ($region_full): No files found"
    fi
done

################################################################################
# STEP 4: Create FSL Mean Priors
################################################################################

print_header "STEP 4: Creating FSL Mean Priors"

fsl_success=0

for i in "${!LABELS[@]}"; do
    region="${REGION_NAMES[$i]}"
    region_full="${REGION_FULL_NAMES[$i]}"
    region_dir="$ORGANIZED_DIR/$region"
    
    file_count=$(find "$region_dir" -name "*.nii.gz" | wc -l)
    
    if [[ $file_count -eq 0 ]]; then
        print_warning "$region_full: No files, skipping"
        continue
    fi
    
    echo "Processing $region_full ($file_count subjects)..."
    
    merged_file="$PRIORS_FSL_DIR/merged_${region}.nii.gz"
    prior_file="$PRIORS_FSL_DIR/fsl_${region}_prior.nii.gz"
    
    if fslmerge -t "$merged_file" "$region_dir"/*.nii.gz 2>/dev/null && \
       fslmaths "$merged_file" -Tmean "$prior_file" 2>/dev/null; then
        print_success "$region_full: FSL prior created"
        ((fsl_success++)) || true
        rm "$merged_file"  # Clean up intermediate file
    else
        print_error "$region_full: FSL prior failed"
    fi
done

echo ""
echo "FSL priors created: $fsl_success / ${#LABELS[@]}"

################################################################################
# STEP 5: Create c3d Mean and STAPLE Priors
################################################################################

print_header "STEP 5: Creating c3d Mean and STAPLE Priors"

c3d_mean_success=0
c3d_staple_success=0

for i in "${!LABELS[@]}"; do
    region="${REGION_NAMES[$i]}"
    region_full="${REGION_FULL_NAMES[$i]}"
    region_dir="$ORGANIZED_DIR/$region"
    
    files=("$region_dir"/*.nii.gz)
    
    if [[ ! -f "${files[0]}" ]]; then
        print_warning "$region_full: No files, skipping"
        continue
    fi
    
    file_count=${#files[@]}
    echo "Processing $region_full ($file_count subjects)..."
    
    # c3d -mean
    prior_mean_file="$PRIORS_C3D_DIR/c3d_mean_${region}_prior.nii.gz"
    if c3d "${files[@]}" -mean -o "$prior_mean_file" 2>/dev/null; then
        print_success "$region_full: c3d mean prior created"
        ((c3d_mean_success++)) || true
    else
        print_error "$region_full: c3d mean failed"
    fi
    
    # c3d -staple (specify intensity value 1 for binary masks)
    prior_staple_file="$PRIORS_C3D_DIR/c3d_staple_${region}_prior.nii.gz"
    if c3d "${files[@]}" -staple 1 -o "$prior_staple_file" 2>/dev/null; then
        print_success "$region_full: c3d STAPLE prior created"
        ((c3d_staple_success++)) || true
    else
        print_error "$region_full: c3d STAPLE failed"
    fi
done

echo ""
echo "c3d mean priors created: $c3d_mean_success / ${#LABELS[@]}"
echo "c3d STAPLE priors created: $c3d_staple_success / ${#LABELS[@]}"

################################################################################
# FINAL SUMMARY
################################################################################

print_header "Pipeline Summary"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

if [[ "$RIGID_MODE" == true ]]; then
    echo "Registration mode: RIGID-ONLY (nnUNet priors)"
else
    echo "Registration mode: SyN (atlas/anatomical priors)"
fi
echo "Template: $TEMPLATE"
echo "Subjects processed: $successful_subjects / ${#SUBJECT_DIRS[@]}"
echo "Time elapsed: ${MINUTES}m ${SECONDS}s"
echo ""

echo "Output structure:"
echo "  $OUTPUT_DIR/"
echo "  ├── transformed/       ($(find "$TRANSFORMED_DIR" -name "*.nii.gz" | wc -l) combined labelmaps in template space)"
echo "  ├── split/             ($(find "$SPLIT_DIR" -name "*.nii.gz" | wc -l) binary masks in template space)"
echo "  ├── organized/         (masks grouped by region)"
echo "  ├── priors_fsl/        ($fsl_success priors)"
echo "  └── priors_c3d/        (mean: $c3d_mean_success, STAPLE: $c3d_staple_success)"
echo ""

echo "Label mapping:"
for i in "${!LABELS[@]}"; do
    printf "  Label %d = %-6s (%s)\n" "${LABELS[$i]}" "${REGION_NAMES[$i]}" "${REGION_FULL_NAMES[$i]}"
done

echo ""
print_success "Prior creation completed!"
echo ""
echo "Next step: Create anatomical atlas using sheep_atlases_boost.sh"
