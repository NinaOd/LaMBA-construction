#!/bin/bash

# Paths
LABEL_DIR="/warped_labels"
OUTPUT_DIR="/warped_labels_split"  

# Label numbers to extract
LABELS=(1 2 3 4 5 6 7)

# Loop through warped labelmap files in LABEL_DIR
# Input naming: tpl_{NAME}_labelmap_combined_toTemplate.nii.gz
for COMBINED in "$LABEL_DIR"/tpl_*_labelmap_combined_toTemplate.nii.gz; do

    if [[ ! -f "$COMBINED" ]]; then
        echo "Warning: No warped labelmap files found in $LABEL_DIR"
        break
    fi

    filename=$(basename "$COMBINED")
    # Extract NAME by stripping tpl_ prefix and _labelmap_combined_toTemplate.nii.gz suffix
    NAME="${filename#tpl_}"
    NAME="${NAME%_labelmap_combined_toTemplate.nii.gz}"

    TPL_PREFIX="tpl_${NAME}"
    SUBJ_FOLDER="Sub_${NAME}"

    echo "Processing $TPL_PREFIX..."
    echo "  Found: $filename"

    # Create subject output folder Sub_{NAME}/
    SUBJ_OUT="$OUTPUT_DIR/$SUBJ_FOLDER"
    mkdir -p "$SUBJ_OUT"

    # Extract each label
    for LABEL in "${LABELS[@]}"; do
        # Binary mask (0 or 1)
        MASK_OUT="$SUBJ_OUT/${TPL_PREFIX}_label${LABEL}_mask.nii.gz"
        ThresholdImage 3 "$COMBINED" "$MASK_OUT" "$LABEL" "$LABEL" 1 0

        # Label-value image (preserves label number)
        LABELVAL_OUT="$SUBJ_OUT/${TPL_PREFIX}_label${LABEL}.nii.gz"
        ImageMath 3 "$LABELVAL_OUT" m "$MASK_OUT" "$LABEL"

        echo "  Extracted label $LABEL"
    done

    # Copy the original combined labelmap to output
    cp "$COMBINED" "$SUBJ_OUT/${TPL_PREFIX}_combined_labelmap.nii.gz"

done

echo ""
echo "✓ Done! Per-label files saved to $OUTPUT_DIR"
echo ""
echo "Output structure:"
echo "  /path/to/outputdir/"
echo "    ├── Sub_{name}_label1_mask.nii.gz"
echo "    ├── Sub_{name}_label1.nii.gz"
echo "    ├── Sub_{name}_label2_mask.nii.gz"
echo "    ├── ..."
echo "    └── Sub_{name}_combined_labelmap.nii.gz"
