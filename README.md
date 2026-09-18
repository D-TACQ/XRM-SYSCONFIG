# XRM Deployment Documentation

This document describes the XRM configuration architecture, the single-template structure (`XRM-BASE`), and the deployment script `deploy_XRM.sh`.

---

## 1. Overview

The `deploy_XRM.sh` utility automates staging and remote deployment of custom system configurations and EPICS IOC parameters for D-TACQ ACQ400-series systems configured for the XRM subsystem.

All template files are consolidated into a single master template directory: **`XRM/XRM-BASE`**. When deploying, `deploy_XRM.sh` stages from this base and dynamically configures the requested XRM flavour.

Key responsibilities:
- **Parameter Validation**: Validates target hostname formats and verifies the requested flavour (`INST-A`, `INST-B`, `MAGPS`, `QPMS`).
- **Offset Calculation**: Dynamically computes secondary IOC hostname numbers using a `+500` offset (e.g., `acq2206_100` -> `acq2206_600`).
- **Single Template Staging**: Copies from `XRM/XRM-BASE/mnt` to `XRM/XRM_STAGING` and includes packages from `XRM/packages` when present.
- **Dynamic Flavour Activation**: Uncomments the appropriate `export XRM_MODEL="..."` line in `xrm_epics.sh`, updates `XRM_PM`, and configures `site-1-peers`.
- **Variable Substitution**: Replaces template placeholders (`ACQ400IOCnum` and `XRMIOCnum`) with system-specific network names.
- **Traceability & Audit Logging**: Prepends metadata headers to `rc.user` recording the deploying user, timestamp, Git commit SHA, and invocation incantation.
- **Remote Deployment Modes**:
  - **Standard (`scp -r`)**: Transfers the staged `/mnt/local` tree and any packages directly to the target unit via recursive `scp`.
  - **Archive Mode (`ARCHIVE=1`)**: Bundles the entire payload into a single compressed `.tgz` archive, SCPs it to `/tmp` on the target, and extracts it directly into `/mnt` via SSH. Streamlines deployment and minimizes authentication prompts when SSH keys are not installed.
- **Dry-Run Validation**: Supports `DRYRUN=1` mode to verify staging, archive generation, and variable substitution locally without touching hardware.

---

## 2. Command Line Usage

### Syntax
```bash
[DRYRUN=1] [ARCHIVE=1] [CLEAN=1] [SR=<sample_rate>] ./deploy_XRM.sh <hostname_string> <flavour_name> [ip_address]
```

### Arguments
* `<hostname_string>`: Target UUT hostname. Must end with an underscore followed by a number (e.g., `acq2206_100`).
* `<flavour_name>`: One of the 4 supported XRM flavours:
  * `INST-A`
  * `INST-B`
  * `MAGPS`
  * `QPMS`
* `[ip_address]`: (Optional) Target UUT IP address for network deployment when DNS resolution is unavailable. When omitted, deployment defaults to `<hostname_string>`.

### Environment Variables
* `DRYRUN=1`: When set, completes all staging, archive generation, regex substitutions, and audit logging locally in `XRM/XRM_STAGING`, but skips SSH/SCP file transfers to the UUT.
* `ARCHIVE=1`: When set, packages the staged payload into `<hostname>_payload.tgz`, copies it via a single `scp` transfer to `/tmp/` on the UUT, and decompresses it into `/mnt` using `ssh`. Ideal for environments without SSH keys or for mass deployment.
* `CLEAN=1`: When set, reaches out to the target UUT right at the start of deployment, displays a warning with a 5-second countdown, and deletes the contents of `/mnt/local` (retaining the `/cal` directory) as well as any packages containing `*xrm*` from `/mnt/packages`.
* `SR=<sample_rate>`: (Optional) Override default sample rate for the selected flavour.

### Usage Examples

**Dry Run Verification (Standard mode):**
```bash
DRYRUN=1 ./deploy_XRM.sh acq2206_100 MAGPS
```

**Dry Run Verification (Archive mode):**
```bash
DRYRUN=1 ARCHIVE=1 ./deploy_XRM.sh acq2206_100 QPMS
```

**Dry Run Verification with explicit IP address (No DNS):**
```bash
DRYRUN=1 ./deploy_XRM.sh acq2206_100 MAGPS 192.168.0.100
```

**Live Deployment (Standard mode):**
```bash
./deploy_XRM.sh acq2206_100 MAGPS
```

**Live Deployment (Archive mode - single SCP transfer):**
```bash
ARCHIVE=1 ./deploy_XRM.sh acq2206_100 QPMS
```

**Live Deployment with explicit IP address (No DNS):**
```bash
./deploy_XRM.sh acq2206_100 MAGPS 192.168.0.100
```

---

