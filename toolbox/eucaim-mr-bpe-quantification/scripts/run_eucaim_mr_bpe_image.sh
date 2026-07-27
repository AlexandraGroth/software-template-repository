#!/usr/bin/env bash
# =============================================================================
# HEADER: run_eucaim_mr_bpe_image.sh
#
# Purpose:
#   Execute the EUCAIM MR BPE Quantification container after Harbor pull,
#   local image load or local image build. Assembles the container run command
#   from configurable options, optionally validates the CLI and mount contract,
#   and checks that the expected output file was generated.
#
# Usage:
#   bash scripts/run_eucaim_mr_bpe_image.sh [options] [-- custom-app-args...]
#
# Typical Harbor usage:
#   bash scripts/run_eucaim_mr_bpe_image.sh --input /path/to/dicom_case
#
# Typical local image usage:
#   bash scripts/run_eucaim_mr_bpe_image.sh \
#     --image eucaim-mr-bpe-quantification:1.0.0 \
#     --input /path/to/dicom_case
#
# Typical local archive usage:
#   bash scripts/run_eucaim_mr_bpe_image.sh \
#     --image-tar release/eucaim-mr-bpe-quantification-1.0.0.docker.tar \
#     --image eucaim-mr-bpe-quantification:1.0.0 \
#     --input /path/to/dicom_case
#
# Custom application arguments:
#   bash scripts/run_eucaim_mr_bpe_image.sh \
#     --input /path/to/dicom_case \
#     -- \
#     --input /input --output /output --noregister --threshold 20 --intermediate
#
# Key options:
#   --input DIR            Host input directory (required)
#   --output DIR           Host output directory
#   --image IMAGE          Container image reference
#   --image-tar FILE       Load image from local archive before running
#   --noregister           Skip registration (default)
#   --register             Enable registration
#   --threshold VALUE      Signal enhancement threshold (default: application default)
#   --intermediate         Store intermediate volumes in /output
#   --useintermediate      Reuse intermediate volumes from /output
#   --dry-run              Print command without executing
#   --help                 Show full usage
#
# Environment variables (all optional, defaults shown):
#   CONTAINER_RUNTIME      Container runtime (podman or docker)
#                          Default: docker
#   APP_IMAGE              Image reference to run
#                          Default: harbor.eucaim.cancerimage.eu/processing-tools/eucaim-mr-bpe-quantification:1.0.0
#   IMAGE_TAR              Path to a local image archive to load first
#   INPUT_DIR              Host input directory
#   OUTPUT_DIR             Host output directory
#                          Default: ./eucaim_mr_bpe_run/out
#   HARBOR_REGISTRY        Harbor registry hostname
#                          Default: harbor.eucaim.cancerimage.eu
#   HARBOR_PROJECT         Harbor project name
#                          Default: processing-tools
#   HARBOR_USER            Harbor username for login (optional)
#   HARBOR_TOKEN           Harbor access token for login (optional)
#   STORAGE_BASE           Base directory for Podman overlay storage
#                          Default: /tmp/<username>/podman-overlay-storage
#   PODMAN_ROOT            Podman root storage directory
#   PODMAN_RUN             Podman run directory
#
# Outputs:
#   ${OUTPUT_DIR}/results.csv  — BPE quantification results table
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
# HEADER: Defaults
# ============================================================

TOOL_NAME="${TOOL_NAME:-eucaim-mr-bpe-quantification}"
IMAGE_VERSION="${IMAGE_VERSION:-1.0.0}"

HARBOR_REGISTRY="${HARBOR_REGISTRY:-harbor.eucaim.cancerimage.eu}"
HARBOR_PROJECT="${HARBOR_PROJECT:-processing-tools}"
DEFAULT_HARBOR_IMAGE="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${TOOL_NAME}:${IMAGE_VERSION}"
DEFAULT_LOCAL_IMAGE="${TOOL_NAME}:${IMAGE_VERSION}"

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-docker}"

APP_IMAGE_WAS_SET=0
if [ -n "${APP_IMAGE:-}" ]; then
    APP_IMAGE_WAS_SET=1
fi

APP_IMAGE="${APP_IMAGE:-${DEFAULT_HARBOR_IMAGE}}"
IMAGE_TAR="${IMAGE_TAR:-}"

INPUT_DIR="${INPUT_DIR:-}"
OUTPUT_DIR="${OUTPUT_DIR:-${PWD}/eucaim_mr_bpe_run/out}"

