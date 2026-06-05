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

**Chosen: `DiUninstallDevice`** (newdev.lib). It uninstalls the device's
current driver (WinUSB) and removes the device node in one call. The
subsequent re-scan then reinstalls the best available match.

`SetupDiCallClassInstaller(DIF_REMOVE, ...)` is the lower-level
alternative but offers no advantage here.

Capture `CM_Get_Parent` on the devnode *before* calling
`DiUninstallDevice` — the devnode vanishes after the call and the parent
DEVINST is needed for the re-enumeration step.

### 3. Re-trigger enumeration

**Chosen: `CM_Reenumerate_DevNode` on the parent hub DEVINST.**

```c
DEVINST parentInst;
CM_Get_Parent(&parentInst, devData.DevInst, 0);
// ... DiUninstallDevice removes devData.DevInst ...
CM_Reenumerate_DevNode(parentInst, CM_REENUMERATE_NORMAL);
```

This asks the parent USB hub/controller to re-scan its ports, which
causes Windows to redetect the device and install the best matching
driver.

### 4. Verify — do not claim success blindly

After the re-scan, **confirm the device came back with a working driver**
before reporting success. Implementation polls up to 5 s (10 × 500 ms):

- Re-open `SetupDiGetClassDevs` and re-run the hardware-ID scan.
- If the device reappears and `SPDRP_DRIVER` is non-empty → `RESTORE_OK`.
- If the device reappears but `SPDRP_DRIVER` is empty → `RESTORE_ERR_DRIVERLESS`
  (no FTDI VCP driver available to install); fail loudly with instructions:
  - install the FTDI CDM package (ftdichip.com) or connect to Windows Update,
  - then replug or run "Scan for hardware changes" in Device Manager.
- If the device does not re-appear within 5 s → `RESTORE_ERR_NOENUM`;
  advise replug.

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
| `hwid_matches_vidpid` string logic | **unit test** (`test_restore`, 14 assertions) |
| Remove + re-enumerate + verify | **human-gated integration** on real FT231X |
| "Came back driverless" detection | integration; assert the failure path reports clearly |

Integration test command sequence (elevated prompt, FT231X plugged in):

```
ftdi-unbind.exe 0403:6015    # install WinUSB
ftdi-bind.exe   0403:6015    # restore VCP
# Verify: COM port returns; WinUSB node gone in Device Manager
```

Both `ftdi-unbind.exe` and `ftdi-bind.exe` are built from the same
`src/main.c` with `ACTION_THIS` set per exe via a CMake compile definition.
The two-exe build is part of Phase 4 (not Phase 5) because `ftdi-bind.exe`
must exist before the integration test can run.

This keeps the project's honest-TDD line: the selectable logic is unit
tested; the system-mutating Win32 sequence is integration tested by a
human with the device and admin rights.
