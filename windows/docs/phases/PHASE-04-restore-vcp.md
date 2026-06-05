# PHASE-04-restore-vcp.md — Bind direction: restore the FTDI VCP

Branch: `phase/04-restore-vcp`

**Human-gated and the hardest phase.** Read `docs/RESTORE-STRATEGY.md`
fully and finalise the design there before writing code.

## Goal

`ftdi-bind.exe 0403:6015` removes the WinUSB association and gets Windows
to reinstall the FTDI VCP driver, so the COM port returns — and verifies
it actually came back, failing loudly if not.

## Steps (see RESTORE-STRATEGY.md for detail)

1. **Locate the device node by VID:PID** via SetupAPI
   (`SetupDiGetClassDevs` + enumerate + match `USB\VID_0403&PID_6015` in
   the hardware id). The hardware-id selection is pure logic → unit-test
   it test-first.
2. **Remove the WinUSB association** (`DiUninstallDevice`, or
   `SetupDiCallClassInstaller(DIF_REMOVE)`). Pick one, document it.
3. **Re-trigger enumeration** (`CM_Reenumerate_DevNode`, or a
   property-change re-scan) so Windows redetects and installs the best
   matching driver — the FTDI VCP on a normal system.
4. **Verify**: re-enumerate, confirm the device returned with a driver
   (ideally a COM port). If it came back driverless, **fail loudly** with
   recovery guidance (replug; ensure FTDI VCP present / Windows Update;
   "Scan for hardware changes"). Never report success when it isn't.
5. Honour `--dry-run`: print what it would remove/re-enumerate, do
   nothing.

## Integration test (human, elevated)

After a Phase 3 unbind: `ftdi-bind 0403:6015` → COM port reappears, the
WinUSB node is gone. Also test the offline/no-VCP caveat path if you can
simulate it (e.g. a machine without the FTDI driver) → tool reports the
driverless outcome clearly.

## Commits

- `docs(restore): finalise the SetupAPI/CfgMgr restore strategy`
- `test(restore): unit-test the hardware-id match/selection logic`
- `feat(restore): locate device node by VID:PID (SetupAPI)`
- `feat(restore): remove WinUSB + re-enumerate to reinstall VCP`
- `feat(restore): verify a working driver returned; else fail loudly`

## Acceptance

- [ ] Hardware-id selection logic has unit tests (the pure part)
- [ ] After unbind→bind, the COM port returns and the WinUSB node is gone
- [ ] If no FTDI VCP is available to reinstall, the tool says so clearly
      and exits nonzero — it does not claim success or leave the device
      silently driverless
- [ ] `--dry-run` changes nothing
- [ ] Branch merged to `main`

## Notes

- This is the part Zadig handles poorly and the main reason the tool adds
  value. Spend the design time in RESTORE-STRATEGY.md up front.
- For a dedicated test dongle, restore is optional — note in the README
  that `ftdi-bind` is for the shared-laptop case, so people don't run it
  needlessly.
