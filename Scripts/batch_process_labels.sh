
# Batch processing script for process_labels.sh
# Processes multiple subjects in Sub_A, Sub_B, etc. format


function logo { 
	echo " "
	echo "----------------------------------------------------------------------------------------------"
	echo "|     Processing of manually annotated labels, FetA2020 dataset                               |"
   	echo "|        Adapted to LaMBA 2026 Dataset                                                        |"
	echo "|                                                                                             |"
    echo "|                                                                  Step 1. Process labels     |"
	echo "|                                           Andras Jakab,  University of Zurich               |"
	echo "----------------------------------------------------------------------------------------------"
	echo " "
}

function Usage {
    echo "Requirements: C3D, FSL, python, ITK (PIP package)"
    echo " "
    echo "-----------------------------------------------------------------------------------------------------------"
    echo "Usage:"
    echo " "
    echo "batch_process_labels.sh (1)"
    echo " "
    echo "(1): main directory containing the 'subjects' subdirectory (Sub_A, Sub_B, etc.)"
    echo " "
    echo "Usage notes:"
    echo "- Input subject folders must be located in a 'subjects' subdirectory"
    echo "- Each subject folder should contain annotated label files and a T2 image"
    echo "- Output will be saved in 'subjects_combined/<subject_name>/' within the main directory"
    echo " "
    echo "More documentation: email@box.com"
    echo "-----------------------------------------------------------------------------------------------------------"
    exit 1
}

# Check arguments
[ "$1" = "" ] && Usage
[ "$1" = "-help" ] && Usage
[ "$1" = "-h" ] && Usage
[ "$1" = "--help" ] && Usage

MAIN_DIR=$1
SUBJECTS_DIR="$MAIN_DIR/subjects"
COMBINED_DIR="$MAIN_DIR/subjects_combined"

# Check if main directory exists
if [ ! -d "$MAIN_DIR" ]; then
    echo "Error: Main directory $MAIN_DIR does not exist."
    exit 1
fi

# Check if subjects subdirectory exists
if [ ! -d "$SUBJECTS_DIR" ]; then
    echo "Error: Expected 'subjects' subdirectory not found in $MAIN_DIR"
    exit 1
fi

# Create output base directory
mkdir -p "$COMBINED_DIR"

# Find all subject directories (Sub_*)
SUBJECT_DIRS=$(find "$SUBJECTS_DIR" -maxdepth 1 -type d -name "Sub_*" | sort)

if [ -z "$SUBJECT_DIRS" ]; then
    echo "Error: No subject directories found in $SUBJECTS_DIR"
    echo "Looking for directories with pattern 'Sub_*'"
    exit 1
fi

echo "Found subject directories:"
echo "$SUBJECT_DIRS"
echo ""

# Process each subject
for subject_dir in $SUBJECT_DIRS; do
    subject_name=$(basename "$subject_dir")
    echo "=========================================="
    echo "Processing subject: $subject_name"
    echo "Directory: $subject_dir"
    echo "=========================================="

 
    
    # Find T2 image in subject directory
    T2_IMAGE=$(find "$subject_dir" -maxdepth 1 -name "*_ref.nii.gz" | head -1)
    
    if [ -z "$T2_IMAGE" ]; then
        echo "Warning: No T2 image found in $subject_dir. Skipping..."
        continue
    fi
    
    echo "Found T2 image: $T2_IMAGE"
    
    # Run process_labels.sh for this subject
    if ./process_labels.sh "$subject_dir" "$T2_IMAGE" "$COMBINED_DIR"; then
        echo "Successfully processed $subject_name"
    else
        echo "Error processing $subject_name"
    fi
    
    echo ""
done

echo "Batch processing completed!"
