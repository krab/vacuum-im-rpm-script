#!/bin/bash
set -euo pipefail

# =============================================================================
# Vacuum-IM RPM Build Wrapper for Mock
# =============================================================================
# Modes:
#   --get      Download sources and create git archive in SOURCES/
#   --update   Update spec file with GIT_HASH/GIT_DATE and run rpmlint
#   --build    Build SRPM and binary RPM with mock
#   --all      Execute --get, --update, and --build in sequence
#
# RPM_BUILD_DIR environment variable can override the build directory.
# Default: directory where this script is located
# =============================================================================

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RPM_BUILD_DIR="${RPM_BUILD_DIR:-${SCRIPT_DIR}}"
SPEC_FILE="${RPM_BUILD_DIR}/SPECS/vacuum-im.spec"
SOURCES_DIR="${RPM_BUILD_DIR}/SOURCES"
METADATA_DIR="${SOURCES_DIR}/.metadata"
DEFAULT_REPO_URL="https://github.com/Vacuum-IM/vacuum-im.git"
DEFAULT_MOCK_CONFIG="redos-80-x86_64"
DEFAULT_REF="HEAD"
GIT_REPO_DIR="${SOURCES_DIR}/vacuum-im-repo"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
    cat <<EOF
Usage: $(basename "$0") <MODE> [OPTIONS]

RPM_BUILD_DIR environment variable overrides the build directory.
Default: directory where this script is located (${SCRIPT_DIR})

Modes:
    --get            Download sources and create git archive in SOURCES/
    --update         Update spec file with GIT_HASH/GIT_DATE and run rpmlint
    --build          Build SRPM and binary RPM with mock
    --all            Execute --get, --update, and --build in sequence

Options:
    --ref REF            Git ref to checkout (branch, tag, commit, or HEAD)
                         Default: ${DEFAULT_REF}
    --repo-url URL       Git repository URL
                         Default: ${DEFAULT_REPO_URL}
    --mock-config CFG    Mock configuration name
                         Default: ${DEFAULT_MOCK_CONFIG}
    --mock-config-path PATH  Path to mock config file
    --dist DIST          Distribution tag suffix (e.g., .redos)
    --no-rpmlint         Skip rpmlint check (only for --update/--all)
    --help               Show this help

Examples:
    # Download sources only
    $(basename "$0") --get

    # Update spec only
    $(basename "$0") --update

    # Build only (assumes sources already downloaded)
    $(basename "$0") --build

    # Full build from scratch
    $(basename "$0") --all

    # Build specific branch with custom mock config
    $(basename "$0") --all --ref master --mock-config redos-73-x86_64

    # Build specific commit
    $(basename "$0") --all --ref abc123def456

    # Build from custom repository
    $(basename "$0") --all --repo-url https://github.com/example/vacuum-im.git --ref develop

    # Use custom build directory
    RPM_BUILD_DIR=/tmp/rpm $(basename "$0") --all
EOF
    exit 0
}

# Parse arguments
MODE=""
REPO_URL="${DEFAULT_REPO_URL}"
MOCK_CONFIG="${DEFAULT_MOCK_CONFIG}"
MOCK_CONFIG_PATH=""
REF="${DEFAULT_REF}"
DIST=""
SKIP_RPMLINT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --get|--update|--build|--all)
            MODE="${1#--}"
            shift
            ;;
        --ref)
            REF="$2"
            shift 2
            ;;
        --repo-url)
            REPO_URL="$2"
            shift 2
            ;;
        --mock-config)
            MOCK_CONFIG="$2"
            shift 2
            ;;
        --mock-config-path)
            MOCK_CONFIG_PATH="$2"
            shift 2
            ;;
        --dist)
            DIST="$2"
            shift 2
            ;;
        --no-rpmlint)
            SKIP_RPMLINT=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ -z "${MODE}" ]]; then
    log_error "No mode specified. Use --get, --update, --build, or --all"
    usage
fi

# Validate prerequisites
log_info "Checking prerequisites..."

for cmd in git mock; do
    command -v "${cmd}" >/dev/null 2>&1 || { log_error "${cmd} is required but not installed. Aborting."; exit 1; }
done

if [[ "${SKIP_RPMLINT}" == "false" ]]; then
    command -v rpmlint >/dev/null 2>&1 || { log_warn "rpmlint not found, will skip lint checks."; SKIP_RPMLINT=true; }
fi

