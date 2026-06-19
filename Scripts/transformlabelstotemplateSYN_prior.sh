#!/bin/bash

# Sheep Atlas Anatomical Priors Creation Script
# Author: NinaOd
# Date: 2025-11-18
# Transforms combined annotation labelmaps to template space (SyN: rigid + affine + deformable)

# Record start time
START_TIME=$(date +%s)

# Set paths
TEMPLATE="/tpl_template0.nii.gz"
LABEL_BASE_DIR="/subjects_combined"
OUTPUT_DIR="/result_combined"
WARP_DIR="/warps"

# Error checking for template
if [[ ! -f "$TEMPLATE" ]]; then
    echo "Error: Template file not found: $TEMPLATE"
    exit 1
fi

# Check if label directory exists
if [[ ! -d "$LABEL_BASE_DIR" ]]; then
    echo "Error: Label directory not found: $LABEL_BASE_DIR"
    exit 1
fi

# Check if warp directory exists
if [[ ! -d "$WARP_DIR" ]]; then
    echo "Error: Warp directory not found: $WARP_DIR"
    exit 1
fi

# Show what's in the warp directory
echo "=== WARP DIRECTORY CONTENTS ==="
echo "Directory: $WARP_DIR"
echo "Warp files found:"
ls -1 "$WARP_DIR"/*Warp*.nii.gz 2>/dev/null || echo "  No warp files found!"
echo ""

echo "Affine files found:"
ls -1 "$WARP_DIR"/*Affine*.mat 2>/dev/null || echo "  No affine files found!"
echo ""

echo "All files:"
ls -la "$WARP_DIR" 2>/dev/null || echo "  Directory empty or unreadable!"
echo "================================"

echo ""

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Find all combined annotation files
ANNOTATION_FILES=($(find "$LABEL_BASE_DIR" -name "*_T2w-SR_annotation_combined.nii.gz" -type f | sort))

if [[ ${#ANNOTATION_FILES[@]} -eq 0 ]]; then
    echo "Error: No combined annotation files found in $LABEL_BASE_DIR"
    echo "Looking for files matching: *_T2w-SR_annotation_combined.nii.gz"
    exit 1
fi

echo "Found ${#ANNOTATION_FILES[@]} combined annotation files:"
for file in "${ANNOTATION_FILES[@]}"; do
    echo "  $(basename $file)"
done
echo ""

echo "Starting RIGID transformation of combined annotations to template space..."
echo ""

# Transform all combined annotation files to template space
successful_subjects=0
failed_subjects=0

for annotation_file in "${ANNOTATION_FILES[@]}"; do
    # Extract base filename and subject name
    filename=$(basename "$annotation_file")
    # Remove '_T2w-SR_annotation_combined.nii.gz' to get subject name
    subject_name="${filename%_T2w-SR_annotation_combined.nii.gz}"
    
    echo "Processing subject $((successful_subjects + failed_subjects + 1))/${#ANNOTATION_FILES[@]}: $subject_name"
    echo "  Input file: $filename"
    
    # Find matching warp and affine files using wildcards (SyN registration produces both)
    warp_files=("$WARP_DIR"/${subject_name}*Warp.nii.gz)
    affine_files=("$WARP_DIR"/${subject_name}*GenericAffine.mat)
    
    # Check if warp file exists
    if [[ ! -f "${warp_files[0]}" ]]; then
        echo "  ✗ ERROR: No warp file found matching: ${subject_name}*Warp.nii.gz"
        echo "    Files in warp directory matching pattern:"
        ls -1 "$WARP_DIR"/*${subject_name}* 2>/dev/null | head -5
        echo ""
        ((failed_subjects++))
        continue
    fi
    
    # Check if affine file exists
    if [[ ! -f "${affine_files[0]}" ]]; then
        echo "  ✗ ERROR: No affine file found matching: ${subject_name}*GenericAffine.mat"
        echo "    Files in warp directory matching pattern:"
        ls -1 "$WARP_DIR"/*${subject_name}* 2>/dev/null | head -5
        echo ""
        ((failed_subjects++))
        continue
    fi
    
    warp_file="${warp_files[0]}"
    affine_file="${affine_files[0]}"
    
    echo "  ✓ Using warp (SyN): $(basename $warp_file)"
    echo "  ✓ Using affine: $(basename $affine_file)"
    
    # Define output file
    output_file="$OUTPUT_DIR/${subject_name}combined_toTemplate.nii.gz"
    
    echo "  → Transforming combined annotation to template space (SyN: rigid + affine + warp)..."
    
    # Apply transformation with NearestNeighbor interpolation
    # IMPORTANT: Transform order matters! Apply warp first, then affine
    # This is the inverse transformation (moving FROM subject TO template)
    antsApplyTransforms \
        -d 3 \
        -i "$annotation_file" \
        -r "$TEMPLATE" \
        -t "$warp_file" \
        -t "$affine_file" \
        -o "$output_file" \
        -n NearestNeighbor \
        --verbose 0
    
    if [[ $? -eq 0 ]]; then
        echo "  ✓ Successfully transformed combined annotation"
        echo "  Output: $(basename $output_file)"
        ((successful_subjects++))
    else
        echo "  ✗ Failed to transform combined annotation"
        ((failed_subjects++))
    fi
    echo ""
done

echo "========================================"
echo "Transformation completed"
echo "Successful subjects: $successful_subjects"
echo "Failed subjects: $failed_subjects"
echo "========================================"
echo ""

if [[ $successful_subjects -eq 0 ]]; then
    echo "❌ ERROR: No subjects were successfully processed."
    echo ""
    echo "Debugging suggestions:"
    echo "1. Check annotation directory: ls -la $LABEL_BASE_DIR"
    echo "2. Check warp directory: ls -la $WARP_DIR"
    echo "3. Verify affine .mat files exist and match subject names"
    exit 1
fi

# Quality control summary
echo ""
echo "========================================"
echo "QUALITY CONTROL SUMMARY"
echo "========================================"
echo "Template used: $TEMPLATE"
echo "Input directory: $LABEL_BASE_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Subjects processed: $successful_subjects / ${#ANNOTATION_FILES[@]}"
echo ""
echo "Transformed combined annotation files:"
ls -1h "$OUTPUT_DIR"/*_labelmap_combined_toTemplate.nii.gz 2>/dev/null || echo "  No output files found!"
echo ""

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

echo ""
echo "========================================"
echo "🐑 Sheep combined annotation transformation completed (SyN)!"
echo "Time elapsed: ${MINUTES}m ${SECONDS}s"
echo "========================================"
echo ""
