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
(`scripts/release-local.ps1` / `scripts/RELEASE.cmd`) and CI signing via Azure
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

**Topology.** The internal GitLab (the *Git origin* above) is
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

**Release pipeline shakedown — state as of 2026-06-10 (first real runs):**

The "cut a fresh tag and the mirror triggers GitHub" plan did NOT work and
four latent bugs were found and fixed on the way. Current knowledge:

- **Tag pushes generate NO push events on the GitHub repo** — neither from
  the GitLab mirror nor from direct authenticated pushes (branch pushes do;
  verified via the events API). `on: push: tags:` therefore never fires.
  `release.yml` now has a `workflow_dispatch` escape hatch — dispatch AT THE
  TAG REF and `github.ref_name` is the tag, so it behaves identically:
  `gh workflow run release.yml -R eriklundh/ftdi-unbind --ref vX.Y.Z`
  (gh on Agentlab1 is authenticated as eriklundh with repo+workflow scopes).
- Fixed in `scripts/build-libwdi.ps1`: USER_DIR was never inserted into
  config.h (substring guard matched upstream's commented mention) → embedder
  C1189; and relative `-OutDir` resolved inside libwdi-src after
  Push-Location → C1083 libwdi.h not found.
- Fixed in `release.yml`: CMake generator un-pinned (windows-latest now
  ships VS 2026 / MSBuild 18; "Visual Studio 17 2022" no longer exists).
- More latent bugs found on the way to green (all fixed on `main`):
  AZURE_TENANT_ID + AZURE_CLIENT_ID secrets were mangled (rewritten
  2026-06-10 22:18 by setup-github-oidc.ps1 -SetGitHubSecrets, from the
  correct az session); the separate `winget install` of the signing tools
  hung hosted runners for 60+ min (removed — the artifact-signing-action
  installs its own tooling); the action's input is
  `trusted-signing-account-name`, not `code-signing-account-name`;
  timeout-minutes added (15 sign step / 45 windows job); GitHub-owned
  actions bumped to Node 24 majors (checkout v6, cache v5,
  upload-artifact v7, download-artifact v8).
- Tag ledger: `v0.1.1`–`v0.1.6` were dead tags from the shakedown (inert /
  failed at successive layers) — **deleted from both remotes 2026-06-12**
  (GitLab: temporary v* unprotect → delete → re-protect Maintainers).
  **`v0.1.7` = RELEASED 2026-06-11** on both
  platforms, fully verified: SHA256SUMS validates all 7 assets; GPL-3.0 in
  the windows zip, MIT in the tarball; all three exes Authenticode-signed
  and `Get-AuthenticodeSignature` says **Valid** on a real Windows machine.
- GitLab side: `publish-from-github` is untagged (any Linux runner); the
  Agentlab1 runner (id 2) is enabled on this project, so releases push
  through with the Pi 5 offline (the Pi stays a pure HIL-test runner).
  Gotcha: a pipeline created while no eligible runner existed can stay
  stuck `pending` after the runner appears — cancel+retry the job.

**Release runbook (proven 2026-06-11):**
1. `git tag -a vX.Y.Z -m "..." && git push origin vX.Y.Z` and ALSO push the
   tag to GitHub directly (mirror tag pushes create no events):
   `git -c credential.helper='!gh auth git-credential' push https://github.com/eriklundh/ftdi-unbind.git refs/tags/vX.Y.Z`
2. Dispatch the workflow at the tag (push events for tags never fire):
   `gh workflow run release.yml -R eriklundh/ftdi-unbind --ref vX.Y.Z`
3. When the GitHub release is published, the GitLab tag pipeline's
   `publish-from-github` job picks up the assets and creates the GitLab
   release (kick it with a job retry if it pre-dates runner availability).

**Next (optional, precondition met):** execute the private CI-hardening
plan at `~/unified-serial-terminal/ACTIONS-SECURITY-UPGRADE-PLAN.md`
(SHA-pin all actions, Dependabot, artifact-signing-action v0→v2). Keep
that file out of the public repo until done.

**Open content decisions (non-blocking):**
- Download/release links — **resolved 2026-06-10:** every public-facing
  URL (diagnosis scripts, DEVELOPER.md, signing docs) points at
  github.com/eriklundh/ftdi-unbind. The internal GitLab group URL appears
  in this file only; other docs say `<gitlab-instance>`.
- winget package ID — **resolved 2026-06-12: keep `Compelcon.FtdiUnbind`**
  (matches the Authenticode signer identity, Compelcon AB; consistent
  publisher branding beats namespace symmetry with GitHub).

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
