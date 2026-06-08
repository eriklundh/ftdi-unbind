# scripts/setup-gitlab-oidc.ps1
#
# One-shot setup of signing auth for the GitLab release pipeline. Reuses the
# SAME Entra App Registration as the GitHub setup (scripts/setup-github-oidc.ps1)
# and adds a second federated credential for your GitLab instance — so the same
# signing identity serves both hosts. Creates the app/role if they do not exist
# yet, so it is fine to run this first.
#
# OIDC (no stored secret) PREREQUISITE — read this:
#   Microsoft Entra must be able to fetch
#     <GitLabUrl>/.well-known/openid-configuration
#   over the PUBLIC internet with valid TLS. For a private / air-gapped
#   gitlab.compelcon.se this is the crux: if Entra cannot reach the discovery
#   document it cannot validate the token, and OIDC is impossible. In that case
#   run with -CreateClientSecret and use the AZURE_CLIENT_SECRET fallback
#   (store it as a Masked + Protected GitLab CI/CD variable).
#
# Idempotent: safe to re-run.
#
# Usage:
#   az login
#   pwsh -File scripts\setup-gitlab-oidc.ps1 -GitLabProject unified-serial-terminal/ftdi-unbind
#   pwsh -File scripts\setup-gitlab-oidc.ps1 -GitLabProject unified-serial-terminal/ftdi-unbind -CreateClientSecret

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GitLabProject,                              # "group/subgroup/project" path

    [string]$GitLabUrl          = "https://gitlab.compelcon.se",
    [string]$TagPattern         = "v*",                  # which tags may sign

    [string]$AppName            = "ftdi-unbind-ci-signing",   # shared with the GitHub setup
    [string]$ResourceGroup      = "Trusted-Signing-TJE",
    [string]$CodeSigningAccount = "Trusted-Signing-TJE1",
    [switch]$ScopeToAccount,

    [string]$SubscriptionId,
    [string]$TenantId,
    [switch]$CreateClientSecret                          # fallback for non-reachable instances
)

$ErrorActionPreference = 'Stop'

$script:step = 0
function Step($m){ $script:step++; Write-Host ""; Write-Host ("[{0}] {1}" -f $script:step,$m) -ForegroundColor Cyan }
function Ok($m){ Write-Host "    OK  $m" -ForegroundColor Green }
function Note($m){ Write-Host "    --  $m" -ForegroundColor DarkGray }
function Warn($m){ Write-Host "    !!  $m" -ForegroundColor Yellow }
function Die($m,$fix){ Write-Host ""; Write-Host "███ SETUP ABORTED ███" -ForegroundColor Red; Write-Host "  $m" -ForegroundColor Red; if($fix){ Write-Host "  Fix: $fix" -ForegroundColor Yellow }; exit 1 }
# NB: must NOT be named "Az" — PowerShell is case-insensitive, so a function
# named "Az" shadows the external "az" and `& az` recurses (call-depth overflow).
function Invoke-Az(){ $out = & az @args; if ($LASTEXITCODE -ne 0){ Die "az $($args -join ' ') failed." }; return $out }

