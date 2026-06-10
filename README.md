# ftdi-unbind

## Something not working? Start with the diagnosis script

If your FPGA board, FTDI USB adapter, or serial port is not behaving as
expected — no COM port, device not recognised, wrong driver, high port
numbers, connection refused — **run the diagnosis script first.**

It is **read-only and safe**: no changes to your system, no Administrator
or sudo required. It checks your device state, explains what it finds in
plain language, and tells you exactly what to do next.

| Platform | Command |
|---|---|
| Windows — PowerShell | `.\diagnosis.ps1` |
| Windows — Command Prompt | `diagnosis.cmd` |
| Linux or macOS | `bash diagnosis.sh` |

The output ends with a **SUMMARY** section listing any issues found and
the specific commands to fix them.

---

> **Windows users:** these tools do the same driver switch as the well-known
> [Zadig](https://zadig.akeo.ie/) — but scoped to the one FTDI device you
> name on the command line. Zadig's device menu lists *every* USB device in
> the machine, and a single mis-click can replace the driver of an internal
> device (webcam, touchpad, card reader) with WinUSB. `ftdi-unbind` cannot
> touch anything except the VID:PID you give it, and `ftdi-bind` restores
> the original serial driver afterwards.
> (See the [Zadig acknowledgement](#acknowledgement--zadig-and-libwdi) below.)

Cross-platform tools for **rebinding FTDI USB devices** — switching an
FTDI chip between its serial (VCP / `ftdi_sio`) driver and a raw-USB mode
(**WinUSB** on Windows, unbound kernel driver on Linux/macOS) so the
device can be claimed by WebUSB, libusb, or pyftdi — and back again.

```
ftdi-unbind 0403:6015     release FTDI  →  WebUSB / libusb / pyftdi ready
ftdi-bind   0403:6015     restore FTDI  →  serial COM/tty port returns
```

---

## Download

**Download a pre-built release — no compiler or build tools needed.**

→ **[github.com/eriklundh/ftdi-unbind — Releases](https://github.com/eriklundh/ftdi-unbind/releases)**

Each release includes:

- **Windows:** signed `ftdi-unbind.exe` and `ftdi-bind.exe` binaries
- **Linux / macOS:** SHAR-verified shell scripts (`ftdi-unbind.sh`,
  `ftdi-bind.sh`, `diagnosis.sh`)

Verify the shell archive before running:

```sh
shasum -a 256 -c ftdi-unbind-linux.sha256
```

---

## Install and use

### Windows

1. Download `ftdi-unbind.exe` and `ftdi-bind.exe` from the
   [Releases](https://github.com/eriklundh/ftdi-unbind/releases) page.
2. Open PowerShell (Administrator needed for bind/unbind; not for diagnosis).
3. Run `.\diagnosis.ps1` to confirm the device state.
4. Run `.\ftdi-unbind.exe 0403:6015` (replace VID:PID with your device).

See [`windows/README.md`](windows/README.md) for SmartScreen guidance and
full details.

### Linux

```sh
sudo ftdi-unbind 0403:6015    # release to WebUSB/libusb
sudo ftdi-bind   0403:6015    # restore serial driver
```

See [`macos-linux/README.md`](macos-linux/README.md) for install steps.

### macOS

```sh
sudo ftdi-unbind 0403:6015
sudo ftdi-bind   0403:6015
```

See [`macos-linux/README.md`](macos-linux/README.md) for install steps.

---

## Used with

- **[Unified Serial Console](https://unified-serial.delivery-academy.se)** —
  browser-based serial terminal; needs the FTDI chip unbound from the VCP
  driver to use the WebUSB backend.
- **pyftdi** / **libusb** — Python and C FTDI access libraries.
- **OpenOCD / UrJTAG** — JTAG tools that claim the USB device directly.

---

## Acknowledgement — Zadig and libwdi

The Windows side of this toolkit stands on the shoulders of
[Pete Batard](https://github.com/pbatard)'s work. His
[Zadig](https://zadig.akeo.ie/) has been *the* tool for generic USB driver
installation on Windows for well over a decade, and the engineering behind
it — driver packaging, certificate handling, and WinUSB installation that
just works, on machines without any development tooling — is substantial
and relied upon by the whole embedded community.

`ftdi-unbind.exe` uses [libwdi](https://github.com/pbatard/libwdi),
Zadig's actual backend library, to install WinUSB. Our contribution is
only a narrow, FTDI-specific command-line front end with guard rails for
students. If you need to switch drivers on arbitrary USB devices, use
Zadig itself.

---

Developers and contributors: see [DEVELOPER.md](DEVELOPER.md).
