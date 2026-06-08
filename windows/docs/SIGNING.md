# SIGNING.md — code signing on the cheap (for independent developers)

The goal of this doc is not just "how the maintainer signs these tools."
It's a map of the **cheapest legitimate path to publicly-trusted code
signing for an independent developer in 2026**, with the trade-offs
stated honestly — so anyone forking this project can get to
production-quality signed binaries without overspending.

> Prices below were checked in mid-2026. The code-signing market changed
> a lot in 2023–2026; re-verify current pricing and policy before you
> buy. This is practical guidance, not legal or procurement advice.

## The 2026 reality check (read first — it overturns old advice)

Three changes make most pre-2026 "how to code sign cheaply" articles
wrong:

1. **Keys must live in hardware.** Since June 2023, publicly-trusted
   code-signing private keys must be on a FIPS HSM — a USB token, or a
   cloud HSM. The old "$80 cert as a downloadable `.pfx`" is gone. For
   automation you want a **cloud HSM** (no physical token to plug into a
   CI runner).
2. **EV no longer auto-skips SmartScreen.** EV certificates used to
   bypass the SmartScreen warning instantly, which justified their
   premium. Microsoft is removing that benefit across 2026 updates — EV
   now builds reputation over time, like OV. So **don't pay for EV just
   to skip SmartScreen anymore**; the cheap OV/Open-Source cert gets you
   most of the way.
3. **Validity shrank.** From 1 March 2026 the maximum cert validity
   dropped to ~460 days (~15 months); multi-year certs are largely gone.
   Budget annually.

Net effect: the cheapest *cloud-HSM* OV or Open-Source certificate is now
the sweet spot for an independent developer. EV is for niche cases
(kernel-mode driver signing), not for skipping SmartScreen.

## The options, cheapest first

| Option | ~Cost/yr | Trust | Token-free / CI? | Eligibility | Best for |
|--------|---------|-------|------------------|-------------|----------|
| **Certum Open Source Code Signing** | **~$50** | Public (OV-class, builds reputation) | Cloud (SimplySign), CI doable | Projects under an OSS licence | **The showcase cheap path** — these tools are GPL/LGPL, so they qualify |
| **Certum Standard OV (cloud)** | ~$90 | Public, builds reputation | Cloud (SimplySign), CI doable | Anyone (identity-validated) | Closed-source independent projects |
| **Azure Trusted / Artifact Signing** | ~$120 | Public, builds reputation | Cloud HSM, **best CI action + OIDC** | **EU orgs yes; EU individuals NO** (individuals US/Canada only) | Teams wanting turnkey CI who clear the eligibility gate |
| **SSL.com / DigiCert / GlobalSign OV** | $65–400 | Public | Cloud HSM (KV-compatible: DigiCert/GlobalSign) | Anyone | If you need Azure Key Vault + AzureSignTool specifically |
| **EV (any CA)** | $230+ | Public, **no longer instant SmartScreen** | Token or cloud HSM | Anyone | Kernel-mode driver signing — not worth it just for SmartScreen now |
| **Self-signed** | free | None publicly (Private Trust only) | n/a | Anyone | Internal/test only; libwdi already self-signs its driver `.cat` |

Also worth investigating for OSS: **SignPath Foundation** reportedly
sponsors free code signing for qualifying open-source projects — verify
current terms directly, as I have not confirmed them here. If it applies,
it's the one path cheaper than Certum's $50.

## Recommended path for this project

These tools are open source, so the showcase path is **Certum Open
Source Code Signing (~$50/yr)** — the cheapest publicly-trusted route,
cloud-based, from an EU CA, no token. That's the path this doc centres,
because it's the one an independent engineer anywhere can actually take.

The maintainer additionally has **Azure Trusted Signing**, which is the
more turnkey CI option (official GitHub Action). Both are documented
below. **The eligibility gate is why Certum is the showcase, not Azure
TS:** Azure TS public-trust signing is open to EU *organizations* but
**not** EU *individuals* (individual onboarding is US/Canada only), so it
isn't a path every independent developer can follow.

## The honest CI trade-off

- **Cheapest (Certum OSS, ~$50):** signing in CI goes through Certum's
  **SimplySign** cloud. It works in GitHub Actions but takes more setup
  than a one-line action (SimplySign credential + `signtool`/CLI), and
  Certum keys are **not** importable into Azure Key Vault. Plan for an
  hour of first-time fiddling.
- **Most turnkey (Azure Trusted Signing, ~$120):** official
  `azure/trusted-signing-action` (now Artifact Signing) + OIDC, a few
  lines in the workflow. Costs more and is eligibility-gated.

