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
