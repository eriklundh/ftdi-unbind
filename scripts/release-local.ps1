# scripts/release-local.ps1
# Author Erik Lundh, The Joy of Engineering, erik.lundh@ingenjorsgladje.se
#
#   ███  THE BIG RED BUTTON  ███
#
# Manual, fail-fast local release of the three Windows tools:
#   build (release, tools only) -> test -> SIGN -> verify -> package.
#
# Signing is DELIBERATELY not part of the normal build/test cycle: the signing
# step can pop a browser for Azure auth, which would hang an unattended build
# (e.g. a Claude agent doing code updates while you are away). This button is
# the *only* thing that signs, and you run it on purpose, while present.
#
# Usage:
#   pwsh -File scripts\release-local.ps1                 # build + test + sign + package
#   pwsh -File scripts\release-local.ps1 -Version v0.2.0 # stamp a specific version
#   pwsh -File scripts\release-local.ps1 -SkipTests      # tight path: skip the test gate
#   pwsh -File scripts\release-local.ps1 -Login          # run `az login` first if needed
#   pwsh -File scripts\release-local.ps1 -Clean          # wipe the release build dir first
#
# Output: ftdi-unbind\dist\
#   ftdi-unbind.exe ftdi-bind.exe ftdi-doctor.exe   (signed)
#   ftdi-tools-<version>-windows-x64.zip            (the three, signed)
#   SHA256SUMS                                        (sha256sum -c compatible)
#
# Requires (same as sign-local.ps1): Azure CLI logged in (`az login`),
# Microsoft.Azure.TrustedSigningClientTools, a recent x64 signtool, libwdi
# built as a static lib, and signing.metadata.json filled in.

[CmdletBinding()]
param(
    [string]$Version,
    [switch]$SkipTests,
    [switch]$Clean,
    [switch]$Login,
    [string]$LibwdiIncludeDir = "C:/usr/local/src/libwdi/libwdi",
    [string]$LibwdiLib        = "C:/usr/local/src/libwdi/x64/Release/lib/libwdi.lib",
    [string]$Generator        = "Visual Studio 17 2022"
)

$ErrorActionPreference = 'Stop'

# ── Paths (all derived from this script's location — cwd independent) ─────────
$RepoRoot  = (Resolve-Path "$PSScriptRoot\..").Path
$WinDir    = Join-Path $RepoRoot 'windows'
$BuildDir  = Join-Path $WinDir   'build-release'   # dedicated; never clobbers your dev build dir
$ReleaseBin= Join-Path $BuildDir 'Release'
$DistDir   = Join-Path $RepoRoot 'dist'
$Metadata  = Join-Path $PSScriptRoot 'signing.metadata.json'
$SignScript= Join-Path $PSScriptRoot 'sign-local.ps1'
$Exes      = 'ftdi-unbind.exe','ftdi-bind.exe','ftdi-doctor.exe'

