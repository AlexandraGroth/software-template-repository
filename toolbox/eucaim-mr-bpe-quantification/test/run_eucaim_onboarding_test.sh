#!/usr/bin/env bash
# =============================================================================
# HEADER: run_eucaim_onboarding_test.sh
#
# Purpose:
#   End-to-end onboarding validation test for the EUCAIM MR BPE Quantification
#   container. Intended for use by the EUCAIM onboarding board to verify that
#   the container image functions correctly before platform integration.
#
#   The test performs the following steps:
#     1. Check prerequisites (container runtime, Python, tcia_utils).
#     2. Use the curated TCIA test data if it is already present locally; only if
#        it is missing, download it (curated ACRIN-Contralateral-Breast-MR
#        cases).
#     3. Pull the BPE container image from Harbor (interactive login if needed).
#     4. For each case, run the full BPE pipeline and validate the output
#        results.csv.
#     5. Print a consolidated test summary.
#
# Usage:
#   bash test/run_eucaim_onboarding_test.sh
#
# Prerequisites:
#   - Docker or Podman installed and available.
#   - Python 3 with tcia_utils and pandas installed:
#       pip install -r requirements-dev.txt
#   - Network access to harbor.eucaim.cancerimage.eu and nbia.cancer.gov (TCIA).
#   - Harbor credentials (entered interactively when prompted).
#
# Environment variables (all optional, defaults shown):
#   CONTAINER_RUNTIME   Container runtime to use (docker or podman)
#                       Default: docker
#   APP_IMAGE           BPE container image reference
#                       Default: harbor.eucaim.cancerimage.eu/processing-tools/eucaim-mr-bpe-quantification:1.0.0
#   TCIA_DATA_DIR       Directory where the curated TCIA test data is stored.
#                       Reused if already present; downloaded if missing.
#                       Default: third_party/tcia_test_data
#   RESULTS_DIR         Directory where BPE results are written
#                       Default: /tmp/eucaim_onboarding_results
#   N_CASES             Number of curated TCIA cases to download and test
#                       Default: 1 (sufficient for functional validation)
#   BPE_TOLERANCE       Allowed absolute BPE% deviation from the recorded
#                       baseline for curated cases before a regression failure.
#                       Default: 1.0
#   FORCE_DOWNLOAD      Set to 1 to re-download the curated TCIA data even if it
#                       is already present locally.
#                       Default: 0
#
# Outputs:
#   ${RESULTS_DIR}/<patient_id>/results.csv  — BPE result per case
#   Consolidated pass/fail summary printed at the end.
#
# :Authors:   Alexandra Groth
#             Jose Alejandro Matute Flores
#
# :Copyright: Copyright (c) 2026 Philips GmbH Innovative Technologies.
#             Use of this file is governed by the LICENSE.md included
#             in the delivery package.
# =============================================================================

set -euo pipefail

# ============================================================
# HEADER: Configuration
# ============================================================

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-docker}"
APP_IMAGE="${APP_IMAGE:-harbor.eucaim.cancerimage.eu/processing-tools/eucaim-mr-bpe-quantification:1.0.0}"
# Location of the curated TCIA test data. It is reused if already present and
# downloaded only when missing.
TCIA_DATA_DIR="${TCIA_DATA_DIR:-third_party/tcia_test_data}"
RESULTS_DIR="${RESULTS_DIR:-/tmp/eucaim_onboarding_results}"
N_CASES="${N_CASES:-1}"
FORCE_DOWNLOAD="${FORCE_DOWNLOAD:-0}"


# Expected BPE% per curated case (regression baseline).
# These values were produced by running the curated ACRIN-Contralateral-Breast-MR
# cases through the BPE container (image tag 1.0.0) and recorded as the reference
# baseline. When a curated case is tested, its measured BPE% must match the
# expected value within BPE_TOLERANCE. Cases without an entry here only undergo
# the generic plausibility check.
declare -A EXPECTED_BPE=(
    [ACRIN-Contralateral-Breast-MR-026]=61.58
    [ACRIN-Contralateral-Breast-MR-127]=79.13
    [ACRIN-Contralateral-Breast-MR-160]=60.27
    [ACRIN-Contralateral-Breast-MR-161]=61.05
    [ACRIN-Contralateral-Breast-MR-245]=78.99
    [ACRIN-Contralateral-Breast-MR-254]=80.20
    [ACRIN-Contralateral-Breast-MR-262]=57.65
    [ACRIN-Contralateral-Breast-MR-267]=43.42
    [ACRIN-Contralateral-Breast-MR-447]=80.36
    [ACRIN-Contralateral-Breast-MR-481]=64.80
)

# Allowed absolute deviation (in BPE percentage points) between the measured and
# the expected BPE% before a curated case is treated as a regression failure.
BPE_TOLERANCE="${BPE_TOLERANCE:-1.0}"

