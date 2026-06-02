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

Phases 0–2 and 5 are fully buildable/testable by Claude Code without a
device. Phases 3–4 need a human with the FT231X attached and admin.

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
See `docs/RESTORE-STRATEGY.md` — design before coding.

Strategy (refined in the doc):
1. Locate the device node by VID:PID via SetupAPI
   (`SetupDiGetClassDevs` + enumerate + match hardware id).
2. Remove the WinUSB driver association / uninstall the device node
   (`DiUninstallDevice` or `SetupDiCallClassInstaller(DIF_REMOVE)`), then
   re-trigger enumeration (`CM_Reenumerate_DevNode` on the parent, or
   `cfgmgr32` re-scan) so Windows redetects and installs the best driver
   (the in-box/Windows-Update FTDI VCP).
3. **Verify** the device came back with a driver (and ideally a COM port);
   if it came back driverless, report failure loudly with recovery hints
   (replug, Windows Update, "Scan for hardware changes").

Integration test (human, elevated): after Phase 3 unbind, run bind →
confirm the COM port reappears and the WinUSB node is gone.

Document the caveat: if the FTDI VCP driver isn't present on the system
(no in-box, no Windows Update reach), reinstallation can't conjure it —
the tool must say so rather than silently leaving it WinUSB or driverless.

Commits:
- `docs(restore): finalise the SetupAPI/CfgMgr restore strategy`
- `test(restore): unit-test the device-node match/selection logic`
- `feat(restore): locate device node by VID:PID (SetupAPI)`
- `feat(restore): remove WinUSB + re-enumerate to reinstall VCP`
- `feat(restore): verify a working driver returned; else fail loudly`

Acceptance:
- [ ] After unbind→bind, the COM port returns and WinUSB node is gone
- [ ] If no FTDI VCP is available to reinstall, the tool reports it
      clearly and does not claim success
- [ ] Device-node match logic has unit tests (the selectable pure part)

---

## Phase 5 — Two exes, CLI parity, packaging-ready

Branch: `phase/05-cli-two-exes`

**Goal:** Ship `ftdi-unbind.exe` and `ftdi-bind.exe` as two thin mains
over one shared core, with flags/exit codes identical to the Linux
scripts.

Steps:
1. CMake: build `core` (static lib: match, enum, install, restore) once;
   link into two exes with `src/main_unbind.c` and `src/main_bind.c`
   that set the action.
2. Flag/exit-code parity audit against the Linux scripts: `--dry-run`,
   `--all`, `-h/--help`; exit 2 usage, 1 no-match/ambiguous, 0 ok.
3. Help text mirroring the scripts' wording.

Commits:
- `refactor(core): extract shared core static lib`
- `feat(cli): ftdi-unbind.exe and ftdi-bind.exe over shared core`
- `test(cli): exit-code + flag parity with the Linux scripts`

Acceptance:
- [ ] Both exes built from one core
- [ ] Same flags, exit codes, VID:PID formats as `ftdi-(un)bind` scripts
- [ ] `--help` reads consistently with the Linux tools

---

## Phase 6 — Release

Branch: `phase/06-release`

Steps:
1. `README.md`: what/why, the bind/unbind semantics, quick start, the
   build-from-source steps (link to BUILD-ENVIRONMENT.md), the LGPL
   relink note.
2. `LICENSE`: GPLv3 (recommended for static LGPLv3 libwdi linking — see
   BUILD-ENVIRONMENT.md §licensing) or a permissive licence plus a
   documented relink path. Decide and be consistent.
3. `CHANGELOG.md`; tag `v0.1.0`.
4. Attach both `.exe`s (x64; ARM64 optional — libwdi 1.5.0 supports it).
5. Confirm self-contained: `dumpbin /dependents` shows only system DLLs.

Acceptance:
- [ ] Fresh checkout builds both exes per the README on a clean VS box
- [ ] Exes are self-contained (no third-party DLLs)
- [ ] `v0.1.0` tagged; binaries attached
- [ ] README lets a contributor build from source in VSCode or VS
