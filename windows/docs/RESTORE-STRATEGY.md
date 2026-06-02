# RESTORE-STRATEGY.md — restoring the FTDI VCP (the hard direction)

This is the riskiest part of the project and the reason the two
directions are not symmetric. Read it fully before writing Phase 4.

## The problem

`ftdi-unbind` installs WinUSB over the device — easy, libwdi does it.
`ftdi-bind` must undo that: get the device back onto FTDI's VCP driver so
it reappears as a COM port. **libwdi cannot do this** — it installs
WinUSB/libusb/usbser/custom drivers, not FTDI's proprietary VCP. So
restore is a Win32 SetupAPI / CfgMgr32 operation:

> Remove the WinUSB driver association from the device, then re-trigger
> enumeration so Windows redetects the device and installs the best
> available matching driver — which, for an FTDI device on a normal
> Windows 10/11 system, is the FTDI VCP (in-box or via Windows Update).

The tool does not *install* the FTDI driver; it *removes WinUSB and lets
Windows reinstall the original*. That distinction is the whole design.

## Strategy

### 1. Locate the device node by VID:PID

```c
HDEVINFO h = SetupDiGetClassDevs(NULL, "USB", NULL,
                                 DIGCF_ALLCLASSES | DIGCF_PRESENT);
// enumerate SP_DEVINFO_DATA; for each, read the hardware id
// (SetupDiGetDeviceRegistryProperty SPDRP_HARDWAREID) and match
// "USB\VID_0403&PID_6015" (case-insensitive substring on VID_/PID_).
```

The hardware-id match is the same strict VID:PID semantics as the rest of
the tool. The *parsing/selection* of which devinfo entry matches is pure
logic and **can be unit-tested** (feed candidate hardware-id strings,
assert which are selected) — do that test-first. The SetupDi calls
themselves are integration-only.

### 2. Remove the WinUSB association

Two viable mechanisms; pick one and document the choice:

- **`DiUninstallDevice`** (newdev.lib) — uninstalls the device's current
  driver (WinUSB) and the device node. Simple; the subsequent re-scan
  reinstalls the best match.
- **`SetupDiCallClassInstaller(DIF_REMOVE, ...)`** — lower-level removal.

Either way the goal is the same: drop the WinUSB binding.

### 3. Re-trigger enumeration

```c
// Re-scan so Windows redetects the device and installs the best driver.
DEVINST devinst; // obtain via CM_Locate_DevNode on the device-id, or the
                 // parent hub's devinst
CM_Reenumerate_DevNode(devinst, CM_REENUMERATE_NORMAL);
```

(`SetupDiCallClassInstaller(DIF_PROPERTYCHANGE)` with
`DICS_PROPCHANGE`, or a full `CM_Reenumerate_DevNode` on the parent, are
the common ways to force a re-scan. Settle on one in Phase 4 and note it
here.)

### 4. Verify — do not claim success blindly

After the re-scan, **confirm the device came back with a working driver**
before reporting success:
- Re-enumerate and read the current `driver` / driver class of the
  matched device.
- Ideally confirm a COM port exists again (the device now has a
  `Ports (COM & LPT)` class / a `PortName` in its registry key).
- If the device returns **driverless** (no FTDI VCP available to
  install), **fail loudly** with recovery guidance:
  - replug the device,
  - ensure the FTDI VCP driver is present (Windows Update online, or
    install FTDI's CDM package once),
  - or "Scan for hardware changes" in Device Manager.

Never leave the user thinking the COM port is back when it isn't.

## The unavoidable caveat

If the FTDI VCP driver is **not present on the system at all** (no in-box
driver, no Windows Update connectivity, never installed), no amount of
re-enumeration can reinstall it — there is nothing to install. The tool
must detect "came back driverless" and say exactly this, rather than
silently leaving the device WinUSB-bound or driverless. On a typical
networked Windows 10/11 lab machine the FTDI VCP is available and the
re-scan reinstalls it cleanly; document the offline case as a known
limitation with the one-time fix (install FTDI CDM drivers).

## Why not just keep it on WinUSB?

For a dedicated test dongle you often *don't* need to restore — leave it
WinUSB and it's permanently WebUSB/pyftdi-ready. `ftdi-bind` exists for
the shared-laptop classroom case where a student needs their COM port
back for other coursework. Make that framing explicit in the README so
people don't run `ftdi-bind` needlessly.

## Testability summary

| Part | Testable how |
|------|--------------|
| Hardware-id VID:PID selection | **unit test** (pure string logic), test-first |
| Remove + re-enumerate + verify | **human-gated integration** on real FT231X |
| "Came back driverless" detection | integration; assert the failure path reports clearly |

This keeps the project's honest-TDD line: the selectable logic is unit
tested; the system-mutating Win32 sequence is integration tested by a
human with the device and admin rights.
