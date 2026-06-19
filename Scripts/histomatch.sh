#!/usr/bin/env bash

set -e



DIR_BC="1biascorrect"

DIR_MASKS="brainmask"

DIR_HM="2histogram"

REF_BC="${DIR_BC}/sub-reference.nii.gz"

mkdir -p "$DIR_HM"



for f in "$DIR_BC"/sub-*_brain_T2_BC.nii.gz; do

    [[ "$f" == "$REF_BC" ]] && continue

    id=$(basename "$f" _brain_T2_BC.nii.gz)

    echo "HistogramMatch → $id"

    ImageMath 3 "${DIR_HM}/${id}_brain_T2_BC_HM.nii.gz" HistogramMatch "$f" "$REF_BC" 255 64 1

done



cp "$REF_BC" "${DIR_HM}/sub-reference_T2_BC_HM.nii.gz"



echo "Done. Results in $DIR_HM"
