# Developer guide — ftdi-unbind

Everything you need to build, modify, and contribute to ftdi-unbind.
For end-user documentation see [README.md](README.md).

## Repository layout

| Directory | Platform | Implementation |
|---|---|---|
| [`windows/`](windows/) | Windows | C / CMake; WinUSB install via [libwdi](https://github.com/pbatard/libwdi), VCP restore via SetupAPI. Ships `ftdi-unbind.exe` / `ftdi-bind.exe`. |
| [`macos-linux/`](macos-linux/) | Linux & macOS | POSIX shell scripts; sysfs `ftdi_sio` bind/unbind on Linux, `kextunload`/`kextload` on macOS. |

Root-level diagnosis scripts (`diagnosis.ps1`, `diagnosis.cmd`,
`diagnosis.sh`) are cross-platform entry points.

Each subdirectory has its own `README.md` and `PLAN.md` — start there for
platform-specific build and test details.

## Git origin

```
git@gitlab.compelcon.se:unified-serial-terminal/ftdi-unbind.git
```

The project is host-agnostic and may be mirrored to GitHub. The canonical
public mirror for releases is **github.com/eriklundh/ftdi-unbind**.

## Quick start

```sh
git clone git@gitlab.compelcon.se:unified-serial-terminal/ftdi-unbind.git
cd ftdi-unbind
```

### Windows build

Requires CMake, a C compiler (MSVC or MinGW), and the libwdi headers.

```sh
cd windows
cmake -B build
cmake --build build --config Release
```

See [`windows/README.md`](windows/README.md) and
[`scripts/build-libwdi.ps1`](scripts/build-libwdi.ps1) for the full
libwdi dependency setup.

### Code signing (Windows)

Release binaries are signed via Azure Code Signing. See
[`docs/SIGNING.md`](docs/SIGNING.md) for the signing workflow and
[`scripts/sign-local.ps1`](scripts/sign-local.ps1) for local signing.

The signing endpoint configuration is in
[`signing.metadata.json`](signing.metadata.json) (no credentials —
authentication uses Azure OIDC in CI).

### Linux / macOS

The scripts in [`macos-linux/`](macos-linux/) require no build step —
they are POSIX shell. Install script:

```sh
bash install.sh          # installs to /usr/local/bin
bash install.sh --remove # uninstalls
```

## Releasing

The GitHub Actions workflow
[`.github/workflows/release.yml`](.github/workflows/release.yml) builds,
signs, and publishes a GitHub Release automatically on a version tag push:

```sh
git tag v0.2.0
git push origin v0.2.0
```

The workflow:
1. Builds the Windows executables
2. Signs them via Azure Code Signing (OIDC — no stored secrets)
3. Packages the macOS/Linux shell archive with a SHA-256 manifest
4. Creates a GitHub Release and attaches all artifacts

See [`packaging/README.md`](packaging/README.md) for the Homebrew formula
and winget manifest update procedure.

## History

This repository consolidates two formerly standalone projects, with their
full git history preserved:

| Directory | Former repository |
|---|---|
| `windows/` | **ftdi-winusb-rebind** |
| `macos-linux/` | **ftdi-rebind-scripts** |

The original repositories are retained as read-only archives.
