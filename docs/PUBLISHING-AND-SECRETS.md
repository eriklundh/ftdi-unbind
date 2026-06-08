# PUBLISHING-AND-SECRETS.md — what is safe to publish, and what is not

Short version: **this project has no signing key to leak.** Azure
Trusted/Artifact Signing keeps the private key in a FIPS HSM that nothing —
not you, not CI — can export. So "protecting signing secrets" is not about
storing a key; it is about controlling *who is allowed to authenticate as the
signing identity*. This doc is the cross-cutting summary; the deep how-to is
[`windows/docs/SIGNING-AZURE-ARTIFACT.md`](../windows/docs/SIGNING-AZURE-ARTIFACT.md).

## What is safe to commit publicly

| Item | Why it is safe |
|---|---|
| `signing.metadata.json` (Endpoint, account name, profile name) | **Identifiers, not credentials.** Knowing them does not let anyone sign — they would need the *signer role* on our Azure identity. It also *must* be committed: it is the `/dmdf` file `signtool` reads. |
| The release workflows (`.github/workflows/release.yml`, `.gitlab-ci.yml`) | They reference secrets by name (`${{ secrets.* }}` / masked CI vars); the values are never in the file. |
| `scripts/sign-local.ps1`, `scripts/release-local.ps1` | They contain no secrets; auth comes from the surrounding context (`az login` / OIDC). |

## What is a secret (and where it lives — never the repo)

| Item | Where it lives | In git? |
|---|---|---|
| `AZURE_TENANT_ID` / `AZURE_CLIENT_ID` / `AZURE_SUBSCRIPTION_ID` | CI secret store (GitHub Actions secrets / GitLab CI/CD vars) | ❌ Not passwords, but kept out of YAML and **not exposed to fork PRs**, which is what auto-disables signing on forks. |
| `AZURE_CLIENT_SECRET` (only the GitLab client-secret fallback) | GitLab CI/CD variable, **Masked + Protected** | ❌ Never, anywhere. |
| `GPG_PRIVATE_KEY` (for `SHA256SUMS.sig`) | CI secret store | ❌ Never in repo. |
| Local laptop auth | `az login` (interactive token cache) | ❌ Nothing stored in-repo. |
| The Authenticode signing key | Microsoft FIPS HSM | ❌ Cannot be exported. |

## How CI proves it may sign — prefer OIDC (zero stored secret)

Instead of storing a password, the CI provider mints a short-lived **OIDC
token** ("I am repo X building ref Y"); Azure is configured to trust *exactly
that* subject and returns a signing token. Nothing secret is stored, and the
trust is **bound to our repo + ref**, so a fork cannot reuse it.

- **GitHub (public repo):** App Registration with **no secret** + a federated
  credential whose subject is `repo:<owner>/<repo>:ref:refs/tags/v*`. Store
  only the three identifiers above as Actions secrets. Run
  [`scripts/setup-github-oidc.ps1`](../scripts/setup-github-oidc.ps1) to create
  all of this in one go.
- **GitLab (`gitlab.compelcon.se`):** same model **iff** Microsoft Entra can
  reach `https://gitlab.compelcon.se/.well-known/openid-configuration` over the
  public internet with valid TLS.
  [`scripts/setup-gitlab-oidc.ps1`](../scripts/setup-gitlab-oidc.ps1) adds a
  *second* federated credential to the *same* App Registration. If the instance
  is **not** publicly reachable, OIDC cannot validate the token — run that script
  with `-CreateClientSecret` and store the resulting `AZURE_CLIENT_SECRET` as a
  **Masked + Protected** CI/CD variable. That is the only place a real secret exists.

> **Why flexible federated credentials.** A release is triggered by a version
> *tag* (`refs/tags/v*` on GitHub, `ref_type:tag:ref:v*` on GitLab) — a
> wildcard. A *standard* Entra federated credential only matches an exact
> subject, so both setup scripts create a **flexible** credential
> (`claimsMatchingExpression`), which supports the wildcard. Nothing else about
> the trust changes.

## Fork safety (public repo)

Every signing step is gated on `AZURE_CLIENT_ID != ''`. GitHub does not expose
secrets to pull requests from forks, so in a fork the variable is empty, the
signing steps no-op, and the build still succeeds with **unsigned** binaries.
Our signing identity is never reachable from a fork, even one that copies the
workflow — the OIDC subject would not match `repo:<owner>/<repo>`.

## Rotation / incident notes

- **Daily certs** rotate automatically (≈24 h validity); signatures are
  RFC3161-timestamped so they stay valid afterward. Nothing to rotate manually.
- **Compromised CI identity:** delete the federated credential (and/or the App
  Registration) in Entra, or remove the signer role assignment — signing stops
  immediately, with no key to revoke or reissue.
- **Real values** (tenant/subscription/account IDs) are intentionally *not*
  written here; read them with `az account show` and
  `az resource list --resource-type Microsoft.CodeSigning/codeSigningAccounts`.
