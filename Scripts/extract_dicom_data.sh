#!/bin/bash



echo "subject,series_dir,receive_coil,receive_coil_type,transmit_coil,manufacturer,model,field_strength,software_version,TR,TE,TI,slice_thickness,slice_spacing,pixel_BW,flip_angle,phase_direction,averages,images_in_acq,pixel_spacing,frames,protocol,series_description,scanning_seq,seq_variant" > coil_output.csv



for subject_dir in */; do

  series_dir=$(find "$subject_dir" -maxdepth 1 -type d -name "*3D_Brain*1nsa*" | head -1)



  if [ -z "$series_dir" ]; then

    echo "WARNING: No 3D_Brain*1nsa folder found in $subject_dir" >&2

    continue

  fi



  f=$(find "$series_dir" -type f -name "IM_*" | head -1)

  if [ -z "$f" ]; then

    f=$(find "$series_dir" -type f | head -1)

  fi

  if [ -z "$f" ]; then

    echo "WARNING: No DICOM file found under $series_dir" >&2

    continue

  fi



  echo "Processing: $f" >&2



  # Function to extract first value of a tag

  get_tag() {

    dcmdump +P "$1" "$f" 2>/dev/null | grep -oP '\[.*?\]' | tr -d '[]' | head -1

  }



  manufacturer=$(get_tag "0008,0070")

  model=$(get_tag "0008,1090")

  field_strength=$(get_tag "0018,0087")

  software=$(get_tag "0018,1020")

  TR=$(get_tag "0018,0080")

  TE=$(get_tag "0018,0081")

  TI=$(get_tag "0018,0082")

  slice_thickness=$(get_tag "0018,0050")

  slice_spacing=$(get_tag "0018,0088")

  pixel_BW=$(get_tag "0018,0095")

  flip_angle=$(get_tag "0018,1314")

  phase_dir=$(get_tag "0018,1312")

  averages=$(get_tag "0018,0083")

  images_in_acq=$(get_tag "0020,1002")

  pixel_spacing=$(get_tag "0028,0030")

  frames=$(get_tag "0028,0008")

  protocol=$(get_tag "0018,1030")

  series_desc=$(get_tag "0008,103E")

  scanning_seq=$(get_tag "0018,0020")

  seq_variant=$(get_tag "0018,0021")



  receive_coil=$(dcmdump +P 0018,1250 "$f" 2>/dev/null | grep -oP '\[.*?\]' | tr -d '[]' | head -1)

  receive_coil_type=$(dcmdump +P 0018,9043 "$f" 2>/dev/null | grep -oP '\[.*?\]' | tr -d '[]' | head -1)

  transmit_coil=$(dcmdump +P 0018,9051 "$f" 2>/dev/null | grep -oP '\[.*?\]' | tr -d '[]' | head -1)



  echo "${subject_dir%/},${series_dir},${receive_coil},${receive_coil_type},${transmit_coil},${manufacturer},${model},${field_strength},${software},${TR},${TE},${TI},${slice_thickness},${slice_spacing},${pixel_BW},${flip_angle},${phase_dir},${averages},${images_in_acq},${pixel_spacing},${frames},${protocol},${series_desc},${scanning_seq},${seq_variant}" >> coil_output.csv



done



echo "Done. Output saved to coil_output.csv"
