# FTDI-DOCTOR.md — driver store diagnosis and repair strategy

Read this before Phase 5. It is the companion to `RESTORE-STRATEGY.md`:
where that doc covers removing a WinUSB binding from a connected device,
this one covers repairing the Windows driver store so the FTDI VCP driver
can be reinstalled at all.

## The problem

`ftdi-bind` removes WinUSB and re-enumerates the device. If Windows cannot
find a matching driver to reinstall, the device comes back driverless and
`ftdi-bind` reports `RESTORE_ERR_DRIVERLESS`. This happens even after
running FTDI's CDM installer, and CDM itself may fail silently. The root
cause is almost always one of:

1. **Stale/corrupted `oem*.inf` in the driver store** — a previous CDM
   install left an entry that Windows flags as invalid, mismatched, or
   superseded in a way that blocks new installs.
2. **Driver store entry absent entirely** — CDM was never run elevated, or
   a Windows Update that carried the in-box FTDI driver was skipped.
3. **Conflicting lower-ranked entries** — multiple `oem*.inf` files match
   `USB\VID_0403&PID_6015`; Windows picks the wrong one or none.

## What `ftdi-doctor` does

It does not install the FTDI VCP driver. It clears the way so that CDM
(or Windows Update) can install it cleanly. The workflow is:

```
ftdi-doctor --diagnose          # find stale entries; no changes
ftdi-doctor --purge-store       # delete them (elevated)
# Then: run CDM2123620_Setup.exe (elevated)
# Then: replug the FTDI device
# Then: ftdi-bind 0403:6015 should succeed
```

## Strategy

### 1. Enumerate driver store entries

The Windows driver store lives under `%SystemRoot%\System32\DriverStore\FileRepository`
(for staged packages) and is indexed by `oem*.inf` files in `%SystemRoot%\INF`.

Walk all `oem*.inf` files and, for each, read its hardware-ID list using
`SetupAPI`:

```c
HINF hInf = SetupOpenInfFileA(path, NULL, INF_STYLE_WIN4, NULL);
// Section [Manufacturer] → [Models] → hardware IDs
// Look for any line containing "VID_0403" (case-insensitive)
SetupFindFirstLineA(hInf, "Manufacturer", NULL, &ctx);
// ... iterate Models sections ...
SetupCloseInfFile(hInf);
```

For each matching `oem*.inf`, extract and print:
- File name (`oem42.inf`)
- Provider (`FTDI`, `ftdichip.com`, etc.) from `[Version]` section
- `DriverVer` date + version string
- Class name / GUID

This is what `pnputil /enum-drivers` does; doing it from C avoids locale-
dependent output parsing.

Supplement: call `SetupDiBuildDriverInfoList` with the FTDI hardware ID
to see which entry Windows would actually select for a connected device.
This reveals ranking conflicts (multiple matches, Windows picks version X
over Y).

### 2. Purge stale entries

```c
SetupUninstallOEMInfA(
    "oem42.inf",          // filename only, not full path
    SUOI_FORCEDELETE,     // delete even if in use by a device
    NULL);
```

`SUOI_FORCEDELETE` is required because a device may currently be bound to
the entry (e.g., still showing as WinUSB). Without it, `SetupUninstallOEMInf`
returns `ERROR_INF_IN_USE`.

Iterate over all FTDI-matching entries found in step 1 and remove each.
After removal, run CDM (or `pnputil /add-driver`) to install a fresh entry.

### 3. Dry-run

Before any deletion, `--dry-run` prints the list of entries that would
be removed. This is the safe first step and is what the user should share
when diagnosing on a machine they haven't analysed yet.

### 4. Verify

After `--purge-store` + CDM reinstall, `--diagnose` should show exactly
one clean FTDI entry. Then `ftdi-bind 0403:6015` (with device plugged in)
should return `RESTORE_OK` rather than `RESTORE_ERR_DRIVERLESS`.

## The unavoidable caveat

`--purge-store` removes *all* FTDI VCP `oem*.inf` entries — including any
that were working for other FTDI devices on the system. After purging, CDM
must be reinstalled for any FTDI VCP device to work again. Make this clear
in the tool's output before deletion and require the user to pass `--yes`
(or confirm interactively) to proceed beyond `--dry-run`.

## Testability summary

| Part | Testable how |
|------|--------------|
| `oem*.inf` hardware-ID scanning logic | **unit test** (pure string/file logic) |
| `--diagnose` reading real driver store | autonomous (reads only; no mutations) |
| `--dry-run` | autonomous (reads only) |
| `--purge-store` | **human-gated** (mutates driver store; requires elevation) |
| CDM reinstall after purge | human-gated |
| `comdb_is_allocated`, `comdb_clear_port`, `comdb_port_from_name` | **unit test** (`test_comdb`, 23 assertions) |
| `--compact-comdb --dry-run` | autonomous (reads ComDB; no mutations) |
| `--compact-comdb` | **human-gated** (writes ComDB; requires elevation) |
| `--reset-comport` | **human-gated** (writes ComDB + device registry; requires elevation) |

## Known symptom pattern — driver store collision

The failure mode that prompted this tool on the development machine:
- `ftdi-bind` reports `RESTORE_ERR_DRIVERLESS` after every unbind.
- `CDM2123620_Setup.exe` runs without a visible error dialog but the
  driver is not installed (or appears installed but does not take effect).
- `pnputil /enum-drivers` reveals stale `oem*.inf` entries from libwdi
  never cleaned up after previous unbind sessions, including entries that
  wrongly claim the Ports class GUID for a WinUSB driver file. These
  "win" the driver selection race over the real CDM pair.
- Confirmed entries on the development machine: oem292, oem385, oem430,
  oem431, oem472, oem473, oem474 (all libwdi-generated). Real CDM pair:
  oem502 (ftdibus.inf), oem503 (ftdiport.inf).
- Fix: `pnputil /delete-driver oem*.inf /force` for all libwdi entries,
  then replug — CDM was already healthy, no reinstall needed.
- Future fix: `ftdi-doctor --purge-store`, then replug.

## Known symptom pattern — COM port number accumulation

Windows never automatically frees COM port numbers from the `ComDB`
bitmask. Each reinstall (unbind→bind cycle) consumes a new bit. After
many cycles the device reaches COM25, COM30, etc.

Registry location: `HKLM\SYSTEM\CurrentControlSet\Control\COM Name Arbiter`
Value: `ComDB` REG_BINARY (32 bytes). Bit N-1 = COM port N (LSB first).

Active ports (currently live) can be read from:
`HKLM\HARDWARE\DEVICEMAP\SERIALCOMM` — one value per active serial device.

Per-device assignment: `PortName` REG_SZ under the device's
`Device Parameters` registry key (opened via `SetupDiOpenDevRegKey`).

Fix workflow:
1. `ftdi-doctor --compact-comdb --dry-run` — see orphaned ports.
2. `ftdi-doctor --compact-comdb` (elevated) — prune orphaned bits.
3. Replug FTDI device → Windows assigns a low COM port number.

Or for a targeted single-device fix:
1. `ftdi-doctor --reset-comport 0403:6015` (elevated) — clear the FTDI
   device's ComDB bit and delete its `PortName` from the device registry.
2. Replug → gets a fresh, low port number.

Note: `--compact-comdb` does NOT affect ports claimed by other active
devices (printers, Bluetooth, LTE modems, etc.). Only orphaned bits
(allocated in ComDB but not present in SERIALCOMM) are cleared.

This is widely reported for any USB serial device that gets reinstalled
repeatedly on Windows. `ftdi-doctor` automates the manual `regedit` fix.
