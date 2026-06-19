#!/usr/bin/env python3
"""
Segmentation evaluation: for each GT/prediction mask pair (matched by subject
folder + label number), run EvaluateSegmentation and compute HD95 with the
surface_distance library, writing one wide all_metrics.csv.

Two Hausdorff columns, computed by different methods:
  EvalSeg_HDRFDST          - EvaluateSegmentation, HDRFDST@0.95@ (0.95-quantile)
  HD95_surface_distance_mm - surface_distance library (95th percentile, mm)
Other EvaluateSegmentation metrics keep their native symbols, prefixed EvalSeg_.
"""

import os
import re
import glob
import csv
import subprocess
import xml.etree.ElementTree as ET

import nibabel as nib
import surface_distance as sd


# ----- Configuration ---------------------------------------------------------
GT_DIR      = "GT_labels_split"
PRED_DIR    = "outputTs_PP_split"
OUTPUT_DIR  = "evaluatesegmentation"
EVALSEG_BIN = "./EvaluateSegmentation/builds/Ubuntu/EvaluateSegmentation"

OUTPUT_CSV  = os.path.join(OUTPUT_DIR, "all_metrics.csv")
HD95_COLUMN = "HD95_surface_distance_mm"

# -use restricts the XML to these metrics; HDRFDST@0.95@ = 0.95-quantile HD
USE_METRICS = "DICE,JACRD,VOLSMTY,HDRFDST@0.95@,AVGDIST,SNSVTY,SPCFTY,PRCISON,FMEASR"
UNIT = "millimeter"   # voxel | millimeter


# ----- Helpers ---------------------------------------------------------------
def find_prediction(pred_subject_dir, label):
    matches = glob.glob(os.path.join(pred_subject_dir, f"*_label{label}_mask.nii.gz"))
    return matches[0] if matches else None


def parse_evalseg_xml(xml_path):
    metrics = {}
    for el in ET.parse(xml_path).iter():
        symbol = el.get("symbol")
        value = el.get("value")
        if symbol is not None and value is not None:
            metrics[symbol] = value
    return metrics


def run_evalseg(gt_path, pred_path, xml_path):
    subprocess.run(
        [EVALSEG_BIN, gt_path, pred_path,
         "-use", USE_METRICS, "-unit", UNIT, "-xml", xml_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=True,
    )
    return parse_evalseg_xml(xml_path)


def compute_hd95(gt_path, pred_path):
    gt_img = nib.load(gt_path)
    gt_mask = gt_img.get_fdata().astype(bool)
    pred_mask = nib.load(pred_path).get_fdata().astype(bool)
    spacing = gt_img.header.get_zooms()
    surfaces = sd.compute_surface_distances(gt_mask, pred_mask, spacing_mm=spacing)
    return sd.compute_robust_hausdorff(surfaces, 95)


# ----- Main ------------------------------------------------------------------
def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    rows = []
    evalseg_symbols = []
    n_subjects = n_pairs = n_missing_pred = n_evalseg_failed = n_hd95_failed = 0

    subjects = sorted(
        d for d in os.listdir(GT_DIR) if os.path.isdir(os.path.join(GT_DIR, d))
    )

    print("=" * 60)
    print("Segmentation evaluation (EvaluateSegmentation + surface_distance)")
    print("=" * 60)

    for subject in subjects:
        n_subjects += 1
        gt_subject_dir = os.path.join(GT_DIR, subject)
        pred_subject_dir = os.path.join(PRED_DIR, subject)

        print(f"\nSubject [{n_subjects}]: {subject}")

        if not os.path.isdir(pred_subject_dir):
            print("  no prediction directory - skipping subject")
            continue

        gt_files = sorted(
            f for f in os.listdir(gt_subject_dir) if f.endswith("_mask.nii.gz")
        )

        for gt_file in gt_files:
            m = re.search(r"label(\d+)_mask\.nii\.gz$", gt_file)
            if not m:
                print(f"  {gt_file}: cannot parse label number - skipping")
                continue
            label = m.group(1)

            gt_path = os.path.join(gt_subject_dir, gt_file)
            pred_path = find_prediction(pred_subject_dir, label)
            if pred_path is None:
                print(f"  label {label}: no matching prediction - skipping")
                n_missing_pred += 1
                continue

            row = {"Subject": subject, "Label": label}

            xml_path = os.path.join(OUTPUT_DIR, f"{subject}_label{label}_evaluation.xml")
            try:
                metrics = run_evalseg(gt_path, pred_path, xml_path)
                for symbol, value in metrics.items():
                    if symbol not in evalseg_symbols:
                        evalseg_symbols.append(symbol)
                    row[f"EvalSeg_{symbol}"] = value
            except (subprocess.CalledProcessError, ET.ParseError, FileNotFoundError) as exc:
                print(f"  label {label}: EvaluateSegmentation failed ({exc})")
                n_evalseg_failed += 1

            try:
                row[HD95_COLUMN] = f"{compute_hd95(gt_path, pred_path):.4f}"
            except Exception as exc:
                print(f"  label {label}: HD95 (surface_distance) failed ({exc})")
                row[HD95_COLUMN] = ""
                n_hd95_failed += 1

            rows.append(row)
            n_pairs += 1
            print(
                f"  label {label}: "
                f"Dice={row.get('EvalSeg_DICE', '?')}  "
                f"HDRFDST(0.95)={row.get('EvalSeg_HDRFDST', '?')}  "
                f"HD95(surf)={row.get(HD95_COLUMN, '?')}"
            )

    fieldnames = (
        ["Subject", "Label"]
        + [f"EvalSeg_{s}" for s in evalseg_symbols]
        + [HD95_COLUMN]
    )

    with open(OUTPUT_CSV, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, restval="")
        writer.writeheader()
        writer.writerows(rows)

    print("\n" + "=" * 60)
    print("Done.")
    print(f"  Subjects scanned        : {n_subjects}")
    print(f"  Pairs evaluated         : {n_pairs}")
    print(f"  Missing predictions     : {n_missing_pred}")
    print(f"  EvaluateSegmentation err: {n_evalseg_failed}")
    print(f"  HD95 (surface_dist) err : {n_hd95_failed}")
    print(f"  Results CSV             : {OUTPUT_CSV}")
    print("=" * 60)


if __name__ == "__main__":
    main()
