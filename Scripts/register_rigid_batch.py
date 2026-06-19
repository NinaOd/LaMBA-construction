#!/usr/bin/env python3

import subprocess

from pathlib import Path

import sys


# Configuration

TEMPLATE = "/tpl_template0.nii.gz"

INPUT_DIR = Path("/subjects")

OUTPUT_DIR = Path("/fit_RIGID")


# Create output directory

OUTPUT_DIR.mkdir(exist_ok=True)


def extract_subject_name(filename):

    """Extract NAME from sub-{NAME}_brain_T2_BC_HM.nii.gz"""

    prefix = "sub-"

    suffix = "_brain_T2_BC_HM.nii.gz"

    if filename.startswith(prefix) and filename.endswith(suffix):

        return filename[len(prefix):-len(suffix)]

    return Path(filename).stem.split('.')[0]


print("Starting RIGID registration to template...")

print(f"Template: {TEMPLATE}")

print(f"Output directory: {OUTPUT_DIR}")

print()


# Find input files

input_files = sorted(INPUT_DIR.glob("sub-*_brain_T2_BC_HM.nii.gz"))


if not input_files:

    print("No input files found!")

    sys.exit(1)


print(f"Found {len(input_files)} files to register:")

for f in input_files:

    subject = extract_subject_name(f.name)

    print(f"  - {f.name:<50} → {subject}")

print()


# Confirm before starting

response = input("Proceed with registration? [y/N]: ")

if response.lower() != 'y':

    print("Aborted.")

    sys.exit(0)


print()


success_count = 0

failed = []


for img_path in input_files:

    subject = extract_subject_name(img_path.name)



    print("=" * 80)

    print(f"Processing: {img_path.name}")

    print(f"Subject: {subject}")

    print(f"Output prefix: tpl_{subject}_")

    print()



    # Build antsRegistration command — RIGID only

    cmd = [

        "antsRegistration",

        "-d", "3",

        "--float", "1",

        "--verbose", "1",

        "-r", f"[{TEMPLATE},{img_path},1]",

        # Rigid stage

        "-t", "Rigid[0.1]",

        "-m", f"MI[{TEMPLATE},{img_path},1,32,Regular,0.25]",

        "-c", "[1000x500x250x0,1e-6,10]",

        "-f", "6x4x2x1",

        "-s", "4x2x1x0vox",

        "-n", "Linear",

        # Output

        "-o", f"[{OUTPUT_DIR}/tpl_{subject}_,{OUTPUT_DIR}/tpl_{subject}_warped.nii.gz]"

    ]



    try:

        result = subprocess.run(cmd, check=True, capture_output=False)

        print(f"✓ Successfully registered {subject}")

        success_count += 1

    except subprocess.CalledProcessError as e:

        print(f"✗ ERROR registering {subject}")

        failed.append(img_path.name)

    except KeyboardInterrupt:

        print("\n\n⚠ Interrupted by user")

        sys.exit(1)



    print()


# Summary

print("=" * 80)

print(f"Registration complete!")

print(f"  Success: {success_count}/{len(input_files)}")

if failed:

    print(f"  Failed: {len(failed)}")

    for f in failed:

        print(f"    - {f}")

print()

print(f"Results saved in: {OUTPUT_DIR}")

print()

print("Output files for each subject:")

print("  - tpl_{subject}_0GenericAffine.mat (rigid transform)")

print("  - tpl_{subject}_warped.nii.gz (registered image)")