# ── Tiny output helpers ──────────────────────────────────────────────────────
$script:step = 0
function Step($msg) { $script:step++; Write-Host ""; Write-Host ("[{0}] {1}" -f $script:step, $msg) -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    OK  $msg" -ForegroundColor Green }
function Note($msg) { Write-Host "    --  $msg" -ForegroundColor DarkGray }
function Die($msg, $fix) {
    Write-Host ""
    Write-Host "███ RELEASE ABORTED ███" -ForegroundColor Red
    Write-Host "  $msg" -ForegroundColor Red
    if ($fix) { Write-Host ""; Write-Host "  Fix:" -ForegroundColor Yellow; Write-Host "    $fix" -ForegroundColor Yellow }
    exit 1
}

try {
    Write-Host ""
    Write-Host "  ███  ftdi-unbind — local signed release  ███" -ForegroundColor White

    # ── 1. Pre-flight: fail BEFORE building so you never get a half-done run ──
    Step "Pre-flight checks"

    if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
        Die "cmake not found on PATH." "Open the 'x64 Native Tools' / Developer prompt, or install CMake 3.20+."
    }
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Die "Azure CLI (az) not found on PATH." "winget install -e --id Microsoft.AzureCLI   (then restart the shell)"
    }
    if (-not (Test-Path $Metadata)) {
        Die "signing.metadata.json not found at $Metadata." "Fill in Endpoint / CodeSigningAccountName / CertificateProfileName."
    }
    if (-not (Test-Path $LibwdiLib)) {
        Die "libwdi static lib not found:`n      $LibwdiLib" "Build libwdi (see windows\docs\BUILD-ENVIRONMENT.md), or pass -LibwdiLib <path> -LibwdiIncludeDir <dir>."
    }
    if (-not (Test-Path $SignScript)) { Die "sign-local.ps1 missing next to this script." }

    # Show which account we're about to sign with (catches the wrong-account class of bug).
    $meta = Get-Content $Metadata -Raw | ConvertFrom-Json
    Note "signing account : $($meta.CodeSigningAccountName)  /  profile: $($meta.CertificateProfileName)"
    Note "endpoint        : $($meta.Endpoint)"

    # Azure login state — the one thing that can pop a browser. Resolve it up front.
    if ($Login) {
        Note "running az login ..."
        az login | Out-Null
        if ($LASTEXITCODE -ne 0) { Die "az login failed." }
    }
    $acct = az account show 2>$null | ConvertFrom-Json
    if (-not $acct) {
        Die "Not logged in to Azure." "Run:  az login    (or re-run this with -Login).`n    You must be present for this step — it may open a browser."
    }
    Ok "azure: $($acct.user.name)  (tenant: $($acct.tenantDefaultDomain))"

    # ── 2. Version ───────────────────────────────────────────────────────────
    Step "Version"
    if (-not $Version) {
        $desc = (git -C $RepoRoot describe --tags --always 2>$null)
        $Version = if ($desc) { "$desc" } else { "v0.0.0-dev" }
        Note "no -Version given; using git describe"
    }
    $Version = $Version.Trim()
    Ok "version = $Version"

    # ── 3. (Optional) clean ──────────────────────────────────────────────────
    if ($Clean -and (Test-Path $BuildDir)) {
        Step "Clean"
        Remove-Item -Recurse -Force $BuildDir
        Ok "removed $BuildDir"
    }

    # ── 4. Configure + build (release; tools only) ───────────────────────────
    Step "Configure + build (Release)"
    $cfgArgs = @('-S', $WinDir, '-B', $BuildDir, '-G', $Generator, '-A', 'x64',
                 "-DLIBWDI_INCLUDE_DIR=$LibwdiIncludeDir", "-DLIBWDI_LIB=$LibwdiLib")
    if (-not $SkipTests) { $cfgArgs += '-DFTDI_BUILD_TESTS=ON' }   # build tests so we can gate on them
    cmake @cfgArgs
    if ($LASTEXITCODE -ne 0) { Die "CMake configure failed." }
    cmake --build $BuildDir --config Release
    if ($LASTEXITCODE -ne 0) { Die "Build failed." }
    Ok "built into $ReleaseBin"

    # ── 5. Test gate ─────────────────────────────────────────────────────────
    if ($SkipTests) {
        Step "Tests"
        Write-Host "    !!  SKIPPED (-SkipTests) — you are shipping untested binaries." -ForegroundColor Yellow
    } else {
        Step "Tests (must pass before signing)"
        ctest --test-dir $BuildDir -C Release --output-on-failure
        if ($LASTEXITCODE -ne 0) { Die "Tests FAILED — nothing signed, nothing shipped." "Fix the failing test, then press the button again." }
        Ok "all tests passed"
    }

    # ── 6. Confirm the three exes exist ──────────────────────────────────────
    Step "Locate release binaries"
    $paths = foreach ($e in $Exes) {
        $p = Join-Path $ReleaseBin $e
        if (-not (Test-Path $p)) { Die "Expected binary missing: $p" "Build may have failed silently — re-run with -Clean." }
        $p
    }
    $paths | ForEach-Object { Ok (Split-Path $_ -Leaf) }

    # ── 7. SIGN (reuses sign-local.ps1 — the single signing code path) ───────
    Step "Sign (Azure Trusted/Artifact Signing)"
    Note "if a browser opens, complete it as the identity that holds the signer role"
    & $SignScript @paths
    if ($LASTEXITCODE -ne 0) { Die "Signing failed." "Check Azure login + signer role; see windows\docs\SIGNING-AZURE-ARTIFACT.md." }

    # ── 8. Hard-verify every signature (Windows' own validation) ─────────────
    Step "Verify signatures"
    foreach ($p in $paths) {
        $sig = Get-AuthenticodeSignature $p
        if ($sig.Status -ne 'Valid') {
            Die "Signature not valid on $(Split-Path $p -Leaf): $($sig.Status) — $($sig.StatusMessage)"
        }
        $subj = ($sig.SignerCertificate.Subject -split ',')[0]
        Ok ("{0,-18} {1}  (cert exp {2:yyyy-MM-dd})" -f (Split-Path $p -Leaf), $subj, $sig.SignerCertificate.NotAfter)
    }

    # ── 9. Package into dist\ ────────────────────────────────────────────────
    Step "Package -> dist\"
    if (Test-Path $DistDir) { Remove-Item -Recurse -Force $DistDir }
    New-Item -ItemType Directory -Path $DistDir | Out-Null
    Copy-Item $paths -Destination $DistDir

    # GPL-3.0 text must travel with the binaries (they statically link LGPL libwdi)
    $licensePath = Join-Path $RepoRoot 'windows\LICENSE'

    $zipName = "ftdi-tools-$Version-windows-x64.zip"
    $zipPath = Join-Path $DistDir $zipName
    Compress-Archive -Path (@($paths) + $licensePath) -DestinationPath $zipPath -Force
    Ok $zipName

    # SHA256SUMS — `sha256sum -c` compatible (lowercase hash, two spaces, bare names).
    $sumsPath = Join-Path $DistDir 'SHA256SUMS'
    $lines = foreach ($f in (@($zipPath) + $paths)) {
        $h = (Get-FileHash $f -Algorithm SHA256).Hash.ToLower()
        "{0}  {1}" -f $h, (Split-Path $f -Leaf)
    }
    Set-Content -Path $sumsPath -Value $lines -Encoding ascii
    Ok "SHA256SUMS"

    # ── Done ─────────────────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "  ███  RELEASE READY  ███" -ForegroundColor Green
    Write-Host "  $DistDir" -ForegroundColor White
    Get-ChildItem $DistDir | ForEach-Object {
        Write-Host ("    {0,-40} {1,10:N0} bytes" -f $_.Name, $_.Length)
    }
    Write-Host ""
    Write-Host "  Hand these over / attach $zipName to the release." -ForegroundColor White
    Write-Host "  (Signatures are timestamped — they stay valid after today's daily cert expires.)" -ForegroundColor DarkGray
}
catch {
    Die $_.Exception.Message
}