## 3. Step-by-Step Function of `deploy_XRM.sh`

```
  +--------------------------------+
  | 1. Argument & Option Parsing   | Validate arguments (UUT, flavour, optional IP), DRYRUN, CLEAN, ARCHIVE flags
  +---------------+----------------+
                  |
  +---------------v----------------+
  | 2. Flavour Validation          | Validate flavour matches one of INST-A, INST-B, MAGPS, QPMS
  +---------------+----------------+
                  |
  +---------------v----------------+
  | 3. Hostname & Offset Math      | Parse trailing number (e.g. 100), add +500 (e.g. 600)
  +---------------+----------------+
                  |
  +---------------v----------------+
  | 4. Workspace Staging           | Clean/recreate XRM/XRM_STAGING
  +---------------+----------------+
                  |
  +---------------v----------------+
  | 5. Template & Package Copy     | Copy XRM/XRM-BASE/mnt and XRM/packages to staging
  +---------------+----------------+
                  |
  +---------------v----------------+
  | 6. Flavour & Var Substitution  | Enable XRM_MODEL line, set XRM_PM, PEERS, ACQ400IOC, IOC_HOST
  +---------------+----------------+
                  |
  +---------------v----------------+
  | 7. Audit Header Generation     | Prepend Git SHA, user, timestamp, incantation to rc.user
  +---------------+----------------+
                  |
  +---------------v----------------+
  | 8. Remote Deployment           | Direct scp -r or compress -> scp -> ssh tar -xzf
  +--------------------------------+
```

### Detailed Functional Breakdown

1. **Argument & Environment Flag Evaluation**:
   Evaluates positional arguments (`<hostname_string>`, `<flavour_name>`, optional `[ip_address]`) and environment flags (`${DRYRUN}`, `${ARCHIVE}`, `${CLEAN}`, `${SR}`). Resolves `UUT_TARGET` to `[ip_address]` if provided, otherwise defaulting to `<hostname_string>`.

2. **Flavour Parameter Mapping**:
   Maps the command-line flavour argument to its model personality:
   - `INST-A` -> `MODEL_STR="XRM-INST-A"`, `PEERS="1,2"`, `XRM_PM=0`
   - `INST-B` -> `MODEL_STR="XRM-INST-B"`, `PEERS="1,2"`, `XRM_PM=0`
   - `MAGPS`  -> `MODEL_STR="XRM-MagPS"`,  `PEERS="1"`,   `XRM_PM=1`
   - `QPMS`   -> `MODEL_STR="XRM-QPMS"`,   `PEERS="1,2,3,4"`, `XRM_PM=1`

3. **Hostname Offset Calculation**:
   Matches `${HOSTNAME_ARG}` against `^([a-zA-Z0-9]+_)([0-9]+)$`:
   - Adds offset: `NEW_NUM=$((OLD_NUM + 500))`
   - Sets `${NEW_VAR}` (e.g., `acq2206_100` -> `acq2206_600`).

4. **Staging Cleanup & Copy**:
   - Removes any existing `XRM/XRM_STAGING` and creates a fresh staging directory.
   - Copies `XRM/XRM-BASE/mnt` into `XRM/XRM_STAGING/`.
   - Copies `XRM/packages` if present.

5. **Template Configuration (`sed`)**:
   - In `xrm_epics.sh`: Replaces `ACQ400IOCnum` with `${HOSTNAME_ARG}`, `XRMIOCnum` with `${NEW_VAR}`.
   - In `xrm_epics.sh`: Uncomments and activates `export XRM_MODEL="${MODEL_STR}"`.
   - In `xrm_epics.sh`: Sets `export XRM_PM=${XRM_PM}`.
   - In `site-1-peers`: Sets `PEERS=${PEERS}`.

6. **Audit Metadata Injection**:
   Injects deployment metadata into line 2 of `$STAGE_DIR/mnt/local/rc.user`:
   ```sh
   #
   # created by deploy_XRM for uut:$uut xrm_var:$SOURCE_SUBFOLDER
   # by ${user} on $(date)
   # git $githash
   # incant $incant
   ```

7. **UUT Transfer and Decompression**:
   - **Archive Mode (`ARCHIVE=1`)**:
     - Bundles `${STAGE_DIR}/mnt` into a compressed archive: `${STAGE_DIR}/${HOSTNAME_ARG}_payload.tgz`.
     - Securely copies the single archive: `scp ${STAGE_DIR}/${ARCHIVE_NAME} root@${UUT_TARGET}:/tmp/`.
     - Remotely extracts into `/mnt` and cleans up `/tmp`: `ssh root@${UUT_TARGET} "tar -xzf /tmp/${ARCHIVE_NAME} -C /mnt && rm /tmp/${ARCHIVE_NAME}"`.
     - Single SCP transfer minimizes interactive authentication prompts when SSH keys are absent.
   - **Standard Mode (Default)**:
     - Recursively copies directories via `scp -r ${STAGE_DIR}/mnt/local root@${UUT_TARGET}:/mnt/`.
     - Recursively copies packages via `scp -r ${STAGE_DIR}/mnt/packages root@${UUT_TARGET}:/mnt/` (if packages exist).
   - **Dry-Run Mode (`DRYRUN=1`)**:
     - Staging and archive compression are performed locally, while remote SCP and SSH commands are displayed and skipped.

