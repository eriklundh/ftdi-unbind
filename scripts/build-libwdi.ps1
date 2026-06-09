# scripts/build-libwdi.ps1
# Author Erik Lundh, The Joy of Engineering, erik.lundh@ingenjorsgladje.se
#
# Clone libwdi v1.5.0, apply the patches required to build without the WDK
# co-installer DLLs (Windows 8+ in-box WinUSB), and build the static lib.
#
# Outputs:
#   $OutDir\lib\libwdi.lib    — static library
#   $OutDir\include\libwdi.h  — header
#
# Usage (from repo root or the windows/ directory):
#   pwsh -File scripts/build-libwdi.ps1 [-LibwdiDir <path>] [-OutDir <path>]
#
# If LibwdiDir already contains a built libwdi.lib, this script exits
# immediately so CI caching works correctly.

param(
    [string]$LibwdiDir = "$PSScriptRoot\..\libwdi-src",
    [string]$OutDir    = "$PSScriptRoot\..\libwdi-out"
)

$ErrorActionPreference = 'Stop'
$libwdiTag  = 'v1.5.0'
$libwdiRepo = 'https://github.com/pbatard/libwdi.git'

$libFile = Join-Path $OutDir 'lib\libwdi.lib'
$incFile = Join-Path $OutDir 'include\libwdi.h'

# Already built — nothing to do (CI cache hit path).
if ((Test-Path $libFile) -and (Test-Path $incFile)) {
    Write-Host "libwdi already built at $OutDir — skipping."
    exit 0
}

# ── Clone ────────────────────────────────────────────────────────────────────

if (-not (Test-Path (Join-Path $LibwdiDir '.git'))) {
    Write-Host "Cloning libwdi $libwdiTag ..."
    git clone --depth 1 --branch $libwdiTag $libwdiRepo $LibwdiDir
} else {
    Write-Host "libwdi source already present at $LibwdiDir"
}

Push-Location $LibwdiDir

# ── Patch 1: msvc/config.h ───────────────────────────────────────────────────
# Disable WDK/co-installer dirs; keep WDF_VER; disable ARM cross-compile.

Write-Host "Patching msvc/config.h ..."
$cfg = Get-Content 'msvc\config.h' -Raw

# Comment out WDK_DIR, LIBUSB0_DIR, LIBUSBK_DIR lines.
$cfg = $cfg -replace '(?m)^(#define\s+(WDK_DIR|LIBUSB0_DIR|LIBUSBK_DIR)\s+.*)', '// $1'

