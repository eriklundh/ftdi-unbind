# scripts/setup-github-oidc.ps1
#
# One-shot setup of secretless (OIDC) signing for the GitHub release workflow.
# Creates an Entra App Registration WITHOUT a client secret, grants it the
# Trusted/Artifact Signing signer role on the signing account, and adds a
# federated credential that trusts ONLY this repo's version tags. Then prints
# (or, with -SetGitHubSecrets, sets) the three identifiers the workflow needs.
#
# There is no secret to store anywhere — that is the whole point.
#
# Idempotent: safe to re-run; it reuses an existing app / role / credential.
#
# Usage:
#   az login                                              # as an Owner / privileged admin
#   pwsh -File scripts\setup-github-oidc.ps1 -GitHubRepo eriklundh/ftdi-unbind
#   pwsh -File scripts\setup-github-oidc.ps1 -GitHubRepo eriklundh/ftdi-unbind -SetGitHubSecrets
#
# After it runs, push a v* tag — the release workflow signs automatically.

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GitHubRepo,                                  # "owner/repo"

    [string]$AppName            = "ftdi-unbind-ci-signing",   # shared with the GitLab setup
    # The OIDC subject suffix after "repo:<owner>/<repo>:". Default = any v* tag.
    # Other options: "ref:refs/heads/main", "environment:release".
    [string]$SubjectRef         = "ref:refs/tags/v*",

    [string]$ResourceGroup      = "Trusted-Signing-TJE",
    [string]$CodeSigningAccount = "Trusted-Signing-TJE1",
    # Scope the role to the whole RG (default) or just the account.
    [switch]$ScopeToAccount,

    [string]$SubscriptionId,                              # default: current az account
    [string]$TenantId,                                    # default: current az account
    [switch]$SetGitHubSecrets                             # use `gh` to set repo secrets
)

$ErrorActionPreference = 'Stop'

$script:step = 0
function Step($m){ $script:step++; Write-Host ""; Write-Host ("[{0}] {1}" -f $script:step,$m) -ForegroundColor Cyan }
function Ok($m){ Write-Host "    OK  $m" -ForegroundColor Green }
function Note($m){ Write-Host "    --  $m" -ForegroundColor DarkGray }
function Die($m,$fix){ Write-Host ""; Write-Host "███ SETUP ABORTED ███" -ForegroundColor Red; Write-Host "  $m" -ForegroundColor Red; if($fix){ Write-Host "  Fix: $fix" -ForegroundColor Yellow }; exit 1 }
# Run az, fail fast on non-zero exit (az writes the error to stderr itself).
function Az(){ $out = & az @args; if ($LASTEXITCODE -ne 0){ Die "az $($args -join ' ') failed." }; return $out }

