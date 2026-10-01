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
    echo "  - TEST_STAND_FMT_SIM"
    echo "  - INST-B-ALLISON"
    exit 1
fi

HOSTNAME_ARG="$1"       # e.g., acq2206_100
SOURCE_SUBFOLDER="$2"   # Validated below
IP_ARG="$3"             # Optional IP address for target UUT (defaults to HOSTNAME_ARG)
OFFSET=500              # Always add 500

STATIC_DEPLOY=false
SOURCE_DIR="XRM-BASE"

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
    TEST_STAND_FMT_SIM|INST-B-ALLISON)
        STATIC_DEPLOY=true
        SOURCE_DIR="XRM/${SOURCE_SUBFOLDER}"
        ;;
    *)
        echo "Error: Invalid flavour '$SOURCE_SUBFOLDER'."
        echo "Allowed options are:"
        echo "  - INST-A"
        echo "  - INST-B"
        echo "  - MAGPS"
        echo "  - QPMS"
        echo "  - TEST_STAND_FMT_SIM"
        echo "  - INST-B-ALLISON"
        exit 1
        ;;
esac

SAMPLE_RATE="${SR:-$DEFAULT_SR}"

# 3. Define your base paths
BASE_SOURCE_PATH="."
STAGE_DIR="XRM_STAGING"
PACKAGES_DIR="packages"
MANIFEST_FILE="${PACKAGES_DIR}/pack_manifest"

TARGET_FILE="${STAGE_DIR}/mnt/local/sysconfig/xrm_epics.sh"

# 4. Validate that packages directory contains required .tgz packages and no stale packages
EXPECTED_PACKAGES=()
MISSING_PACKAGES=()
STALE_PACKAGES=()

if [ -f "$MANIFEST_FILE" ]; then
    while IFS= read -r url || [ -n "$url" ]; do
        url=$(echo "$url" | tr -d '\r' | xargs)
        [ -z "$url" ] && continue
        [[ "$url" =~ ^# ]] && continue
        pkg_name=$(basename "$url")
        EXPECTED_PACKAGES+=("$pkg_name")
        if [ ! -f "${PACKAGES_DIR}/${pkg_name}" ]; then
            MISSING_PACKAGES+=("$pkg_name")
        fi
    done < "$MANIFEST_FILE"

    # Identify any .tgz in packages/ not listed in manifest (stale packages from previous commits)
    for existing_file in "${PACKAGES_DIR}"/*.tgz; do
        [ -e "$existing_file" ] || continue
        pkg_base=$(basename "$existing_file")
        is_expected=false
        for exp in "${EXPECTED_PACKAGES[@]}"; do
            if [ "$pkg_base" = "$exp" ]; then
                is_expected=true
                break
            fi
        done
        if [ "$is_expected" = false ]; then
            STALE_PACKAGES+=("$pkg_base")
        fi
    done
elif [ -z "$(ls -A "$PACKAGES_DIR"/*.tgz 2>/dev/null)" ]; then
    MISSING_PACKAGES+=("*.tgz")
fi

HAS_PKG_ERROR=false

if [ "${#STALE_PACKAGES[@]}" -gt 0 ]; then
    HAS_PKG_ERROR=true
    echo "======================================================================"
    echo " WARNING: Stale package(s) detected in '${PACKAGES_DIR}'!"
    echo " The following package(s) are not in ${MANIFEST_FILE} (possibly downloaded"
    echo " during previous commits):"
    for pkg in "${STALE_PACKAGES[@]}"; do
        echo "   - $pkg"
    done
    echo "----------------------------------------------------------------------"
    echo " Stale packages will cause duplicate/conflicting services on the UUT."
    echo " To clean stale packages, remove them:"
    for pkg in "${STALE_PACKAGES[@]}"; do
        echo "   rm \"${PACKAGES_DIR}/$pkg\""
    done
    echo "======================================================================"
fi

if [ "${#MISSING_PACKAGES[@]}" -gt 0 ]; then
    HAS_PKG_ERROR=true
    echo "======================================================================"
    echo " WARNING: Packages directory '${PACKAGES_DIR}' is missing .tgz packages!"
    echo " The following package(s) from pack_manifest have not been downloaded:"
    for pkg in "${MISSING_PACKAGES[@]}"; do
        echo "   - $pkg"
    done
    echo "----------------------------------------------------------------------"
    echo " To populate the packages directory, run the following commands:"
    echo "   cd ${PACKAGES_DIR}"
    echo "   wget -i pack_manifest"
    echo "======================================================================"
fi

if [ "$HAS_PKG_ERROR" = true ]; then
    echo "Exiting due to package verification failure."
    exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '${SOURCE_DIR}' does not exist."
    exit 1
fi

# 5. Handle STAGE_DIR cleanup/creation
if [ -d "$STAGE_DIR" ]; then
    rm -rf "$STAGE_DIR"
fi
mkdir -p "$STAGE_DIR"

# 6. Extract the base string and the trailing number from hostname (Only if templating)
if [ "$STATIC_DEPLOY" = false ]; then
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
fi

# 7. Execute copy (Always runs)
echo "Copying from ${SOURCE_DIR} to ${STAGE_DIR}..."
cp -r "$SOURCE_DIR/mnt" "$STAGE_DIR"

if [ -d "$PACKAGES_DIR" ]; then
    echo "Copying packages from ${PACKAGES_DIR} to ${STAGE_DIR}/mnt/packages/..."
    mkdir -p "${STAGE_DIR}/mnt/packages"
    if [ "${#EXPECTED_PACKAGES[@]}" -gt 0 ]; then
        for pkg in "${EXPECTED_PACKAGES[@]}"; do
            if [ -f "${PACKAGES_DIR}/${pkg}" ]; then
                cp "${PACKAGES_DIR}/${pkg}" "${STAGE_DIR}/mnt/packages/"
            fi
        done
    else
        cp "${PACKAGES_DIR}"/*.tgz "${STAGE_DIR}/mnt/packages/" 2>/dev/null || true
    fi
fi

# 8. Replace placeholders and configure model flavor
if [ "$STATIC_DEPLOY" = true ]; then
    echo "Static deployment selected for ${SOURCE_SUBFOLDER}."
    echo "Bypassing file templating..."
else
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
fi

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
