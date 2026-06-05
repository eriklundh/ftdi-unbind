# PHASE-00-build-skeleton.md — Build skeleton + static libwdi link

Branch: `phase/00-build-skeleton`

## Goal

A CMake project that statically links libwdi and runs, printing the
libwdi version. Proves the toolchain + static link before any logic —
the "blink" of this project. If this works, every later phase is
incremental.

## Prerequisites

- libwdi built as a static `libwdi.lib` with WinUSB enabled and static
  CRT (`/MT`), per `docs/BUILD-ENVIRONMENT.md` Step 1. Note the two
  paths: `LIBWDI_INCLUDE_DIR`, `LIBWDI_LIB`.
- VS 2022 or 2026 with "Desktop development with C++".

## Steps

1. `CMakeLists.txt` per BUILD-ENVIRONMENT.md: C11, static CRT, the two
   `LIBWDI_*` cache vars, one executable `ftdi-rebind-probe`. Link
   `${LIBWDI_LIB} setupapi cfgmgr32 ole32 newdev`.
2. `src/probe.c`:
   ```c
   #include <stdio.h>
   #include "libwdi.h"
   int main(void) {
       printf("libwdi %s\n", wdi_get_version()); // confirm name in header
       return 0;
   }
   ```
3. `CMakePresets.json` carrying the `LIBWDI_*` paths so VSCode CMake Tools
   and the CLI agree; a `.vscode/` hint is optional.
4. Configure + build (Release x64), run the exe.
5. `dumpbin /dependents` → only system DLLs (no libwdi.dll, no vcruntime).

## Commits

- `chore(cmake): scaffold CMake/MSVC project, C11, static CRT`
- `build(libwdi): locate and statically link libwdi`
- `feat(proj): probe prints libwdi version to prove the link`
- `docs: record toolchain + libwdi build in BUILD-ENVIRONMENT.md`

## Acceptance

- [ ] `cmake --build build --config Release` produces
      `ftdi-rebind-probe.exe`
- [ ] Running it prints the libwdi version
- [ ] `dumpbin /dependents` shows only system DLLs
- [ ] Opens as a CMake project in both VSCode (CMake Tools) and VS2022/2026
- [ ] Branch merged to `main`

## Notes

- If you get CRT link errors (`LNK2038` mismatch _ITERATOR_DEBUG_LEVEL or
  RuntimeLibrary), libwdi and the tool disagree on `/MT` vs `/MD`. Rebuild
  libwdi with `/MT`. This is the most common first-build failure.
- If `wdi_get_version` doesn't resolve, check the exact symbol name in
  your `libwdi.h` and update the probe + LIBWDI-API.md.
