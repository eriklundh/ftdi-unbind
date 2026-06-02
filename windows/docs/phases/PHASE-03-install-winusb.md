# PHASE-03-install-winusb.md — Unbind direction: install WinUSB

Branch: `phase/03-install-winusb`

**Human-gated:** the build and the elevation-check logic are autonomous,
but the actual install runs on a real FT231X with admin — a human step.

## Goal

`ftdi-unbind.exe 0403:6015` installs WinUSB on the matched device,
freeing it for WebUSB / pyftdi.

> **Note — exe name in Phase 3:** the Phase 5 split into `ftdi-unbind.exe`
> / `ftdi-bind.exe` hasn't happened yet. The built executable is
> `build\Release\ftdi-rebind.exe`; it has `ACTION_UNBIND` baked in and
> behaves identically to the eventual `ftdi-unbind.exe`. Substitute
> `ftdi-rebind.exe` wherever this doc says `ftdi-unbind` below.

## Steps

1. **Elevation check** (`src/elevate.c`): detect via `OpenProcessToken` +
   `GetTokenInformation(TokenElevation)`. If not elevated, print the exact
   command to re-run elevated and exit `EXIT_USAGE`/nonzero. **Do not
   auto-relaunch** (v1 decision — keeps behaviour predictable).
2. **Install** (`src/install.c`): for the single matched device,
   `wdi_prepare_driver(dev, tmp, "ftdi_winusb.inf", &opts)` with
   `opts.driver_type = WDI_WINUSB`, then
   `wdi_install_driver(dev, tmp, "ftdi_winusb.inf", NULL)`. On nonzero,
   print `wdi_strerror(rc)` and exit nonzero.
3. Re-enumerate and report the device now presents as WinUSB.
4. Honour `--dry-run` (from Phase 2) — print intent, skip the install.

## Integration test (human, elevated, real FT231X)

1. `ftdi-unbind 0403:6015 --dry-run` → names the device, no change.
2. Elevated: `ftdi-unbind 0403:6015` → installs WinUSB.
3. Verify: the COM port disappears; Device Manager shows a WinUSB device
   under "Universal Serial Bus devices"; `python list_devices.py` (pyftdi)
   now sees it; `verify_wiring.py` can open it.

## Commits

- `feat(install): elevation check with clear re-run guidance`
- `feat(install): install WinUSB on the matched device via libwdi`
- `docs: record the install flow + libwdi options in LIBWDI-API.md`

## Acceptance

- [ ] Non-elevated run errors cleanly with the exact elevated re-run
      command (no crash, no partial action)
- [ ] Elevated run installs WinUSB on exactly the matched device, nothing
      else
- [ ] pyftdi / WebUSB can claim the device afterwards
- [ ] `--dry-run` still changes nothing
- [ ] Branch merged to `main`

## Notes

- libwdi can elevate its own installer, but we gate on our own elevation
  check first so the failure mode is a clear message, not a surprise UAC
  dialog mid-run.
- This is the easy direction. Do not let its simplicity tempt a combined
  implementation with restore — restore is genuinely different (Phase 4).
