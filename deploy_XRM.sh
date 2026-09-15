#!/bin/bash
set -e

# 1. Check environment variables
if [ "${DRYRUN}" = "1" ]; then
    DRY_RUN=true
else
    DRY_RUN=false
fi

if [ "${ARCHIVE}" = "1" ]; then
    USE_ARCHIVE=true
else
    USE_ARCHIVE=false
fi

# 2. Check if exactly two arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Error: Wrong number of arguments."
    echo "Usage: [DRYRUN=1] [ARCHIVE=1] $0 <hostname_string> <source_subfolder_name>"
    exit 1
fi

HOSTNAME_ARG="$1"       # e.g., acq2206_100
SOURCE_SUBFOLDER="$2"   # Validated below
OFFSET=500              # Always add 500

# Protect against bad input for the source subfolder
case "$SOURCE_SUBFOLDER" in
    INST-A|INST-B|INST-B-ALLISON|MAGPS|QPMS|TEST_STAND_FMT_SIM)
        # Input is valid, carry on
        ;;
    *)
        echo "Error: Invalid source subfolder '$SOURCE_SUBFOLDER'."
        echo "Allowed options are:"
        echo "  - INST-A"
        echo "  - INST-B"
        echo "  - INST-B-ALLISON"
        echo "  - MAGPS"
        echo "  - QPMS"
        echo "  - TEST_STAND_FMT_SIM"
        exit 1
        ;;
esac

# 3. Define your base paths
BASE_SOURCE_PATH="XRM"
STAGE_DIR="XRM/XRM_STAGING"
PACKAGES_DIR="${BASE_SOURCE_PATH}/packages"

# Dynamically construct paths
SOURCE_DIR="${BASE_SOURCE_PATH}/${SOURCE_SUBFOLDER}"
TARGET_FILE="${STAGE_DIR}/mnt/local/sysconfig/xrm_epics.sh"

# 4. Validate that the constructed source directory actually exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '${SOURCE_DIR}' does not exist."
    exit 1
fi

# 5. Handle STAGE_DIR cleanup/creation
mkdir -p "$STAGE_DIR"
if [ -d "$STAGE_DIR/mnt" ]; then
    echo "Cleaning out previous staging files in '${STAGE_DIR}'..."
    rm -rf "${STAGE_DIR}/mnt"
fi
rm -f "${STAGE_DIR}"/*.tgz "${STAGE_DIR}"/*.tar 2>/dev/null || true

# 6. Extract the base string and the trailing number from hostname
if [[ "$HOSTNAME_ARG" =~ ^(.*_)([0-9]+)$ ]]; then
    BASE_STR="${BASH_REMATCH[1]}" # e.g., acq2206_
    OLD_NUM="${BASH_REMATCH[2]}"  # e.g., 100

    # Perform the calculation (e.g., 100 + 500 = 600)
    NEW_NUM=$((OLD_NUM + OFFSET))

    # Reassemble cleanly to get "acq2206_600"
    NEW_VAR="${BASE_STR}${NEW_NUM}"
else
    echo "Error: Hostname format must end in an underscore and a number (e.g., acq2206_100)"
    exit 1
fi

# 7. Execute copy (Always runs)
echo "Copying from ${SOURCE_DIR} to ${STAGE_DIR}..."
mkdir -p "$STAGE_DIR/mnt"
( shopt -s dotglob; cp -rp "$SOURCE_DIR/mnt/"* "$STAGE_DIR/mnt/" )

if [ -d "$PACKAGES_DIR" ]; then
    echo "Copying packages from ${PACKAGES_DIR} to ${STAGE_DIR}/mnt/..."
    cp -rp "$PACKAGES_DIR" "${STAGE_DIR}/mnt/"
fi

# 8. Replace placeholders (Always runs)
echo "Replacing variables..."
echo "  ACQ400IOCnum -> $HOSTNAME_ARG"
echo "  XRMIOCnum    -> $NEW_VAR"

sed -i -E "s/([a-zA-Z0-9]+_)?ACQ400IOCnum/${HOSTNAME_ARG}/g" "$TARGET_FILE"
sed -i -E "s/([a-zA-Z0-9]+_)?XRMIOCnum/${NEW_VAR}/g" "$TARGET_FILE"

incant="$0 $*"
uut="${HOSTNAME_ARG}"
githash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
user="${USER}@$(hostname)"	
sed -i -e "2i#\n# created by deploy_XRM for uut:$uut xrm_var:$SOURCE_DIR\n# by ${user} on $(date)\n# git $githash\n# incant $incant\n" $STAGE_DIR/mnt/local/rc.user

# 9. Deploy to UUT (Omitted if DRYRUN=1)
UUT_TARGET="${HOSTNAME_ARG}"
ARCHIVE_NAME="${HOSTNAME_ARG}_payload.tgz"

if [ "$USE_ARCHIVE" = true ]; then
    echo "Creating compressed archive '${ARCHIVE_NAME}'..."
    tar -czf "${STAGE_DIR}/${ARCHIVE_NAME}" -C "${STAGE_DIR}/mnt" .

    if [ "$DRY_RUN" = true ]; then
        echo "========================================="
        echo "   DRY RUN: Skipping final archive deployment"
        echo "   Would have run: scp ${STAGE_DIR}/${ARCHIVE_NAME} root@${UUT_TARGET}:/tmp/"
        echo "   Would have run: ssh root@${UUT_TARGET} 'tar -xzf /tmp/${ARCHIVE_NAME} -C /mnt && rm -f /tmp/${ARCHIVE_NAME}'"
        echo "========================================="
    else
        echo "Deploying archive to UUT (${HOSTNAME_ARG})..."
        scp "${STAGE_DIR}/${ARCHIVE_NAME}" "root@${UUT_TARGET}:/tmp/"
        echo "Extracting payload on UUT (${HOSTNAME_ARG})..."
        ssh root@${UUT_TARGET} "tar -xzf /tmp/${ARCHIVE_NAME} -C /mnt && rm -f /tmp/${ARCHIVE_NAME}"
    fi
else
    if [ "$DRY_RUN" = true ]; then
        echo "========================================="
        echo "   DRY RUN: Skipping final scp deployment "
        echo "   Would have run: scp -r ${STAGE_DIR}/mnt/local root@${UUT_TARGET}:/mnt/"
        if [ -d "${STAGE_DIR}/mnt/packages" ]; then
            echo "   Would have run: scp -r ${STAGE_DIR}/mnt/packages root@${UUT_TARGET}:/mnt/"
        fi
        echo "========================================="
    else
        echo "Deploying configuration to UUT (${HOSTNAME_ARG})..."
        scp -r "${STAGE_DIR}/mnt/local" "root@${UUT_TARGET}:/mnt/"
        if [ -d "${STAGE_DIR}/mnt/packages" ]; then
            echo "Deploying packages to UUT (${HOSTNAME_ARG})..."
            scp -r "${STAGE_DIR}/mnt/packages" "root@${UUT_TARGET}:/mnt/"
        fi
    fi
fi

echo "Done!"
