# Volume_calculation
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Tue Nov 28 09:47:17 2023

@author: kpa19

Brain T2 Regional Volume Analysis

"""

import matplotlib.pyplot as plt
import matplotlib
import scipy.stats as st
import statsmodels.api as sm
import glob
import pandas as pd
import nibabel as nib
import numpy as np
import csv
import os
import seaborn as sns
from scipy.stats import ttest_ind

print('')
print('*****************************')
print('Script for T2 Brain Regional Volume Analysis')
print('*****************************')
print('')

# Update paths for your data
data_path = '/volume_calc/subjects'
info_path = '/volume_calc'

fm_data = []

# Load subject information
with open(info_path + '/mydata.csv') as csv_file:
    csv_reader = csv.reader(csv_file, delimiter=',')
    for line in csv_reader:
        fm_data.append(line)

# Fix BOM character in header 
if fm_data and fm_data[0] and fm_data[0][0].startswith('\ufeff'):
    fm_data[0][0] = fm_data[0][0].replace('\ufeff', '')

print(f"Number of subjects: {len(fm_data)}")
print("Header:", fm_data[0])

# Create DataFrame with available information
index_df = ['subject_id', 'group', 'birth_weight']
df = pd.DataFrame(columns=index_df)

for folder in fm_data[1:]:
    # Assign colors based on group
    if folder[1] == 'Control':  
        colour = 'blue'
        marker = 'o'
    else:
        colour = 'red'
        marker = '+'
   
    new = pd.Series({
        'subject_id': folder[0], 
        'group': folder[1], 
        'birth_weight': folder[2], 
        'color': colour, 
        'marker': marker
    })

    df = pd.concat([df, new.to_frame().T], ignore_index=True)

print(f"Control subjects: {len(df[df['group'] == 'Control'])}")
print(f"Other subjects: {len(df[df['group'] != 'Control'])}")

# Main analysis - extract regional volumes
values_df = pd.DataFrame()

for index, row in df.iterrows():
    print(f"Processing subject: {row['subject_id']}")
    
    # Look for T2 image and labelmap files
    t2_pattern = os.path.join(data_path, row['subject_id'], '*_ref.nii.gz')
    t2_matches = glob.glob(t2_pattern)
    
    if not t2_matches:
        print(f"No T2 image files found matching pattern: {t2_pattern}")
        continue

    t2_image_file = t2_matches[0]  # Take the first match

    labelmap_pattern = os.path.join(data_path, row['subject_id'], '*_T2w-SR_annotation_combined.nii.gz')
    labelmap_matches = glob.glob(labelmap_pattern)
            
    if not labelmap_matches:
        print(f"Labelmap file does not exist: {labelmap_pattern}")
        continue

    labelmap_file = labelmap_matches[0]  # Get actual file from matches
    
    # Load T2 image for header information (voxel dimensions)
    t2_img = nib.load(t2_image_file)
    header_info = t2_img.header
    
    # Load labelmap
    seg = nib.load(labelmap_file)
    segmentation = seg.get_fdata()
    
    
    # Calculate volumes for each label
    for label in (1, 2, 3, 4, 5, 6, 7):
        label_mask = (segmentation == label)
        voxel_count = np.count_nonzero(label_mask)
        
        # Calculate volume in mL
        voxel_volume = header_info['pixdim'][1] * header_info['pixdim'][2] * header_info['pixdim'][3]
        volume_ml = voxel_count * voxel_volume * 0.001  # Convert to mL
        
        new = pd.Series({
            'subject_id': row['subject_id'], 
            'group': row['group'], 
            'birth_weight': row['birth_weight'], 
            'color': row['color'], 
            'marker': row['marker'], 
            'label': label, 
            'volume': volume_ml
        })
            
        values_df = pd.concat([values_df, new.to_frame().T], ignore_index=True)

# Clean data
values_df["label"] = values_df["label"].astype(int)
values_df["volume"] = values_df["volume"].astype(float)
values_df = values_df.fillna(0)
values_df = values_df.loc[values_df['volume'] != 0]

# Calculate total brain volume (labels 2-7, excluding label 1 intracranial/eCSF)
brain_labels = [2, 3, 4, 5, 6, 7]
brain_vol_df = (
    values_df.loc[values_df['label'].isin(brain_labels)]
    .groupby(['subject_id', 'group', 'birth_weight', 'color', 'marker'], as_index=False)['volume']
    .sum()
    .rename(columns={'volume': 'total_brain_volume'})
)

# Merge total brain volume into main dataframe
values_df = values_df.merge(brain_vol_df[['subject_id', 'total_brain_volume']], on='subject_id', how='left')

# Save results
values_df.to_csv('brain_regional_volumes.csv', index=False)
brain_vol_df.to_csv('brain_total_volumes.csv', index=False)

# Separate by groups
control_df = values_df.loc[values_df['group'] == 'Control']
other_df = values_df.loc[values_df['group'] != 'Control']
control_brain_vol = brain_vol_df.loc[brain_vol_df['group'] == 'Control']
other_brain_vol = brain_vol_df.loc[brain_vol_df['group'] != 'Control']

control_df.to_csv('brain_volumes_control.csv', index=False)
other_df.to_csv('brain_volumes_other.csv', index=False)

print("\nAnalysis complete. Files saved:")
print("- brain_regional_volumes.csv: All data, all labels")
print("- brain_total_volumes.csv: Total brain volume per subject (labels 2-7)")
print("- brain_volumes_control.csv: Regional volumes, control group only")
print("- brain_volumes_other.csv: Regional volumes, non-control group only")
print("- regional_volume_comparison.png: Regional comparison plots")
print("- total_brain_volume_comparison.png: Total brain volume comparison plot")


