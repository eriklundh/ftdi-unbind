# SIGNING-AZURE-ARTIFACT.md — signing these tools with Azure Artifact Signing

Operational companion to `SIGNING.md` (which is the *strategy*: why, and the
cheap-path landscape). This doc is the *how* for the path the maintainer
already owns: **Azure Artifact Signing** (formerly **Azure Trusted
Signing**), used to sign `ftdi-unbind.exe`, `ftdi-bind.exe`, and
`ftdi-doctor.exe` in three contexts — the build laptop (Phase 8), GitHub
Actions (Phase 9), and self-managed GitLab (Phase 10).

> Re-verify specifics before relying on them — the service and its tooling
> have moved fast (rename to Artifact Signing was Jan 2026; the GitHub
> Action versioning changed with it). This is practical guidance, not
> procurement or legal advice.

## What changed since the account was created (2024)

- **Name.** Trusted Signing → **Azure Artifact Signing**, GA Jan 2026.
  Same accounts, same certificate profiles, same signing — only the brand
  and some action/package names changed. Old `azure/trusted-signing-action`
  still resolves; the current one is `azure/artifact-signing-action`.
- **Model unchanged and relevant to us:** certificates live in a FIPS HSM,
  are **renewed daily and valid ~24 h**, and every signature is
  RFC3161-**timestamped** (`http://timestamp.acs.microsoft.com`) so the
  signature stays valid after the short-lived cert expires. There is no
  `.pfx` to manage and nothing to store but *identifiers*.
- **Pricing:** Basic ≈ **$9.99/month** for up to 5,000 signatures and one
  certificate profile — which is what these three exes per release need
  many times over.

## Eligibility — read before Phase 8 (this is location-specific)

For **Public Trust** certificates, Artifact Signing is available to
**organizations** in the USA, Canada, the EU, and the UK, and to
**individual** developers **only in the USA and Canada**. The maintainer is
in the EU (Sweden), so Public Trust only applies if the 2024 identity was
validated as an **organization** (a registered sole trader / *enskild firma*
generally qualifies; a bare individual EU identity does not).

**Action:** in the Azure portal, confirm the identity validation shows
**Completed** and the certificate profile type is **Public Trust** (not
Private Trust, which is only trusted on machines you control). If it reads
as an EU individual, Public Trust isn't available and the identity must be
re-done as an organization.

The signing account is **not** tied to the original (KVM) product — the
certificate carries the validated *identity*, and any binary you're
authorised to sign gets that identity. Reusing it for this utility is fine.

## The values you need everywhere (all non-secret)

Collect these once (portal → your Artifact Signing account):

| Name | Example | Notes |
|------|---------|-------|
| **Endpoint** (region) | `https://neu.codesigning.azure.net/` | This account is **North Europe** = `neu`. Authoritative value is the account's `accountUri` (portal, or `az rest` on the account). |
| **Signing account name** | `Trusted-Signing-TJE1` | the Artifact Signing account (RG `Trusted-Signing-TJE`) |
| **Certificate profile name** | `Compelcon-AB-MS-Code-signed` | the Public Trust profile (Active) |
| **Tenant ID** | `AZURE_TENANT_ID` | Entra directory ID |
| **Subscription ID** | `AZURE_SUBSCRIPTION_ID` | the paid sub (no free/trial subs allowed) |

These four go in a committed `signing.metadata.json` (the `/dmdf` file) and
in CI inputs. They are **identifiers, not credentials** — safe to commit.
The only thing that is ever a secret is a *client secret* (and the OIDC
paths avoid even that).

```json
// signing.metadata.json  (committed; no secrets)
{
  "Endpoint": "https://neu.codesigning.azure.net/",
  "CodeSigningAccountName": "Trusted-Signing-TJE1",
  "CertificateProfileName": "Compelcon-AB-MS-Code-signed"
}
```

## The toolchain (same on every Windows machine that signs)

1. `winget install -e --id Microsoft.AzureCLI`
   — installs the Azure CLI (`az`), needed for `az login` (interactive
   laptop auth). Note: the package ID is `Microsoft.AzureCLI` (no dot
   between Azure and CLI) — `Microsoft.Azure.CLI` returns "no package found".
