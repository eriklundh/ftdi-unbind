# CLAUDE.md — ftdi-unbind (repository root)

Orientation for Claude Code instances working in this repository. Read
this first, then the per-platform `CLAUDE.md` in the relevant subdirectory.

## What this repo is

Cross-platform tooling to **rebind FTDI USB devices** between their serial
(VCP / `ftdi_sio`) driver and a raw-USB mode (WinUSB on Windows, an unbound
kernel driver on Linux/macOS) so the device can be claimed by WebUSB,
libusb, or pyftdi — and restored afterwards. CLI surface is identical on
every platform: `ftdi-unbind <VID:PID>` releases, `ftdi-bind <VID:PID>`
restores.

## Git origin

```
git@gitlab.compelcon.se:unified-serial-terminal/ftdi-unbind.git
```

This is the current canonical remote. The repo is host-agnostic and may be
mirrored to GitHub or elsewhere; per-subdirectory docs refer to it
abstractly as `<git origin>`. Follow the commit/push conventions in each
subdirectory's own `CLAUDE.md`.

## Layout

| Directory | Platform | Stack |
|---|---|---|
| `windows/` | Windows | C / CMake; WinUSB via libwdi, VCP restore via SetupAPI |
| `macos-linux/` | Linux & macOS | POSIX shell scripts; sysfs / kext |

Each subdirectory is self-contained (its own README, PLAN, CLAUDE, tests).
Work in one platform at a time; the two share only their CLI contract.

## History

Consolidated from two former standalone repositories, full git history
preserved: `windows/` ← **ftdi-winusb-rebind**, `macos-linux/` ←
**ftdi-rebind-scripts**. The originals are retained as read-only archives.

---

## Current status — v0.1.0 (2026-06-06)

### What is done

**Diagnosis scripts at repo root** — the main deliverable of this milestone.
All three are read-only, require no elevation/sudo, and default to
`0403:6015` (FTDI FT231X / FT232R, used on ULX3S and similar FPGA boards).
An optional VID:PID argument overrides the default.

| File | Platform | Invocation |
|---|---|---|
| `diagnosis.ps1` | Windows PowerShell 5.1+ | `.\diagnosis.ps1` or `.\diagnosis.ps1 0403:6014` |
| `diagnosis.cmd` | Windows CMD (wrapper) | `diagnosis.cmd` |
| `diagnosis.sh` | Linux & macOS (bash 3.2+) | `bash diagnosis.sh` |

`diagnosis.ps1` accepts `-v` / `-verbose` / `-Detailed` to print the full
pnputil driver store listing (default: count summary only).

`README.md` updated to lead with "Start here: run diagnosis first".

**Windows C tools** (`windows/` subdirectory) — phases 0–8 complete
(build, enumerate, install WinUSB, restore VCP, dual-exe CLI, release
packaging). Code signing (phases 9–11) is wired: local "big red button"
(`scripts/release-local.ps1` / `RELEASE.cmd`) and CI signing via Azure
Artifact Signing OIDC. No signed release has been *published* yet — see the
publishing handoff below.

### What is next / in progress

- **Cross-platform testing of `diagnosis.sh`** on:
  - Raspberry Pi 5, Raspberry OS Trixie (Debian 13 / Linux) — Claude Code installed
  - Mac Mini 2014, macOS 12 Monterey
  Connect a ULX3S (or any 0403:6015 device), run `bash diagnosis.sh`, and
  verify the output is correct for each driver state (ftdi_sio bound,
  unbound, device absent).
- **Windows code signing** (phases 9–11) — Authenticode via Azure Artifact
  Signing; CI workflow is in `windows/`.
- **Release page** — attach signed Windows binaries + `diagnosis.sh` to the
  GitLab releases page once signing is done.

### Publishing, mirror & signing — handoff state (2026-06-08)

This captures cross-host infra set up outside the code, so any Claude can
resume. **No secrets are written here by design** — read identifiers with
`az` / `gh`; see `docs/PUBLISHING-AND-SECRETS.md`.

