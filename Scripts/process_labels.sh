#!/bin/bash

function Usage { 
    echo "Requirements: C3D, FSL, python, ITK (PIP package)" 
    echo " " 
    echo "-----------------------------------------------------------------------------------------------------------"                             
    echo "Usage:"
    echo " "  
    echo "process_labels.sh (1) (2) (3)"
    echo " "
    echo "(1): input directory where annotated labels are found, full path "
    echo "(2): T2 MR image annotated, full path "
    echo "(3): output base directory (subjects_combined), full path"  
    echo " "  
    echo " "  
    echo "Usage notes: "  
    echo " "  
    echo "More documentation: NinaOd @ Github  
    echo "-----------------------------------------------------------------------------------------------------------" 
    exit 1
}

# Check arguments
[ "$1" = "" ] && Usage
[ "$1" = "-help" ] && Usage
[ "$1" = "-h" ] && Usage
[ "$1" = "--help" ] && Usage

# Validate T2 image parameter
[ "$2" = "" ] && echo "Error: T2 image path required" && Usage

# Validate output base directory parameter
[ "$3" = "" ] && echo "Error: Output base directory required" && Usage

#c3d install directory, change when migrating system
export PATH=$PATH:/path/to/c3d/
export PATH=$PATH:/path/to/c3d/bin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/path/to/c3d/

dir=$1
T2_image=$2
combined_base=$3

# Validate inputs
if [ ! -d "$dir" ]; then
    echo "Error: Input directory $dir does not exist."
    exit 1
fi

if [ ! -f "$T2_image" ]; then
    echo "Error: T2 image $T2_image does not exist."
    exit 1
fi

# Create output directory in subjects_combined/<subject_name>/
subject_name=$(basename "$dir")
output_dir="$combined_base/$subject_name"
mkdir -p "$output_dir"

cd "$dir"

# Renames annotated label maps according to actual label value
for file in $(ls *-label*.nii.gz 2>/dev/null); do 
    echo $file; p=$(fslstats $file -M)
    fname=$(echo $p | awk '{print int($1+0.5)}')
    cp $file label_"$fname".nii.gz
done 

for file in $(ls *label*.nii.gz 2>/dev/null); do 
    echo $file; p=$(fslstats $file -M)
    fname=$(echo $p | awk '{print int($1+0.5)}')
    cp $file label_"$fname".nii.gz
done 

for file in $(ls 7.nii.gz 2>/dev/null); do 
    echo $file; p=$(fslstats $file -M)
    fname=$(echo $p | awk '{print int($1+0.5)}')
    cp $file label_"$fname".nii.gz
done 

# Creates background image (every voxel)
fslmaths "$T2_image" -thr 0.01 -bin -mul 4 label_background

function checkfile {
    if [ -f $1 ]; 
        then
        sleep 0
        else
        echo "Previous pre-processing step did not complete successfully. File $1 for case in $dir is missing. Exiting."
        exit 1
    fi
}

function label1 {
	#intracranial space
	cp label_1.nii.gz orig_label_1.nii.gz
	fslmaths label_1.nii.gz -mul 1 label_1.nii.gz -odt char
	fslmaths label_1.nii.gz -bin -mul 1 label_1_proc.nii.gz
}

function label2 {
	#cortex, w smoothing
	cp label_2.nii.gz orig_label_2.nii.gz
	fslmaths label_2.nii.gz -bin -mul 2 label_2_proc.nii.gz
}

function label3 {
	#white matter, minimal smoothing, axial interpolation
	cp label_3.nii.gz orig_label_3.nii.gz
	fslmaths label_3.nii.gz -bin -mul 3 label_3_proc.nii.gz
}

function label4 {
	#ventricle system
	cp label_4.nii.gz orig_label_4.nii.gz
	#IMPORTANT NOTE: LV GETS A LABEL VALUE OF 15 TO MAKE SURE IT IS ON TOP OF EVERYTHING WHEN C3D ACUMMULATES LABELS! It has to be divided by 3 afterwards, see below.
	fslmaths label_4.nii.gz -bin -mul 15 label_4_proc.nii.gz
}

function label5 {
	#cerebellum
	cp label_5.nii.gz orig_label_5.nii.gz
	fslmaths label_5.nii.gz -s 0.25 -thr 0.6 -bin -mul 5 label_5_proc.nii.gz
}

function label6 {
	#basal ganglia and thalamus, some smoothing
	cp label_6.nii.gz orig_label_6.nii.gz
	fslmaths label_6.nii.gz -bin -mul 6 label_6_proc.nii.gz
}

function label7 {
	#brainstem
	cp label_7.nii.gz orig_label_7.nii.gz
	fslmaths label_7.nii.gz -bin -mul 7 label_7_proc.nii.gz
}


# Check if initial annotations exist after renaming
checkfile label_1.nii.gz
checkfile label_2.nii.gz
checkfile label_3.nii.gz
checkfile label_5.nii.gz
checkfile label_6.nii.gz
checkfile label_7.nii.gz

# Process annotated labels
label1 
label2 
label3 
label4
label5 
label6 
label7 

# Check if output files exist
checkfile label_1_proc.nii.gz
checkfile label_2_proc.nii.gz
checkfile label_3_proc.nii.gz
checkfile label_4_proc.nii.gz
checkfile label_5_proc.nii.gz
checkfile label_6_proc.nii.gz
checkfile label_7_proc.nii.gz

# Combines labels 
c3d label_1_proc.nii.gz label_2_proc.nii.gz label_3_proc.nii.gz label_5_proc.nii.gz label_6_proc.nii.gz label_7_proc.nii.gz label_4_proc.nii.gz -accum -max -endaccum -o combined.nii.gz

# Save final output to subjects_combined/<subject_name>/
/usr/local/c3d/bin/c3d combined.nii.gz -replace 15 4 -o "$output_dir/${subject_name}_T2w-SR_annotation_combined.nii.gz"

echo "Output saved to: $output_dir/${subject_name}_T2w-SR_annotation_combined.nii.gz"