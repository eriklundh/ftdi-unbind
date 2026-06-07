# packaging/ — distribution channel artifacts

This directory contains packaging manifests for distribution channels beyond
a direct GitHub Release download. The release workflow (`release.yml`)
produces the binaries and tarballs; these manifests tell each package manager
how to find and install them.

## Channels

| Channel | Files | Platform | Audience |
|---|---|---|---|
| **Homebrew tap** | `homebrew/ftdi-unbind.rb` | macOS (and Linux) | `brew install` users |
| **winget** | `winget/Compelcon.FtdiUnbind/` | Windows | `winget install` users |

Direct download via GitHub Releases (no package manager) is always the
baseline and works everywhere.

---

## Homebrew tap

The formula lives in a separate tap repo (`compelcon/homebrew-tools`).
The `packaging/homebrew/ftdi-unbind.rb` in this repo is the **canonical source**;
after each release you copy/push it to the tap repo.

**User install:**
```bash
brew tap compelcon/tools https://github.com/compelcon/homebrew-tools
brew install ftdi-unbind
```

**Update after a new release:**

Run `update-packaging.sh` from the repo root (see below) to regenerate the
formula with the correct SHA256 and version, then push to the tap repo:

```bash
# from repo root, after the GitHub Release is published:
bash packaging/update-packaging.sh v0.2.0

# copy updated formula to tap repo and push
cp packaging/homebrew/ftdi-unbind.rb /path/to/homebrew-tools/Formula/
cd /path/to/homebrew-tools && git add Formula/ftdi-unbind.rb && git commit -m "ftdi-unbind v0.2.0" && git push
```

---

## winget

winget requires three YAML files per version in the `winget-pkgs` community
repo. The `packaging/winget/` directory contains a version-stamped copy of
those files.

**User install (once the package is in winget-pkgs):**
```powershell
winget install Compelcon.FtdiUnbind
```

**Submitting a new version:**

1. Run `update-packaging.sh` to create the new version directory with correct SHA256.
2. Fork [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs).
3. Copy the new version directory into `manifests/c/Compelcon/FtdiUnbind/<version>/`.
4. Open a PR.

The automated tool `wingetcreate` can also be used to generate and submit
directly from the release URL:

```powershell
wingetcreate update Compelcon.FtdiUnbind `
  --version 0.2.0 `
  --urls https://github.com/compelcon/ftdi-unbind/releases/download/v0.2.0/ftdi-tools-v0.2.0-windows-x64.zip `
  --submit
```

---

## update-packaging.sh

A helper script at `packaging/update-packaging.sh` automates SHA256 lookups
and file updates. Run it after the GitHub Release is published (so the
artifacts are available):

```bash
bash packaging/update-packaging.sh <tag>
# example:
bash packaging/update-packaging.sh v0.2.0
```

It downloads the two release artifacts, verifies against the published
`SHA256SUMS`, updates the Homebrew formula and winget installer manifest in
place, and creates the new winget version directory.