# Application arguments
USE_NOREGISTER="${USE_NOREGISTER:-1}"
THRESHOLD="${THRESHOLD:-}"
RUN_INTERMEDIATE="${RUN_INTERMEDIATE:-0}"
RUN_USEINTERMEDIATE="${RUN_USEINTERMEDIATE:-0}"

# Runtime behavior
PULL_IF_MISSING="${PULL_IF_MISSING:-1}"
LOGIN_IF_TOKEN="${LOGIN_IF_TOKEN:-1}"
NO_NETWORK="${NO_NETWORK:-1}"
CLEAN_OUTPUT="${CLEAN_OUTPUT:-1}"
CLEAN_OUTPUT_WAS_SET=0

# Validation behavior
CLI_CHECK="${CLI_CHECK:-1}"
STRICT_CLI_CHECK="${STRICT_CLI_CHECK:-0}"
MOUNT_CHECK="${MOUNT_CHECK:-1}"
OUTPUT_CHECK="${OUTPUT_CHECK:-1}"
EXPECTED_OUTPUT="${EXPECTED_OUTPUT:-results.csv}"
DRY_RUN="${DRY_RUN:-0}"

# Podman storage configuration, aligned with the existing build/test scripts
USER_NAME="${USER:-$(id -un)}"
STORAGE_BASE="${STORAGE_BASE:-/tmp/${USER_NAME}/podman-overlay-storage}"
PODMAN_ROOT="${PODMAN_ROOT:-${STORAGE_BASE}/root}"
PODMAN_RUN="${PODMAN_RUN:-${STORAGE_BASE}/run}"

CUSTOM_APP_ARGS=()

# ============================================================
# HEADER: Utility functions
# ============================================================

print_usage() {
    cat <<'EOF'
Usage:
  run_eucaim_mr_bpe_image.sh [options] [-- custom-app-args...]

Image source options:
  --image IMAGE            Container image reference to run.
                           Default:
                           harbor.eucaim.cancerimage.eu/processing-tools/eucaim-mr-bpe-quantification:1.0.0

  --image-tar FILE         Optional Docker-compatible image archive to load first.
                           Use only when testing a delivered .docker.tar package.

  --pull                   Pull the image if it is missing locally.
                           Default behavior.

  --no-pull                Do not pull the image if it is missing locally.

  --harbor-login           If HARBOR_USER and HARBOR_TOKEN are set, login before pulling.
                           Default behavior.

  --no-harbor-login        Do not attempt Harbor login.

Execution options:
  --input DIR              Host input directory containing one DICOM case or series.
                           Required unless INPUT_DIR is set.

  --output DIR             Host output directory.
                           Default: ./eucaim_mr_bpe_run/out

  --runtime podman|docker  Container runtime.
                           Default: docker

  --noregister             Pass --noregister to the application.
                           Default behavior for EUCAIM runtime execution.

  --register               Do not pass --noregister.

  --threshold VALUE        Pass --threshold VALUE to the application.
                           If omitted, the application default is used.

  --intermediate           Pass --intermediate to store intermediate volumes in /output.

  --useintermediate        Pass --useintermediate to reuse intermediate volumes from /output.
                           This automatically keeps the existing output directory.

  --allow-network          Do not disable networking inside the container.
                           Default: container network disabled.

  --keep-output            Do not delete the output directory before execution.

  --clean-output           Delete the output directory before execution.
                           Default behavior, except with --useintermediate.

Validation options:
  --cli-check              Check application --help before execution.
                           Default behavior.

  --no-cli-check           Skip CLI help check.

  --strict-cli-check       Require all documented CLI options in --help:
                           --input, --output, --noregister, --threshold,
                           --intermediate, --useintermediate.

  --no-mount-check         Skip mount and embedded model check.

  --expected-output FILE   Expected output file relative to /output.
                           Default: results.csv

  --no-output-check        Do not validate the expected output file.

  --dry-run                Print the container command but do not execute it.

  -h, --help               Show this help.

Custom application arguments:
  Everything after "--" replaces the automatically assembled app arguments.

Examples:
  # 1) Pull from Harbor if missing, then run with EUCAIM defaults:
  bash scripts/run_eucaim_mr_bpe_image.sh \
    --input /data/case01

  # 2) Use a local image tag:
  bash scripts/run_eucaim_mr_bpe_image.sh \
    --image eucaim-mr-bpe-quantification:1.0.0 \
    --input /data/case01 \
    --output ./out

  # 3) Custom threshold and intermediate export:
  bash scripts/run_eucaim_mr_bpe_image.sh \
    --input /data/case01 \
    --threshold 20 \
    --intermediate

  # 4) Run without --noregister:
  bash scripts/run_eucaim_mr_bpe_image.sh \
    --input /data/case01 \
    --register

  # 5) Full manual app arguments:
  bash scripts/run_eucaim_mr_bpe_image.sh \
    --input /data/case01 \
    -- \
    --input /input --output /output --noregister --threshold 20
EOF
}

