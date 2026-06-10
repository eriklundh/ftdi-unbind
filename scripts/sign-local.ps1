# scripts/sign-local.ps1
# Author Erik Lundh, The Joy of Engineering, erik.lundh@ingenjorsgladje.se
#
# Sign one or more executables using Azure Artifact Signing.
# Reads endpoint/account/profile from signing.metadata.json (non-secret).
# Authentication is provided by the surrounding context:
#   - Laptop:  az login (AzureCLI credential, interactive)
#   - GitHub:  azure/login action with OIDC (no secret)
#   - GitLab:  az login --service-principal --federated-token (OIDC)
#              or AZURE_CLIENT_SECRET env var (fallback)
#
# Usage:
#   pwsh -File scripts/sign-local.ps1 path\to\ftdi-unbind.exe [path\to\...more...]
#
# Requires:
#   - Microsoft.Azure.TrustedSigningClientTools installed
#     (winget install -e --id Microsoft.Azure.TrustedSigningClientTools)
#   - The 64-bit signtool.exe on PATH (the x64 Native Tools prompt, or full path)
#   - signing.metadata.json in scripts/ (next to this script)

param(
    [string]$MetadataFile = "$PSScriptRoot\signing.metadata.json",

    [Parameter(Mandatory, Position = 0, ValueFromRemainingArguments)]
    [string[]]$Files
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $MetadataFile)) {
    throw "signing.metadata.json not found at $MetadataFile.`nCreate it with Endpoint / CodeSigningAccountName / CertificateProfileName (see docs/SIGNING.md)."
}

# Locate the Azure CodeSigning dlib.
# The TrustedSigningClientTools package installs it to the .NET tools path.
$dlibSearch = @(
    # v1.0.0+ (MSI, winget Microsoft.Azure.TrustedSigningClientTools >= 1.0.0)
    "$env:LOCALAPPDATA\Microsoft\MicrosoftTrustedSigningClientTools\Azure.CodeSigning.Dlib.dll",
    # v0.1.x (older MSI / manual NuGet install)
    "$env:LOCALAPPDATA\Microsoft\Azure.CodeSigning.Dlib\Azure.CodeSigning.Dlib.dll",
    "$env:PROGRAMFILES\Microsoft\Azure Trusted Signing Client\bin\x64\Azure.CodeSigning.Dlib.dll"
)
$dlib = $dlibSearch | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $dlib) {
    # Fallback: NuGet global packages cache (dotnet tool install path)
    $dlib = Get-ChildItem "$env:USERPROFILE\.nuget\packages\microsoft.trusted.signing.client" `
        -Recurse -Filter 'Azure.CodeSigning.Dlib.dll' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $dlib) {
    throw "Azure.CodeSigning.Dlib.dll not found.`nRun: winget install -e --id Microsoft.Azure.TrustedSigningClientTools"
}

# Locate the 64-bit signtool.exe. Prefer the one from the Windows SDK.
$sdkBase = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
$signtool = Get-ChildItem $sdkBase -Filter 'signtool.exe' -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like '*\x64\*' } |
    Sort-Object { [version]($_.Directory.Parent.Name) } -Descending |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $signtool) {
    $signtool = 'signtool.exe'   # hope it's on PATH
}

Write-Host "signtool: $signtool"
Write-Host "dlib:     $dlib"
Write-Host "metadata: $MetadataFile"
Write-Host "files:    $($Files -join ', ')"
Write-Host ""

& $signtool sign /v /fd SHA256 `
    /tr  http://timestamp.acs.microsoft.com /td SHA256 `
    /dlib $dlib `
    /dmdf (Resolve-Path $MetadataFile) `
    @Files

if ($LASTEXITCODE -ne 0) { throw "signtool exited with code $LASTEXITCODE" }

Write-Host ""
Write-Host "Verifying signatures ..."
foreach ($f in $Files) {
    & $signtool verify /pa /v $f
    if ($LASTEXITCODE -ne 0) { throw "Verification failed for $f" }
}
Write-Host "All signatures verified."
