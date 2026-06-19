#!/usr/bin/env bash

set -e



DIR_BRAINS="0masked_brains"

DIR_MASKS="brainmask"

DIR_BC="1biascorrect"

DIR_BF="1biascorrect_fields"

mkdir -p "$DIR_BC" "$DIR_BF"



for f in "$DIR_BRAINS"/Sub_*_brain_T2.nii.gz; do

    id=$(basename "$f" _brain_T2.nii.gz)

    mask="${DIR_MASKS}/${id}_labels_2-7_merged_grown.nii.gz"

    if [ ! -f "$mask" ]; then

        echo "WARNING: No mask found for $id → skipping"

        continue

    fi

    echo "N4 → $id"

    N4BiasFieldCorrection -d 3 -s 4 -b [180] -c [50x50x50x50,0.0] -i "$f" -x "$mask" -o "[${DIR_BC}/${id}_brain_T2_BC.nii.gz,${DIR_BF}/${id}_brain_T2_biasfield.nii.gz]"

done



echo "Done. Bias corrected images in $DIR_BC"
