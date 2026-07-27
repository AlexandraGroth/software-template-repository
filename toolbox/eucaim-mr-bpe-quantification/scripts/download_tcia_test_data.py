# -*- coding: utf-8 -*-
"""
Download curated TCIA test data for EUCAIM MR BPE Quantification validation.

Purpose:
    Download a bounded, deterministic set of public TCIA DCE breast MRI cases
    (from the ACRIN-Contralateral-Breast-MR collection) so that the EUCAIM MR
    BPE Quantification container can be tested end-to-end without proprietary
    input data.

    The script intentionally uses a curated allowlist of pre-validated cases.
    This avoids unstable onboarding behavior caused by mixed TCIA series,
    multiple visits, non-DCE acquisitions, or changing API result order.

Usage:
    # Download one curated case (default) to ./third_party/tcia_test_data
    python scripts/download_tcia_test_data.py

    # Download up to ten curated cases
    python scripts/download_tcia_test_data.py --n_cases 10

    # Download one specific curated patient
    python scripts/download_tcia_test_data.py \\
        --patient_id ACRIN-Contralateral-Breast-MR-026

    # List curated cases without downloading
    python scripts/download_tcia_test_data.py --list_only

Prerequisites:
    pip install tcia_utils pandas

    No TCIA API key is required. ACRIN-Contralateral-Breast-MR is a public
    TCIA collection.

Outputs:
    <output_dir>/<patient_id>/          - one directory per downloaded case
        <series_uid>/                   - DICOM files for one curated DCE series

    After downloading, run the BPE container for each case:
        bash scripts/run_eucaim_mr_bpe_image.sh \\
            --input <output_dir>/<patient_id> \\
            --output <results_dir>/<patient_id>

Authors:
    Alexandra Groth
    Jose Alejandro Matute Flores

Copyright:
    Copyright (c) 2026 Philips GmbH Innovative Technologies.
    Use of this file is governed by the LICENSE.md included
    in the delivery package.
"""

import argparse
import logging
from pathlib import Path

import pandas as pd
from tcia_utils import nbia

# ============================================================
# HEADER: Constants
# ============================================================

# Default one case keeps the onboarding test small and fast.
DEFAULT_N_CASES = 1

# The onboarding package is intentionally capped to avoid uncontrolled public
# data downloads and to keep the validation set deterministic.
MAX_N_CASES = 10

# TCIA collection name for the curated breast DCE MRI cases.
# All curated cases below belong to the public ACRIN-Contralateral-Breast-MR
# collection on TCIA.
COLLECTION = "ACRIN-Contralateral-Breast-MR"

# Curated onboarding test cases. These cases are pinned by PatientID,
# StudyInstanceUID and SeriesInstanceUID and were selected from known-good
# validation material. The breast scores are included as traceability metadata.
KNOWN_GOOD_CASES = [
    {
        "patient_id": "ACRIN-Contralateral-Breast-MR-026",
        "study_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.169825170612900900773192349323",
        "series_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.902786320940367024222758357995",
        "left_breast": 1,
        "right_breast": 1,
    },
    {
        "patient_id": "ACRIN-Contralateral-Breast-MR-127",
        "study_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.210558543478614911978641780563",
        "series_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.276934798033622673688202989278",
        "left_breast": 0,
        "right_breast": 0,
    },
    {
        "patient_id": "ACRIN-Contralateral-Breast-MR-160",
        "study_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.87459228099656694369137021217",
        "series_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.321135818892279577030748505245",
        "left_breast": 2,
        "right_breast": 2,
    },
    {
        "patient_id": "ACRIN-Contralateral-Breast-MR-161",
        "study_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.607862446254824431491451476513",
        "series_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.165801406142560265128352183383",
        "left_breast": 0,
        "right_breast": 0,
    },
    {
        "patient_id": "ACRIN-Contralateral-Breast-MR-245",
        "study_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.169334440085333381303793130291",
        "series_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.257391624402017257262203646344",
        "left_breast": 3,
        "right_breast": 3,
    },
    {
        "patient_id": "ACRIN-Contralateral-Breast-MR-254",
        "study_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.374606207912694502148255781618",
        "series_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.656919838372772307143697507200",
        "left_breast": 2,
        "right_breast": 2,
    },
    {
        "patient_id": "ACRIN-Contralateral-Breast-MR-262",
        "study_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.121506178587308957707199611908",
        "series_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.105483105906238167946799472788",
        "left_breast": 2,
        "right_breast": 2,
    },
    {
        "patient_id": "ACRIN-Contralateral-Breast-MR-267",
        "study_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.279005417064175686015152969949",
        "series_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.122429092787679844383360974394",
        "left_breast": 0,
        "right_breast": 0,
    },
    {
        "patient_id": "ACRIN-Contralateral-Breast-MR-447",
        "study_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.228421555516430543034811747013",
        "series_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.194060709470700645395569476717",
        "left_breast": 3,
        "right_breast": 3,
    },
    {
        "patient_id": "ACRIN-Contralateral-Breast-MR-481",
        "study_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.196600902543556833715832741103",
        "series_uid": "1.3.6.1.4.1.14519.5.2.1.7009.2406.263826229036051837214763404486",
        "left_breast": 2,
        "right_breast": 2,
    },
]