# Add USER_DIR placeholder if not already present.
if ($cfg -notmatch 'USER_DIR') {
    $cfg = $cfg -replace '(// #define WDK_DIR)', "`$1`r`n#define USER_DIR `"C:/nonexistent-placeholder`""
}

# Comment out OPT_ARM.
$cfg = $cfg -replace '(?m)^(#define\s+OPT_ARM\b.*)', '// $1'

Set-Content 'msvc\config.h' $cfg -NoNewline

# ── Patch 2: libwdi/libwdi.c — WinUSB always supported ──────────────────────

Write-Host "Patching libwdi/libwdi.c ..."
$src = Get-Content 'libwdi\libwdi.c' -Raw

# Replace the WinUSB conditional block with an unconditional return TRUE.
$src = $src -replace `
    '(?s)(case WDI_WINUSB:\s*)#if defined\(WDK_DIR\)\s*return TRUE;\s*#else\s*return FALSE;\s*#endif', `
    '$1/* WinUSB is in-box on Windows 7+; co-installers not required on 8+. */
        return TRUE;'

Set-Content 'libwdi\libwdi.c' $src -NoNewline

# ── Patch 3: libwdi/winusb.inf.in — strip co-installer DLL entries ───────────

Write-Host "Patching libwdi/winusb.inf.in ..."
$inf = Get-Content 'libwdi\winusb.inf.in' -Raw

# Replace SourceDisksFiles sections with empty stubs.
$inf = $inf -replace '(?m)^\[SourceDisksFiles\.x86\][^\[]*', "[SourceDisksFiles.x86]`r`n;`r`n"
$inf = $inf -replace '(?m)^\[SourceDisksFiles\.amd64\][^\[]*', "[SourceDisksFiles.amd64]`r`n;`r`n"

# Replace CoInstaller sections with no-ops.
$inf = $inf -replace '(?m)^\[USB_Install\.NTx86\.CoInstallers\][^\[]*',
    "[USB_Install.NTx86.CoInstallers]`r`n; Co-installers not required on Windows 8+`r`n"
$inf = $inf -replace '(?m)^\[USB_Install\.NTamd64\.CoInstallers\][^\[]*',
    "[USB_Install.NTamd64.CoInstallers]`r`n; Co-installers not required on Windows 8+`r`n"

Set-Content 'libwdi\winusb.inf.in' $inf -NoNewline

# ── Patch 4: remove installer_arm64 from vcxproj ────────────────────────────

Write-Host "Patching libwdi/.msvc/libwdi_static.vcxproj ..."
$vcx = Get-Content 'libwdi\.msvc\libwdi_static.vcxproj' -Raw
$vcx = $vcx -replace '(?s)<ProjectReference[^>]*installer_arm64[^>]*/>', ''
$vcx = $vcx -replace '(?s)<ProjectReference[^>]*installer_arm64.*?</ProjectReference>', ''
Set-Content 'libwdi\.msvc\libwdi_static.vcxproj' $vcx -NoNewline

# ── Patch 5: remove installer_arm64 Build entries from libwdi.sln ────────────

Write-Host "Patching libwdi.sln ..."
$sln = Get-Content 'libwdi.sln' -Raw
# Remove Build.0 configuration lines that reference installer_arm64 GUID.
# The GUID is referenced in the "Global" section after the project definition.
$sln = $sln -replace '(?m)^\s*\{[0-9A-Fa-f\-]+\}\.Release\|x64\.Build\.0[^\r\n]*installer_arm64[^\r\n]*\r?\n', ''
# Remove the Project block for installer_arm64.
$sln = $sln -replace '(?s)Project\("[^"]*"\)\s*=\s*"installer_arm64".*?EndProject\r?\n', ''
Set-Content 'libwdi.sln' $sln -NoNewline

# ── Patch 6: redirect stderr in pre-build event ──────────────────────────────

Write-Host "Patching embedder pre-build event ..."
$vcx2 = Get-Content 'libwdi\.msvc\libwdi_static.vcxproj' -Raw
$vcx2 = $vcx2 -replace '(embedder embedded\.h)(?!\s*2>nul)', '$1 2>nul'
Set-Content 'libwdi\.msvc\libwdi_static.vcxproj' $vcx2 -NoNewline

# ── Build ────────────────────────────────────────────────────────────────────

Write-Host "Building libwdi (Release|x64) ..."
$msbuild = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" `
    -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe |
    Select-Object -First 1

if (-not $msbuild) {
    # Fallback: try the PATH
    $msbuild = 'MSBuild.exe'
}

& $msbuild libwdi.sln /p:Configuration=Release /p:Platform=x64 /m /v:m
if ($LASTEXITCODE -ne 0) { throw "MSBuild failed (exit $LASTEXITCODE)" }

# ── Collect outputs ──────────────────────────────────────────────────────────

Write-Host "Collecting outputs to $OutDir ..."
New-Item -ItemType Directory -Force (Join-Path $OutDir 'lib')     | Out-Null
New-Item -ItemType Directory -Force (Join-Path $OutDir 'include') | Out-Null

Copy-Item 'x64\Release\lib\libwdi.lib' (Join-Path $OutDir 'lib\libwdi.lib')
Copy-Item 'libwdi\libwdi.h'            (Join-Path $OutDir 'include\libwdi.h')

Pop-Location
Write-Host "libwdi build complete."
Write-Host "  lib:     $libFile"
Write-Host "  header:  $incFile"
