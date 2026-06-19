#!/bin/bash

################################################################################
# Sheep Atlas Creation Script with Ventricle Boosting
# Author: NinaOd & Claude Code AI
# Date: 2026-03-12
# Description: Creates anatomical atlases from existing probabilistic priors
#              (FSL, c3d mean, c3d STAPLE) using FSL find_the_biggest,
#              c3d -vote, and c3d -vote-mrf fusion methods.
#              Applies optional ventricle boosting to improve preservation 
#              of small structures.
################################################################################

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

################################################################################
# USAGE AND HELP
################################################################################

usage() {
    cat << EOF
Usage: $0 -i <input_dir> [options]

Create anatomical atlases from probabilistic priors with optional ventricle boosting.

Required arguments:
  -i, --input       Input directory containing priors (from sheep_priors_create.sh)
                    Expected subdirectories: priors_fsl/, priors_c3d/

Optional arguments:
  -b, --boost       Ventricle boost multiplier (default: 2, use 1 for no boost)
  -h, --help        Show this help message

Examples:
  # Default (2x ventricle boost)
  $0 -i /path/to/results

  # No boost
  $0 -i /path/to/results -b 1

  # Custom boost (3x)
  $0 -i /path/to/results -b 3

Expected input structure:
  <input_dir>/
  ├── priors_fsl/
  │   ├── fsl_ic_prior.nii.gz
  │   ├── fsl_gm_prior.nii.gz
  │   ├── fsl_wm_prior.nii.gz
  │   ├── fsl_ven_prior.nii.gz
  │   ├── fsl_cb_prior.nii.gz
  │   ├── fsl_dp_prior.nii.gz
  │   └── fsl_bs_prior.nii.gz
  └── priors_c3d/
      ├── c3d_mean_*_prior.nii.gz (7 files)
      └── c3d_staple_*_prior.nii.gz (7 files)

Output:
  <input_dir>/final_atlases/
    ├── *_ftb_atlas_no_boost.nii.gz (baseline, FSL find_the_biggest)
      ├── *_vote_atlas_no_boost.nii.gz (baseline, no boosting)
      ├── *_vote_mrf_atlas_no_boost.nii.gz (baseline with MRF smoothing)
    ├── *_ftb_atlas_vboost2.nii.gz (if boost > 1)
      ├── *_vote_atlas_vboost2.nii.gz (if boost > 1)
      └── *_vote_mrf_atlas_vboost2.nii.gz (if boost > 1)

EOF
    exit 1
}

################################################################################
# PARSE COMMAND LINE ARGUMENTS
################################################################################

INPUT_DIR=""
VENTRICLE_MULTIPLIER=2  # Default value

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--input)
            INPUT_DIR="$2"
            shift 2
            ;;
        -b|--boost)
            VENTRICLE_MULTIPLIER="$2"
            shift 2
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
if [[ -z "$INPUT_DIR" ]]; then
    echo "Error: Missing required argument: -i/--input"
    echo ""
    usage
fi

# Validate boost multiplier
if ! [[ "$VENTRICLE_MULTIPLIER" =~ ^[0-9]+$ ]] || [[ "$VENTRICLE_MULTIPLIER" -lt 1 ]]; then
    echo "Error: Boost multiplier must be a positive integer (got: $VENTRICLE_MULTIPLIER)"
    exit 1
fi

################################################################################
# SETUP
################################################################################

# Set derived paths
PRIORS_FSL_DIR="$INPUT_DIR/priors_fsl"
PRIORS_C3D_DIR="$INPUT_DIR/priors_c3d"
FINAL_ATLASES_DIR="$INPUT_DIR/final_atlases"

# Define labels and region names
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

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# HELPER FUNCTIONS
################################################################################