# ============================================================
# HEADER: Logging configuration
# ============================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)


# ============================================================
# HEADER: Helper functions
# ============================================================

def curated_cases_as_dataframe() -> pd.DataFrame:
    """
    Return the curated onboarding cases as a DataFrame.

    Returns
    -------
    pd.DataFrame
        DataFrame with one row per curated case.
    """
    # Build a DataFrame from the hard-coded allowlist for uniform handling.
    return pd.DataFrame(KNOWN_GOOD_CASES)


def validate_n_cases(n_cases: int) -> None:
    """
    Validate requested onboarding case count.

    Parameters
    ----------
    n_cases : int
        Requested number of cases.
    """
    # A negative or zero case count is not a valid onboarding request.
    if n_cases < 1:
        raise ValueError("--n_cases must be at least 1.")

    # Cap the request to keep the onboarding download bounded and deterministic.
    if n_cases > MAX_N_CASES:
        raise ValueError(
            f"--n_cases={n_cases} is not supported. "
            f"The onboarding package is capped at {MAX_N_CASES} curated cases."
        )


def select_curated_cases(n_cases: int, patient_id: str | None = None) -> pd.DataFrame:
    """
    Select curated cases for download.

    Parameters
    ----------
    n_cases : int
        Number of curated cases to select when patient_id is not provided.
    patient_id : str or None
        Specific curated PatientID to select.

    Returns
    -------
    pd.DataFrame
        Selected curated cases.
    """
    # Start from the full curated allowlist.
    df = curated_cases_as_dataframe()

    if patient_id is not None:
        # Restrict the selection to a single curated patient.
        selected = df[df["patient_id"] == patient_id]
        # Reject any patient that is not part of the curated allowlist.
        if selected.empty:
            available = "\n".join(f"  {pid}" for pid in df["patient_id"].tolist())
            raise ValueError(
                f"Patient ID is not part of the curated onboarding set: {patient_id}\n"
                f"Available curated PatientIDs:\n{available}"
            )
        return selected

    # Validate the requested count before slicing the allowlist.
    validate_n_cases(n_cases)
    # Take the first N curated cases in their fixed, deterministic order.
    return df.head(n_cases)


def print_selected_cases(df_selected: pd.DataFrame) -> None:
    """
    Print selected curated cases.

    Parameters
    ----------
    df_selected : pd.DataFrame
        Selected curated cases.
    """
    # Print a human-readable summary of the curated cases about to be handled.
    print("\nSelected curated onboarding cases:")
    print("-" * 100)
    for _, row in df_selected.iterrows():
        print(f"  Patient: {row['patient_id']}")
        print(f"    StudyInstanceUID:  {row['study_uid']}")
        print(f"    SeriesInstanceUID: {row['series_uid']}")
        print(
            f"    Reference scores: Left Breast={row['left_breast']}  "
            f"Right Breast={row['right_breast']}"
        )
    print("-" * 100)


