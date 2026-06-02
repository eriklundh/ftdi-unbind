# BUILD-ENVIRONMENT.md — toolchain, dependencies, download sources

The tools are C, built with **CMake + the MSVC toolset**, statically
linked against **libwdi**. CMake is the deliberate choice: VSCode
consumes it via the CMake Tools extension (the approachable,
contribution-friendly path), and Visual Studio 2022/2026 open a CMake
project natively — so neither IDE is privileged and contributors can use
whichever they have.

## Download sources (all dependencies)

| Dependency | Source | Version | Licence | Notes |
|-----------|--------|---------|---------|-------|
| **libwdi** | https://github.com/pbatard/libwdi | v1.5.0 | **LGPL-3.0** | The driver-install engine (same author as Zadig/Rufus). Build as a static lib. |
| **Visual Studio 2022 or 2026** | already installed on this machine | — | — | Need the **"Desktop development with C++"** workload (MSVC compiler + Windows SDK). |
| **Windows SDK** | bundled with the VS C++ workload | current | — | Provides `setupapi.lib`, `cfgmgr32.lib`, `newdev.lib` for the restore path. |
| **CMake** | bundled with VS2022/2026; or https://cmake.org/download/ | ≥ 3.20 | BSD-3 | VSCode "CMake Tools" can use the VS-bundled CMake. |
| **Unity** (optional test fw) | https://github.com/ThrowTheSwitch/Unity | latest | MIT | Only if you prefer it over the zero-dependency CTest+assert approach. |
| **usb.ids** (optional) | http://www.linux-usb.org/usb.ids | rolling | public | Only if you want libwdi to resolve vendor names; not required. |

**No separate WDK / WinUSB redistributable download is needed on Windows
10/11.** libwdi v1.5.0 ships the WinUSB driver payload embedded, and the
Win8-era redistributables it once needed are only required when targeting
Windows 8 or earlier — out of scope here. (Reference: the libwdi wiki
"Compiling and debugging" page states the redistributable is "not needed
on Windows 10 or later".)

## Step 1 — Get and build libwdi as a static library

```bat
git clone https://github.com/pbatard/libwdi.git
cd libwdi
git checkout v1.5.0
```

libwdi builds with its own MSVC solution (it does not ship CMake). Two
things to configure before building, both in `msvc/config.h`:

1. **Enable WinUSB, ignore the others.** We only need WinUSB (that's what
   WebUSB/pyftdi use). Tell libwdi not to expect libusb0/libusbK driver
   trees, so the build doesn't demand directories you don't have. In
   `msvc/config.h` enable the WinUSB path and disable
   `LIBUSB0_DIR` / `LIBUSBK_DIR` per the comments in that file.
2. **`WDF_VER`** — set the WinUSB CoInstaller version define as documented
   in `config.h` (current value per the libwdi install wiki).

Then open `libwdi.sln` in Visual Studio, choose **Release / x64**, and
build the **library** target. The static lib and header land under
`.\x64\Release\` (e.g. `libwdi.lib`) with `libwdi.h` in `libwdi\`.

> **Static CRT consistency (important).** Build libwdi with the **static
> CRT (`/MT`)** so it matches our tools. Mixing `/MT` and `/MD` across
> libwdi and our exe causes CRT link errors and/or runtime breakage. Our
> CMake sets `/MT`; libwdi must match. In the VS project this is
> C/C++ → Code Generation → Runtime Library → **Multi-threaded (/MT)**.

Record the resulting paths; Phase 0's CMake takes them as cache vars:
- `LIBWDI_INCLUDE_DIR` → folder containing `libwdi.h`
- `LIBWDI_LIB` → full path to `libwdi.lib`

## Step 2 — Our tools' CMake project

`CMakeLists.txt` essentials (fleshed out in Phase 0):

```cmake
cmake_minimum_required(VERSION 3.20)
project(ftdi-winusb-rebind C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Static CRT to match libwdi and produce self-contained exes.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# libwdi location — set on the command line or in CMakePresets.json
set(LIBWDI_INCLUDE_DIR "" CACHE PATH "Folder containing libwdi.h")
set(LIBWDI_LIB         "" CACHE FILEPATH "Path to libwdi.lib (static)")

# ... targets defined in later phases ...
# Link deps for libwdi + the restore path:
#   ${LIBWDI_LIB} setupapi cfgmgr32 ole32 newdev
```

Configure/build:

```bat
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 ^
      -DLIBWDI_INCLUDE_DIR=C:/src/libwdi/libwdi ^
      -DLIBWDI_LIB=C:/src/libwdi/x64/Release/libwdi.lib
cmake --build build --config Release
```

(For VS2026 use its generator string, e.g. `-G "Visual Studio 18 2026"`;
confirm the exact name with `cmake --help`. In VSCode, the CMake Tools
extension picks the kit and you set the same two cache vars in
`CMakePresets.json`.)

## Step 3 — Link dependencies

The tools link, beyond libwdi:
- `setupapi.lib` — device enumeration + uninstall (restore path)
- `cfgmgr32.lib` — `CM_Reenumerate_DevNode` (restore path)
- `ole32.lib` — GUID/COM helpers used by SetupAPI
- `newdev.lib` — `DiUninstallDevice` / driver update helpers

All ship with the Windows SDK (VS C++ workload). No extra downloads.

## Verifying a clean, self-contained build

```bat
dumpbin /dependents build\Release\ftdi-unbind.exe
```

Should list only system DLLs (`KERNEL32`, `SETUPAPI`, `CFGMGR32`,
`ole32`, etc.) — no `libwdi.dll`, no `vcruntime*.dll` (because `/MT`),
no third-party DLLs. That's the goal: two drop-in `.exe`s a student runs
with no install.

## Licensing note (LGPL-3.0 static linking — not legal advice)

libwdi is **LGPL-3.0**. Static-linking LGPL code is permitted, but the
LGPL expects that an end user can **relink** against a modified libwdi.
For an open-source tool this is easy to satisfy: publish the full source
and the build instructions (this doc), which lets anyone rebuild/relink.
The cleanest options, in rough order of simplicity:

1. **License the tools under GPL-3.0** (compatible with LGPL-3.0). Then
   the relink requirement is moot because everything is open. Recommended
   for a contribution-friendly project.
2. A **permissive licence** (MIT/BSD) for the tool source, while
   documenting the relink path and shipping the libwdi source/version
   used. Also fine; slightly more to keep track of.

This is general information, not legal advice — if the project's
distribution model matters to you, confirm with someone qualified. The
practical takeaway: keep the source public with these build instructions
and you're in good shape either way.

## Where Claude Code fits

Claude Code can do Step 2–3 and all of the unit-test loop autonomously
(compile, link, `ctest`). Step 1 (building libwdi) is a one-time setup it
can also perform, but the **driver-install/restore integration tests**
(Phases 3–4) need admin + the real FT231X and are human-run — see
`CLAUDE.md` "build vs install".
