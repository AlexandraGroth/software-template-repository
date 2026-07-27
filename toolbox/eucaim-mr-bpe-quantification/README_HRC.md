# EUCAIM MR BPE Quantification — User Guide for HR&C

This guide is intended for HR&C researchers and study coordinators who run
the BPE quantification tool on their DICOM data within the EUCAIM platform.

---

## Quick start

One command does everything — it pulls the tool image automatically on the
first run (asking for your Harbor login once), then processes your case and
writes the result:

```bash
bash scripts/run_eucaim_mr_bpe_image.sh \
  --input /path/to/your/dicom_case \
  --output /path/to/your/output
```

The results are written to `/path/to/your/output/results.csv`.


---

## What does this tool do?

The tool calculates **Background Parenchymal Enhancement (BPE)** from a
breast DCE-MRI examination.

BPE describes the degree of contrast enhancement of the fibroglandular tissue
(FGT) in the breast. The tool processes a DCE-MRI examination — one
pre-contrast and one post-contrast timepoint — and reports the BPE percentage:

```
BPE (%) = highlighted FGT volume / total FGT volume × 100
```

A voxel is considered *highlighted* when its relative signal enhancement
exceeds the configured threshold (default: 15 %).

BPE categories follow the ACR BI-RADS classification:

| Category | BPE% range | Label |
|---|---|---|
| 0 | < 25 % | Minimal |
| 1 | 25 – 50 % | Mild |
| 2 | 50 – 75 % | Moderate |
| 3 | > 75 % | Marked |

> **Important:** This tool is not a clinical diagnostic application.
> Results must be interpreted by qualified medical professionals within the
> appropriate clinical or research context.

---

## What do I receive as output?

The tool writes one result file per processed case:

```
results.csv
```

The file contains one row per case with the following columns:

| Column | Description |
|---|---|
| `patient_id` | Patient identifier (folder name or from batch input) |
| `study_uid` | Study identifier |
| `series_uid` | Series identifier |
| `HighlightedVolume` | Volume of highlighted FGT voxels in mm³ |
| `BPE%` | BPE percentage |
| `Category` | ACR category (0 = minimal, 1 = mild, 2 = moderate, 3 = marked) |

Example output:

```csv
,patient_id,study_uid,series_uid,HighlightedVolume,BPE%,Category
0,PATIENT_001,STUDY_001,SERIES_001,2302.35,41.23,1
```

---

## Prerequisites

You need the following:

- A Linux system with **Docker** installed and available
- Access to the EUCAIM Harbor registry:
  `harbor.eucaim.cancerimage.eu`
- DICOM input data for one case (pre- and post-contrast DCE breast MRI
  series in one folder)
- The run script from the delivery package:
  `scripts/run_eucaim_mr_bpe_image.sh`

---

## How to run — step by step

### Step 1 — First run (pulls image from Harbor)

On the first run, the tool needs to download the container image from the
EUCAIM Harbor registry. You will be asked for your Harbor username and token.

```bash
bash scripts/run_eucaim_mr_bpe_image.sh \
  --input /path/to/your/dicom_case \
  --output /path/to/your/output
```

The script will:
1. Ask for your Harbor username and token (entered interactively — token is
   not shown on screen)
2. Pull the container image from Harbor (~8 GB, only once)
3. Validate the container
4. Run the BPE pipeline
5. Write `results.csv` to your output directory

### Step 2 — All subsequent runs (image already available)

After the first run the image is stored locally — no login or download needed:

```bash
bash scripts/run_eucaim_mr_bpe_image.sh \
  --input /path/to/your/dicom_case \
  --output /path/to/your/output
```

The script will confirm that the image is already available and show when it
was built:

```
[INFO] Image already available locally, skipping pull: harbor.eucaim.cancerimage.eu/...
[INFO] Image created: 2026-06-25 14:32:00 +0000 UTC
```

---

## Running multiple cases

There are two ways to process more than one case.

### Option A — One run per case (simple)

Run the script once per case, each time with a different `--input` and
`--output` directory:

```bash
bash scripts/run_eucaim_mr_bpe_image.sh \
  --input /path/to/case01 \
  --output /path/to/results/case01

bash scripts/run_eucaim_mr_bpe_image.sh \
  --input /path/to/case02 \
  --output /path/to/results/case02
```