def download_series(series_uid: str, patient_dir: Path) -> None:
    """
    Download one DICOM series from TCIA into a per-patient directory.

    Parameters
    ----------
    series_uid : str
        SeriesInstanceUID to download.
    patient_dir : Path
        Directory under which tcia_utils creates a sub-folder named after the
        SeriesInstanceUID containing the DICOM files.
    """
    # Ensure the per-patient output directory exists before downloading.
    patient_dir.mkdir(parents=True, exist_ok=True)

    # tcia_utils downloads the series into <patient_dir>/<series_uid>/ and
    # handles the zip download and extraction internally.
    logging.info(f"  Downloading series {series_uid} -> {patient_dir}")
    nbia.downloadSeries(
        [series_uid],
        input_type="list",
        path=str(patient_dir),
    )
    logging.info(f"  Downloaded {series_uid}.")


# ============================================================
# HEADER: Main download workflow
# ============================================================

def download_test_cases(
    n_cases: int,
    output_dir: Path,
    list_only: bool = False,
    patient_id: str | None = None,
) -> None:
    """
    Download curated TCIA DCE breast MRI cases for BPE testing.

    Parameters
    ----------
    n_cases : int
        Number of curated patient cases to download.
    output_dir : Path
        Root directory where downloaded cases will be stored.
    list_only : bool
        If True, print curated cases without downloading.
    patient_id : str or None
        If provided, download only this specific curated patient and ignore
        n_cases.
    """
    # Resolve which curated cases to work with (raises on invalid requests).
    df_selected = select_curated_cases(n_cases=n_cases, patient_id=patient_id)

    logging.info(
        f"Selected {len(df_selected)} curated patient(s) from TCIA collection {COLLECTION}."
    )
    print_selected_cases(df_selected)

    # In list-only mode we stop before performing any network download.
    if list_only:
        logging.info("--list_only set - skipping download.")
        return

    # Ensure the root output directory exists.
    output_dir.mkdir(parents=True, exist_ok=True)

    # Download each curated case by its pinned SeriesInstanceUID.
    for _, row in df_selected.iterrows():
        patient = row["patient_id"]
        series_uid = row["series_uid"]
        patient_dir = output_dir / patient

        logging.info(f"Downloading curated patient: {patient}")
        download_series(series_uid=series_uid, patient_dir=patient_dir)
        logging.info(f"Patient {patient} downloaded to: {patient_dir}")

    # Print ready-to-run instructions for each downloaded case.
    print("\nDownload complete. Run the BPE container for each case:")
    print("-" * 100)
    for _, row in df_selected.iterrows():
        patient = row["patient_id"]
        print(
            f"  bash scripts/run_eucaim_mr_bpe_image.sh \\\n"
            f"    --input {output_dir / patient} \\\n"
            f"    --output {output_dir / (patient + '_results')}\n"
        )
    print("-" * 100)


# ============================================================
# HEADER: Command-line entry point
# ============================================================

def main() -> None:
    """Parse command-line arguments and run the download workflow."""
    parser = argparse.ArgumentParser(
        description=(
            "Download curated TCIA DCE breast MRI test cases for "
            "EUCAIM MR BPE Quantification validation."
        )
    )
    parser.add_argument(
        "--n_cases",
        "--n-cases",
        dest="n_cases",
        type=int,
        default=DEFAULT_N_CASES,
        help=(
            f"Number of curated patient cases to download "
            f"(default: {DEFAULT_N_CASES}, maximum: {MAX_N_CASES})."
        ),
    )
    parser.add_argument(
        "--output_dir",
        "--output-dir",
        dest="output_dir",
        type=Path,
        default=Path("third_party/tcia_test_data"),
        help=(
            "Root output directory for downloaded DICOM data "
            "(default: ./third_party/tcia_test_data). "
            "This path is excluded from Git via .gitignore."
        ),
    )
    parser.add_argument(
        "--list_only",
        "--list-only",
        dest="list_only",
        action="store_true",
        help="List curated onboarding cases without downloading.",
    )
    parser.add_argument(
        "--patient_id",
        "--patient-id",
        dest="patient_id",
        type=str,
        default=None,
        help=(
            "Download a specific curated PatientID instead of the first N cases. "
            "Use --list_only to see available curated PatientIDs."
        ),
    )

    args = parser.parse_args()

    logging.info(
        f"n_cases={args.n_cases}  output_dir={args.output_dir}  "
        f"list_only={args.list_only}  patient_id={args.patient_id}"
    )

    download_test_cases(
        n_cases=args.n_cases,
        output_dir=args.output_dir,
        list_only=args.list_only,
        patient_id=args.patient_id,
    )


if __name__ == "__main__":
    main()