try {
    Write-Host ""
    Write-Host "  ███  GitLab OIDC signing setup  ███" -ForegroundColor White

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Die "Azure CLI (az) not found." "winget install -e --id Microsoft.AzureCLI" }
    $GitLabUrl = $GitLabUrl.TrimEnd('/')

    Step "Azure context"
    $acct = (Invoke-Az account show) | ConvertFrom-Json
    if (-not $SubscriptionId) { $SubscriptionId = $acct.id }
    if (-not $TenantId)       { $TenantId       = $acct.tenantId }
    Ok "signed in as $($acct.user.name)"
    Note "subscription $SubscriptionId"
    Note "tenant       $TenantId"

    $scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"
    if ($ScopeToAccount) { $scope += "/providers/Microsoft.CodeSigning/codeSigningAccounts/$CodeSigningAccount" }
    Note "role scope   $scope"

    # ── App Registration (shared, no secret unless -CreateClientSecret) ──────
    Step "App Registration '$AppName'"
    $appId = (Invoke-Az ad app list --display-name $AppName --query "[0].appId" -o tsv)
    if ($appId) { Ok "reusing existing app  (appId $appId)" }
    else { $appId = (Invoke-Az ad app create --display-name $AppName --query appId -o tsv); Ok "created app  (appId $appId)" }

    $spOid = (& az ad sp show --id $appId --query id -o tsv 2>$null)
    if (-not $spOid) { $spOid = (Invoke-Az ad sp create --id $appId --query id -o tsv); Ok "created service principal  (objectId $spOid)" }
    else { Ok "service principal exists  (objectId $spOid)" }

    # ── Signer role ──────────────────────────────────────────────────────────
    Step "Signer role assignment"
    $roleName = "Trusted Signing Certificate Profile Signer"
    $roleId = (& az role definition list --name $roleName --query "[0].name" -o tsv 2>$null)
    if (-not $roleId) { $roleName = "Artifact Signing Certificate Profile Signer"; $roleId = (& az role definition list --name $roleName --query "[0].name" -o tsv 2>$null) }
    if (-not $roleId) { Die "Could not find the signing signer role definition." }
    Note "role: $roleName"
    $existingAssign = (& az role assignment list --assignee $appId --scope $scope --role $roleId --query "[0].id" -o tsv 2>$null)
    if ($existingAssign) { Ok "role already assigned" }
    else { Invoke-Az role assignment create --role $roleId --assignee-object-id $spOid --assignee-principal-type ServicePrincipal --scope $scope | Out-Null; Ok "role assigned at scope" }

    # ── Federated credential for GitLab (the OIDC trust) ─────────────────────
    # GitLab's `sub` claim for a tag pipeline is
    #   project_path:<group>/<project>:ref_type:tag:ref:<tag>
    # <tag> varies, so we use a FLEXIBLE federated credential (wildcard match).
    # NB: flexible credentials (claimsMatchingExpression) are NOT supported by
    # `az ad app federated-credential create` — it demands a static `subject`.
    # They exist only on the Graph **beta** endpoint, so POST via `az rest`.
    Step "Federated credential (issuer $GitLabUrl)"
    $sub = "project_path:${GitLabProject}:ref_type:tag:ref:${TagPattern}"
    $matchExpr = "claims['sub'] matches '$sub'"
    $fcName = "gitlab-" + (("$GitLabProject-$TagPattern") -replace '[^a-zA-Z0-9]+','-')
    if ($fcName.Length -gt 120) { $fcName = $fcName.Substring(0,120) }
    $objId = (Invoke-Az ad app show --id $appId --query id -o tsv)
    $graph = "https://graph.microsoft.com/beta/applications/$objId/federatedIdentityCredentials"
    $existingFc = (& az rest --method GET --url $graph --query "value[?name=='$fcName'].name" -o tsv 2>$null)
    if ($existingFc) {
        Ok "federated credential '$fcName' already present"
    } else {
        $params = [ordered]@{
            name      = $fcName
            issuer    = $GitLabUrl
            audiences = @("api://AzureADTokenExchange")
            claimsMatchingExpression = [ordered]@{ value = $matchExpr; languageVersion = 1 }
        } | ConvertTo-Json -Compress -Depth 5
        $tmp = New-TemporaryFile
        Set-Content -Path $tmp -Value $params -Encoding ascii
        Invoke-Az rest --method POST --url $graph --headers "Content-Type=application/json" --body "@$tmp" | Out-Null
        Remove-Item $tmp -ErrorAction SilentlyContinue
        Ok "flexible federated credential created: $fcName"
    }
    Note "trusts: $sub"
    Warn "OIDC works only if Entra can reach $GitLabUrl/.well-known/openid-configuration"
    Warn "over the public internet. If it cannot, re-run with -CreateClientSecret."

    # ── Optional: client-secret fallback (non-reachable instances) ───────────
    $clientSecret = $null
    if ($CreateClientSecret) {
        Step "Client secret (fallback)"
        $clientSecret = (Invoke-Az ad app credential reset --id $appId --display-name "gitlab-ci" --years 1 --query password -o tsv)
        Ok "client secret created (shown once below — store it now)"
    }

    # ── Hand off the CI/CD variables ─────────────────────────────────────────
    Step "GitLab CI/CD variables"
    Note "Project → Settings → CI/CD → Variables. Mark secrets Masked + Protected:"
    Write-Host ("      {0,-22} {1}" -f "AZURE_CLIENT_ID",       $appId)
    Write-Host ("      {0,-22} {1}" -f "AZURE_TENANT_ID",       $TenantId)
    Write-Host ("      {0,-22} {1}" -f "AZURE_SUBSCRIPTION_ID", $SubscriptionId)
    if ($clientSecret) {
        Write-Host ("      {0,-22} {1}" -f "AZURE_CLIENT_SECRET", $clientSecret) -ForegroundColor Yellow
        Warn "AZURE_CLIENT_SECRET is shown ONCE — set it Masked + Protected now."
    }

    Write-Host ""
    Write-Host "  ███  GITLAB SIGNING READY  ███" -ForegroundColor Green
    if ($clientSecret) {
        Write-Host "  Client-secret fallback configured. Tag a v* release on a protected tag." -ForegroundColor White
    } else {
        Write-Host "  OIDC federation configured (no stored secret). Tag a v* release." -ForegroundColor White
    }
    Write-Host "  To revoke: delete the federated credential / secret / App Registration." -ForegroundColor DarkGray
}
catch { Die $_.Exception.Message }
