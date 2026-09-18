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

if [ "${CLEAN}" = "1" ]; then
    CLEAN_BOX=true
else
    CLEAN_BOX=false
fi

# 2. Check if arguments are provided
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Error: Wrong number of arguments."
    echo "Usage: [DRYRUN=1] [ARCHIVE=1] [CLEAN=1] [SR=<sample_rate>] $0 <hostname_string> <xrm_sysconfig_variant> [ip_address]"
    echo "Allowed xrm_sysconfig_variant options:"
    echo "  - INST-A"
    echo "  - INST-B"
    echo "  - MAGPS"
    echo "  - QPMS"
    exit 1
fi

HOSTNAME_ARG="$1"       # e.g., acq2206_100
SOURCE_SUBFOLDER="$2"   # Validated below
IP_ARG="$3"             # Optional IP address for target UUT (defaults to HOSTNAME_ARG)
OFFSET=500              # Always add 500

# Protect against bad input for the source subfolder
case "$SOURCE_SUBFOLDER" in
    INST-A)
        MODEL_STR="XRM-INST-A"
        PEERS="1,2"
        XRM_PM=0
        DEFAULT_SR=4000000
        ;;
    INST-B)
        MODEL_STR="XRM-INST-B"
        PEERS="1,2"
        XRM_PM=0
        DEFAULT_SR=4000000
        ;;
    MAGPS)
        MODEL_STR="XRM-MagPS"
        PEERS="1"
        XRM_PM=1
        DEFAULT_SR=100000
        ;;
    QPMS)
        MODEL_STR="XRM-QPMS"
        PEERS="1,2,3,4"
        XRM_PM=1
        DEFAULT_SR=100000
        ;;
    *)
        echo "Error: Invalid flavour '$SOURCE_SUBFOLDER'."
        echo "Allowed options are:"
        echo "  - INST-A"
        echo "  - INST-B"
        echo "  - MAGPS"
        echo "  - QPMS"
        exit 1
        ;;
esac

SAMPLE_RATE="${SR:-$DEFAULT_SR}"

# 3. Define your base paths
BASE_SOURCE_PATH="."
STAGE_DIR="XRM_STAGING"
PACKAGES_DIR="packages"

# Source template is consolidated in XRM-BASE
SOURCE_DIR="XRM-BASE"
TARGET_FILE="${STAGE_DIR}/mnt/local/sysconfig/xrm_epics.sh"

# 4. Validate that the base template directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '${SOURCE_DIR}' does not exist."
    exit 1
fi

# 5. Handle STAGE_DIR cleanup/creation
if [ -d "$STAGE_DIR" ]; then
    rm -rf "$STAGE_DIR"
fi
mkdir -p "$STAGE_DIR"

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
cp -r "$SOURCE_DIR/mnt" "$STAGE_DIR"

if [ -d "$PACKAGES_DIR" ]; then
    echo "Copying packages from ${PACKAGES_DIR} to ${STAGE_DIR}/mnt/..."
    cp -r "$PACKAGES_DIR" "${STAGE_DIR}/mnt/"
fi

# 8. Replace placeholders and configure model flavor
echo "Configuring parameters for ${SOURCE_SUBFOLDER}..."
echo "  ACQ400IOCnum -> $HOSTNAME_ARG"
echo "  XRMIOCnum    -> $NEW_VAR"
echo "  XRM_MODEL    -> $MODEL_STR"
echo "  Sample Rate  -> $SAMPLE_RATE"
if [ -n "$IP_ARG" ]; then
    echo "  Target IP    -> $IP_ARG"
fi

sed -i -E "s/([a-zA-Z0-9]+_)?ACQ400IOCnum/${HOSTNAME_ARG}/g" "$TARGET_FILE"
sed -i -E "s/([a-zA-Z0-9]+_)?XRMIOCnum/${NEW_VAR}/g" "$TARGET_FILE"
sed -i -E "s/^#?export XRM_MODEL=\"${MODEL_STR}\"/export XRM_MODEL=\"${MODEL_STR}\"/g" "$TARGET_FILE"
sed -i -E "s/^export XRM_PM=.*/export XRM_PM=${XRM_PM}/g" "$TARGET_FILE"

