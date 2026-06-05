# ftdi-unbind

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

## Quick start

```sh
git clone <git origin> ftdi-unbind
cd ftdi-unbind
```

Replace `<git origin>` with this repository's remote URL (GitHub, GitLab,
or wherever you host it).

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