# Validate directories
[[ -d "${RPM_BUILD_DIR}" ]] || { log_error "RPM build directory ${RPM_BUILD_DIR} does not exist. Aborting."; exit 1; }
[[ -f "${SPEC_FILE}" ]] || { log_error "Spec file ${SPEC_FILE} not found. Aborting."; exit 1; }
[[ -d "${SOURCES_DIR}" ]] || mkdir -p "${SOURCES_DIR}"

# Validate mock config
if [[ -n "${MOCK_CONFIG_PATH}" ]]; then
    MOCK_CONFIG_ARG="--root ${MOCK_CONFIG_PATH}"
else
    MOCK_CONFIG_ARG="-r ${MOCK_CONFIG}"
fi

log_info "Using mock configuration: ${MOCK_CONFIG}"
log_info "RPM build directory: ${RPM_BUILD_DIR}"

# =============================================================================
# Mode: --get
# =============================================================================
do_get() {
    log_info "========================================="
    log_info "Mode: GET - Download sources and create archive"
    log_info "========================================="

    # Clean previous repo if exists
    if [[ -d "${GIT_REPO_DIR}" ]]; then
        log_info "Removing previous git repo at ${GIT_REPO_DIR}..."
        rm -rf "${GIT_REPO_DIR}"
    fi

    # Clone repository
    log_info "Cloning repository from ${REPO_URL}..."
    log_info "Ref: ${REF}"

    if ! git clone "${REPO_URL}" "${GIT_REPO_DIR}" 2>&1; then
        log_error "Failed to clone repository from ${REPO_URL}"
        return 1
    fi

    cd "${GIT_REPO_DIR}"

    # Checkout the specified ref
    log_info "Checking out ref: ${REF}"
    if ! git checkout "${REF}" 2>&1; then
        log_error "Failed to checkout ref: ${REF}"
        return 1
    fi

    # Verify we're on the right commit
    CURRENT_REF=$(git rev-parse HEAD)
    log_info "Checked out commit: ${CURRENT_REF}"

    # Extract version from CMakeLists.txt
    VERSION=$(grep -oP '(?<=^project\(vacuum-im\s+)?[0-9]+\.[0-9]+\.[0-9]+' CMakeLists.txt 2>/dev/null || \
             grep -oP 'VERSION[= ]+[0-9]+\.[0-9]+\.[0-9]+' CMakeLists.txt 2>/dev/null | head -1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || \
             echo "1.3.0")

    if [[ -z "${VERSION}" ]]; then
        VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "1.3.0")
    fi

    log_info "Detected version: ${VERSION}"

    # Get git hash, date, and human-readable date
    GIT_HASH=$(git log -n 1 --format=%H)
    GIT_DATE=$(git log -n 1 --format=%ct)
    GIT_SHORT_ID=$(git log -n 1 --format=%h)
    GIT_HUMAN_DATE=$(git log -n 1 --format="%cd" --date=format:'%Y.%m.%d.%H.%M')

    log_info "Git hash: ${GIT_HASH}"
    log_info "Git date: ${GIT_DATE} ($(date -d @${GIT_DATE} '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo 'N/A'))"
    log_info "Git short id: ${GIT_SHORT_ID}"
    log_info "Git human date: ${GIT_HUMAN_DATE}"

    # Create git archive with short id
    ARCHIVE_NAME="vacuum-im-${GIT_SHORT_ID}.tar.gz"
    ARCHIVE_PATH="${SOURCES_DIR}/${ARCHIVE_NAME}"

    # Remove old archive if exists
    if [[ -f "${ARCHIVE_PATH}" ]]; then
        log_info "Removing old archive: ${ARCHIVE_NAME}"
        rm -f "${ARCHIVE_PATH}"
    fi

    log_info "Creating git archive: ${ARCHIVE_NAME}"
    git archive --format=tar.gz --prefix="vacuum-im-${GIT_SHORT_ID}/" HEAD -o "${ARCHIVE_PATH}"

    if [[ ! -f "${ARCHIVE_PATH}" ]]; then
        log_error "Failed to create git archive at ${ARCHIVE_PATH}"
        return 1
    fi

    log_info "Archive created successfully: ${ARCHIVE_PATH}"
    log_info "Archive size: $(du -h "${ARCHIVE_PATH}" | cut -f1)"

    # Store metadata for later steps
    mkdir -p "${METADATA_DIR}"
    echo "${VERSION}" > "${METADATA_DIR}/.vacuum-im-version"
    echo "${GIT_HASH}" > "${METADATA_DIR}/.vacuum-im-git-hash"
    echo "${GIT_DATE}" > "${METADATA_DIR}/.vacuum-im-git-date"
    echo "${GIT_SHORT_ID}" > "${METADATA_DIR}/.vacuum-im-git-short-id"
    echo "${GIT_HUMAN_DATE}" > "${METADATA_DIR}/.vacuum-im-git-human-date"
    echo "${REF}" > "${METADATA_DIR}/.vacuum-im-ref"

    log_info "Git repo preserved at: ${GIT_REPO_DIR}"
    log_info "========================================="
    log_info "GET completed successfully"
    log_info "========================================="
}