try {
    Write-Host ""
    Write-Host "  ███  GitHub OIDC signing setup (no stored secret)  ███" -ForegroundColor White

    if ($GitHubRepo -notmatch '^[^/]+/[^/]+$') { Die "GitHubRepo must be 'owner/repo' (got '$GitHubRepo')." }
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Die "Azure CLI (az) not found." "winget install -e --id Microsoft.AzureCLI" }

    Step "Azure context"
    $acct = (Az account show) | ConvertFrom-Json
    if (-not $SubscriptionId) { $SubscriptionId = $acct.id }
    if (-not $TenantId)       { $TenantId       = $acct.tenantId }
    Ok "signed in as $($acct.user.name)"
    Note "subscription $SubscriptionId"
    Note "tenant       $TenantId"

    # Resolve the scope the signer role is granted on.
    $scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"
    if ($ScopeToAccount) {
        $scope += "/providers/Microsoft.CodeSigning/codeSigningAccounts/$CodeSigningAccount"
    }
    Note "role scope   $scope"

    # ── App Registration (no secret) ─────────────────────────────────────────
    Step "App Registration '$AppName'"
    $appId = (Az ad app list --display-name $AppName --query "[0].appId" -o tsv)
    if ($appId) {
        Ok "reusing existing app  (appId $appId)"
    } else {
        $appId = (Az ad app create --display-name $AppName --query appId -o tsv)
        Ok "created app  (appId $appId)"
    }

    # Service principal for the app.
    $spOid = (& az ad sp show --id $appId --query id -o tsv 2>$null)
    if (-not $spOid) {
        $spOid = (Az ad sp create --id $appId --query id -o tsv)
        Ok "created service principal  (objectId $spOid)"
    } else {
        Ok "service principal exists  (objectId $spOid)"
    }

    # ── Signer role assignment ───────────────────────────────────────────────
    Step "Signer role assignment"
    $roleName = "Trusted Signing Certificate Profile Signer"
    $roleId = (& az role definition list --name $roleName --query "[0].name" -o tsv 2>$null)
    if (-not $roleId) {
        $roleName = "Artifact Signing Certificate Profile Signer"   # post-rename name
        $roleId = (& az role definition list --name $roleName --query "[0].name" -o tsv 2>$null)
    }
    if (-not $roleId) { Die "Could not find the signing signer role definition." "Check you are in the right tenant/subscription." }
    Note "role: $roleName"

    $existingAssign = (& az role assignment list --assignee $appId --scope $scope --role $roleId --query "[0].id" -o tsv 2>$null)
    if ($existingAssign) {
        Ok "role already assigned"
    } else {
        Az role assignment create --role $roleId --assignee-object-id $spOid `
            --assignee-principal-type ServicePrincipal --scope $scope | Out-Null
        Ok "role assigned at scope"
    }

    # ── Federated credential (the OIDC trust) ────────────────────────────────
    # A version tag (refs/tags/v*) is a WILDCARD, which a *standard* federated
    # credential (exact subject) cannot match — so we create a FLEXIBLE federated
    # credential whose claims-matching expression supports the wildcard.
    Step "Federated credential (trusts repo:${GitHubRepo}:${SubjectRef})"
    $matchExpr = "claims['sub'] matches 'repo:${GitHubRepo}:${SubjectRef}'"
    $fcName = "github-" + (("$GitHubRepo-$SubjectRef") -replace '[^a-zA-Z0-9]+','-')
    if ($fcName.Length -gt 120) { $fcName = $fcName.Substring(0,120) }
    $existingFc = (& az ad app federated-credential list --id $appId --query "[?name=='$fcName'].name" -o tsv 2>$null)
    if ($existingFc) {
        Ok "federated credential '$fcName' already present"
    } else {
        $params = [ordered]@{
            name      = $fcName
            issuer    = "https://token.actions.githubusercontent.com"
            audiences = @("api://AzureADTokenExchange")
            claimsMatchingExpression = [ordered]@{ value = $matchExpr; languageVersion = 1 }
        } | ConvertTo-Json -Compress -Depth 5
        $tmp = New-TemporaryFile
        Set-Content -Path $tmp -Value $params -Encoding ascii
        Az ad app federated-credential create --id $appId --parameters "@$tmp" | Out-Null
        Remove-Item $tmp -ErrorAction SilentlyContinue
        Ok "flexible federated credential created: $fcName"
    }

    # ── Hand off the three identifiers ───────────────────────────────────────
    Step "GitHub Actions secrets"
    $secrets = [ordered]@{
        AZURE_CLIENT_ID       = $appId
        AZURE_TENANT_ID       = $TenantId
        AZURE_SUBSCRIPTION_ID = $SubscriptionId
    }
    if ($SetGitHubSecrets) {
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Die "gh CLI not found." "Install GitHub CLI, or omit -SetGitHubSecrets and set them in the web UI." }
        foreach ($k in $secrets.Keys) {
            $secrets[$k] | gh secret set $k -R $GitHubRepo | Out-Null
            if ($LASTEXITCODE -ne 0) { Die "gh secret set $k failed." }
            Ok "set secret $k on $GitHubRepo"
        }
    } else {
        Note "Add these in GitHub → Settings → Secrets and variables → Actions:"
        foreach ($k in $secrets.Keys) { Write-Host ("      {0,-22} {1}" -f $k, $secrets[$k]) }
    }

    Write-Host ""
    Write-Host "  ███  OIDC SIGNING READY  ███" -ForegroundColor Green
    Write-Host "  No secret was created or stored. Push a v* tag and the release"  -ForegroundColor White
    Write-Host "  workflow will sign the exes via this federated identity."        -ForegroundColor White
    Write-Host "  To revoke: delete the federated credential or App Registration." -ForegroundColor DarkGray
}
catch { Die $_.Exception.Message }
