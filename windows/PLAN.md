# PLAN.md — ftdi-winusb-rebind

Phased, test-first where the target allows. Pure logic gets classic
red-green-refactor unit tests; the driver-mutating directions get
human-gated integration tests against a real FT231X.

## "Phase complete" criteria

1. Builds clean via CMake + MSVC (no warnings-as-errors tripped).
2. Unit tests pass (`ctest`) where the phase has any.
3. The phase's integration check passes on a real device where it has one
   (human-run, elevated).
4. Docs updated for any divergence.
5. Branch merged to `main` with `--no-ff`.

Phases 0–2, 6, and 7 are fully buildable/testable by Claude Code without
a device. Phase 5 (ftdi-doctor) needs elevation but no device. Phases 3–4
need a human with the FT231X attached and admin.

---

## Phase 0 — Build skeleton + static libwdi link

Branch: `phase/00-build-skeleton`

**Goal:** A CMake project that statically links libwdi and runs, proving
the toolchain + static link before any logic. The "blink" equivalent.

Prereq: libwdi built as a static lib per `docs/BUILD-ENVIRONMENT.md`
(clone pbatard/libwdi, build `libwdi.lib` with WinUSB enabled, static
CRT `/MT`).

Steps:
1. `CMakeLists.txt`: C11, MSVC, `/MT`. An executable `ftdi-rebind-probe`.
2. Locate libwdi: `LIBWDI_INCLUDE_DIR`, `LIBWDI_LIB` (cache vars, doc'd).
   Link `${LIBWDI_LIB}` plus `setupapi cfgmgr32 ole32 newdev`.
3. `src/probe.c`: call `wdi_get_version_info()` (or equivalent) and print
   the libwdi version → proves the static link resolves.
4. `.vscode/` with CMake Tools kit hints; confirm it also opens in
   VS2022/2026 as a CMake project.
5. Build, run, see the libwdi version.

Commits:
- `chore(cmake): scaffold CMake/MSVC project, C11, static CRT`
- `build(libwdi): locate and statically link libwdi`
- `feat(proj): probe prints libwdi version to prove the link`
- `docs: record toolchain + libwdi build in BUILD-ENVIRONMENT.md`

Acceptance:
- [ ] `cmake --build` produces `ftdi-rebind-probe.exe`
- [ ] Running it prints the libwdi version
- [ ] `.exe` has no non-system DLL dependencies (`dumpbin /dependents`)
- [ ] Opens cleanly in both VSCode (CMake Tools) and VS2022/2026

---

## Phase 1 — Pure core: VID:PID parse + matching (TDD)

Branch: `phase/01-match-core`

**Goal:** The pure, hardware-free logic, developed test-first. No libwdi,
no Windows driver APIs — operates on a plain `device_record` struct so
the unit tests run anywhere.

Files: `src/match.c/.h`, `tests/test_match.c`, CTest wiring.

Develop test-first (red → green → refactor):
1. `vidpid_parse("0x0403:0x6015", &vid, &pid)` and friends:
   accept `0403:6015`, `0x0403:0x6015`, `403:6015`; lowercase; reject
   missing colon, non-hex, out-of-range. Returns status + 16-bit values.
2. `match_devices(records[], n, vid, pid, out_matches[])`: strict VID&&PID
   equality; returns count. Ambiguity = count > 1.
3. Arg model: `parse_args(argc, argv, &opts)` → action implied by the
   built exe, plus `--dry-run`, `--all`, `-h`; exit-code mapping
   (2 usage, 1 no-match/ambiguous-without-all, 0 ok).

Commits (interleaved test/feat):
- `test(match): vidpid_parse accepts/normalises/rejects forms`
- `feat(match): implement vidpid_parse`
- `test(match): strict matching + ambiguity detection`
- `feat(match): implement device matching`
- `test(cli): argument + exit-code model`
- `feat(cli): implement arg parsing`

Acceptance:
- [ ] `ctest` green; covers normalisation, rejection, match, ambiguity
- [ ] Core compiles with no libwdi/Windows-driver dependency
- [ ] Semantics match the Linux scripts exactly (same inputs → same calls)

---

## Phase 2 — Enumeration + `--list` + `--dry-run`

Branch: `phase/02-enumerate-list`

**Goal:** Wire real libwdi enumeration to the pure matcher. Read-only —
no driver changes, no admin.

Steps:
1. Adapter: `wdi_create_list()` → array of `device_record` (vid, pid,
   description, hardware/instance id). `wdi_destroy_list()` after.
2. `--list`: print all FTDI-ish devices with VID:PID + description +
   current driver (parallels `list_devices.py`).
3. `--dry-run`: resolve the VID:PID, print exactly which device(s) would
   be acted on (with description + instance id), change nothing.
4. Enforce the ambiguity rule here: >1 match → list + non-zero exit
   unless `--all`.

Commits:
- `feat(enum): adapt wdi_create_list to device_record`
- `feat(cli): --list shows devices and current driver`
- `feat(cli): --dry-run reports the target without acting`
- `feat(cli): refuse ambiguous match unless --all`

Acceptance:
- [ ] `--list` shows the attached FT231X with `0403:6015`
- [ ] `--dry-run 0403:6015` names the exact device, changes nothing
- [ ] Two identical dongles → `--dry-run` lists both; acting refuses
      without `--all`

---

## Phase 3 — Unbind direction: install WinUSB (human-gated)

Branch: `phase/03-install-winusb`

**Goal:** `ftdi-unbind.exe 0403:6015` installs WinUSB on the matching
device, freeing it for WebUSB/pyftdi.

Steps:
1. Elevation check: if not elevated, print the exact elevated re-run
   command and exit non-zero. **Do not** auto-relaunch (v1 decision).
2. `wdi_prepare_driver(info, tmpdir, inf, &WINUSB_opts)` then
   `wdi_install_driver(...)` for the matched device. Surface libwdi
   error strings (`wdi_strerror`).
3. On success, report the device now presents as a WinUSB device.

Integration test (human, elevated, real FT231X):
- Run it; confirm the COM port disappears and Device Manager shows a
  WinUSB device under "Universal Serial Bus devices"; confirm
  `python list_devices.py` (pyftdi) now sees it and `verify_wiring.py`
  can open it.

Commits:
- `feat(install): elevation check with clear re-run guidance`
- `feat(install): install WinUSB on the matched device via libwdi`
- `docs: record the install flow + libwdi options in LIBWDI-API.md`

Acceptance:
- [ ] Non-elevated run errors cleanly with the re-run command
- [ ] Elevated run installs WinUSB on exactly the matched device
- [ ] pyftdi/WebUSB can subsequently claim the device

---

## Phase 4 — Bind direction: restore the FTDI VCP (human-gated, hard)

Branch: `phase/04-restore-vcp`

**Goal:** `ftdi-bind.exe 0403:6015` removes the WinUSB association and
gets Windows to reinstall the FTDI VCP driver, so the COM port returns.
See `docs/RESTORE-STRATEGY.md`.

The two-exe build is done in this phase (not Phase 5) because
`ftdi-bind.exe` must exist before the integration test can run.

Implementation:
1. `hwid_matches_vidpid(hwid, vid, pid)` — pure function added to
   `match.c`: finds `VID_XXXX&PID_XXXX` in a Windows hardware-ID string,
   exactly 4 hex digits each, case-insensitive. Unit-tested in
   `tests/test_restore.c` (14 assertions; runs without admin or hardware).
2. `src/restore.c`: SetupAPI + CfgMgr32 restore flow:
   - `SetupDiGetClassDevs("USB")` + SPDRP_HARDWAREID multi-sz scan via
     `hwid_matches_vidpid` to locate the device node.
   - `CM_Get_Parent` to capture the hub DEVINST before removal.
   - `DiUninstallDevice` to drop the WinUSB binding and remove the node.
   - `CM_Reenumerate_DevNode` on the parent to re-trigger enumeration.
   - Poll up to 5 s (10 × 500 ms): device returns with driver →
     `RESTORE_OK`; driverless → `RESTORE_ERR_DRIVERLESS` with actionable
     recovery guidance; never re-enumerated → `RESTORE_ERR_NOENUM`.
3. `src/main.c` takes `ACTION_THIS` as a compile-time define; CMake
   builds `ftdi-unbind.exe` (`ACTION_THIS=ACTION_UNBIND`) and
   `ftdi-bind.exe` (`ACTION_THIS=ACTION_BIND`) from the same source.

Integration test (human, elevated, real FT231X):

```
# From an elevated prompt, with the FT231X plugged in:
ftdi-unbind.exe 0403:6015          # install WinUSB (Phase 3 flow)
ftdi-bind.exe   0403:6015          # restore VCP (Phase 4 flow)
# Confirm: COM port returns; WinUSB node gone in Device Manager
```

Caveat: if the FTDI VCP driver is not present on the system (no in-box
driver, no Windows Update connectivity, never installed), re-enumeration
cannot conjure it. The tool detects "driverless after re-enum" and reports
`RESTORE_ERR_DRIVERLESS` with recovery instructions (install FTDI CDM
package or connect to Windows Update, then replug).

Commits:
- `test(restore): unit-test hwid_matches_vidpid (device-node selection)`
- `feat(restore): locate devnode, remove WinUSB, re-enumerate, verify VCP`
- `build(cli): build ftdi-unbind.exe and ftdi-bind.exe from shared main.c`
- `docs(phase-04): record implementation choices and integration test`

Acceptance:
- [x] Device-node match logic has unit tests (`ctest` green, no admin)
- [x] `ftdi-unbind.exe` and `ftdi-bind.exe` both build from one `main.c`
- [ ] Elevated: after `ftdi-unbind`, `ftdi-bind 0403:6015` restores the
      COM port; WinUSB node gone in Device Manager
- [ ] If no FTDI VCP driver is present, the tool reports clearly and does
      not claim success

---

## Phase 5 — ftdi-doctor: driver store diagnosis and repair

Branch: `phase/05-ftdi-doctor`

**Goal:** `ftdi-doctor.exe` diagnoses and repairs the FTDI VCP driver
store state — the failure mode behind `RESTORE_ERR_DRIVERLESS` when the
CDM driver package is missing, corrupted, or blocked by a conflicting
stale entry.

This is a separate tool from `ftdi-bind` because it operates on the
Windows driver store rather than a connected device, and often must run
before the device is plugged in. See `docs/FTDI-DOCTOR.md` for strategy.

Commands:
- `ftdi-doctor --diagnose` — enumerate driver store packages and registry
  entries matching FTDI/VCP hardware IDs; no mutations; no elevation
  needed beyond driver store listing.
- `ftdi-doctor --purge-store` — remove stale/conflicting FTDI `oem*.inf`
  entries via `SetupUninstallOEMInf(..., SUOI_FORCEDELETE)`; requires
  elevation; prepares the system for a clean CDM reinstall.
- Both commands support `--dry-run` (show what would happen; no changes).

Implementation approach:
- Enumerate driver packages: walk `%SystemRoot%\INF\oem*.inf` and check
  each with `SetupGetInfInformation` / `SetupFindFirstLine` for hardware
  IDs matching `USB\VID_0403` (the approach `pnputil /enum-drivers` uses
  internally). Print `oem*.inf` name, provider, driver version, and class.
- Supplement with `SetupDiBuildDriverInfoList` to show which entry Windows
  would actually pick for the connected hardware ID.
- Remove: `SetupUninstallOEMInf(infFileName, SUOI_FORCEDELETE, NULL)`.

Testability:
- `--diagnose` and `--dry-run`: runnable by Claude Code autonomously
  (reads driver store; no mutations; no device required).
- `--purge-store`: human-gated (mutates driver store; requires elevation).

Commits:
- `docs(doctor): FTDI-DOCTOR.md — driver store diagnosis + repair strategy`
- `feat(doctor): --diagnose enumerates FTDI oem*.inf driver store entries`
- `feat(doctor): --purge-store removes stale FTDI INFs (SetupUninstallOEMInf)`
- `feat(doctor): --dry-run for purge-store`

Acceptance:
- [ ] `--diagnose` lists FTDI `oem*.inf` entries without elevation;
      output includes inf name, provider, driver version
- [ ] `--purge-store --dry-run` shows what would be deleted, changes nothing
- [ ] `--purge-store` (elevated) removes stale entries; CDM setup succeeds after
- [ ] After `--purge-store` + CDM reinstall, `ftdi-bind 0403:6015`
      restores the COM port

---

## Phase 6 — CLI parity audit and help text

Branch: `phase/06-cli-parity`

**Goal:** Verify flag/exit-code/help-text parity with the Linux
`ftdi-unbind` / `ftdi-bind` scripts now that both exes exist.

Steps:
1. Flag/exit-code audit against the Linux scripts: `--dry-run`, `--all`,
   `-h/--help`; exit 2 usage, 1 no-match/ambiguous, 0 ok.
2. Help text: tighten wording to mirror the Linux tools' phrasing.
3. CTest: add exit-code tests (run the exes with bad args, check `$?`).

Commits:
- `test(cli): exit-code + flag parity with the Linux scripts`
- `fix(cli): align help text and exit codes with Linux tools`

Acceptance:
- [ ] Same flags, exit codes, VID:PID formats as `ftdi-(un)bind` scripts
- [ ] `--help` reads consistently with the Linux tools
- [ ] CTest covers the exit-code contract

---

## Phase 7 — Release

Branch: `phase/07-release`

Steps:
1. `README.md`: what/why, the bind/unbind/doctor semantics, quick start,
   the build-from-source steps (link to BUILD-ENVIRONMENT.md), the LGPL
   relink note.
2. `LICENSE`: GPLv3 (recommended for static LGPLv3 libwdi linking — see
   BUILD-ENVIRONMENT.md §licensing) or a permissive licence plus a
   documented relink path. Decide and be consistent.
3. `CHANGELOG.md`; tag `v0.1.0`.
4. Attach all three `.exe`s (x64; ARM64 optional — libwdi 1.5.0 supports it).
5. Confirm self-contained: `dumpbin /dependents` shows only system DLLs.

Acceptance:
- [ ] Fresh checkout builds all exes per the README on a clean VS box
- [ ] Exes are self-contained (no third-party DLLs)
- [ ] `v0.1.0` tagged; binaries attached
- [ ] README lets a contributor build from source in VSCode or VS