# =============================================================================
# Mode: --update
# =============================================================================
do_update() {
    log_info "========================================="
    log_info "Mode: UPDATE - Update spec and run rpmlint"
    log_info "========================================="

    # Determine version, git hash, date, short id, and human date
    if [[ -d "${GIT_REPO_DIR}" ]]; then
        log_info "Using existing git repo at ${GIT_REPO_DIR}"
        cd "${GIT_REPO_DIR}"
        VERSION=$(grep -oP '(?<=^project\(vacuum-im\s+)?[0-9]+\.[0-9]+\.[0-9]+' CMakeLists.txt 2>/dev/null || \
                 grep -oP 'VERSION[= ]+[0-9]+\.[0-9]+\.[0-9]+' CMakeLists.txt 2>/dev/null | head -1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || \
                 echo "1.3.0")
        if [[ -z "${VERSION}" ]]; then
            VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "1.3.0")
        fi
        GIT_HASH=$(git log -n 1 --format=%H)
        GIT_DATE=$(git log -n 1 --format=%ct)
        GIT_SHORT_ID=$(git log -n 1 --format=%h)
        GIT_HUMAN_DATE=$(git log -n 1 --format="%cd" --date=format:'%Y.%m.%d.%H.%M')
    else
        log_warn "Git repo not found at ${GIT_REPO_DIR}"
        
        # Try to read from stored metadata
        if [[ -f "${METADATA_DIR}/.vacuum-im-git-hash" ]]; then
            GIT_HASH=$(cat "${METADATA_DIR}/.vacuum-im-git-hash")
            GIT_DATE=$(cat "${METADATA_DIR}/.vacuum-im-git-date")
            GIT_SHORT_ID=$(cat "${METADATA_DIR}/.vacuum-im-git-short-id")
            GIT_HUMAN_DATE=$(cat "${METADATA_DIR}/.vacuum-im-git-human-date")
            VERSION=$(cat "${METADATA_DIR}/.vacuum-im-version")
            log_info "Using stored metadata from .metadata/"
        else
            # Try to extract from existing archive
            ARCHIVE=$(find "${SOURCES_DIR}" -name "vacuum-im-*.tar.gz" -type f 2>/dev/null | head -1)
            if [[ -n "${ARCHIVE}" ]]; then
                log_info "Found archive: ${ARCHIVE}"
                VERSION=$(basename "${ARCHIVE}" | sed -E 's/vacuum-im-([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
                log_info "Extracted version from archive: ${VERSION}"
                GIT_HASH="unknown"
                GIT_DATE="unknown"
                GIT_SHORT_ID="unknown"
                GIT_HUMAN_DATE="unknown"
            else
                log_error "No git repo or archive found. Run --get first."
                return 1
            fi
        fi
    fi

    log_info "Version: ${VERSION}"
    log_info "Git hash: ${GIT_HASH}"
    log_info "Git date: ${GIT_DATE}"
    log_info "Git short id: ${GIT_SHORT_ID}"
    log_info "Git human date: ${GIT_HUMAN_DATE}"

    # Update spec file
    log_info "Updating spec file..."

    cp "${SPEC_FILE}" "${SPEC_FILE}.bak"

    # Update git_hash, git_date, git_short_id, and git_human_date
    # Use a single sed invocation to avoid multiple backup files
    if [[ "${GIT_HASH}" != "unknown" ]] && [[ "${GIT_DATE}" != "unknown" ]] && [[ "${GIT_SHORT_ID}" != "unknown" ]] && [[ "${GIT_HUMAN_DATE}" != "unknown" ]]; then
        sed -i.bak \
            -e "s|^%define git_hash.*|%define git_hash ${GIT_HASH}|" \
            -e "s|^%define git_date.*|%define git_date ${GIT_DATE}|" \
            -e "s|^%define git_short_id.*|%define git_short_id ${GIT_SHORT_ID}|" \
            -e "s|^%define git_human_date.*|%define git_human_date ${GIT_HUMAN_DATE}|" \
            "${SPEC_FILE}"
    elif [[ "${GIT_HASH}" != "unknown" ]] && [[ "${GIT_DATE}" != "unknown" ]] && [[ "${GIT_SHORT_ID}" != "unknown" ]]; then
        sed -i.bak \
            -e "s|^%define git_hash.*|%define git_hash ${GIT_HASH}|" \
            -e "s|^%define git_date.*|%define git_date ${GIT_DATE}|" \
            -e "s|^%define git_short_id.*|%define git_short_id ${GIT_SHORT_ID}|" \
            "${SPEC_FILE}"
    elif [[ "${GIT_HASH}" != "unknown" ]] && [[ "${GIT_DATE}" != "unknown" ]]; then
        sed -i.bak \
            -e "s|^%define git_hash.*|%define git_hash ${GIT_HASH}|" \
            -e "s|^%define git_date.*|%define git_date ${GIT_DATE}|" \
            "${SPEC_FILE}"
    elif [[ "${GIT_HASH}" != "unknown" ]]; then
        sed -i.bak "s|^%define git_hash.*|%define git_hash ${GIT_HASH}|" "${SPEC_FILE}"
    fi

    # Clean up sed backup
    rm -f "${SPEC_FILE}.bak"

    # Verify changes
    UPDATED_HASH=$(grep -oP '(?<=^%define git_hash ).+' "${SPEC_FILE}")
    UPDATED_DATE=$(grep -oP '(?<=^%define git_date ).+' "${SPEC_FILE}")
    UPDATED_SHORT_ID=$(grep -oP '(?<=^%define git_short_id ).+' "${SPEC_FILE}")
    UPDATED_HUMAN_DATE=$(grep -oP '(?<=^%define git_human_date ).+' "${SPEC_FILE}")

    log_info "Spec file updated:"
    log_info "  git_hash = ${UPDATED_HASH}"
    log_info "  git_date = ${UPDATED_DATE}"
    log_info "  git_short_id = ${UPDATED_SHORT_ID}"
    log_info "  git_human_date = ${UPDATED_HUMAN_DATE}"

    if [[ -z "${UPDATED_HASH}" ]] || [[ -z "${UPDATED_DATE}" ]] || [[ -z "${UPDATED_SHORT_ID}" ]] || [[ -z "${UPDATED_HUMAN_DATE}" ]]; then
        log_error "Failed to update spec file: one or more git macros are empty after update."
        log_error "git_hash='${UPDATED_HASH}' git_date='${UPDATED_DATE}' git_short_id='${UPDATED_SHORT_ID}' git_human_date='${UPDATED_HUMAN_DATE}'"
        return 1
    fi

    # Run rpmlint
    if [[ "${SKIP_RPMLINT}" == "false" ]]; then
        log_info "Running rpmlint on spec file..."
        
        RPNLINT_OUTPUT=$(rpmlint "${SPEC_FILE}" 2>&1) || true
        
        # Check for errors
        if echo "${RPNLINT_OUTPUT}" | grep -qE '^[^:]+:[^:]+: E'; then
            log_error "rpmlint found errors:"
            echo "${RPNLINT_OUTPUT}" | grep -E '^[^:]+:[^:]+: E'
            log_error "Aborting due to rpmlint errors"
            return 1
        fi
        
        # Show warnings
        if echo "${RPNLINT_OUTPUT}" | grep -qE '^[^:]+:[^:]+: [WE]'; then
            log_warn "rpmlint warnings:"
            echo "${RPNLINT_OUTPUT}" | grep -E '^[^:]+:[^:]+: [WE]'
        fi
        
        log_info "rpmlint check passed"
    else
        log_warn "Skipping rpmlint check"
    fi

    log_info "========================================="
    log_info "UPDATE completed successfully"
    log_info "========================================="
}