print_step() {
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

################################################################################
# VALIDATION
################################################################################

print_step "Validating Environment and Inputs"

# Check if c3d is available
if ! command -v c3d &> /dev/null; then
    print_error "c3d (Convert3D) not found. Please install or add to PATH."
    exit 1
fi
print_success "c3d found"

# Check if fslmaths is available (for boosting)
if ! command -v fslmaths &> /dev/null; then
    print_error "fslmaths not found. Please install FSL or add to PATH."
    exit 1
fi
print_success "fslmaths found"

# Check if find_the_biggest is available (FSL fusion method)
HAS_FSL_FTB=1
if ! command -v find_the_biggest &> /dev/null; then
    HAS_FSL_FTB=0
    print_warning "find_the_biggest not found. FSL fusion method (ftb) will be skipped."
else
    print_success "find_the_biggest found"
fi

# Check directories exist
if [[ ! -d "$PRIORS_FSL_DIR" ]]; then
    print_error "FSL priors directory not found: $PRIORS_FSL_DIR"
    exit 1
fi

if [[ ! -d "$PRIORS_C3D_DIR" ]]; then
    print_error "c3d priors directory not found: $PRIORS_C3D_DIR"
    exit 1
fi

print_success "Prior directories validated"

# Create output directory
mkdir -p "$FINAL_ATLASES_DIR"
print_success "Output directory ready: $FINAL_ATLASES_DIR"

################################################################################
# MAIN EXECUTION
################################################################################

START_TIME=$(date +%s)

echo ""
echo "Configuration:"
echo "  Input directory: $INPUT_DIR"
echo "  Ventricle boost multiplier: ${VENTRICLE_MULTIPLIER}x"
echo ""

################################################################################
# FUNCTION: Create atlases for a given prior set
################################################################################

create_atlases() {
    local prior_type=$1        # fsl, c3d_mean, or c3d_staple
    local prior_dir=$2         # directory containing priors
    local output_prefix=$3     # prefix for prior files (e.g., "fsl", "c3d_mean")
    local boost_mult=$4        # boost multiplier (1 = no boost)
    
    print_step "Creating Atlases: $prior_type priors (boost=${boost_mult}x)"
    
    # Define prior file paths in correct label order
    local priors_ordered=(
        "$prior_dir/${output_prefix}_ic_prior.nii.gz"   # Label 1
        "$prior_dir/${output_prefix}_gm_prior.nii.gz"   # Label 2
        "$prior_dir/${output_prefix}_wm_prior.nii.gz"   # Label 3
        "$prior_dir/${output_prefix}_ven_prior.nii.gz"  # Label 4
        "$prior_dir/${output_prefix}_cb_prior.nii.gz"   # Label 5
        "$prior_dir/${output_prefix}_dp_prior.nii.gz"   # Label 6
        "$prior_dir/${output_prefix}_bs_prior.nii.gz"   # Label 7
    )
    
    # Check if priors exist
    local prior_count=0
    for file in "${priors_ordered[@]}"; do
        if [[ -f "$file" ]]; then
            ((prior_count++)) || true
        fi
    done
    
    if [[ $prior_count -eq 0 ]]; then
        print_error "No valid priors found for $prior_type"
        return 1
    fi
    echo "Found $prior_count prior files"
    
    # Determine boost label for output filenames
    local boost_label=""
    if [[ $boost_mult -eq 1 ]]; then
        boost_label="no_boost"
    else
        boost_label="vboost${boost_mult}"
    fi
    
    # Apply ventricle boosting if boost_mult > 1
    local priors_to_use=("${priors_ordered[@]}")  # Default: use original priors
    
    if [[ $boost_mult -gt 1 ]]; then
        echo ""
        echo "Boosting ventricle prior (${boost_mult}x)..."
        
        local ven_prior="${priors_ordered[3]}"  # Index 3 = ventricles (label 4)
        local ven_boosted="${prior_dir}/${output_prefix}_ven_prior_temp_vboost${boost_mult}.nii.gz"
        
        if [[ -f "$ven_prior" ]]; then
            if fslmaths "$ven_prior" -mul $boost_mult "$ven_boosted" 2>/dev/null; then
                print_success "Ventricle prior boosted by ${boost_mult}x"
                # Update array to use boosted ventricle prior
                priors_to_use[3]="$ven_boosted"
            else
                print_error "Failed to boost ventricle prior"
                return 1
            fi
        else
            print_error "Ventricle prior not found: $ven_prior"
            return 1
        fi
    else
        echo "No ventricle boosting applied"
    fi
    
    # Create background (zero) image for correct c3d label numbering
    echo ""
    echo "Creating background image for c3d label numbering..."
    local background_zero="${prior_dir}/background_zero_${output_prefix}_${boost_label}.nii.gz"
    c3d "${priors_to_use[0]}" -scale 0 -o "$background_zero" 2>/dev/null
    
    # Method 1: FSL find_the_biggest
    echo ""
    echo "Method 1: FSL find_the_biggest (input priors: ${prior_type})..."
    local ftb_output="$FINAL_ATLASES_DIR/${prior_type}_ftb_atlas_${boost_label}.nii.gz"

    if [[ $HAS_FSL_FTB -eq 1 ]]; then
        find_the_biggest "${priors_to_use[@]}" "$ftb_output" >/dev/null 2>&1 || true

        if [[ -f "$ftb_output" ]]; then
            print_success "find_the_biggest atlas created: ${prior_type}_ftb_atlas_${boost_label}.nii.gz"
        else
            print_error "find_the_biggest failed (no output file produced)"
        fi
    else
        print_warning "Skipping find_the_biggest for ${prior_type} (command not available)"
    fi

    # Method 2: c3d -vote
    echo ""
    echo "Method 2: c3d -vote (input priors: ${prior_type})..."
    local vote_output="$FINAL_ATLASES_DIR/${prior_type}_vote_atlas_${boost_label}.nii.gz"

    c3d "$background_zero" "${priors_to_use[@]}" -vote -o "$vote_output" >/dev/null 2>&1 || true
    if [[ -f "$vote_output" ]]; then
        print_success "c3d -vote atlas created: ${prior_type}_vote_atlas_${boost_label}.nii.gz"
    else
        print_error "c3d -vote failed (no output file produced)"
    fi
    
    # Method 3: c3d -vote-mrf (smoothness = 0.3)
    echo ""
    echo "Method 3: c3d -vote-mrf (smoothness=0.3, input priors: ${prior_type})..."
    local vote_mrf_output="$FINAL_ATLASES_DIR/${prior_type}_vote_mrf_atlas_${boost_label}.nii.gz"

    c3d "$background_zero" "${priors_to_use[@]}" -vote-mrf 0.3 -o "$vote_mrf_output" >/dev/null 2>&1 || true
    if [[ -f "$vote_mrf_output" ]]; then
        print_success "c3d -vote-mrf atlas created: ${prior_type}_vote_mrf_atlas_${boost_label}.nii.gz"
    else
        print_error "c3d -vote-mrf failed (no output file produced)"
    fi
    
    # Clean up temporary boosted file if it exists
    if [[ $boost_mult -gt 1 ]] && [[ -f "${priors_to_use[3]}" ]]; then
        rm -f "${priors_to_use[3]}"
    fi
    
    # Clean up temporary background file
    rm -f "$background_zero"
}

################################################################################
# CREATE BASELINE (NON-BOOSTED) ATLASES
################################################################################

print_step "Creating Baseline (Non-Boosted) Atlases"
echo "These serve as reference for comparison with boosted versions"

create_atlases "fsl" "$PRIORS_FSL_DIR" "fsl" 1
create_atlases "c3d_mean" "$PRIORS_C3D_DIR" "c3d_mean" 1
create_atlases "c3d_staple" "$PRIORS_C3D_DIR" "c3d_staple" 1

################################################################################
# CREATE BOOSTED ATLASES (if boost > 1)
################################################################################

if [[ $VENTRICLE_MULTIPLIER -gt 1 ]]; then
    print_step "Creating Boosted Atlases (${VENTRICLE_MULTIPLIER}x)"
    echo "Ventricle prior will be multiplied by ${VENTRICLE_MULTIPLIER}x"
    
    create_atlases "fsl" "$PRIORS_FSL_DIR" "fsl" "$VENTRICLE_MULTIPLIER"
    create_atlases "c3d_mean" "$PRIORS_C3D_DIR" "c3d_mean" "$VENTRICLE_MULTIPLIER"
    create_atlases "c3d_staple" "$PRIORS_C3D_DIR" "c3d_staple" "$VENTRICLE_MULTIPLIER"
fi

################################################################################
# SUMMARY
################################################################################

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

print_step "Atlas Creation Complete"
echo "Time elapsed: $((ELAPSED / 60)) minutes $((ELAPSED % 60)) seconds"
echo ""

# Count atlases
atlas_count=$(find "$FINAL_ATLASES_DIR" -name "*_atlas_*.nii.gz" 2>/dev/null | wc -l)

if [[ $HAS_FSL_FTB -eq 1 ]]; then
    expected_non_boosted=9
    expected_with_boost=18
    SUMMARY_METHODS=(ftb vote vote_mrf)
else
    expected_non_boosted=6
    expected_with_boost=12
    SUMMARY_METHODS=(vote vote_mrf)
fi

if [[ $VENTRICLE_MULTIPLIER -eq 1 ]]; then
    echo "Total atlases created: $atlas_count / $expected_non_boosted (expected - non-boosted only)"
else
    echo "Total atlases created: $atlas_count / $expected_with_boost (expected - non-boosted + boosted)"
fi
echo ""

echo "Created atlases:"
echo ""
echo "=== NON-BOOSTED (BASELINE) ==="
echo ""
echo "FSL priors:"
for method in "${SUMMARY_METHODS[@]}"; do
    file="$FINAL_ATLASES_DIR/fsl_${method}_atlas_no_boost.nii.gz"
    if [[ -f "$file" ]]; then
        print_success "  fsl_${method}_atlas_no_boost.nii.gz"
    else
        print_error "  fsl_${method}_atlas_no_boost.nii.gz (MISSING)"
    fi
done

echo ""
echo "c3d mean priors:"
for method in "${SUMMARY_METHODS[@]}"; do
    file="$FINAL_ATLASES_DIR/c3d_mean_${method}_atlas_no_boost.nii.gz"
    if [[ -f "$file" ]]; then
        print_success "  c3d_mean_${method}_atlas_no_boost.nii.gz"
    else
        print_error "  c3d_mean_${method}_atlas_no_boost.nii.gz (MISSING)"
    fi
done

echo ""
echo "c3d STAPLE priors (RECOMMENDED):"
for method in "${SUMMARY_METHODS[@]}"; do
    file="$FINAL_ATLASES_DIR/c3d_staple_${method}_atlas_no_boost.nii.gz"
    if [[ -f "$file" ]]; then
        print_success "  c3d_staple_${method}_atlas_no_boost.nii.gz"
    else
        print_error "  c3d_staple_${method}_atlas_no_boost.nii.gz (MISSING)"
    fi
done

if [[ $VENTRICLE_MULTIPLIER -gt 1 ]]; then
    echo ""
    echo "=== BOOSTED (${VENTRICLE_MULTIPLIER}x ventricle boost) ==="
    echo ""
    echo "FSL priors:"
    for method in "${SUMMARY_METHODS[@]}"; do
        file="$FINAL_ATLASES_DIR/fsl_${method}_atlas_vboost${VENTRICLE_MULTIPLIER}.nii.gz"
        if [[ -f "$file" ]]; then
            print_success "  fsl_${method}_atlas_vboost${VENTRICLE_MULTIPLIER}.nii.gz"
        else
            print_error "  fsl_${method}_atlas_vboost${VENTRICLE_MULTIPLIER}.nii.gz (MISSING)"
        fi
    done
    
    echo ""
    echo "c3d mean priors:"
    for method in "${SUMMARY_METHODS[@]}"; do
        file="$FINAL_ATLASES_DIR/c3d_mean_${method}_atlas_vboost${VENTRICLE_MULTIPLIER}.nii.gz"
        if [[ -f "$file" ]]; then
            print_success "  c3d_mean_${method}_atlas_vboost${VENTRICLE_MULTIPLIER}.nii.gz"
        else
            print_error "  c3d_mean_${method}_atlas_vboost${VENTRICLE_MULTIPLIER}.nii.gz (MISSING)"
        fi
    done
    
    echo ""
    echo "c3d STAPLE priors (RECOMMENDED):"
    for method in "${SUMMARY_METHODS[@]}"; do
        file="$FINAL_ATLASES_DIR/c3d_staple_${method}_atlas_vboost${VENTRICLE_MULTIPLIER}.nii.gz"
        if [[ -f "$file" ]]; then
            print_success "  c3d_staple_${method}_atlas_vboost${VENTRICLE_MULTIPLIER}.nii.gz"
        else
            print_error "  c3d_staple_${method}_atlas_vboost${VENTRICLE_MULTIPLIER}.nii.gz (MISSING)"
        fi
    done
fi

echo ""
echo "Label mapping:"
for i in "${!LABELS[@]}"; do
    printf "  Label %d = %-6s (%s)\n" "${LABELS[$i]}" "${REGION_NAMES[$i]}" "${REGION_FULL_NAMES[$i]}"
done

echo ""
print_success "Atlas creation completed!"
echo ""
echo "Quality control suggestions:"
echo "  1. Verify label ranges:"
if [[ $VENTRICLE_MULTIPLIER -gt 1 ]]; then
    echo "     fslstats $FINAL_ATLASES_DIR/c3d_staple_vote_atlas_vboost${VENTRICLE_MULTIPLIER}.nii.gz -R"
else
    echo "     fslstats $FINAL_ATLASES_DIR/c3d_staple_vote_atlas_no_boost.nii.gz -R"
fi
echo "     (Expected: 0.000000 7.000000)"
echo ""
echo "  2. Check label distribution:"
if [[ $VENTRICLE_MULTIPLIER -gt 1 ]]; then
    echo "     fslstats $FINAL_ATLASES_DIR/c3d_staple_vote_atlas_vboost${VENTRICLE_MULTIPLIER}.nii.gz -H 8 0 8"
else
    echo "     fslstats $FINAL_ATLASES_DIR/c3d_staple_vote_atlas_no_boost.nii.gz -H 8 0 8"
fi
echo ""
echo "  3. Compare boosted vs non-boosted ventricles:"
if [[ $VENTRICLE_MULTIPLIER -gt 1 ]]; then
    echo "     fsleyes $FINAL_ATLASES_DIR/c3d_staple_vote_atlas_no_boost.nii.gz \\"
    echo "             $FINAL_ATLASES_DIR/c3d_staple_vote_atlas_vboost${VENTRICLE_MULTIPLIER}.nii.gz"
else
    echo "     (Re-run with -b 2 or -b 3 to create boosted versions for comparison)"
fi
echo ""
echo "  4. Compare all fusion methods (recommended: c3d_staple):"
echo "     fsleyes $FINAL_ATLASES_DIR/c3d_staple_*_atlas_*.nii.gz"
echo ""
if [[ $VENTRICLE_MULTIPLIER -gt 1 ]]; then
    echo "RECOMMENDED ATLAS: c3d_staple_vote_mrf_atlas_vboost${VENTRICLE_MULTIPLIER}.nii.gz"
else
    echo "RECOMMENDED ATLAS: c3d_staple_vote_mrf_atlas_no_boost.nii.gz"
fi
echo ""