**Topology.** GitLab `gitlab.compelcon.se/unified-serial-terminal/*` is
canonical and **push-mirrors** to public GitHub `eriklundh/*`. GitHub Actions
always builds + signs on a `v*` tag (the authoritative signed build); the
GitLab tag pipeline either signs natively (if it has a `windows` runner) or
pulls GitHub's signed assets (`publish-from-github`).

**Done:**
- GitHub repos `eriklundh/ftdi-unbind` and `eriklundh/unified-serial-term`
  created **public**. GitLab project IDs: ftdi-unbind **447**,
  unified-serial-term **446**.
- **Push mirrors** configured on both (GitLab → GitHub), enabled,
  mirror-all-branches-and-tags. Auth = one fine-grained GitHub PAT (owner
  eriklundh, those two repos, **no expiry**, Contents:RW + Workflows:RW)
  stored **only** in each project's GitLab mirror config — never a CI var,
  never in git. First sync verified clean.
- GitLab CI var `GITHUB_REPO=eriklundh/ftdi-unbind` set on project 447.
- **OIDC signing live** for `eriklundh/ftdi-unbind`: Entra app
  `ftdi-unbind-ci-signing` (no client secret), *Artifact Signing Certificate
  Profile Signer* role at **account scope** (`Trusted-Signing-TJE1`), one
  flexible federated credential trusting `repo:eriklundh/ftdi-unbind:ref:refs/tags/v*`.
  The three `AZURE_*` GitHub Actions secrets are set. Recreate/verify any time
  with `scripts/setup-github-oidc.ps1 -GitHubRepo eriklundh/ftdi-unbind -ScopeToAccount`
  (idempotent; needs `az login` as an Owner).
- Fixed two bugs that stopped both `setup-*-oidc.ps1` scripts from running:
  the `az` helper was named `Az` (PowerShell is case-insensitive → infinite
  recursion; now `Invoke-Az`), and flexible federated credentials must be
  created via Graph **beta** with `az rest` (the `az ad app
  federated-credential create` command rejects them). **This fix is committed
  locally on `main` but may be UNPUSHED** — check `git log origin/main..main`.

**Next steps (in order):**
1. Push the local `main` commits if any are unpushed (`git push origin main`);
   the mirror carries them to GitHub.
2. **Publish the first signed release.** The mirrored `v0.1.0` tag will NOT
   trigger `release.yml` because that workflow post-dates the tagged commit.
   Cut a fresh tag whose commit contains `.github/workflows/release.yml`
   (e.g. `git tag v0.1.1 && git push origin v0.1.1`). On GitLab that push
   mirrors to GitHub, where `release.yml` builds libwdi → builds → ctest →
   signs via `azure/artifact-signing-action@v0` (endpoint
   `https://neu.codesigning.azure.net/`, account `Trusted-Signing-TJE1`,
   profile `Compelcon-AB-MS-Code-signed`) → assembles all assets + SHA256SUMS
   → `gh release create`. Then the GitLab `publish-from-github` job pulls
   those signed assets and creates the GitLab release.
3. Verify: GitHub Release has the three exes signed (Authenticode Valid) plus
   the Linux/macOS tarball, three diagnosis scripts, the all-in-one zip, and
   SHA256SUMS.

**Open content decisions (non-blocking):**
- Diagnosis scripts point downloads at `gitlab.compelcon.se/.../-/releases`;
  decide whether to also/instead point public users at the GitHub releases.
- winget package ID `Compelcon.FtdiUnbind` — keep (company/signer branding)
  or rebrand under eriklundh.

### Key design decisions (carry into new sessions)

- Scripts must be read-only and require **no elevation / no sudo**.
- Default VID:PID is `0403:6015`; all three scripts accept a positional
  override argument so the same script covers other FTDI chips.
- Target audience: EE students mid-lab who are stressed and confused, not
  USB driver experts. Output is verbose and pedagogical by design.
- `unified-serial-terminal` (sister project) is always mentioned as an
  alternative that avoids bind/unbind entirely — critical for university
  lab computers where students cannot run admin tools.
- `diagnosis.sh` is written for bash 3.2 compatibility (macOS ships 3.2).
  No `${var,,}`, no `declare -A`; use `tr` and positional tricks instead.