# =============================================================================
# Mode: --build
# =============================================================================
do_build() {
    log_info "========================================="
    log_info "Mode: BUILD - Build RPM with mock"
    log_info "========================================="

    # Find archive
    ARCHIVE=$(find "${SOURCES_DIR}" -name "vacuum-im-*.tar.gz" -type f ! -name "*.bak" 2>/dev/null | head -1)
    if [[ -z "${ARCHIVE}" ]]; then
        log_error "Source archive not found in ${SOURCES_DIR}. Run --get first."
        return 1
    fi

    log_info "Found source archive: $(basename "${ARCHIVE}")"

    # Verify spec macros are populated before building
    CHECK_HASH=$(grep -oP '(?<=^%define git_hash ).+' "${SPEC_FILE}")
    CHECK_DATE=$(grep -oP '(?<=^%define git_date ).+' "${SPEC_FILE}")
    CHECK_SHORT_ID=$(grep -oP '(?<=^%define git_short_id ).+' "${SPEC_FILE}")
    CHECK_HUMAN_DATE=$(grep -oP '(?<=^%define git_human_date ).+' "${SPEC_FILE}")

    if [[ -z "${CHECK_HASH}" ]] || [[ -z "${CHECK_DATE}" ]] || [[ -z "${CHECK_SHORT_ID}" ]] || [[ -z "${CHECK_HUMAN_DATE}" ]]; then
        log_error "Spec file macros are not fully populated. Run --update first."
        log_error "git_hash='${CHECK_HASH}' git_date='${CHECK_DATE}' git_short_id='${CHECK_SHORT_ID}' git_human_date='${CHECK_HUMAN_DATE}'"
        return 1
    fi

    # Determine dist tag if not provided
    if [[ -z "${DIST}" ]]; then
        if [[ "${MOCK_CONFIG}" =~ redos-([0-9]+) ]]; then
            DIST=".redos${BASH_REMATCH[1]}"
        elif [[ "${MOCK_CONFIG}" =~ fedora-([0-9]+) ]]; then
            DIST=".fc${BASH_REMATCH[1]}"
        elif [[ "${MOCK_CONFIG}" =~ centos-([0-9]+) ]]; then
            DIST=".el${BASH_REMATCH[1]}"
        elif [[ "${MOCK_CONFIG}" =~ rhel-([0-9]+) ]]; then
            DIST=".el${BASH_REMATCH[1]}"
        else
            DIST=".redos"
        fi
    fi

    log_info "Dist tag: ${DIST}"

    # Ensure result directories exist
    mkdir -p "${RPM_BUILD_DIR}/SRPMS"
    mkdir -p "${RPM_BUILD_DIR}/RPMS"

    # Build SRPM
    log_info "Building SRPM with mock..."
    log_info "Config: ${MOCK_CONFIG}"
    log_info "Sources: ${SOURCES_DIR}"
    log_info "Result dir: ${RPM_BUILD_DIR}/SRPMS"

    SRPM_CMD="mock ${MOCK_CONFIG_ARG} --buildsrpm --spec ${SPEC_FILE} --sources ${SOURCES_DIR} --resultdir ${RPM_BUILD_DIR}/SRPMS"
    if [[ -n "${DIST}" ]]; then
        SRPM_CMD="${SRPM_CMD} --define \"dist ${DIST}\""
    fi

    log_info "Running: ${SRPM_CMD}"
    eval "${SRPM_CMD}"

    # Find SRPM in result directory
    SRPM_FILE=$(find "${RPM_BUILD_DIR}/SRPMS" -name "vacuum-im-*.src.rpm" -type f 2>/dev/null | head -1)
    if [[ -z "${SRPM_FILE}" ]]; then
        SRPM_FILE=$(find /var/lib/mock -name "vacuum-im-*.src.rpm" -type f 2>/dev/null | head -1)
    fi

    if [[ -z "${SRPM_FILE}" ]]; then
        log_error "SRPM not found after build"
        return 1
    fi

    log_info "SRPM created: ${SRPM_FILE}"

    # Rebuild binary RPM
    log_info "Rebuilding binary RPM from SRPM..."
    log_info "Result dir: ${RPM_BUILD_DIR}/RPMS"
    mock ${MOCK_CONFIG_ARG} --rebuild "${SRPM_FILE}" --resultdir "${RPM_BUILD_DIR}/RPMS"

    # Find built binary RPMs in result directory
    log_info "Searching for built RPMs..."
    
    BINARY_RPMS=$(find "${RPM_BUILD_DIR}/RPMS" -name "vacuum-im-*.rpm" -type f ! -name "*.src.rpm" 2>/dev/null)
    
    if [[ -z "${BINARY_RPMS}" ]]; then
        BINARY_RPMS=$(find /var/lib/mock -name "vacuum-im-*.rpm" -type f ! -name "*.src.rpm" 2>/dev/null)
    fi

    if [[ -n "${BINARY_RPMS}" ]]; then
        log_info "Built RPMs:"
        for rpm in ${BINARY_RPMS}; do
            SIZE=$(du -h "${rpm}" | cut -f1)
            log_info "  $(basename "${rpm}") (${SIZE})"
        done
    else
        log_warn "No binary RPMs found after build"
    fi

    log_info "========================================="
    log_info "BUILD completed successfully"
    log_info "========================================="
}

# =============================================================================
# Main execution
# =============================================================================
case "${MODE}" in
    get)
        do_get
        ;;
    update)
        do_update
        ;;
    build)
        do_build
        ;;
    all)
        do_get && do_update && do_build
        log_info "========================================="
        log_info "ALL steps completed successfully"
        log_info "========================================="
        ;;
esac
