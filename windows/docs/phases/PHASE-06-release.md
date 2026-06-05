# PHASE-06-release.md — Release

Branch: `phase/06-release`

## Goal

Ship v0.1.0: two self-contained `.exe`s and the docs a contributor needs
to build from source in either VSCode or Visual Studio.

## Steps

1. **README.md**: what/why, the bind/unbind verb semantics (point at
   `DEVICE-BINDING.md`), quick start, build-from-source (link
   `BUILD-ENVIRONMENT.md`), and the LGPL relink note. State plainly that
   for a dedicated test dongle `ftdi-bind` is optional (leave it WinUSB).
2. **LICENSE**: GPL-3.0 recommended (clean fit with static LGPL-3.0
   libwdi — see BUILD-ENVIRONMENT.md §licensing), or a permissive licence
   plus a documented relink path. Pick one, be consistent.
3. **CHANGELOG.md**: v0.1.0 summary.
4. **Self-contained check**: `dumpbin /dependents` on both exes shows
   only system DLLs (no libwdi.dll, no vcruntime — thanks to `/MT`).
5. **Build artifacts**: x64 `ftdi-unbind.exe` + `ftdi-bind.exe`. ARM64
   optional (libwdi 1.5.0 supports ARM64 WinUSB install).
6. Tag `v0.1.0`, attach the binaries.

## Commits

- `docs: write README with semantics, build, and LGPL note`
- `chore: add CHANGELOG and LICENSE`
- `chore: build self-contained x64 release exes`
- `chore: tag v0.1.0`

## Acceptance

- [ ] Fresh checkout builds both exes per the README on a clean VS box
      (the build-from-source path actually works for a newcomer)
- [ ] Both exes self-contained (only system DLLs)
- [ ] `v0.1.0` tagged; binaries attached
- [ ] README lets a contributor build in VSCode (CMake Tools) or
      VS2022/2026 with equal ease

## The payoff

A student on Windows runs `ftdi-unbind 0403:6015` (elevated) and the FTDI
dongle is WebUSB/pyftdi-ready — no Zadig, no GUI mispick, no wrong-device
accidents. `ftdi-bind 0403:6015` puts the COM port back when they need it.
Same commands, flags, and behaviour as the Linux and macOS scripts, so the
lab instructions read identically across all platforms and
`DEVICE-BINDING.md`'s "planned" Windows tools become "shipping".
