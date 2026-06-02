# PHASE-05-cli-two-exes.md — Two exes, CLI parity, packaging-ready

Branch: `phase/05-cli-two-exes`

## Goal

Ship `ftdi-unbind.exe` and `ftdi-bind.exe` as two thin mains over one
shared core, with flags, exit codes, and VID:PID formats identical to the
Linux `ftdi-unbind` / `ftdi-bind` scripts — so the cross-platform mental
model is exact.

## Steps

1. **CMake**: build a `core` static lib (match, args, enum, install,
   restore, elevate) once; link it into two executables with thin mains:
   ```
   src/main_unbind.c   -> sets ACTION_UNBIND, calls core
   src/main_bind.c     -> sets ACTION_BIND,   calls core
   ```
   One core compiled once, two `.exe`s — no logic duplication.
2. **Parity audit** against the Linux scripts:
   - flags: `--dry-run`/`-n`, `--all`, `-h`/`--help`
   - exit codes: `0` ok, `1` no-match/ambiguous-without-`--all`, `2` usage
   - VID:PID forms: `0403:6015`, `0x0403:0x6015`, `403:6015`
3. **Help text** mirroring the scripts' wording (same verbs, same
   examples) so docs and muscle memory transfer between platforms.

## Commits

- `refactor(core): extract shared core static lib`
- `feat(cli): ftdi-unbind.exe and ftdi-bind.exe over shared core`
- `test(cli): exit-code + flag parity with the Linux scripts`

## Acceptance

- [ ] Both exes built from one `core` lib (verify: a logic change in core
      affects both)
- [ ] Flags, exit codes, and VID:PID formats match the Linux scripts
- [ ] `--help` for each reads consistently with its Linux counterpart
- [ ] Branch merged to `main`

## Notes

- Two real `.exe`s (not one exe + symlinks) is the right call on Windows —
  symlinks are awkward and need privilege; two binaries from a shared core
  is clean and mirrors the two Linux scripts one-to-one.