2. `winget install -e --id Microsoft.Azure.TrustedSigningClientTools`
   — installs the `Microsoft.Trusted.Signing.Client` dlib
   (`Azure.CodeSigning.Dlib.dll`), the .NET runtime, and VC++ deps.
   **v1.0.0+** installs the dlib to
   `%LOCALAPPDATA%\Microsoft\MicrosoftTrustedSigningClientTools\`
   (no space, no dot — different from the 0.1.x path
   `%LOCALAPPDATA%\Microsoft\Azure.CodeSigning.Dlib\`).
   `sign-local.ps1` searches both paths automatically.
2. **Use the 64-bit `signtool`.** The classic failure is the *Developer
   Command Prompt* defaulting to 32-bit signtool → "0 certs after EKU
   filter" / "parameter is incorrect". Use the **x64 Native Tools** prompt
   or a full path like
   `C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe`.
4. The `/dlib` + `/dmdf` parameters need a recent SDK signtool
   (10.0.26100+). Older Windows hosts can choke on the new signtool.

The one signing command (identical across contexts; only auth differs):

```powershell
signtool.exe sign /v /fd SHA256 `
  /tr http://timestamp.acs.microsoft.com /td SHA256 `
  /dlib "<path>\Azure.CodeSigning.Dlib.dll" `
  /dmdf "<repo>\signing.metadata.json" `
  ftdi-unbind.exe ftdi-bind.exe ftdi-doctor.exe
```

Verify: `signtool verify /pa /v ftdi-unbind.exe` (and right-click →
Properties → Digital Signatures). Expect your validated identity + a
trusted timestamp.

## The three auth models (this is the only thing that varies)

The dlib authenticates with **`DefaultAzureCredential`**, so "providing
auth" means "make the right credential discoverable," then run the *same*
signtool command.

1. **Interactive — laptop (Phase 8).** `az login`. The dlib uses the
   AzureCLI credential. Best for the first manual proof. Requires the
   **"Trusted Signing Certificate Profile Signer"** role on your user.
   (Heads-up: some dlib builds prompt browser auth per-sign interactively;
   the SP/OIDC paths below are the non-interactive ones for CI.)

2. **OIDC federated credential — GitHub & GitLab (preferred).** No secret
   stored anywhere. You create an Entra **App Registration**, grant it the
   signer role, and add a **federated identity credential** that trusts
   tokens from a *specific repo/ref*. CI exchanges its OIDC token for an
   Azure token. A fork can't reuse it — the federation is bound to your
   repo. You store only `AZURE_TENANT_ID` / `AZURE_CLIENT_ID` /
   `AZURE_SUBSCRIPTION_ID` (identifiers).

3. **Service-principal client secret — fallback.** A real secret
   (`AZURE_CLIENT_SECRET`) exported as an env var; the dlib's
   EnvironmentCredential picks up `AZURE_TENANT_ID`/`AZURE_CLIENT_ID`/
   `AZURE_CLIENT_SECRET`. Use only where OIDC federation isn't possible
   (see the GitLab reachability caveat). Store masked + protected.

Role assignment is the same regardless of identity type — assign **Trusted
Signing Certificate Profile Signer** on the signing account (scope it to the
account, or the resource group / subscription if you have several):

```bash
az role assignment create \
  --role "Trusted Signing Certificate Profile Signer" \
  --assignee-object-id <user-or-sp-object-id> \
  --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CodeSigning/codeSigningAccounts/<account>
```

## GitHub OIDC (Phase 9)

Azure side (human, once): App Registration **without a secret** → signer
role → **federated credential** with subject like
`repo:<owner>/<repo>:ref:refs/tags/v*` (or an environment subject). Then add
`AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_SUBSCRIPTION_ID` as repo
secrets.

Workflow step (fork-safe gate per `SIGNING.md` — no-ops when the IDs are
absent):

```yaml
permissions:
  id-token: write      # fetch the OIDC token
  contents: write      # attach release assets

jobs:
  release:
    runs-on: windows-latest
    env:
      AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}   # empty in forks
    steps:
      # ... checkout + cmake build into build\Release ...

      - name: Azure login (OIDC) — skipped if secrets absent
        if: ${{ env.AZURE_CLIENT_ID != '' }}
        uses: azure/login@v3
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Sign (Azure Artifact Signing) — skipped if secrets absent
        if: ${{ env.AZURE_CLIENT_ID != '' }}
        uses: azure/artifact-signing-action@v2
        with:
          endpoint: https://neu.codesigning.azure.net/
          signing-account-name: Trusted-Signing-TJE1
          certificate-profile-name: Compelcon-AB-MS-Code-signed
          files-folder: ${{ github.workspace }}\build\Release
          files-folder-filter: exe
          file-digest: SHA256
          timestamp-rfc3161: http://timestamp.acs.microsoft.com
          timestamp-digest: SHA256

      # ... attach build\Release\*.exe to the release (signed or not) ...
