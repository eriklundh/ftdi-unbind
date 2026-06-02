# CLAUDE.md — ftdi-winusb-rebind

Project memory for Claude Code. Read this first, every session.

## What this is

Two small Windows command-line tools, written in **C** and statically
linked against **libwdi**, that switch an FTDI device between its serial
(VCP) driver and **WinUSB** — the Windows half of the cross-platform
device-binding story:

```
ftdi-unbind.exe 0403:6015     install WinUSB on the FTDI  → WebUSB / pyftdi ready
ftdi-bind.exe   0403:6015     restore the FTDI VCP driver → COM port returns
```

The verb semantics deliberately match the Linux `ftdi-unbind` /
`ftdi-bind` scripts and `DEVICE-BINDING.md`: **unbind = free the device
from the serial driver for libusb/WebUSB; bind = give it back.** Same
command names, same flags, same exit codes, same forgiving `VID:PID`
formats — one mental model across platforms. The whole point is to
replace Zadig's error-prone GUI device-picking with a strict,
VID:PID-scoped CLI.

## Why this exists

Zadig (also built on libwdi) is powerful but GUI-driven, and its classic
failure mode in a classroom is a student swapping the driver on the
*wrong* device. These tools match strictly on VID:PID, refuse to act on
ambiguity unless forced, and never touch a non-matching device.

## The two directions are NOT symmetric — read this before Phase 3/4

- **unbind (install WinUSB)** is what libwdi does natively:
  `wdi_prepare_driver(WINUSB)` + `wdi_install_driver()`. Straightforward.
- **bind (restore FTDI VCP)** is **not** a libwdi install. libwdi installs
  WinUSB/libusb0/libusbK/usbser/custom — it does **not** reinstall FTDI's
  proprietary VCP driver. Restoring means using **SetupAPI / CfgMgr32**
  to remove the WinUSB driver association and re-trigger enumeration so
  Windows reinstalls the original FTDI driver (in-box or via Windows
  Update). This is the riskiest part of the project — see
  `docs/RESTORE-STRATEGY.md`. Design it carefully; a naive version can
  leave the device with no working driver.

## Operating principles

1. **Test-Driven Development (TDD), as far as the target allows.** Same
   discipline as the sibling repos. Driver installation can't be unit
   tested (needs admin + a real device + mutates system state), but the
   **core logic can and must be** — and it's where bugs hide:
   - **Pure logic → classic host-side TDD, test-first, red-green-refactor:**
     VID:PID parsing/normalisation, device-list filtering, ambiguity
     detection, argument parsing, exit-code mapping. These compile
     **without** libwdi or Windows driver APIs (operate on a plain
     `device_record` struct), so the unit tests run anywhere, including
     CI with no hardware.
   - **Driver install/restore → human-gated integration tests** against a
     real FT231X. Never loop an autonomous agent on driver install/remove
     — it mutates system state and needs admin. Claude Code builds and
     unit-tests autonomously; the install/restore checks are run by a
     human (see "build vs install" below).
2. **Small commits**, one logical step each.
3. **Strict safety invariants** (see below) — these are not optional.
4. **No speculative features.** Stick to `PLAN.md`.
5. **Maintain the docs as code.** `PLAN.md`, `docs/BUILD-ENVIRONMENT.md`,
   `docs/LIBWDI-API.md`, `docs/RESTORE-STRATEGY.md`, the phase docs are
   not write-once — update them in the same commit when reality diverges
   (a libwdi API quirk, a SetupAPI gotcha). Commit:
   `docs: update <doc> to match reality`.

## Safety invariants (must hold in every build)

- **Strict VID:PID match.** Only ever act on devices whose VID *and* PID
  equal the requested pair. Never substring/loose match.
- **Refuse on ambiguity.** If more than one device matches, do NOT act;
  list them and exit non-zero — unless `--all` is explicitly given.
- **Never touch a non-matching device.** The Zadig footgun this tool
  exists to kill.
- **`--dry-run` mutates nothing** and needs no admin.
- **Require elevation to act; never silently fail.** If not elevated,
  error clearly with the exact command to re-run elevated (do not
  auto-relaunch in v1 — see PLAN Phase 3).
- **Restore must not leave the device driverless.** The bind direction
  verifies the device re-enumerated with a driver before reporting
  success.

## Build vs install (the autonomy boundary)

| Job | Needs admin + real device? | Who does it |
|-----|----------------------------|-------------|
| Compile, link static libwdi, run unit tests | No | Claude Code, autonomously |
| `--dry-run` / `--list` against real devices | No (enum only) | Claude Code or human |
| Actually install WinUSB / restore VCP | **Yes** | **Human-gated** |

Claude Code owns the build and the pure-logic TDD loop. The
driver-mutating integration tests are run by a human on a machine with
the FT231X attached, because they change system driver state and require
elevation. Don't automate them in a loop.

## Stack

- **Language:** C (C11).
- **Driver install:** libwdi (static), `wdi_*` API. LGPLv3 — see the
  licensing note in `docs/BUILD-ENVIRONMENT.md`.
- **Driver restore:** Win32 SetupAPI (`setupapi.lib`) + CfgMgr32
  (`cfgmgr32.lib`).
- **Build system:** CMake, MSVC toolset (cl.exe). Opens in VSCode (CMake
  Tools) and natively in Visual Studio 2022/2026. Static CRT (`/MT`) so
  the `.exe`s are self-contained and CRT-consistent with libwdi.
- **Tests:** CTest driving small assert-based unit executables (zero
  extra deps); Unity (MIT) is an optional upgrade.
- **Output:** two self-contained `.exe`s, no DLL dependencies (libwdi
  embeds its driver payload).

## Commit convention

Same as the sibling repos:

```
<type>(<scope>): <imperative subject ≤ 60 chars>
```

Types: `test`, `feat`, `fix`, `refactor`, `docs`, `chore`, `build`.
Scopes: `match`, `cli`, `enum`, `install`, `restore`, `cmake`, `core`,
`proj`.

## Branching

`main` always green (builds clean; unit tests pass). One feature branch
per phase (`phase/NN-name`), merged `--no-ff`.

## What to read, in order

1. This file (`CLAUDE.md`)
2. `docs/OPERATING-CLAUDE-CODE.md` if copied in (Remote Control + budget
   apply; the Linux-specific scheduling bits do not — this is Windows)
3. `PLAN.md`
4. `docs/BUILD-ENVIRONMENT.md` — toolchain, libwdi download + static build
5. `docs/LIBWDI-API.md` — the wdi_* calls used
6. `docs/RESTORE-STRATEGY.md` — before Phase 4 (the hard part)

## Out of scope (v0.1)

- A GUI (this is the anti-Zadig: CLI only)
- Non-FTDI devices (the logic is general, but scope/test to FTDI)
- libusb0 / libusbK targets (WinUSB only — that's what WebUSB needs)
- Auto-relaunch with UAC (require elevation, error cleanly instead)
- Signing the `.exe` itself (libwdi self-signs the driver package; EXE
  signing is a later concern)
