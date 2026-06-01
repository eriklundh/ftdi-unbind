# ftdi-unbind / ftdi-bind

Two small, safe scripts to detach the kernel `ftdi_sio` driver from an
FTDI device (freeing it for libusb / pyftdi / WebUSB) and to re-attach it
afterwards. Targeted by `VID:PID`.

## Install

```bash
chmod +x ftdi-unbind ftdi-bind
# put them on your PATH, e.g.
mkdir -p ~/bin && cp ftdi-unbind ftdi-bind ~/bin/
#   (ensure ~/bin is in PATH; or use /usr/local/bin)
```

## Use

**Always dry-run first.** It shows exactly which devices and interfaces
would be touched, and changes nothing:

```bash
ftdi-unbind 0403:6015 --dry-run
```

Then for real (the script elevates itself with sudo only when it needs
to write):

```bash
ftdi-unbind 0403:6015      # detach ftdi_sio  → device free for pyftdi
# ... run verify_wiring.py / your driver test ...
ftdi-bind   0403:6015      # re-attach ftdi_sio → /dev/ttyUSB* returns
```

VID:PID is forgiving about format: `0403:6015`, `0x0403:0x6015`, and
`403:6015` all normalise to the same thing.

## What makes them safe

- **Scoped to ftdi_sio.** `ftdi-unbind` only detaches interfaces that are
  *currently bound to ftdi_sio*. `ftdi-bind` only attaches interfaces
  that are *currently driverless* — it never steals an interface from
  another driver, and skips ones already bound.
- **`--dry-run` / `-n`** previews without writing and without needing
  root.
- **Self-elevating.** Runs unprivileged for dry-runs; re-execs under
  `sudo` only when it actually has to write to sysfs.
- **Nothing persistent.** These only change runtime sysfs state. A
  reboot, or an unplug/replug, always restores the default binding — so
  the ultimate "undo" is to power-cycle the device.
- **Clear reporting.** Every device matched is printed with its USB id
  and serial; every interface is reported as unbound / bound / skipped.

## Try without unbinding first

pyftdi (via libusb) can often detach `ftdi_sio` itself when it claims the
device, and reattach on close. So before reaching for these scripts, just
run your pyftdi tool. Only if you get `LIBUSB_ERROR_BUSY` / "unable to
claim interface" do you need `ftdi-unbind`. When libusb auto-detaches but
doesn't reattach on exit, `ftdi-bind` is the clean way to restore.

## Multi-device caveat (important)

VID:PID identifies a *model*, not a *unit*. If two identical FTDI devices
are attached — e.g. your loopback rig **and** a ULX3S board, both
FT231X (0403:6015) — then `ftdi-unbind 0403:6015` detaches **both**.

Mitigations:

1. **Dry-run first** — it lists every matching device with its serial, so
   you see if more than one will be hit before anything changes.
2. If two match and you want only one, either unplug the other first, or
   unbind that one interface by hand using the id from the dry-run:
   ```bash
   echo -n "1-1.4:1.0" | sudo tee /sys/bus/usb/drivers/ftdi_sio/unbind
   ```
   (`1-1.4:1.0` being the specific interface shown in the dry-run output.)

## Restore options, fastest first

1. `ftdi-bind VID:PID` — rebinds in place, no replug.
2. Unplug/replug the device — the kernel re-enumerates and auto-binds.
3. Reboot — guaranteed, since nothing here is persistent.

## Requirements

Linux with the `ftdi_sio` module available (standard on Debian 13 / RPi
OS Trixie). `ftdi-bind` will `modprobe ftdi_sio` if it isn't loaded.
