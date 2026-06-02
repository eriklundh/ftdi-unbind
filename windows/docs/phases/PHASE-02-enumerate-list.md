# PHASE-02-enumerate-list.md — Enumeration + --list + --dry-run

Branch: `phase/02-enumerate-list`

## Goal

Connect real libwdi enumeration to the Phase 1 matcher. Read-only: no
driver changes, no admin required. By the end, `--list` and `--dry-run`
work against real hardware and the ambiguity-refusal safety rule is
enforced.

## Steps

1. **Adapter** `src/enum.c`: `wdi_create_list()` → array of
   `device_record` (copy vid, pid, desc, device_id, driver), then
   `wdi_destroy_list()`. Keep ownership clear: the adapter owns copies so
   the core never holds libwdi-freed pointers.
2. **`--list`**: print every device with `VID:PID  description  [driver]`,
   so the current driver is visible (parallels `list_devices.py`). Useful
   for finding the right VID:PID and seeing whether a device is already on
   WinUSB.
3. **`--dry-run VID:PID`**: run the matcher, print exactly which device(s)
   would be acted on (description + instance id), change nothing, need no
   admin.
4. **Ambiguity rule**: if `match_devices` returns >1 and `--all` is not
   set, list the matches and exit `EXIT_NOMATCH` (1) without acting.

## Commits

- `feat(enum): adapt wdi_create_list to device_record`
- `feat(cli): --list shows devices and current driver`
- `feat(cli): --dry-run reports the target without acting`
- `feat(cli): refuse ambiguous match unless --all`

## Acceptance

- [x] `--list` shows the attached FT231X as `0403:6015` with driver `usbser`
- [x] `--dry-run 0403:6015` names the exact device (instance USB\VID_0403&PID_6015\D30JZVRL, driver usbser) and changes nothing
- [ ] Two identical dongles → `--dry-run` lists both; a real action
      refuses without `--all` and exits 1  *(hardware-gated: needs a second FT231X)*
- [x] No admin needed for either path
- [ ] Branch merged to `main`

## Exe path

```
build\Release\ftdi-rebind.exe
```

`CMakePresets.json` `vs2022-x64-release` hardwires `binaryDir` to
`${sourceDir}/build` and config to `Release`, so this path is stable for
the lifetime of this preset.

## Notes

- Enumeration via libwdi does not require elevation; only install/restore
  do. Keep this phase admin-free so it's a safe, fast inner loop.
- The adapter is the boundary: core logic stays on `device_record` and
  remains unit-testable; only `enum.c` knows about `wdi_device_info`.
