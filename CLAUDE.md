# CLAUDE.md — ftdi-unbind (repository root)

Orientation for Claude Code instances working in this repository. Read
this first, then the per-platform `CLAUDE.md` in the relevant subdirectory.

## What this repo is

Cross-platform tooling to **rebind FTDI USB devices** between their serial
(VCP / `ftdi_sio`) driver and a raw-USB mode (WinUSB on Windows, an unbound
kernel driver on Linux/macOS) so the device can be claimed by WebUSB,
libusb, or pyftdi — and restored afterwards. CLI surface is identical on
every platform: `ftdi-unbind <VID:PID>` releases, `ftdi-bind <VID:PID>`
restores.

## Git origin

```
git@gitlab.compelcon.se:unified-serial-terminal/ftdi-unbind.git
```

This is the current canonical remote. The repo is host-agnostic and may be
mirrored to GitHub or elsewhere; per-subdirectory docs refer to it
abstractly as `<git origin>`. Follow the commit/push conventions in each
subdirectory's own `CLAUDE.md`.

## Layout

| Directory | Platform | Stack |
|---|---|---|
| `windows/` | Windows | C / CMake; WinUSB via libwdi, VCP restore via SetupAPI |
| `macos-linux/` | Linux & macOS | POSIX shell scripts; sysfs / kext |

Each subdirectory is self-contained (its own README, PLAN, CLAUDE, tests).
Work in one platform at a time; the two share only their CLI contract.

## History

Consolidated from two former standalone repositories, full git history
preserved: `windows/` ← **ftdi-winusb-rebind**, `macos-linux/` ←
**ftdi-rebind-scripts**. The originals are retained as read-only archives.

---

## Current status — v0.1.0 (2026-06-06)

### What is done

**Diagnosis scripts at repo root** — the main deliverable of this milestone.
All three are read-only, require no elevation/sudo, and default to
`0403:6015` (FTDI FT231X / FT232R, used on ULX3S and similar FPGA boards).
An optional VID:PID argument overrides the default.

| File | Platform | Invocation |
|---|---|---|
| `diagnosis.ps1` | Windows PowerShell 5.1+ | `.\diagnosis.ps1` or `.\diagnosis.ps1 0403:6014` |
| `diagnosis.cmd` | Windows CMD (wrapper) | `diagnosis.cmd` |
| `diagnosis.sh` | Linux & macOS (bash 3.2+) | `bash diagnosis.sh` |

`diagnosis.ps1` accepts `-v` / `-verbose` / `-Detailed` to print the full
pnputil driver store listing (default: count summary only).

`README.md` updated to lead with "Start here: run diagnosis first".

**Windows C tools** (`windows/` subdirectory) — phases 0–8 complete
(build, enumerate, install WinUSB, restore VCP, dual-exe CLI, release
packaging). Phases 9–11 (code signing) are in progress. Pre-built binaries
are not yet attached to the release page pending signing.

### What is next / in progress

- **Cross-platform testing of `diagnosis.sh`** on:
  - Raspberry Pi 5, Raspberry OS Trixie (Debian 13 / Linux) — Claude Code installed
  - Mac Mini 2014, macOS 12 Monterey
  Connect a ULX3S (or any 0403:6015 device), run `bash diagnosis.sh`, and
  verify the output is correct for each driver state (ftdi_sio bound,
  unbound, device absent).
- **Windows code signing** (phases 9–11) — Authenticode via Azure Artifact
  Signing; CI workflow is in `windows/`.
- **Release page** — attach signed Windows binaries + `diagnosis.sh` to the
  GitLab releases page once signing is done.

### Key design decisions (carry into new sessions)

- Scripts must be read-only and require **no elevation / no sudo**.
- Default VID:PID is `0403:6015`; all three scripts accept a positional
  override argument so the same script covers other FTDI chips.
- Target audience: EE students mid-lab who are stressed and confused, not
  USB driver experts. Output is verbose and pedagogical by design.
- `unified-serial-terminal` (sister project) is always mentioned as an
  alternative that avoids bind/unbind entirely — critical for university
  lab computers where students cannot run admin tools.
- `diagnosis.sh` is written for bash 3.2 compatibility (macOS ships 3.2).
  No `${var,,}`, no `declare -A`; use `tr` and positional tricks instead.