---

## 4. XRM Flavour Reference

All template files are maintained under `XRM/XRM-BASE/`. The 4 supported operational flavours and their auto-configured parameters are:

| Flavour Name | `XRM_MODEL` String | Sample Rate (Hz) | `PEERS` Sites | `XRM_PM` | `NCHAN` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`MAGPS`** | `XRM-MagPS` | 100,000 (100 kHz) | `1` | `1` | 128 |
| **`QPMS`** | `XRM-QPMS` | 100,000 (100 kHz) | `1,2,3,4` | `1` | 128 |
| **`INST-A`** | `XRM-INST-A` | 4,000,000 (4 MHz) | `1,2` | `0` | 32 |
| **`INST-B`** | `XRM-INST-B` | 4,000,000 (4 MHz) | `1,2` | `0` | 32 |

---

## 5. Core Configuration Files Reference

Configuration files reside in `XRM/XRM-BASE/mnt/local/`:

### `mnt/local/sysconfig/xrm_epics.sh`
The primary environment file loaded by the EPICS startup environment. It defines:
- `IOC_HOST`: Secondary / XRM IOC identifier (assigned `${NEW_VAR}` / `+500`).
- `ACQ400IOC`: Primary hardware IOC identifier (assigned `${HOSTNAME_ARG}`).
- `EPICS_CAS_INTF_ADDR_LIST` / `EPICS_PVAS_INTF_ADDR_LIST`: Network interfaces for Channel Access and PVAccess servers (`eth0:44000`).
- `EPICS_CA_ADDR_LIST` / `EPICS_PVA_ADDR_LIST`: Broadcast and interface lists for clients.
- `XRM_MODEL`: Subsystem personality string (`XRM-INST-A`, `XRM-INST-B`, `XRM-MagPS`, or `XRM-QPMS`).
- `XRM_PM`: Process Management flag (`1` for MAGPS/QPMS, `0` for INST-A/B).
- `XRM_INST1` / `XRM_INST2`: Redis publisher strategy pipelines (`STR`, `SPY`).

### `mnt/local/rc.user`
Executed at the end of the Linux boot sequence. Dynamically reads `XRM_MODEL` to configure:
- Clock sample rate (`100000` for MAGPS and QPMS, `4000000` for INST-A and INST-B).
- Judgement mode setup and parameters.
- Cycle trigger direct from front panel and burst mode settings.
- Stream daemon configuration and White Rabbit clock phase adjustment.

### `mnt/local/sysconfig/transient.init`
Dynamically reads `XRM_MODEL` to configure:
- `run0` aggregator site list (`1,5,6` for MAGPS; `1,2,3,4` for QPMS; `1,2` for INST-A; `1,2,5` for INST-B).
- SPAD scratchpad timestamp settings.
- Channel count `NCHAN` (128 for MAGPS/QPMS, 32 for INST-A/INST-B).

### `mnt/local/sysconfig/acq400.sh`
Dynamically reads `XRM_MODEL` to configure `ACQ400_JUDGEMENT` buffer lengths (`4096 d0` for MAGPS/QPMS; `16384 d0` for INST-A/INST-B). Also sets system DMA buffer memory allocation (`BLEN=4194304`, `NBUF=128`) and fan speed.

### `mnt/local/sysconfig/custom_xrm.init`
Performs dynamic hardware mezzanine discovery across sites 1 through 6, applying calibration gain for `acq428elf`, voltage reference and gain for `ao420fmc`, dynamic `CLKDIV` for `dio482elf_xrm`, and White Rabbit TAI timestamp insertion into SPAD words.

### `mnt/local/sysconfig/site-1-peers`
Configures peer site aggregation across ADC mezzanines.

### `mnt/local/sysconfig/bos.sh`, `wr.sh`, `wr_cal`
Configure Buffer-on-System streaming and White Rabbit timing calibration.

---

## 6. Git Version Control Conventions

- All template configurations are stored under `XRM/XRM-BASE/`.
- Binary files (`.bin`) and compressed packages (`.tgz`) are ignored by Git.
- `XRM/XRM_STAGING` is ephemeral and cleared automatically on every deployment run.
- Template files under `XRM/XRM-BASE/` remain clean and version-controlled.


