# ftdi-unbind — Windows (WinUSB)

Two Windows command-line tools that switch an FTDI device between its
serial (VCP) driver and **WinUSB** — the Windows part of the
cross-platform device-binding story:

```
ftdi-unbind.exe 0403:6015     install WinUSB   -> WebUSB / pyftdi ready
ftdi-bind.exe   0403:6015     restore FTDI VCP -> COM port returns
```

The Linux and macOS counterparts (`ftdi-unbind` / `ftdi-bind` in the
sibling [`macos-linux/`](../macos-linux/) directory) share identical
flags, exit codes, and VID:PID formats — lab instructions read the same
on every platform.

| Platform | Tool | Mechanism | Scope |
|---|---|---|---|
| **Windows** | `ftdi-unbind.exe` / `ftdi-bind.exe` | libwdi (WinUSB install) / SetupAPI (VCP restore) | Per-device by VID:PID |
| **Linux** | `ftdi-unbind` / `ftdi-bind` | sysfs `ftdi_sio` bind/unbind | Per-device, per-interface |
| **macOS** | `ftdi-unbind` / `ftdi-bind` | `kextunload` / `kextload` | Global (all FTDI devices) |

A third tool handles driver-store cleanup when the VCP driver goes
missing or the COM port number keeps creeping up:

```
ftdi-doctor.exe --diagnose
ftdi-doctor.exe --compact-comdb [--dry-run]
ftdi-doctor.exe --reset-comport 0403:6015 [--dry-run]
ftdi-doctor.exe --purge-store [--dry-run] [--yes]
```

## Why this exists

[Zadig](https://zadig.akeo.ie/) is the standard Windows tool for
installing WinUSB, but its classic failure mode in a classroom or lab is
a student accidentally swapping the driver on the **wrong** device.

`ftdi-unbind` and `ftdi-bind` are the purpose-built replacement:

- strict **VID:PID matching** — never touch a non-matching device
- **refuse on ambiguity** — two identical dongles plugged in? error out,
  list them, and wait for `--all` or for one to be unplugged
- flag/exit-code/VID:PID format **parity with the Linux and macOS
  `ftdi-unbind` / `ftdi-bind` scripts** so lab instructions read
  identically on all platforms

## Quick start

```
# install WinUSB (releases the device for WebUSB / pyftdi)
ftdi-unbind.exe 0403:6015

# restore the FTDI VCP driver (COM port returns)
ftdi-bind.exe 0403:6015

# see all USB devices and their current driver
ftdi-unbind.exe --list

# dry run: show which device would be acted on, change nothing
ftdi-unbind.exe --dry-run 0403:6015
```

Driver-mutating operations (`ftdi-unbind`, `ftdi-bind`,
`ftdi-doctor --purge-store`, `--compact-comdb`, `--reset-comport`)
require an **elevated (administrator) prompt**.  `--list`, `--dry-run`,
and `ftdi-doctor --diagnose` do not.

## VID:PID formats accepted

All three tools accept the same forms the Linux and macOS scripts do:

```
0403:6015       # canonical
0x0403:0x6015   # with 0x prefix
403:6015        # leading-zero-optional
```

## Exit codes

| Code | Meaning |
|------|---------|
| `0`  | success |
| `1`  | no matching device, or ambiguous without `--all` |
| `2`  | bad / missing arguments |

These are identical to the Linux and macOS `ftdi-bind` / `ftdi-unbind` scripts.

## Flags

```
--list            list all USB devices with serial and current driver
--dry-run         resolve + report the target; change nothing (no elevation needed)
--serial SN       target the device with this USB serial number; resolves
                  ambiguity when multiple devices share the same VID:PID
                  without needing --all
--all             act on every matching device (overrides the ambiguity check)
-h/--help         show usage
--about           show copyright information
```

`--serial` and `--all` are mutually exclusive.  When two identical dongles
are attached, the ambiguity error lists each candidate's serial number and
hints `use --serial <value> to select one`.

## Build from source

Requirements: Visual Studio 2022 or 2026 with the **Desktop development
with C++** workload (MSVC + Windows SDK), CMake 3.20+, and
[libwdi v1.5.0](https://github.com/pbatard/libwdi) built as a static
library.  See [`docs/BUILD-ENVIRONMENT.md`](docs/BUILD-ENVIRONMENT.md)
for the full toolchain setup, the libwdi static-build steps, and the
**LGPL-3.0 relink note**.

```
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 ^
    -DLIBWDI_INCLUDE_DIR=C:\path\to\libwdi\libwdi ^
    -DLIBWDI_LIB=C:\path\to\libwdi\x64\Release\lib\libwdi.lib

cmake --build build --config Release
ctest --test-dir build -C Release
```

The unit tests (`ctest`) do not need admin or hardware.  The driver
install/restore integration tests do — see
[`docs/BUILD-ENVIRONMENT.md`](docs/BUILD-ENVIRONMENT.md).

## Why does Windows warn about these binaries?

These executables are unsigned.  Windows SmartScreen shows a blue
"Windows protected your PC" dialog on first run because the binary has no
Authenticode signature and no reputation yet.

**To run them today:**

1. Click **More info** in the SmartScreen dialog.
2. Click **Run anyway**.

This click-through is a one-time action per binary.  Signing will be added
in a future release (see `docs/SIGNING.md`); once signed and reputation is
established the dialog disappears automatically.

If you prefer to build from source — which skips the SmartScreen warning on
your own machine — see the **Build from source** section above.

> **Note for administrators:** Smart App Control and Defender's real-time
> scanner can also block freshly compiled unsigned binaries during
> development.  See [`docs/WINDOWS-DEV-SETTINGS.md`](docs/WINDOWS-DEV-SETTINGS.md)
> for the one-time exclusion steps.

## Licensing

The tool sources are licensed under **GPL-3.0-only** (see `LICENSE`).
They statically link [libwdi](https://github.com/pbatard/libwdi)
(LGPL-3.0).  The GPL-3.0 satisfies the LGPL-3.0 requirement that
end-users can relink against a modified libwdi; if you need a more
permissive licence for your own fork, you must provide a relink path —
see [`docs/BUILD-ENVIRONMENT.md`](docs/BUILD-ENVIRONMENT.md) §Licensing.

---

(c) 2026 Erik Lundh - The Joy of Engineering Compelcon AB