sed -i -E "s/^PEERS=.*/PEERS=${PEERS}/" "$STAGE_DIR/mnt/local/sysconfig/site-1-peers"
sed -i -E "s/%SR%/${SAMPLE_RATE}/g" "$STAGE_DIR/mnt/local/rc.user"

incant="$0 $*"
uut="${HOSTNAME_ARG}"
githash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
user="${USER}@$(hostname)"	
sed -i -e "2i#\n# created by deploy_XRM for uut:$uut xrm_var:$SOURCE_SUBFOLDER\n# by ${user} on $(date)\n# git $githash\n# incant $incant\n" $STAGE_DIR/mnt/local/rc.user

# 9. Deploy to UUT (Omitted if DRYRUN=1)
UUT_TARGET="${IP_ARG:-$HOSTNAME_ARG}"
ARCHIVE_NAME="${HOSTNAME_ARG}_payload.tgz"

if [ "$CLEAN_BOX" = true ]; then
    echo "======================================================================"
    echo " WARNING: CLEAN=1 is enabled!"
    echo " This will delete the contents of /mnt/local (retaining /cal)"
    echo " and remove any packages containing *xrm* from /mnt/packages on:"
    echo " Target UUT: ${UUT_TARGET}"
    echo "======================================================================"
    if [ "$DRY_RUN" = true ]; then
        echo " [DRY RUN] Would have executed countdown and remote cleanup."
    else
        echo " Starting cleanup in 5 seconds... Press Ctrl+C to abort!"
        for i in 5 4 3 2 1; do
            echo -n "$i... "
            sleep 1
        done
        echo "0"
        echo "Executing remote cleanup on ${UUT_TARGET}..."
        ssh root@${UUT_TARGET} "find /mnt/local -mindepth 1 ! -path '/mnt/local/cal' ! -path '/mnt/local/cal/*' -exec rm -rf {} + 2>/dev/null || true; rm -f /mnt/packages/*xrm* 2>/dev/null || true"
    fi
fi

if [ "$USE_ARCHIVE" = true ]; then
    echo "Creating compressed archive '${ARCHIVE_NAME}'..."
    tar -czf "${STAGE_DIR}/${ARCHIVE_NAME}" -C "${STAGE_DIR}/mnt" .

    if [ "$DRY_RUN" = true ]; then
        echo "========================================="
        echo "   DRY RUN: Skipping final archive deployment"
        echo "   Would have run: scp ${STAGE_DIR}/${ARCHIVE_NAME} root@${UUT_TARGET}:/tmp/"
        echo "   Would have run: ssh root@${UUT_TARGET} 'tar -xzf /tmp/${ARCHIVE_NAME} -C /mnt && rm /tmp/${ARCHIVE_NAME}'"
        echo "========================================="
    else
        echo "Deploying archive to UUT (${UUT_TARGET})..."
        scp "${STAGE_DIR}/${ARCHIVE_NAME}" "root@${UUT_TARGET}:/tmp/"
        echo "Extracting payload on UUT (${UUT_TARGET})..."
        ssh root@${UUT_TARGET} "tar -xzf /tmp/${ARCHIVE_NAME} -C /mnt && rm /tmp/${ARCHIVE_NAME}"
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
        echo "Deploying configuration to UUT (${UUT_TARGET})..."
        scp -r "${STAGE_DIR}/mnt/local" "root@${UUT_TARGET}:/mnt/"
        if [ -d "${STAGE_DIR}/mnt/packages" ]; then
            echo "Deploying packages to UUT (${UUT_TARGET})..."
            scp -r "${STAGE_DIR}/mnt/packages" "root@${UUT_TARGET}:/mnt/"
        fi
    fi
fi

echo "Done!"
