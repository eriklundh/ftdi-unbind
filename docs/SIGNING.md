# SIGNING.md — code signing across Linux, macOS, and Windows

Cross-platform signing overview for the `ftdi-unbind` toolset.
Each platform has a different concern; only Windows needs a code-signing
certificate for the compiled `.exe` binaries.

| Platform | Distributed as | Signing needed? | What we do |
|---|---|---|---|
| **Linux** | bash script | No binary signing | GPG-sign the `SHA256SUMS` release file |
| **macOS** | bash script | No (Gatekeeper is Mach-O only) | Homebrew tap; no certificate needed |
| **Windows** | compiled `.exe` | Yes — SmartScreen | Azure Artifact Signing (OIDC, cloud HSM) |
| **All** | GitHub Release | Checksum integrity | `SHA256SUMS` + `SHA256SUMS.sig` (GPG) |

---

## Linux — bash scripts, no code signing

The Linux tool (`ftdi-unbind`, `ftdi-bind`) is a bash script.  
Linux does not have an OS-level Authenticode equivalent for shell scripts.
There is nothing to sign from a distribution or execution standpoint.

**What we do instead:** every GitHub Release includes a `SHA256SUMS` file
(and an optional `SHA256SUMS.sig`) so users can verify download integrity:

```bash
# verify after downloading the tarball
sha256sum --check SHA256SUMS
# optionally verify GPG signature (key ID in README)
gpg --verify SHA256SUMS.sig SHA256SUMS
```

The GPG key is documented in the project `README.md`.

---

## macOS — bash scripts, no code signing required

**Gatekeeper does not apply to shell scripts executed from the terminal.**
Apple's notarization and code-signing requirements cover Mach-O binaries
(apps, command-line tools, dylibs, kernel extensions).  
A file installed via Homebrew or run with `bash <file>` is never subject
to this check — no Apple Developer certificate or notarization workflow is
needed for these tools.

> If a user downloads the tarball from a browser and then tries to execute
> the shell script directly (double-click in Finder, or `./ftdi-unbind` on
> a file with the quarantine xattr), they _may_ get a Gatekeeper dialog on
> older macOS releases. Running `bash ftdi-unbind` from Terminal, or
> installing via the Homebrew tap (which strips quarantine), avoids this
> entirely. Our install path is the tap; the tarball is provided for manual
> inspection.

The Homebrew tap formula (see `packaging/homebrew/ftdi-unbind.rb`) handles
installation without any quarantine friction. No Apple Developer Program
membership is required for this distribution model.

**Future note:** if this project ever ships a macOS compiled binary
(e.g., a native Swift or C helper), that binary would require notarization.
The Apple Developer account is already in place if that need arises.

---

## Windows — compiled `.exe`, Azure Artifact Signing

The Windows tools (`ftdi-unbind.exe`, `ftdi-bind.exe`, `ftdi-doctor.exe`)
are compiled C++ binaries. Windows Defender / SmartScreen will warn on
unsigned PE files downloaded from the internet. These tools are signed
with **Azure Artifact Signing** (formerly Azure Trusted Signing).

Key properties:
- Certificates live in a FIPS cloud HSM — no `.pfx` to manage or leak.
- Each certificate is **daily-renewed and ~24h valid**; signatures carry an
  RFC3161 **timestamp** (`http://timestamp.acs.microsoft.com`) so they
  remain valid after the short-lived cert expires.
- CI signing uses **OIDC** — no long-lived secrets; forks build unsigned by
  default (the signing steps no-op when `AZURE_CLIENT_ID` is absent).

For the signing strategy (cheap-path landscape, forker paths, eligibility),
see:
→ **[windows/docs/SIGNING.md](../windows/docs/SIGNING.md)**

For the operational how-to (account setup, toolchain, three auth models —
laptop, GitHub OIDC, GitLab OIDC):
→ **[windows/docs/SIGNING-AZURE-ARTIFACT.md](../windows/docs/SIGNING-AZURE-ARTIFACT.md)**

Non-secret identifiers committed to the repo:
```json
// signing.metadata.json
{
  "Endpoint": "https://neu.codesigning.azure.net/",
  "CodeSigningAccountName": "Trusted-Signing-TJE1",
  "CertificateProfileName": "Compelcon-AB-MS-Code-signed"
}
```

Signing is triggered by the GitHub Actions `release.yml` workflow on every
`v*` tag. The shared signing script (`scripts/sign-local.ps1`) works in
all three contexts — laptop, GitHub, GitLab — differing only in how Azure
credentials are made available.

---

## Release checksums (all platforms)

Every GitHub Release (built by `.github/workflows/release.yml`) publishes:

| File | Content |
|---|---|
| `SHA256SUMS` | SHA-256 hashes of all release artifacts |
| `SHA256SUMS.sig` | Detached GPG signature of `SHA256SUMS` (when `GPG_PRIVATE_KEY` secret is set) |

Users can verify any release artifact:

```bash
sha256sum --check SHA256SUMS                # verify any artifact in the release
gpg --verify SHA256SUMS.sig SHA256SUMS      # verify GPG signature (optional)
```

The GPG public key ID and fingerprint are in the project `README.md`.