### Option B — Whole dataset in one run (EUCAIM CDM structure)

If your data follows the **EUCAIM CDM structure**, you can process all cases in
a single run. Your folder must look like this:

```text
EUCAIM_CDM_Structure/
├── imaging_mandatory_view.csv
└── dataset/
    └── imaging_data/
        └── <patient_id>/
            └── <study_uid>/
                └── <series_uid>/
                    └── ... DICOM files ...
```

Then run:

```bash
bash scripts/run_eucaim_mr_bpe_image.sh \
  --input /path/to/EUCAIM_CDM_Structure \
  --output /path/to/results \
  -- \
  --input /input/imaging_mandatory_view.csv --output /output --noregister
```

Just replace `/path/to/EUCAIM_CDM_Structure` with your data folder and
`/path/to/results` with where you want the results. The rest stays exactly as
shown.

The result file `/path/to/results/results.csv` will contain **one row per
case** in your dataset.

---

## Using Podman instead of Docker

Docker is the default container runtime and does not require any additional
storage configuration.

If your system uses Podman instead of Docker, add `--runtime podman`:

```bash
bash scripts/run_eucaim_mr_bpe_image.sh \
  --runtime podman \
  --input /path/to/your/dicom_case \
  --output /path/to/your/output
```

For Podman, the script uses a project-specific storage directory aligned with
the existing build and test scripts:

```text
/tmp/<username>/podman-overlay-storage
```

No additional configuration is required. This configuration is only used when
Podman is selected and does not affect Docker users.

The storage location may be cleared by the operating system. If persistent
storage is required, set `STORAGE_BASE` to a directory in the user's home
folder:

```bash
STORAGE_BASE="${HOME}/podman-overlay-storage" \
bash scripts/run_eucaim_mr_bpe_image.sh \
  --runtime podman \
  --input /path/to/your/dicom_case \
  --output /path/to/your/output
```

---

## Optional parameters

| Parameter | Description | Default |
|---|---|---|
| `--threshold VALUE` | Relative enhancement threshold in % | 15 |
| `--intermediate` | Store intermediate volumes (Breast ROI, FGT) in output | off |
| `--useintermediate` | Reuse existing intermediate volumes from a previous run | off |
| `--runtime podman\|docker` | Container runtime | docker |

### Example with custom threshold

```bash
bash scripts/run_eucaim_mr_bpe_image.sh \
  --input /path/to/case01 \
  --output /path/to/results/case01 \
  --threshold 20
```

### Example storing intermediate volumes

```bash
bash scripts/run_eucaim_mr_bpe_image.sh \
  --input /path/to/case01 \
  --output /path/to/results/case01 \
  --intermediate
```

This stores the segmentation masks (Breast ROI and FGT) in the output
directory for review.

---

## Updating to a new image version

When a new version of the tool is available on Harbor, remove the local image
first. The script prints the exact command when the image is already present:

```
[INFO] To force a fresh pull, remove the image first:
[INFO]   docker rmi harbor.eucaim.cancerimage.eu/processing-tools/eucaim-mr-bpe-quantification:1.0.0
```

After removing, the next run will pull the new version automatically.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `Container runtime not found: docker` | Install Docker or use `--runtime podman` |
| `Login failed` | Check your Harbor username and token |
| `Input directory does not exist` | Verify the path to your DICOM data |
| `results.csv missing or empty` | Check the terminal output for error messages |
| `Cannot connect to the Docker daemon` | Start the Docker service: `sudo systemctl start docker` |

---

## Limitations

- Input can be **either** a single DICOM case folder **or** a full EUCAIM CDM
  dataset described by an `imaging_mandatory_view.csv` (batch mode, see
  *Running multiple cases → Option B*).
- Each case must be a valid **DCE breast MRI** DICOM series with at least two
  temporal positions (pre- and post-contrast).
- **CPU-only** execution. No GPU required.
---

## Contact

```
Matute Flores, Jose Alejandro
Groth, Alexandra
```

---

*Use of this tool is governed by the `LICENSE.md` included in the delivery
package.*

