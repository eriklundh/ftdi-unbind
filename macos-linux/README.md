# ftdi-unbind / ftdi-bind

Two small, safe scripts to detach the FTDI kernel driver from a device
(freeing it for WebUSB / libusb / pyftdi) and to re-attach it afterwards.
Targeted by `VID:PID`.  Work on **Linux** and **macOS**.

## Platform differences

| | Linux | macOS |
|---|---|---|
| Driver name | `ftdi_sio` (kernel module) | `AppleUSBFTDI` kext + optional `FTDIUSBSerialDriver` kext |
| Mechanism | sysfs bind/unbind | `kextunload` / `kextload` |
| Scope | per-device, per-interface | **global** — all attached FTDI devices |
| Root needed? | yes (sysfs writes) | yes (kext operations) |
| Self-elevating? | yes — re-execs under sudo | yes |
| macOS version limit | — | kextunload of Apple built-in kext may fail on macOS 13 (Ventura)+ with SIP; see below |

## Install

```bash
chmod +x ftdi-unbind ftdi-bind
# Add to PATH, e.g.:
mkdir -p ~/bin && cp ftdi-unbind ftdi-bind ~/bin/
```

## Use

**Always dry-run first.** It shows exactly which devices and interfaces
(Linux) or kexts (macOS) would be touched, and changes nothing:

```bash
ftdi-unbind 0403:6015 --dry-run
```

Then for real:

```bash
ftdi-unbind 0403:6015      # detach FTDI driver → device free for WebUSB
# ... use WebUSB / pyftdi / libusb ...
ftdi-bind   0403:6015      # re-attach driver → /dev/ttyUSB* (Linux) or
                           #                    /dev/cu.usbserial-* (macOS) returns
```

VID:PID is forgiving: `0403:6015`, `0x0403:0x6015`, and `403:6015` all
normalise to the same thing.

## macOS notes

### What gets unloaded

`ftdi-unbind` checks for two kexts and unloads whichever are loaded:

| Kext bundle ID | Source | When present |
|---|---|---|
| `com.apple.driver.AppleUSBFTDI` | macOS built-in | always |
| `com.FTDI.driver.FTDIUSBSerialDriver` | FTDI official VCP driver | only if user installed it |

### Global scope

macOS kext unload/load is not per-device.  If two FTDI devices are
attached — e.g. a ULX3S board and a loopback plug — **both** are
released by `ftdi-unbind`.  The dry-run output lists all matching
devices so you can see the impact before acting.

### macOS 13 (Ventura) and later — SIP restriction

Apple's built-in `com.apple.driver.AppleUSBFTDI` is part of the
immutable system volume on macOS 13+.  `kextunload` may fail with
"Operation not permitted" even as root.

**Practical options:**

1. **Use the Web Serial backend** in the terminal app — it talks to
   the FTDI chip through the VCP driver (`/dev/cu.usbserial-*`) and
   needs no driver swap at all.

2. **Reduce Security** — boot into Recovery OS, open Startup Security
   Utility, choose "Reduced Security" (Intel) or allow user-approved
   kernel extensions (Apple Silicon), reboot, then retry `ftdi-unbind`.

3. **If FTDI's own VCP kext is installed** — it is a third-party kext
   and CAN be unloaded even under standard SIP:
   ```bash
   sudo kextunload -b com.FTDI.driver.FTDIUSBSerialDriver
   ```

### macOS 12 (Monterey) and earlier

`kextunload` of `com.apple.driver.AppleUSBFTDI` works normally without
any security changes.

## Linux notes

`ftdi-unbind` touches only interfaces currently bound to `ftdi_sio` —
other drivers are untouched.  `ftdi-bind` only re-binds interfaces that
are currently driverless; it never steals an interface from another driver.

`ftdi-bind` will `modprobe ftdi_sio` if the module isn't loaded.

### Try without unbinding first

pyftdi (via libusb) can often detach `ftdi_sio` itself when it claims
the device, and reattach on close.  Only if you get
`LIBUSB_ERROR_BUSY` / "unable to claim interface" do you need
`ftdi-unbind`.

## Multi-device caveat (Linux and macOS)

`VID:PID` identifies a *model*, not a *unit*.  Two identical FTDI chips
(e.g. two FT231X boards) will both be matched.

- **Dry-run first** — the output lists every matching device with its
  USB serial number, so you can see exactly what will be hit.
- On Linux, if you need to unbind only one of two identical devices,
  use the interface ID from the dry-run output directly:
  ```bash
  echo -n "1-1.4:1.0" | sudo tee /sys/bus/usb/drivers/ftdi_sio/unbind
  ```
- On macOS, kext operations are always global; if you need to keep one
  device bound, unplug it before running the script, then replug it
  after `ftdi-bind` (or after your WebUSB session).

## Restore options

| Method | Linux | macOS |
|---|---|---|
| `ftdi-bind VID:PID` | rebinds in place (no replug) | reloads kext (no replug) |
| Unplug/replug | always works | always works (simplest) |
| Reboot | always works | always works |

## Requirements

- **Linux:** bash, `ftdi_sio` module available (standard on Debian 13 /
  RPi OS Trixie).
- **macOS:** bash (pre-installed), python3 (pre-installed or via Xcode CLT),
  macOS 10.13 or later.  Tested on macOS 12 (Monterey).