log_header() {
    echo
    echo "============================================================"
    echo "HEADER: $1"
    echo "============================================================"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

print_shell_command() {
    printf '  %q' "$@"
    echo
}

# ============================================================
# HEADER: Parse arguments
# ============================================================

while [ "$#" -gt 0 ]; do
    case "$1" in
        --image)
            [ "$#" -ge 2 ] || die "--image requires a value"
            APP_IMAGE="$2"
            APP_IMAGE_WAS_SET=1
            shift 2
            ;;
        --image-tar)
            [ "$#" -ge 2 ] || die "--image-tar requires a value"
            IMAGE_TAR="$2"
            shift 2
            ;;
        --pull)
            PULL_IF_MISSING=1
            shift
            ;;
        --no-pull)
            PULL_IF_MISSING=0
            shift
            ;;
        --harbor-login)
            LOGIN_IF_TOKEN=1
            shift
            ;;
        --no-harbor-login)
            LOGIN_IF_TOKEN=0
            shift
            ;;
        --input)
            [ "$#" -ge 2 ] || die "--input requires a value"
            INPUT_DIR="$2"
            shift 2
            ;;
        --output)
            [ "$#" -ge 2 ] || die "--output requires a value"
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --runtime)
            [ "$#" -ge 2 ] || die "--runtime requires a value"
            CONTAINER_RUNTIME="$2"
            shift 2
            ;;
        --noregister)
            USE_NOREGISTER=1
            shift
            ;;
        --register)
            USE_NOREGISTER=0
            shift
            ;;
        --threshold)
            [ "$#" -ge 2 ] || die "--threshold requires a value"
            THRESHOLD="$2"
            shift 2
            ;;
        --intermediate)
            RUN_INTERMEDIATE=1
            shift
            ;;
        --useintermediate)
            RUN_USEINTERMEDIATE=1
            if [ "${CLEAN_OUTPUT_WAS_SET}" -eq 0 ]; then
                CLEAN_OUTPUT=0
            fi
            shift
            ;;
        --allow-network)
            NO_NETWORK=0
            shift
            ;;
        --keep-output)
            CLEAN_OUTPUT=0
            CLEAN_OUTPUT_WAS_SET=1
            shift
            ;;
        --clean-output)
            CLEAN_OUTPUT=1
            CLEAN_OUTPUT_WAS_SET=1
            shift
            ;;
        --cli-check)
            CLI_CHECK=1
            shift
            ;;
        --no-cli-check)
            CLI_CHECK=0
            shift
            ;;
        --strict-cli-check)
            STRICT_CLI_CHECK=1
            CLI_CHECK=1
            shift
            ;;
        --no-mount-check)
            MOUNT_CHECK=0
            shift
            ;;
        --expected-output)
            [ "$#" -ge 2 ] || die "--expected-output requires a value"
            EXPECTED_OUTPUT="$2"
            shift 2
            ;;
        --no-output-check)
            OUTPUT_CHECK=0
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        --)
            shift
            CUSTOM_APP_ARGS=("$@")
            break
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

# ============================================================
# HEADER: Validate configuration
# ============================================================

case "${CONTAINER_RUNTIME}" in
    podman|docker)
        ;;
    *)
        die "Unsupported container runtime: ${CONTAINER_RUNTIME}"
        ;;
esac

command -v "${CONTAINER_RUNTIME}" >/dev/null 2>&1 || die "Container runtime not found: ${CONTAINER_RUNTIME}"

[ -n "${INPUT_DIR}" ] || die "Input directory is required. Use --input DIR or set INPUT_DIR."
[ -d "${INPUT_DIR}" ] || die "Input directory does not exist: ${INPUT_DIR}"

if [ -n "${THRESHOLD}" ] && ! [[ "${THRESHOLD}" =~ ^[0-9]+$ ]]; then
    die "Threshold must be an integer: ${THRESHOLD}"
