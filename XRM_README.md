# XRM Deployment Documentation

This document describes the XRM (Extensible Radio Module) configuration architecture, the Git-tracked configuration files, and the function of the deployment script `deploy_XRM.sh`.

---

## 1. Overview

The `deploy_XRM.sh` utility automates staging and remote deployment of custom system configurations and EPICS IOC parameters for D-TACQ ACQ400-series systems configured for the XRM subsystem.

Key responsibilities:
- **Parameter Validation**: Ensures valid hostname formats and validates that the selected deployment model is permitted.
- **Offset Calculation**: Dynamically computes secondary IOC hostname numbers using a `+500` offset (e.g., `acq2206_100` -> `acq2206_600`).
- **Clean Staging Workspace**: Manages a dedicated staging tree in `XRM/XRM_STAGING` to prepare filesystem payloads without dirtying source templates.
- **Variable Substitution**: Replaces template placeholders (`ACQ400IOCnum` and `XRMIOCnum`) with system-specific network names in `xrm_epics.sh`.
- **Traceability & Audit Logging**: Prepends metadata headers to `rc.user` recording the deploying user, timestamp, Git commit SHA, and invocation incantation.
- **Remote Deployment Modes**:
  - **Standard (`scp -r`)**: Transfers the staged `/mnt/local` tree and any packages directly to the target unit via recursive `scp`.
  - **Archive Mode (`ARCHIVE=1`)**: Bundles the entire payload into a single compressed `.tgz` archive, SCPs it to `/tmp` on the target, and extracts it directly into `/mnt` via SSH. Designed to streamline multi-unit rollout and minimize password prompts when SSH keys are not installed.
- **Dry-Run Validation**: Supports `DRYRUN=1` mode to verify staging, archive generation, and variable substitution locally without touching hardware.

---

## 2. Command Line Usage

### Syntax
```bash
[DRYRUN=1] [ARCHIVE=1] ./deploy_XRM.sh <hostname_string> <source_subfolder_name>
```

### Arguments
* `<hostname_string>`: Target UUT hostname. Must end with an underscore followed by a number (e.g., `acq2206_100`).
* `<source_subfolder_name>`: Model/profile directory located under `XRM/`. Must be one of:
  * `INST-A`
  * `INST-B`
  * `INST-B-ALLISON`
  * `MAGPS`
  * `QPMS`
  * `TEST_STAND_FMT_SIM`

### Environment Variables
* `DRYRUN=1`: When set, completes all staging, archive generation, regex substitutions, and audit logging locally in `XRM/XRM_STAGING`, but skips SSH/SCP file transfers to the UUT.
* `ARCHIVE=1`: When set, packages the staged payload into `<hostname>_payload.tgz`, copies it via a single `scp` transfer to `/tmp/` on the UUT, and decompresses it into `/mnt` using `ssh`. Ideal for environments without SSH keys or for high-latency connections.

### Usage Examples

**Dry Run Verification (Standard mode):**
```bash
DRYRUN=1 ./deploy_XRM.sh acq2206_100 MAGPS
```

**Dry Run Verification (Archive mode):**
```bash
DRYRUN=1 ARCHIVE=1 ./deploy_XRM.sh acq2206_100 MAGPS
```

**Live Deployment (Standard mode):**
```bash
./deploy_XRM.sh acq2206_100 MAGPS
```

**Live Deployment (Archive mode - single SCP transfer):**
```bash
ARCHIVE=1 ./deploy_XRM.sh acq2206_100 MAGPS
```

---

## 3. Step-by-Step Function of `deploy_XRM.sh`

```
  +--------------------------------+
  | 1. Argument & Option Parsing   | Validate argument count (2 required) and DRYRUN flag
  +---------------+----------------+
                  |
  +---------------v----------------+
  | 2. Profile Validation          | Validate subfolder matches one of 6 supported profiles
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
  | 5. Template & Package Copy     | Copy XRM/<model>/mnt and XRM/packages to staging
  +---------------+----------------+
                  |
  +---------------v----------------+
  | 6. Variable Substitution       | Replace ACQ400IOCnum and XRMIOCnum in xrm_epics.sh
  +---------------+----------------+
                  |
  +---------------v----------------+
  | 7. Audit Header Generation     | Prepend Git SHA, user, timestamp, incantation to rc.user
  +---------------+----------------+
                  |
  +---------------v----------------+
  | 8. Remote Deployment (SCP)     | Copy staged files to root@<hostname>:/mnt/ (or skip if dry run)
  +--------------------------------+
```