```

A fork without the federated credential: the two steps no-op, the build
succeeds, unsigned exes attach. Your identity is never reachable.

## GitLab (Phase 10) — self-managed, `gitlab.compelcon.se`

Two hard constraints:

1. **Windows runner.** Authenticode PE signing is Windows-only — register a
   runner tagged `windows` with the Client Tools installed. A Linux runner
   can build but cannot sign.
2. **Pick the auth path based on internet reachability of your instance.**

**Preferred — OIDC workload-identity federation (no stored secret):** add a
**second** federated credential to the *same* App Registration from Phase 9:
issuer `https://gitlab.compelcon.se`, subject = your GitLab project/ref
claim (e.g. `project_path:<group>/<project>:ref_type:branch:ref:main`, or a
tag pattern). **Pre-requisite:** Microsoft Entra must be able to fetch
`https://gitlab.compelcon.se/.well-known/openid-configuration` over the
public internet with valid TLS. For a private-cloud instance this is the
crux — if Entra can't reach the discovery document, federation cannot
validate the token.

```yaml
sign:
  stage: release
  tags: [windows]
  rules:
    - if: $CI_COMMIT_TAG
  id_tokens:
    AZURE_FEDERATED_TOKEN:
      aud: api://AzureADTokenExchange
  variables:
    AZURE_TENANT_ID: $AZURE_TENANT_ID
    AZURE_CLIENT_ID: $AZURE_CLIENT_ID
  script:
    - az login --service-principal -u $AZURE_CLIENT_ID -t $AZURE_TENANT_ID --federated-token $AZURE_FEDERATED_TOKEN
    - pwsh -File scripts/sign-local.ps1 build/Release/ftdi-unbind.exe build/Release/ftdi-bind.exe build/Release/ftdi-doctor.exe
```

**Fallback — client secret (if the instance isn't publicly reachable):**
create a client secret on the App Registration; store
`AZURE_TENANT_ID` / `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` as GitLab
CI/CD variables that are **Masked** and **Protected** (protected = exposed
only on protected branches/tags). The dlib's EnvironmentCredential consumes
them directly:

```yaml
sign:
  stage: release
  tags: [windows]
  rules:
    - if: $CI_COMMIT_TAG
  script:
    # AZURE_TENANT_ID / AZURE_CLIENT_ID / AZURE_CLIENT_SECRET come from
    # masked+protected CI/CD variables; DefaultAzureCredential picks them up
    - pwsh -File scripts/sign-local.ps1 build/Release/ftdi-unbind.exe build/Release/ftdi-bind.exe build/Release/ftdi-doctor.exe
```

`scripts/sign-local.ps1` is the single signing entry point shared by laptop,
GitHub, and GitLab — it just runs the one `signtool … /dlib … /dmdf
signing.metadata.json …` command on whatever files it's given, and relies
on whatever credential the surrounding context made discoverable.

## Order of operations (and why)

1. **Phase 8 — laptop, `az login`, sign one exe by hand.** Confirms the
   account, eligibility, region, account/profile names, role, and the 64-bit
   signtool/dlib reality with the tightest feedback loop. Everything after is
   the same command with a different credential.
2. **Phase 9 — GitHub OIDC.** Mechanical once the laptop works; gives the
   fork-safe, secretless `release.yml`.
3. **Phase 10 — GitLab.** Hardest only because of the Windows-runner and
   instance-reachability constraints — neither is a signing problem, both are
   infra. Reuse the App Registration and the shared script.

## Cross-references

- `SIGNING.md` — the cheap-path strategy; why Certum is the *forker* path and
  Azure Artifact Signing is the maintainer's; the "sign only if secrets
  present" fork-safety design this doc implements.
- `PLAN.md` — Phases 7–10.
- libwdi still **self-signs the driver `.cat`** during the elevated install;
  that is independent of signing the three `.exe`s and needs none of the
  above.
