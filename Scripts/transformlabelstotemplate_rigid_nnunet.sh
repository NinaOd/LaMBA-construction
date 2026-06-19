#!/bin/bash

# Sheep Atlas Anatomical Priors Creation Script
# Author: NinaOd
# Date: 2025-11-18
# Transforms combined annotation labelmaps to template space (rigid only)

# Record start time
START_TIME=$(date +%s)

# Set paths
TEMPLATE="/tpl_template0.nii.gz"
LABEL_BASE_DIR="/labels"
OUTPUT_DIR="/warped_labels"
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
echo "Affine files found:"
ls -1 "$WARP_DIR"/*Affine*.mat || echo "  No affine files found!"
echo ""
echo "================================"
echo ""

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Find all combined annotation files
ANNOTATION_FILES=($(find "$LABEL_BASE_DIR" -name "Sub_*_T2w-SR_annotation_combined.nii.gz" -type f | sort))

if [[ ${#ANNOTATION_FILES[@]} -eq 0 ]]; then
    echo "Error: No combined annotation files found in $LABEL_BASE_DIR"
    echo "Looking for files matching: Sub_*_T2w-SR_annotation_combined.nii.gz"
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
    
    # Derive the name used by register_rigid_batch.py:
    name_no_prefix="${subject_name#Sub_}"
    affine_file="$WARP_DIR/tpl_${name_no_prefix}_0GenericAffine.mat"

    # Check if affine file exists
    if [[ ! -f "$affine_file" ]]; then
        echo "  ✗ ERROR: No affine file found: $(basename $affine_file)"
        echo "    Expected: $affine_file"
        echo "    Files in warp directory:"
        ls -1 "$WARP_DIR"/*.mat 2>/dev/null || echo "    No .mat files found"
        echo ""
        ((failed_subjects++))
        continue
    fi
    
    echo "  ✓ Using affine (rigid): $(basename $affine_file)"
    
    # Define output file
    output_file="$OUTPUT_DIR/tpl_${name_no_prefix}_labelmap_combined_toTemplate.nii.gz"
    
    echo "  → Transforming combined annotation to template space (rigid only)..."
    
    # Apply transformation with NearestNeighbor interpolation
    # Note: Only using affine transform - no warp file for rigid registration
    antsApplyTransforms \
        -d 3 \
        -i "$annotation_file" \
        -r "$TEMPLATE" \
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
ls -1h "$OUTPUT_DIR"/*_labelmap_toTemplate.nii.gz || echo "  No output files found!"
echo ""

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

echo ""
echo "========================================"
echo "🐑 Sheep combined annotation transformation completed!"
echo "Time elapsed: ${MINUTES}m ${SECONDS}s"
echo "========================================"
echo ""
