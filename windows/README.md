# ftdi-winusb-rebind planning package

A TDD-style development plan for **ftdi-winusb-rebind** — two Windows CLI
tools in **C**, statically linked against **libwdi**, that switch an FTDI
device between its serial (VCP) driver and **WinUSB**:

```
ftdi-unbind.exe 0403:6015     install WinUSB  → WebUSB / pyftdi ready
ftdi-bind.exe   0403:6015     restore the FTDI VCP → COM port returns
```

These are the Windows half of `DEVICE-BINDING.md` and the purpose-built
replacement for Zadig's error-prone GUI — strict VID:PID matching, refuse
on ambiguity, never touch the wrong device. The verb semantics, flags,
exit codes, and VID:PID formats deliberately match the Linux
`ftdi-unbind` / `ftdi-bind` scripts so the lab instructions read
identically across platforms.

## Hand-off to Claude Code

Clone an empty `ftdi-winusb-rebind` repo and copy this package in:

```
CLAUDE.md                              ->  CLAUDE.md
PLAN.md                                ->  PLAN.md
docs/BUILD-ENVIRONMENT.md              ->  docs/BUILD-ENVIRONMENT.md
docs/LIBWDI-API.md                     ->  docs/LIBWDI-API.md
docs/RESTORE-STRATEGY.md               ->  docs/RESTORE-STRATEGY.md
docs/phases/PHASE-00-build-skeleton.md ->  docs/phases/PHASE-00-build-skeleton.md
docs/phases/PHASE-01-match-core.md     ->  docs/phases/PHASE-01-match-core.md
docs/phases/PHASE-02-enumerate-list.md ->  docs/phases/PHASE-02-enumerate-list.md
docs/phases/PHASE-03-install-winusb.md ->  docs/phases/PHASE-03-install-winusb.md
docs/phases/PHASE-04-restore-vcp.md    ->  docs/phases/PHASE-04-restore-vcp.md
docs/phases/PHASE-05-cli-two-exes.md   ->  docs/phases/PHASE-05-cli-two-exes.md
docs/phases/PHASE-06-release.md        ->  docs/phases/PHASE-06-release.md
```

Optionally copy `OPERATING-CLAUDE-CODE.md` from the main package into
`docs/` — the Remote Control and budget guidance apply, but note this is
**Windows**: the Linux-specific scheduling bits (`at`, `tmux`, `sudo`)
don't apply; Windows uses Task Scheduler and UAC. Then point Claude Code
at it:

> Read CLAUDE.md and docs/BUILD-ENVIRONMENT.md, then start Phase 0 from
> docs/phases/PHASE-00-build-skeleton.md.

## Build vs install — the autonomy boundary

The key operational rule (full table in CLAUDE.md): Claude Code builds,
links static libwdi, and runs the pure-logic unit tests **autonomously**.
The driver-mutating integration tests (Phases 3–4) need **admin + the
real FT231X** and are **human-run** — you don't loop an autonomous agent
on driver install/remove. Bring any libwdi or SetupAPI surprises from
those back to the design thread.

## Toolchain (decided)

- **C11**, **CMake**, **MSVC** toolset, **static CRT (`/MT`)**.
- Opens in **VSCode** (CMake Tools — the contribution-friendly path) and
  natively in **Visual Studio 2022/2026**. CMake is the common
  denominator so neither IDE is required.
- Two self-contained `.exe`s (libwdi embeds its WinUSB payload; `/MT`
  removes the vcruntime dependency).

See `docs/BUILD-ENVIRONMENT.md` for every download source (libwdi v1.5.0
from github.com/pbatard/libwdi, the VS C++ workload, optional Unity), the
static-libwdi build steps, the link dependencies, and the **LGPL-3.0**
relink note.

## The one thing to understand first

**The two directions are not symmetric.**
- **unbind** (install WinUSB) is native libwdi — easy.
- **bind** (restore FTDI VCP) is **not** a libwdi install. libwdi doesn't
  reinstall FTDI's proprietary driver. Restore means SetupAPI/CfgMgr32:
  remove the WinUSB association, re-trigger enumeration so Windows
  reinstalls the FTDI VCP, then verify it actually came back. This is the
  riskiest part — `docs/RESTORE-STRATEGY.md` designs it before Phase 4.

## TDD on a driver tool — what's honest

Driver installation can't be unit-tested (admin + real device + mutates
system state). So, exactly like the firmware repo:
- **Pure logic → classic host-side TDD, test-first:** VID:PID
  parse/normalise, device matching, ambiguity detection, arg parsing,
  exit codes, and the hardware-id selection in the restore path. These
  compile without libwdi/Windows-driver APIs and run anywhere — and
  they're where the *safety* lives.
- **Install/restore → human-gated integration tests** on a real FT231X.

## Package layout

```
ftdi-winusb-rebind-plan/
├── README.md                 ← this file
├── CLAUDE.md                 ← project memory: semantics, safety, stack, TDD
├── PLAN.md                   ← phases 0–6
└── docs/
    ├── BUILD-ENVIRONMENT.md  ← toolchain + ALL download sources + LGPL note
    ├── LIBWDI-API.md         ← the wdi_* calls (unbind direction)
    ├── RESTORE-STRATEGY.md   ← SetupAPI/CfgMgr restore (bind direction, hard)
    ├── SIGNING.md            ← cheapest-path code signing + CI secrets + forker setup
    │                            (CI.md — the release pipeline matrix — still to come)
    └── phases/
        ├── PHASE-00-build-skeleton.md   ← CMake + static libwdi link (the "blink")
        ├── PHASE-01-match-core.md       ← pure VID:PID + matching (TDD)
        ├── PHASE-02-enumerate-list.md   ← wdi_create_list, --list, --dry-run
        ├── PHASE-03-install-winusb.md   ← unbind: install WinUSB (human-gated)
        ├── PHASE-04-restore-vcp.md      ← bind: restore VCP (human-gated, hard)
        ├── PHASE-05-cli-two-exes.md     ← two exes over one core, CLI parity
        └── PHASE-06-release.md          ← self-contained exes, LICENSE, tag
```

## Where it sits in the project

Fourth repo in the family, alongside `ftdi-webusb-driver`, `terminal-app`,
and `pico-cdc-test-rig`. It makes `DEVICE-BINDING.md`'s Windows section
real: the "planned `ftdi-unbind.exe` / `ftdi-bind.exe`" become shipping
tools with the same interface as the Linux scripts.