Lowering the threshold means documenting the cheap path *and* being
honest that it costs you some setup time the pricier path doesn't.

## CI signing — sign only when secrets are present

Whichever path, the release workflow must **sign only if the signing
secrets exist, and build unsigned (without failing) when they don't.**
This is what lets forks build out of the box and keeps your identity
un-shareable.

Sketch (the live step lands in `CI.md`'s `release.yml`):

```yaml
  - name: Sign (Azure Trusted Signing) — skipped if secrets absent
    if: ${{ env.AZURE_CLIENT_ID != '' }}
    uses: azure/trusted-signing-action@v0
    with:
      azure-tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      azure-client-id: ${{ secrets.AZURE_CLIENT_ID }}
      endpoint: https://neu.codesigning.azure.net/   # North Europe (this account)
      trusted-signing-account-name: Trusted-Signing-TJE1
      certificate-profile-name: Compelcon-AB-MS-Code-signed
      files-folder: ${{ github.workspace }}/build/Release
      files-folder-filter: exe
  # Certum SimplySign alternative: a signtool step gated the same way,
  # using SIMPLYSIGN_* secrets. See the Certum path section.
```

## Bring your own identity (for forkers)

You never share your dev ID or signing credential, and forkers never need
it:

- A fork **builds unsigned by default** — the signing step no-ops because
  the secrets aren't set. No failure, no access to your identity.
- A forker who wants signed builds adds **their own** identity:
  - **Certum OSS path:** buy the ~$50 cert, add `SIMPLYSIGN_*` secrets,
    enable the Certum signing step.
  - **Azure TS path:** create their own Trusted/Artifact Signing account,
    register an App + **OIDC federated credential scoped to their repo**,
    add `AZURE_TENANT_ID` / `AZURE_CLIENT_ID`. With OIDC there is no
    long-lived secret, and a fork *cannot* sign with your identity even
    in principle — the federated credential is bound to a specific repo.

Document the secret names and the federated-credential setup so a forker
self-serves. The "skip if absent" behaviour is the mechanism that makes
this safe and frictionless.

## What this does NOT cover: the driver catalog

Signing the `.exe`s (above) is separate from the WinUSB **driver**
catalog. libwdi auto-generates and **self-signs** the driver `.cat` it
installs, handling that trust during the elevated install itself — you do
not need your public cert for the driver step. Keep the two concerns
separate: your code-signing cert is for the `ftdi-unbind.exe` /
`ftdi-bind.exe` binaries; libwdi owns the driver-catalog signing.

## MSIX + Microsoft Store: documented, but ruled out for *these* tools

It's natural to reach for the Store's free signing: submit a *free*
product, Microsoft signs the MSIX package for Store distribution, no
certificate cost, and free products carry no revenue share. For an
ordinary utility that's a legitimate, genuinely free signing path — worth
knowing.

It does **not** work for these tools, on two independent grounds that
Microsoft states explicitly in its own MSIX packaging guidance:

1. **Elevation.** These tools require admin to install/remove drivers.
   Microsoft's MSIX prep guidance is unambiguous: an app that requires
   elevation for *any* part of its functionality will not be accepted
   into the Store. MSIX enforces a user-level context and cannot itself
   trigger UAC — a component that needs elevation can't run properly
   under the package model.
2. **Drivers.** The same guidance states MSIX does not support Windows
   drivers. These tools install the in-box WinUSB driver via libwdi,
   exactly the kind of driver-binding operation the model excludes.

So the free-signing benefit is real, but it attaches to a packaging model
that structurally rejects elevation- and driver-dependent tools. This is
a documented disqualification, not a "try and see" — don't invest effort
in MSIX packaging for these utilities.

Scope note: even setting the disqualifiers aside, what the Store signs is
the *Store-distributed MSIX*, **not** the standalone `.exe` you attach to
a GitHub Release. Store submission would never sign the bare binaries your
users actually run — that's what the Certum / Azure Trusted Signing path
above is for.

**When the Store path *is* right:** an ordinary, non-elevating,
driver-free free utility. There, MSIX + Store free signing is a fine,
genuinely no-cost route, worth remembering for other projects. It's this
project's *driver + admin* nature that rules it out — nothing about the
Store itself.

## v0.1 stance

The tools **function unsigned** — signing is about trust, not behaviour.
A reasonable first release ships unsigned with a documented SmartScreen
click-through, then adds the signing step once the cert is in hand. The
workflow's "sign if secrets present" design means turning signing on
later is just adding the secrets — no workflow rewrite.