### Detailed Functional Breakdown

1. **Dry-Run Check**:
   Evaluates `${DRYRUN}`. If set to `1`, sets `DRY_RUN=true`; otherwise `false`.

2. **Argument & Subfolder Validation**:
   Checks that exactly two positional arguments are passed. Validates `$2` against allowed models (`INST-A`, `INST-B`, `INST-B-ALLISON`, `MAGPS`, `QPMS`, `TEST_STAND_FMT_SIM`). Exits immediately with an error and usage instructions if input is invalid.

3. **Source Directory Verification**:
   Ensures `XRM/${SOURCE_SUBFOLDER}` exists as a valid directory on disk.

4. **Staging Cleanup**:
   Ensures `XRM/XRM_STAGING` exists. If it already exists and is non-empty, clears all files and hidden entries to avoid contamination from previous runs.

5. **Hostname Regex Parsing & Offset Calculation**:
   Matches `${HOSTNAME_ARG}` against regex `^([a-zA-Z0-9]+_)([0-9]+)$`:
   - Extracts base prefix `${BASE_STR}` (e.g., `acq2206_`).
   - Extracts numeric suffix `${OLD_NUM}` (e.g., `100`).
   - Adds offset: `NEW_NUM=$((OLD_NUM + 500))` (e.g., `100 + 500 = 600`).
   - Assembles `${NEW_VAR}` (e.g., `acq2206_600`).

6. **Filesystem Staging**:
   - Recursively copies `XRM/${SOURCE_SUBFOLDER}/mnt` to `XRM/XRM_STAGING/`.
   - If `XRM/packages` exists, copies it into `XRM/XRM_STAGING/mnt/packages`.

7. **Placeholder Replacements (`sed`)**:
   Targets `XRM/XRM_STAGING/mnt/local/sysconfig/xrm_epics.sh`:
   - Replaces `([a-zA-Z0-9]+_)?ACQ400IOCnum` with `${HOSTNAME_ARG}`.
   - Replaces `([a-zA-Z0-9]+_)?XRMIOCnum` with `${NEW_VAR}`.

8. **Audit Metadata Injection**:
   Retrieves current git commit hash (`git rev-parse HEAD`), current user/host, and command-line incantation, then prepends an audit block at line 2 of `$STAGE_DIR/mnt/local/rc.user`:
   ```sh
   #
   # created by deploy_XRM for uut:$uut xrm_var:$SOURCE_DIR
   # by ${user} on $(date)
   # git $githash
   # incant $incant
   ```

9. **UUT Transfer and Decompression**:
   - **Archive Mode (`ARCHIVE=1`)**:
     - Bundles `${STAGE_DIR}/mnt` into a compressed archive: `${STAGE_DIR}/${HOSTNAME_ARG}_payload.tgz`.
     - Securely copies the single archive: `scp ${STAGE_DIR}/${ARCHIVE_NAME} root@${UUT_TARGET}:/tmp/`.
     - Remotely extracts into `/mnt` and cleans up `/tmp`: `ssh root@${UUT_TARGET} "tar -xzf /tmp/${ARCHIVE_NAME} -C /mnt && rm -f /tmp/${ARCHIVE_NAME}"`.
     - Single SCP transfer minimizes interactive authentication prompts when SSH keys are absent.
   - **Standard Mode (Default)**:
     - Recursively copies directories via `scp -r ${STAGE_DIR}/mnt/local root@${HOSTNAME_ARG}:/mnt/`.
     - Recursively copies packages via `scp -r ${STAGE_DIR}/mnt/packages root@${HOSTNAME_ARG}:/mnt/` (if packages exist).
   - **Dry-Run Mode (`DRYRUN=1`)**:
     - Staging and archive compression are performed locally, while remote SCP and SSH commands are displayed and skipped.


---

## 4. XRM Profiles Reference

The `XRM/` directory contains template configurations for various operational targets. Binary files (`.bin`) and compressed packages (`.tgz`) are ignored by this documentation.