fi

if [ "${RUN_INTERMEDIATE}" -eq 1 ] && [ "${RUN_USEINTERMEDIATE}" -eq 1 ]; then
    die "--intermediate and --useintermediate should not be used in the same run."
fi

if [ -n "${IMAGE_TAR}" ]; then
    [ -s "${IMAGE_TAR}" ] || die "Image archive is missing or empty: ${IMAGE_TAR}"

    if [ "${APP_IMAGE_WAS_SET}" -eq 0 ]; then
        APP_IMAGE="${DEFAULT_LOCAL_IMAGE}"
    fi
fi

# ============================================================
# HEADER: Configure runtime command
# ============================================================

if [ "${CONTAINER_RUNTIME}" = "podman" ]; then
    mkdir -p "${PODMAN_ROOT}" "${PODMAN_RUN}"
    RUNTIME_CMD=(
        podman
        --storage-driver overlay
        --root "${PODMAN_ROOT}"
        --runroot "${PODMAN_RUN}"
    )
else
    RUNTIME_CMD=(docker)
fi

container_image_exists() {
    # Check whether the image is available in the local storage only.
    # Use 'image inspect' for both runtimes to avoid podman resolving
    # the image from a remote registry when using 'image exists'.
    # The '|| true' is intentional: set -e must not abort on a failed inspect.
    local image="$1"
    local result
    result="$("${RUNTIME_CMD[@]}" image inspect "${image}" --format "{{.Id}}" 2>/dev/null || true)"
    [ -n "${result}" ]
}

container_load_image() {
    local archive="$1"
    "${RUNTIME_CMD[@]}" load -i "${archive}"
}

container_pull_image() {
    local image="$1"
    "${RUNTIME_CMD[@]}" pull "${image}"
}

