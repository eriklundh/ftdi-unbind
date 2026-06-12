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
https://github.com/eriklundh/ftdi-unbind.git
```

The public repository and Releases page live on GitHub
(**github.com/eriklundh/ftdi-unbind**). The project is host-agnostic; the
internal canonical remote is documented in `CLAUDE.md`.

## Quick start

```sh
git clone https://github.com/eriklundh/ftdi-unbind.git
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
[`scripts/signing.metadata.json`](scripts/signing.metadata.json) (no credentials —
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

### Supply-chain policy: every action is SHA-pinned

All `uses:` lines in the workflows reference a **full commit SHA**, with
the human-readable version as a trailing comment:

```yaml
uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10   # v6.0.3
```

Why: a `@vN` tag is mutable — whoever controls (or compromises) the action
repository can move it. The release job holds `id-token: write` (the Azure
signing identity) and `contents: write` (release publishing), so a
malicious action would run with the authority to sign and publish
binaries. Pinning to a SHA makes the executed code immutable.

Maintenance rules:

- **New actions enter the workflow pinned.** Resolve the SHA at the time
  of adding (never copy one from a doc or chat):

  ```sh
  gh api repos/<owner>/<action>/git/ref/tags/<version> --jq .object.sha
  # if .object.type was "tag" (annotated), dereference once more:
  gh api repos/<owner>/<action>/git/tags/<that-sha> --jq .object.sha
  ```

- **Updates come from Dependabot** ([`.github/dependabot.yml`](.github/dependabot.yml),
  monthly, github-actions ecosystem). It understands the
  sha-plus-version-comment format and PRs both together. Note the mirror
  rule in that file: apply the diff to the canonical remote; never merge
  the PR on the GitHub mirror.

## History

This repository consolidates two formerly standalone projects, with their
full git history preserved:

| Directory | Former repository |
|---|---|
| `windows/` | **ftdi-winusb-rebind** |
| `macos-linux/` | **ftdi-rebind-scripts** |

The original repositories are retained as read-only archives.