| Profile Name | Operational Purpose | Distinguishing Features |
| :--- | :--- | :--- |
| **`MAGPS`** | Magnet Power Supply System | Dynamic hostname templating (`ACQ400IOCnum`, `XRMIOCnum`), dynamic multi-site mezzanine autodetection via `custom_xrm.init`, and `xrm-aliases.db`. |
| **`QPMS`** | Quadrupole Power Supply Monitoring | Dynamic hostname templating (`ACQ400IOCnum`, `XRMIOCnum`), customized EPICS environment for quadrupole monitoring. |
| **`INST-A`** | Instrumentation System A | Bound to unit `acq2206_097`. Contains system-specific SSL credentials and calibration XMLs (`E42810004.xml`, `E42810005.xml`). |
| **`INST-B`** | Instrumentation System B | Bound to unit `acq2206_099`. Contains system-specific SSL credentials and calibration XMLs (`E42810002.xml`, `E42810003.xml`). |
| **`INST-B-ALLISON`** | Allison Scanner Variant | Variant of `INST-B` setting `XRM_MODEL="XRM-ALLISON"`, using dedicated Redis stream parameters and customized buffer chunk sizes (`320512`). |
| **`TEST_STAND_FMT_SIM`** | Test Stand / Simulation | Simulation configuration (`XRM_MODEL="FMT-SIM"`, `XRM_FMT_SIM=1`) designed for testbenches without physical magnet/detector links. |

---

## 5. Core Configuration Files Reference

Configuration files are organized under the target filesystem structure `mnt/local/`:

### `mnt/local/sysconfig/xrm_epics.sh`
The primary environment file loaded by the EPICS startup environment. It defines:
- `IOC_HOST`: The secondary / XRM IOC name (`${NEW_VAR}` after substitution).
- `ACQ400IOC`: The primary hardware IOC name (`${HOSTNAME_ARG}` after substitution).
- `EPICS_CAS_INTF_ADDR_LIST` / `EPICS_PVAS_INTF_ADDR_LIST`: Interfaces on which Channel Access and PVAccess servers bind (usually `eth0:44000`).
- `EPICS_CA_ADDR_LIST` / `EPICS_PVA_ADDR_LIST`: Broadcast and interface lists for in-process and local clients.
- `XRM_MODEL`: Subsystem model string (`XRM-INST-A`, `XRM-INST-B`, `XRM-ALLISON`, `XRM-MagPS`, `XRM-QPMS`, or `FMT-SIM`).
- `XRM_INST1` / `XRM_INST2`: Data publishing strategies (`STR`, `SPY`) communicating with external Redis brokers.

### `mnt/local/sysconfig/custom_xrm.init` (MAGPS Profile)
A dynamic hardware detection and configuration script:
- Waits for `/var/www/d-tacq/rc-user-complete` to ensure system IOC services are ready.
- Loops through site slots 1 to 6 inspecting `/etc/acq400/<site>/module_name` and `module_type`:
  - **`acq428elf`**: Sets calibration status and sets all channel gains to 1.
  - **`ao420fmc`**: Sets clocks, triggers, sets `CLKDIV 40`, sets reference to 5.0V, and gain to x2.
  - **`dio482elf_xrm`**: Sets clocks/triggers and dynamically adjusts `CLKDIV` (`2` if an `acq428elf` is present in the carrier, `1` otherwise).
- **SPAD Configuration**: Enables White Rabbit TAI seconds-since-epoch timestamping into the scratchpad (`spadcop3`) and aligns the microsecond counter (`spad1_us`).
- **Trigger & Mon Flags**: Configures external hardware cycle trigger (`caput $(hostname):0:SIG:SRC:TRG:0 EXT`) and live waveform monitoring limits.

### `mnt/local/rc.user`
Executed at the end of the Linux boot process. Contains clock master/slave configuration (`set.site 0 sync_role master <freq>`), trigger routing, stream options, White Rabbit clock phase adjustments (`si5326_tune_phase`), and application startup commands.

### `mnt/local/sysconfig/acq400.sh`
Global carrier settings:
- Fan speed tuning (`FANSPEED=100`).
- DMA buffer sizing (`BLEN=4194304`, `NBUF=128`).
- SSL and web authentication settings.

### `mnt/local/sysconfig/bos.sh`
Configures Buffer-on-System and custom streaming options.

### `mnt/local/sysconfig/wr.sh` & `mnt/local/wr_cal`
Holds White Rabbit transceiver calibration constants, link startup scripts, and SFP clock tick configurations.

---

## 6. Git Version Control Notes

When managing files under version control:
- All `.bin` and `.tgz` binaries are excluded from version control tracking.
- Template files under `XRM/<profile>/` must remain clean and checked in without local machine runtime side effects.
- The `XRM/XRM_STAGING` directory is purely transient and will be cleared automatically on every execution of `deploy_XRM.sh`.