maybe_harbor_login() {
    if [ "${LOGIN_IF_TOKEN}" -ne 1 ]; then
        return 0
    fi

    case "${APP_IMAGE}" in
        "${HARBOR_REGISTRY}"/*)
            ;;
        *)
            return 0
            ;;
    esac

    if [ -n "${HARBOR_USER:-}" ] && [ -n "${HARBOR_TOKEN:-}" ]; then
        # Credentials provided via environment variables — use them directly.
        log_header "Harbor login"
        printf '%s' "${HARBOR_TOKEN}" | "${RUNTIME_CMD[@]}" login "${HARBOR_REGISTRY}" \
            -u "${HARBOR_USER}" \
            --password-stdin
    elif [ -t 0 ]; then
        # No credentials in environment and terminal is interactive — ask the user.
        log_header "Harbor login (interactive)"
        echo "HARBOR_USER and HARBOR_TOKEN are not set."
        echo "Enter credentials for ${HARBOR_REGISTRY} or press Ctrl+C to abort."
        echo
        read -rp "Username: " HARBOR_USER
        read -rsp "Token / Password: " HARBOR_TOKEN
        echo
        printf '%s' "${HARBOR_TOKEN}" | "${RUNTIME_CMD[@]}" login "${HARBOR_REGISTRY}" \
            -u "${HARBOR_USER}" \
            --password-stdin
        # Clear credentials from memory after login.
        HARBOR_USER=""
        HARBOR_TOKEN=""
    else
        # Non-interactive and no credentials — assume already logged in.
        echo "Harbor image selected, but HARBOR_USER/HARBOR_TOKEN are not set."
        echo "Assuming that the container runtime is already logged in."
    fi
}

# ============================================================
# HEADER: Assemble application arguments
# ============================================================

if [ "${#CUSTOM_APP_ARGS[@]}" -gt 0 ]; then
    APP_ARGS=("${CUSTOM_APP_ARGS[@]}")
else
    APP_ARGS=(
        --input /input
        --output /output
    )

    if [ "${USE_NOREGISTER}" -eq 1 ]; then
        APP_ARGS+=(--noregister)
    fi

    if [ -n "${THRESHOLD}" ]; then
        APP_ARGS+=(--threshold "${THRESHOLD}")
    fi

    if [ "${RUN_INTERMEDIATE}" -eq 1 ]; then
        APP_ARGS+=(--intermediate)
    fi

    if [ "${RUN_USEINTERMEDIATE}" -eq 1 ]; then
        APP_ARGS+=(--useintermediate)
    fi
fi

RUN_ARGS=(run --rm)

if [ "${NO_NETWORK}" -eq 1 ]; then
    RUN_ARGS+=(--network none)
fi

if [ "${CONTAINER_RUNTIME}" = "podman" ] && command -v id >/dev/null 2>&1; then
    RUN_ARGS+=(--userns=keep-id --user "$(id -u):$(id -g)")
fi

# ============================================================
# HEADER: Print effective configuration
# ============================================================

log_header "Effective configuration"
echo "CONTAINER_RUNTIME=${CONTAINER_RUNTIME}"
echo "APP_IMAGE=${APP_IMAGE}"
echo "IMAGE_TAR=${IMAGE_TAR:-<none>}"
echo "INPUT_DIR=${INPUT_DIR}"
echo "OUTPUT_DIR=${OUTPUT_DIR}"
echo "USE_NOREGISTER=${USE_NOREGISTER}"
echo "THRESHOLD=${THRESHOLD:-<application default>}"
echo "RUN_INTERMEDIATE=${RUN_INTERMEDIATE}"
echo "RUN_USEINTERMEDIATE=${RUN_USEINTERMEDIATE}"
echo "PULL_IF_MISSING=${PULL_IF_MISSING}"
echo "NO_NETWORK=${NO_NETWORK}"
echo "CLEAN_OUTPUT=${CLEAN_OUTPUT}"
echo "CLI_CHECK=${CLI_CHECK}"
echo "STRICT_CLI_CHECK=${STRICT_CLI_CHECK}"
echo "MOUNT_CHECK=${MOUNT_CHECK}"
echo "OUTPUT_CHECK=${OUTPUT_CHECK}"
echo "EXPECTED_OUTPUT=${EXPECTED_OUTPUT}"
echo "DRY_RUN=${DRY_RUN}"

if [ "${CONTAINER_RUNTIME}" = "podman" ]; then
    echo "PODMAN_ROOT=${PODMAN_ROOT}"
    echo "PODMAN_RUN=${PODMAN_RUN}"
fi

echo
echo "Application arguments:"
for arg in "${APP_ARGS[@]}"; do
    printf '  %q\n' "${arg}"
done

# ============================================================
# HEADER: Load or pull image
# ============================================================

if [ -n "${IMAGE_TAR}" ]; then
    log_header "Load local image archive"
    container_load_image "${IMAGE_TAR}"
fi

if container_image_exists "${APP_IMAGE}"; then
    # Image is already present locally — no pull needed.
    # Print the image creation date so the user can verify it is up to date.
    echo "[INFO] Image already available locally, skipping pull: ${APP_IMAGE}"
    IMAGE_CREATED_LOCAL="$("${RUNTIME_CMD[@]}" image inspect "${APP_IMAGE}" \
        --format "{{.Created}}" 2>/dev/null || true)"
    echo "[INFO] Image created: ${IMAGE_CREATED_LOCAL:-unknown}"
    echo "[INFO] To force a fresh pull, remove the image first:"
    echo "[INFO]   ${RUNTIME_CMD[*]} rmi ${APP_IMAGE}"
else
    if [ "${PULL_IF_MISSING}" -eq 1 ]; then
        # Image not found locally — pull from registry.
        echo "[INFO] Image not found locally, pulling from registry: ${APP_IMAGE}"
        maybe_harbor_login
        log_header "Pull image"
        container_pull_image "${APP_IMAGE}"
        echo "[INFO] Pull completed: ${APP_IMAGE}"
    else
        die "Image not available locally and pull is disabled: ${APP_IMAGE}"
    fi
fi

log_header "Image available"
"${RUNTIME_CMD[@]}" images --format "{{.Repository}}:{{.Tag}}" | grep -E "eucaim-mr-bpe-quantification|processing-tools" || true

# ============================================================
# HEADER: Prepare output directory
# ============================================================

log_header "Prepare output directory"

if [ "${CLEAN_OUTPUT}" -eq 1 ]; then
    rm -rf "${OUTPUT_DIR}"
fi

mkdir -p "${OUTPUT_DIR}"

echo "Input directory preview:"
find "${INPUT_DIR}" -maxdepth 1 -mindepth 1 -print | sed -n '1,20p' || true

echo
echo "Output directory:"
ls -ld "${OUTPUT_DIR}"

# ============================================================
# HEADER: Optional CLI validation
# ============================================================

if [ "${CLI_CHECK}" -eq 1 ]; then
    log_header "Validate application CLI"

    set +e
    HELP_OUTPUT="$("${RUNTIME_CMD[@]}" run --rm "${APP_IMAGE}" --help 2>&1)"
    HELP_STATUS=$?
    set -e

    printf '%s\n' "${HELP_OUTPUT}" | sed -n '1,120p'

    if [ "${HELP_STATUS}" -ne 0 ]; then
        die "Application --help failed for image: ${APP_IMAGE}"
    fi

    REQUIRED_CLI_OPTIONS=(--input --output)

    if [ "${USE_NOREGISTER}" -eq 1 ] || [ "${STRICT_CLI_CHECK}" -eq 1 ]; then
        REQUIRED_CLI_OPTIONS+=(--noregister)
    fi

    if [ -n "${THRESHOLD}" ] || [ "${STRICT_CLI_CHECK}" -eq 1 ]; then
        REQUIRED_CLI_OPTIONS+=(--threshold)
    fi

    if [ "${RUN_INTERMEDIATE}" -eq 1 ] || [ "${STRICT_CLI_CHECK}" -eq 1 ]; then
        REQUIRED_CLI_OPTIONS+=(--intermediate)
    fi

    if [ "${RUN_USEINTERMEDIATE}" -eq 1 ] || [ "${STRICT_CLI_CHECK}" -eq 1 ]; then
        REQUIRED_CLI_OPTIONS+=(--useintermediate)
    fi

    for expected in "${REQUIRED_CLI_OPTIONS[@]}"; do
        printf '%s\n' "${HELP_OUTPUT}" | grep -- "${expected}" >/dev/null || \
            die "Application --help does not contain expected option: ${expected}"
    done

    echo "CLI_CHECK_OK"
fi

# ============================================================
# HEADER: Optional mount and model validation
# ============================================================

if [ "${MOUNT_CHECK}" -eq 1 ]; then
    log_header "Validate mount contract and embedded models"

    "${RUNTIME_CMD[@]}" "${RUN_ARGS[@]}" \
        --entrypoint /bin/sh \
        -v "${INPUT_DIR}:/input:ro" \
        -v "${OUTPUT_DIR}:/output:rw" \
        "${APP_IMAGE}" \
        -c '
set -eu

test -d /input
test -d /output
test -w /output
test -d /opt/bpe_models
test -d /tmp

for model_name in t0_model t1_model tissue_model fgt_model; do
    test -f "/opt/bpe_models/${model_name}/model.xml"
    test -f "/opt/bpe_models/${model_name}/model.xnml"
    test -f "/opt/bpe_models/${model_name}/model.onnx"
    test -f "/opt/bpe_models/${model_name}/model.params"
done

touch /output/.write_test
rm -f /output/.write_test

echo "MOUNT_AND_MODEL_CHECK_OK"
'
fi

# ============================================================
# HEADER: Execute container
# ============================================================

log_header "Execute container"

FULL_COMMAND=(
    "${RUNTIME_CMD[@]}"
    "${RUN_ARGS[@]}"
    -v "${INPUT_DIR}:/input:ro"
    -v "${OUTPUT_DIR}:/output:rw"
    "${APP_IMAGE}"
    "${APP_ARGS[@]}"
)

echo "Container command:"
print_shell_command "${FULL_COMMAND[@]}"

if [ "${DRY_RUN}" -eq 1 ]; then
    echo "DRY_RUN_OK"
    exit 0
fi

"${FULL_COMMAND[@]}"

# ============================================================
# HEADER: Optional output validation
# ============================================================

if [ "${OUTPUT_CHECK}" -eq 1 ]; then
    log_header "Validate output"

    echo "Generated files:"
    find "${OUTPUT_DIR}" -maxdepth 5 -type f -print | sort

    EXPECTED_OUTPUT_PATH="${OUTPUT_DIR}/${EXPECTED_OUTPUT}"

    if [ ! -s "${EXPECTED_OUTPUT_PATH}" ]; then
        die "Expected output file is missing or empty: ${EXPECTED_OUTPUT_PATH}"
    fi

    echo
    echo "Expected output found:"
    echo "${EXPECTED_OUTPUT_PATH}"

    echo
    echo "Output preview:"
    sed -n '1,20p' "${EXPECTED_OUTPUT_PATH}" || true

    echo "OUTPUT_CHECK_OK"
fi

log_header "Execution completed successfully"
echo "IMAGE=${APP_IMAGE}"
echo "OUTPUT_DIR=${OUTPUT_DIR}"