# Resolve script location so the test can be run from any directory.
# This must happen before VENV_DIR is derived from REPO_ROOT below.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Virtual environment for Python dependencies.
# Created automatically if it does not exist — keeps the system Python clean.
# Stored under the repo root so it can be reused across test runs.
VENV_DIR="${VENV_DIR:-${REPO_ROOT}/.venv_onboarding}"
VENV_CREATED=0


# ============================================================
# HEADER: Utility functions
# ============================================================

log_header() {
    # Print a visible section header to stdout.
    echo
    echo "============================================================"
    echo "  $1"
    echo "============================================================"
}

log_info() {
    echo "[INFO] $*"
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

die() {
    log_error "$*"
    exit 1
}

# ============================================================
# HEADER: Check prerequisites
# ============================================================

log_header "Step 1 — Check prerequisites"

# Verify container runtime is available.
command -v "${CONTAINER_RUNTIME}" >/dev/null 2>&1 \
    || die "Container runtime not found: ${CONTAINER_RUNTIME}. Install Docker or Podman."
log_info "Container runtime: ${CONTAINER_RUNTIME} ($(${CONTAINER_RUNTIME} --version 2>&1 | head -1))"

# Verify Python 3 is available.
command -v python3 >/dev/null 2>&1 \
    || die "python3 not found. Please install Python 3."
log_info "Python: $(python3 --version)"

# Create and activate a virtual environment to keep the system Python clean.
# If the venv already exists it is reused — no reinstall needed.
if [ ! -d "${VENV_DIR}" ]; then
    log_info "Creating virtual environment: ${VENV_DIR}"
    python3 -m venv "${VENV_DIR}"
    VENV_CREATED=1
else
    log_info "Reusing existing virtual environment: ${VENV_DIR}"
fi

# Activate the virtual environment.
# shellcheck source=/dev/null
source "${VENV_DIR}/bin/activate"
log_info "Virtual environment activated."

# Check if required Python packages are installed inside the venv.
# Install automatically if missing — no user prompt needed since we are in a venv.
MISSING_DEPS=0
python3 -c "from tcia_utils import nbia" 2>/dev/null || MISSING_DEPS=1
python3 -c "import pandas" 2>/dev/null || MISSING_DEPS=1

if [ "${MISSING_DEPS}" -eq 1 ]; then
    log_info "Installing required Python packages into virtual environment ..."
    pip install -r "${REPO_ROOT}/requirements-dev.txt" \
        || die "pip install failed. Please check your network connection and try again."
    log_info "Installation complete."
fi

# Verify packages are now available.
python3 -c "from tcia_utils import nbia" 2>/dev/null \
    || die "tcia_utils still not available after install attempt."
log_info "tcia_utils: OK"

python3 -c "import pandas" 2>/dev/null \
    || die "pandas still not available after install attempt."
log_info "pandas: OK"

log_info "All prerequisites satisfied."

# ============================================================
# HEADER: Provide curated TCIA test data
# ============================================================

log_header "Step 2 — Provide curated TCIA test data (reuse if present, else download)"

cd "${REPO_ROOT}"

TCIA_DATA_DIR_ABS="$(realpath -m "${TCIA_DATA_DIR}")"

# Count how many curated case directories already exist locally.
# Each case is one sub-directory (one patient) under TCIA_DATA_DIR.
EXISTING_CASES=0
if [ -d "${TCIA_DATA_DIR_ABS}" ]; then
    EXISTING_CASES="$(find "${TCIA_DATA_DIR_ABS}" -mindepth 1 -maxdepth 1 -type d | wc -l)"
fi

if [ "${FORCE_DOWNLOAD}" -eq 1 ]; then
    # Force a fresh download of the curated data.
    log_info "FORCE_DOWNLOAD=1 — downloading ${N_CASES} curated TCIA case(s) to: ${TCIA_DATA_DIR_ABS}"
    python3 scripts/download_tcia_test_data.py \
        --n_cases "${N_CASES}" \
        --output_dir "${TCIA_DATA_DIR_ABS}"
elif [ "${EXISTING_CASES}" -gt 0 ]; then
    # Standard case: curated data already downloaded from a previous run.
    log_info "Found ${EXISTING_CASES} curated case(s) in ${TCIA_DATA_DIR_ABS} — reusing, skipping download."
else
    # Curated data not present yet: download it now.
    log_info "No curated data found in ${TCIA_DATA_DIR_ABS} — downloading ${N_CASES} curated TCIA case(s)."
    python3 scripts/download_tcia_test_data.py \
        --n_cases "${N_CASES}" \
        --output_dir "${TCIA_DATA_DIR_ABS}"
fi

# Collect patient directories — one per case.
mapfile -t PATIENT_DIRS < <(find "${TCIA_DATA_DIR_ABS}" -mindepth 1 -maxdepth 1 -type d | sort)

[ "${#PATIENT_DIRS[@]}" -gt 0 ] \
    || die "No patient directories found in: ${TCIA_DATA_DIR_ABS}"

log_info "Found ${#PATIENT_DIRS[@]} patient case(s) to test."

# ============================================================
# HEADER: Run BPE container for each case
# ============================================================

log_header "Step 3 — Run BPE container for each case"

mkdir -p "${RESULTS_DIR}"

# Track pass/fail per case for the final summary.
PASSED=()
FAILED=()

FIRST_CASE=1

for PATIENT_DIR in "${PATIENT_DIRS[@]}"; do
    PATIENT_ID="$(basename "${PATIENT_DIR}")"
    OUTPUT_DIR="${RESULTS_DIR}/${PATIENT_ID}"

    log_info "Processing case: ${PATIENT_ID}"
    log_info "  Input:  ${PATIENT_DIR}"
    log_info "  Output: ${OUTPUT_DIR}"

    # Run CLI-check and mount-check only on the first case to validate the
    # container contract once — skip on subsequent cases to save time.
    EXTRA_ARGS=()
    if [ "${FIRST_CASE}" -eq 1 ]; then
        log_info "  Running full validation (CLI-check + mount-check) on first case."
        FIRST_CASE=0
    else
        EXTRA_ARGS+=(--no-cli-check --no-mount-check)
    fi

    # Run the BPE container via the shared run script.
    set +e
    bash scripts/run_eucaim_mr_bpe_image.sh \
        --runtime "${CONTAINER_RUNTIME}" \
        --image "${APP_IMAGE}" \
        --input "${PATIENT_DIR}" \
        --output "${OUTPUT_DIR}" \
        "${EXTRA_ARGS[@]}"
    RUN_EXIT=$?
    set -e

    if [ "${RUN_EXIT}" -ne 0 ]; then
        log_error "  BPE run FAILED for case: ${PATIENT_ID} (exit code ${RUN_EXIT})"
        FAILED+=("${PATIENT_ID}")
        continue
    fi

    # Validate that results.csv was generated and is non-empty.
    RESULTS_CSV="${OUTPUT_DIR}/results.csv"
    if [ ! -s "${RESULTS_CSV}" ]; then
        log_error "  results.csv missing or empty for case: ${PATIENT_ID}"
        FAILED+=("${PATIENT_ID}")
        continue
    fi

    # Print the result row for this case.
    log_info "  results.csv:"
    sed -n '1,5p' "${RESULTS_CSV}" | sed 's/^/    /'

    # Basic plausibility check — BPE% must be a number between 0 and 100.
    BPE_VALUE="$(python3 -c "
import pandas as pd, sys
df = pd.read_csv('${RESULTS_CSV}')
if 'BPE%' not in df.columns:
    print('MISSING_COLUMN')
    sys.exit(1)
val = float(df['BPE%'].iloc[0])
if val < 0 or val > 100:
    print(f'OUT_OF_RANGE:{val}')
    sys.exit(1)
print(f'{val:.2f}')
" 2>&1)"

    # The BPE% must first be a valid number in range.
    if ! echo "${BPE_VALUE}" | grep -qE "^[0-9]+\.[0-9]+$"; then
        log_error "  BPE% plausibility check FAILED: ${BPE_VALUE}"
        FAILED+=("${PATIENT_ID}")
        continue
    fi
    log_info "  BPE% = ${BPE_VALUE} — plausibility check PASSED"

    # Regression check: if this is a curated case with a known expected value,
    # the measured BPE% must match the baseline within BPE_TOLERANCE.
    EXPECTED="${EXPECTED_BPE[${PATIENT_ID}]:-}"
    if [ -n "${EXPECTED}" ]; then
        # Compare with tolerance using python for reliable float arithmetic.
        MATCH="$(python3 -c "
import sys
measured = float('${BPE_VALUE}')
expected = float('${EXPECTED}')
tol = float('${BPE_TOLERANCE}')
print('OK' if abs(measured - expected) <= tol else 'MISMATCH')
")"
        if [ "${MATCH}" = "OK" ]; then
            log_info "  BPE% regression check PASSED (expected ${EXPECTED} ± ${BPE_TOLERANCE})"
            PASSED+=("${PATIENT_ID} BPE%=${BPE_VALUE} (expected ${EXPECTED})")
        else
            log_error "  BPE% regression check FAILED: measured ${BPE_VALUE}, expected ${EXPECTED} ± ${BPE_TOLERANCE}"
            FAILED+=("${PATIENT_ID} BPE%=${BPE_VALUE} (expected ${EXPECTED})")
        fi
    else
        # No baseline recorded for this case — plausibility check only.
        log_info "  No BPE% baseline for ${PATIENT_ID} — plausibility check only."
        PASSED+=("${PATIENT_ID} BPE%=${BPE_VALUE}")
    fi
done

# ============================================================
# HEADER: Test summary
# ============================================================

log_header "Onboarding test summary"

echo
echo "  Cases passed: ${#PASSED[@]}"
for item in "${PASSED[@]}"; do
    echo "    PASS  ${item}"
done

echo
echo "  Cases failed: ${#FAILED[@]}"
for item in "${FAILED[@]}"; do
    echo "    FAIL  ${item}"
done

echo
echo "  Image tested: ${APP_IMAGE}"
echo "  Results:      ${RESULTS_DIR}"
echo

if [ "${#FAILED[@]}" -gt 0 ]; then
    log_error "Onboarding test FAILED — ${#FAILED[@]} case(s) did not pass."
    # Run cleanup even on failure so the user can decide what to keep.
    TEST_FAILED=1
else
    log_info "Onboarding test PASSED — all ${#PASSED[@]} case(s) completed successfully."
    TEST_FAILED=0
fi

# ============================================================
# HEADER: Optional cleanup
# ============================================================
#
# Cleanup is opt-in and safe by default:
#   - On an interactive terminal the user is asked per resource (default: keep).
#   - Non-interactively (CI, pipe, nohup) nothing is removed unless an override
#     is set, so the script never blocks on a prompt or aborts on EOF.
#
# Environment overrides (optional):
#   AUTO_CLEANUP=1        Remove every resource without prompting.
#   CLEANUP_TCIA=1|0      Force remove/keep the TCIA test data.
#   CLEANUP_RESULTS=1|0   Force remove/keep the BPE results.
#   CLEANUP_IMAGE=1|0     Force remove/keep the container image.
#   CLEANUP_VENV=1|0      Force remove/keep the virtual environment.

# Decide whether a resource should be removed.
# Priority: AUTO_CLEANUP > explicit per-resource override > interactive prompt
# > default keep (non-interactive).
should_remove() {
    local prompt="$1"
    local override="$2"

    # Global auto-cleanup forces removal of every resource.
    if [ "${AUTO_CLEANUP:-0}" = "1" ]; then
        return 0
    fi

    # Explicit per-resource override (1 = remove, 0 = keep).
    if [ "${override}" = "1" ]; then
        return 0
    fi
    if [ "${override}" = "0" ]; then
        return 1
    fi

    # Prompt only when attached to an interactive terminal.
    if [ -t 0 ]; then
        local answer
        read -rp "${prompt} [y/N] " answer
        [[ "${answer}" =~ ^[Yy]$ ]] && return 0
        return 1
    fi

    # Non-interactive and no override — keep the resource.
    return 1
}

echo
echo "Cleanup options:"
echo "  [1] TCIA test data:  ${TCIA_DATA_DIR_ABS}  (~several GB)"
echo "  [2] BPE results:     ${RESULTS_DIR}"
echo "  [3] Container image: ${APP_IMAGE}"
echo "  [4] Virtual environment: ${VENV_DIR}"
echo

if should_remove "Remove TCIA test data?" "${CLEANUP_TCIA:-}"; then
    log_info "Removing TCIA test data: ${TCIA_DATA_DIR_ABS}"
    rm -rf "${TCIA_DATA_DIR_ABS}"
    log_info "TCIA test data removed."
else
    log_info "TCIA test data kept: ${TCIA_DATA_DIR_ABS}"
fi

if should_remove "Remove BPE results?" "${CLEANUP_RESULTS:-}"; then
    log_info "Removing BPE results: ${RESULTS_DIR}"
    rm -rf "${RESULTS_DIR}"
    log_info "BPE results removed."
else
    log_info "BPE results kept: ${RESULTS_DIR}"
fi

if should_remove "Remove container image from local storage?" "${CLEANUP_IMAGE:-}"; then
    log_info "Removing container image: ${APP_IMAGE}"
    "${CONTAINER_RUNTIME}" rmi "${APP_IMAGE}" 2>/dev/null || true
    log_info "Container image removed."
else
    log_info "Container image kept: ${APP_IMAGE}"
fi

if should_remove "Remove virtual environment?" "${CLEANUP_VENV:-}"; then
    # Deactivate before removing.
    deactivate 2>/dev/null || true
    log_info "Removing virtual environment: ${VENV_DIR}"
    rm -rf "${VENV_DIR}"
    log_info "Virtual environment removed."
else
    log_info "Virtual environment kept: ${VENV_DIR}"
    log_info "To reuse it next time: source ${VENV_DIR}/bin/activate"
fi

log_info "Cleanup complete."

# Exit with failure code if the test failed.
if [ "${TEST_FAILED}" -eq 1 ]; then
    log_error "Onboarding test FAILED — see errors above."
    exit 1
fi

log_info "Onboarding test PASSED."




