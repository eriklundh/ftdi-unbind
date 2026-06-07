# ftdi-unbind

## Something not working? Start with the diagnosis script

If your FPGA board, FTDI USB adapter, or serial port is not behaving as
expected — no COM port, device not recognised, wrong driver, high port
numbers, connection refused — **run the diagnosis script first.**

It is **read-only and safe**. It makes no changes to your system and does
not require Administrator or sudo. It checks your device state, explains
what it finds in plain language, and tells you exactly what to do next.

| Your platform | Command |
|---|---|
| Windows — PowerShell | `.\diagnosis.ps1` |
| Windows — Command Prompt | `diagnosis.cmd` |
| Linux or macOS | `bash diagnosis.sh` |

All three scripts are in the root of this repository. The output ends
with a **SUMMARY** section listing any issues found and the specific
commands to fix them. The sections above the summary explain the *why*
— read as much or as little as you need.

---

Cross-platform tools for **rebinding FTDI USB devices** — switching an
FTDI chip between its serial (VCP/`ftdi_sio`) driver and a raw-USB mode
(**WinUSB** on Windows, an unbound kernel driver on Linux/macOS) so the
device can be claimed by WebUSB, libusb, or pyftdi — and back again.

The command-line surface is identical on every platform: `ftdi-unbind`
frees the device, `ftdi-bind` restores the serial driver, both targeted
by `VID:PID`. Lab instructions read the same everywhere.

```
ftdi-unbind 0403:6015     release FTDI  -> WebUSB / libusb / pyftdi ready
ftdi-bind   0403:6015     restore FTDI  -> serial COM/tty port returns
```

## Layout

| Directory | Platform | Implementation |
|---|---|---|
| [`windows/`](windows/) | Windows | C / CMake; WinUSB install via [libwdi](https://github.com/pbatard/libwdi), VCP restore via SetupAPI. Ships `ftdi-unbind.exe` / `ftdi-bind.exe`. |
| [`macos-linux/`](macos-linux/) | Linux & macOS | POSIX shell scripts; sysfs `ftdi_sio` bind/unbind on Linux, `kextunload`/`kextload` on macOS. |

Each subdirectory has its own README, plan, and tests — start there for
platform-specific build and usage details.

## Pre-built downloads

**Always check this repository's _Releases_ page first** — published builds of
the `ftdi-unbind` / `ftdi-bind` utilities for both Windows and Linux/macOS are
attached there, so you can grab a ready-made binary instead of building from
source. Where the link lives depends on the host:

- **GitHub:** the **Releases** section in the right-hand sidebar of the
  repository home page, or append `/releases` to the repository URL.
- **GitLab:** **Deploy → Releases** in the left-hand sidebar (older instances:
  **Project → Releases**), or append `/-/releases` to the repository URL.

If no release covers your platform, build from source as below.

## Quick start

```sh
# GitHub mirror (public):
git clone https://github.com/eriklundh/ftdi-unbind.git
# GitLab canonical:
git clone git@gitlab.compelcon.se:unified-serial-terminal/ftdi-unbind.git
cd ftdi-unbind
```

The canonical origin is `git@gitlab.compelcon.se:unified-serial-terminal/ftdi-unbind.git`;
the project is mirrored publicly at **https://github.com/eriklundh/ftdi-unbind**.
Elsewhere in the docs the remote is referred to abstractly as `<git origin>`.

- **Windows:** see [`windows/README.md`](windows/README.md) for the libwdi
  build and signing notes.
- **Linux / macOS:** the scripts in [`macos-linux/`](macos-linux/) are
  ready to run; see [`macos-linux/README.md`](macos-linux/README.md).

## History

This repository consolidates two formerly standalone projects, with their
full git history preserved here under the directories above:

- `windows/` ← **ftdi-winusb-rebind**
- `macos-linux/` ← **ftdi-rebind-scripts**

The original repositories are retained as read-only archives.
