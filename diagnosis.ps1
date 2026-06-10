#Requires -Version 5.1
<#
.SYNOPSIS
    FTDI USB device diagnostic for Windows.
    Read-only. Makes no changes. Does not require Administrator rights.

.DESCRIPTION
    Checks and explains: which FTDI USB devices Windows sees, their driver
    state (VCP serial / WinUSB / driverless), COM port health (orphaned
    assignments), the Windows driver store, and Smart App Control.

    The SUMMARY at the end tells you what to do next. The numbered sections
    explain why each finding matters — read as much or as little as you need.

.PARAMETER VidPid
    USB Vendor ID and Product ID to search for.
    Accepted forms: 0403:6015   403:6015   0x0403:0x6015
    Default: 0403:6015  (FTDI FT231X / FT232R — used on the ULX3S and many
    other FPGA boards).

.EXAMPLE
    .\diagnosis.ps1
    .\diagnosis.ps1 0403:6014
    .\diagnosis.ps1 0x0403:0x6010
    .\diagnosis.ps1 /?            # show this help (also -? /h -h /help --help)

.NOTES
    Part of the ftdi-unbind toolkit.
    Author Erik Lundh, The Joy of Engineering, erik.lundh@ingenjorsgladje.se
    Repository: github.com/eriklundh/ftdi-unbind
#>
param(
    [string]$VidPid = '0403:6015',
    [Alias('v','verbose')][switch]$Detailed,
    [Alias('h','help')][switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# Help: accept the same spellings as diagnosis.cmd — /? -? /h -h /help --help —
# so the script behaves the same whether the student is in CMD or PowerShell.
# (-h and -help bind to $Help via alias; the slash/double-dash forms arrive as
# the positional VidPid argument or in $args.)
$_helpPattern = '^(?:[-/]\?|[-/]h|[-/]help|--help|help)$'
if ($Help -or $VidPid -match $_helpPattern -or ($args -match $_helpPattern)) {
    Get-Help -Full $PSCommandPath
    exit 0
}

# Normalise VID:PID: strip 0x prefix, pad to 4 hex digits, lower case
$_raw = $VidPid -replace '(?i)0x','' -replace '\s',''
if ($_raw -notmatch '^[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}$') {
    Write-Host ""
    Write-Host "  Invalid VID:PID '$VidPid'." -ForegroundColor Red
    Write-Host "  Expected format: 0403:6015  (or 403:6015 or 0x0403:0x6015)" -ForegroundColor Red
    Write-Host ""
    exit 2
}
$_parts  = $_raw -split ':'
$VID     = $_parts[0].PadLeft(4,'0').ToLower()
$UsbPid  = $_parts[1].PadLeft(4,'0').ToLower()
$VID_UP  = $VID.ToUpper()
$PID_UP  = $UsbPid.ToUpper()

# ─────────────────────────────────────────────────────────────────────────────
#  Output helpers
# ─────────────────────────────────────────────────────────────────────────────

function Write-Banner {
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║   FTDI USB Device Diagnostic — Windows                        ║" -ForegroundColor Cyan
    Write-Host "  ║   Read-only.  Makes no changes.  No Administrator needed.     ║" -ForegroundColor Cyan
    Write-Host "  ╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Tip: scroll to SUMMARY at the bottom for what to do next." -ForegroundColor DarkGray
    Write-Host "  The numbered sections explain why each finding matters." -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Section {
    param([int]$Num, [int]$Total, [string]$Title)
    Write-Host ""
    Write-Host ("  " + ("─" * 66)) -ForegroundColor DarkCyan
    Write-Host "  $Num / $Total   $Title" -ForegroundColor Cyan
    Write-Host ("  " + ("─" * 66)) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-OK   { param([string]$m) Write-Host "  [OK]     " -ForegroundColor Green  -NoNewline; Write-Host $m }
function Write-Note { param([string]$m) Write-Host "  [NOTE]   " -ForegroundColor Cyan   -NoNewline; Write-Host $m }
function Write-Warn { param([string]$m) Write-Host "  [WARN]   " -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Write-Act  { param([string]$m) Write-Host "  [ACTION] " -ForegroundColor Red    -NoNewline; Write-Host $m }

function Write-Explain {
    param([string]$Text)
    $Text -split "`n" | ForEach-Object {
        Write-Host "           $_" -ForegroundColor DarkGray
    }
}

# Issue / action tracking for the SUMMARY
$script:Issues  = [System.Collections.Generic.List[string]]::new()
$script:Actions = [System.Collections.Generic.List[string]]::new()

# Device state flags — set in Section 2, read in Section 4
$script:DeviceHasVCP      = $false
$script:DeviceHasWinUSB   = $false
$script:DeviceHasNoDriver = $false

# ─────────────────────────────────────────────────────────────────────────────
#  BANNER
# ─────────────────────────────────────────────────────────────────────────────

Write-Banner

# ─────────────────────────────────────────────────────────────────────────────
#  1 / 6   SYSTEM
# ─────────────────────────────────────────────────────────────────────────────

Write-Section 1 6 "SYSTEM"

$os     = Get-CimInstance Win32_OperatingSystem
$osName = if ($os) { $os.Caption } else { "Windows (version unknown)" }
$build  = if ($os) { $os.BuildNumber } else { "?" }
$psVer  = $PSVersionTable.PSVersion.ToString()

Write-Host "  Operating system : $osName (build $build)"
Write-Host "  PowerShell       : $psVer"
Write-Host "  Script running as: $env:USERNAME"
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
#  2 / 6   FTDI USB DEVICES
# ─────────────────────────────────────────────────────────────────────────────

Write-Section 2 6 "FTDI USB DEVICES"

Write-Host "  Searching for VID:PID = $VID`:$UsbPid  (pass a different VID:PID as an argument to override)" -ForegroundColor DarkGray
Write-Host ""

$allDevices  = Get-PnpDevice -PresentOnly
$ftdiDevices = @($allDevices | Where-Object { $_.InstanceId -like "USB\VID_$VID_UP&PID_$PID_UP*" })

if ($ftdiDevices.Count -eq 0) {
    Write-Note "No $VID`:$UsbPid device found."
    Write-Host ""
    Write-Explain @"
Windows does not see a device with VID:PID $VID`:$UsbPid right now.
Possible reasons:
  · The board is not plugged in.
  · The USB cable carries power only — no data lines. This is common
    with cheap USB-C cables. Try a different cable (one you know works
    for data, like the one that came with the board or a phone charger
    cable that supports file transfer).
  · The USB port or hub is faulty — try a different port directly on
    the computer, not through a hub.
  · The device needs a replug: unplug, wait 5 seconds, plug back in.
  · On some FPGA boards a hardware jumper or switch selects between USB
    and JTAG — check your board's documentation.

If you just plugged the board in, wait 5 seconds and run this script again.
"@
    # Secondary scan: any OTHER FTDI VID_0403 devices present?
    $otherFtdi = @($allDevices | Where-Object {
        $_.InstanceId -like 'USB\VID_0403*' -and
        $_.InstanceId -notlike "USB\VID_$VID_UP&PID_$PID_UP*"
    })
    if ($otherFtdi.Count -gt 0) {
        Write-Host ""
        Write-Note "However, $($otherFtdi.Count) other FTDI device(s) with VID 0403 were found:"
        foreach ($o in $otherFtdi) {
            $om   = [regex]::Match($o.InstanceId, 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})')
            $ovid = if ($om.Success) { $om.Groups[1].Value.ToLower() } else { "????" }
            $opid = if ($om.Success) { $om.Groups[2].Value.ToLower() } else { "????" }
            $oname = if ($o.FriendlyName) { $o.FriendlyName } else { "(unnamed)" }
            Write-Host "    $oname  ($ovid`:$opid)" -ForegroundColor DarkGray
        }
        Write-Host ""
        Write-Explain "  If one of these is your board, run:  .\diagnosis.ps1 <vid>:<pid>"
        Write-Explain "  For example:  .\diagnosis.ps1 0403:6014"
    }
    $script:Issues.Add("No $VID`:$UsbPid device found -- board may not be connected or recognised")
} else {
    foreach ($dev in $ftdiDevices) {
        $iid  = $dev.InstanceId
        $name = if ($dev.FriendlyName) { $dev.FriendlyName } else { "(unnamed device)" }
        $cls  = if ($dev.Class) { $dev.Class } else { "" }
        $sts  = $dev.Status

        # Extract PID from instance ID
        $pidMatch = [regex]::Match($iid, 'PID_([0-9A-Fa-f]{4})')
        $pid4     = if ($pidMatch.Success) { $pidMatch.Groups[1].Value.ToLower() } else { "????" }

        # Extract serial number (last backslash-delimited segment)
        $usbSerial = $iid.Split('\')[-1]
        # If it looks like a composite ID (contains &), it's not a real serial
        if ($usbSerial -match '&') { $usbSerial = "(none)" }

        Write-Host "  ┌─ $name"
        Write-Host "  │  Instance ID : $iid" -ForegroundColor DarkGray
        Write-Host "  │  VID:PID     : $VID`:$pid4"
        Write-Host "  │  USB serial  : $usbSerial"
        Write-Host "  │  Device class: $cls"
        Write-Host "  │  Status      : $sts"
        Write-Host "  └─"
        Write-Host ""

        switch -Regex ($cls) {
            '^Ports$' {
                $script:DeviceHasVCP = $true
                # FTDI VCP driver active — find the COM port
                $comPort = ""
                if ($name -match '\(COM(\d+)\)') { $comPort = "COM$($Matches[1])" }

                if ($comPort) {
                    Write-OK "VCP (serial) driver active — $comPort is assigned"
                    $portNum = [int]($comPort -replace 'COM','')
                    Write-Explain @"
The FTDI chip is running the 'Virtual COM Port' driver. Windows has
assigned $comPort to this device.

Your serial terminal app (PuTTY, Tera Term, screen, minicom, etc.)
should be able to open $comPort at 115200 baud (typical for FPGA
lab consoles). Settings: 115200 baud, 8 data bits, no parity, 1 stop bit.

If the terminal app still cannot connect:
  · Make sure no other application has $comPort open.
  · Try unplugging and replugging the USB cable.
  · Try a different USB cable.

Looking for a terminal app that works with this port and doesn't
require any driver changes? See the unified-serial-terminal project
(sister project of this one) — it connects over the VCP driver
directly and avoids the bind/unbind step entirely.
"@
                    if ($portNum -gt 9) {
                        Write-Host ""
                        Write-Warn "High port number: $comPort (numbers above COM9 can cause problems)"
                        Write-Explain @"
Some terminal apps and lab tools only look for COM1–COM9. Having the
board appear on COM$portNum is confusing during a lab and can cause
'port not found' errors in software that doesn't handle high numbers.

This is caused by Windows never freeing old COM port allocations when
a device is reinstalled. See Section 3 (COM port health) for details
and how to fix it.
"@
                        $script:Issues.Add("$comPort — high port number; some apps only scan COM1–COM9")
                        $script:Actions.Add("Fix high COM port: run ftdi-doctor.exe --compact-comdb (elevated), then replug the board")
                    }
                } else {
                    Write-Note "VCP driver active (COM port not visible in device name)"
                    Write-Explain "  The driver is loaded but the COM port was not read from the device name."
                }
            }

            '^(USB|Universal Serial Bus devices)$' {
                $script:DeviceHasWinUSB = $true
                Write-Warn "WinUSB driver — NO COM port (device is in 'raw USB' mode)"
                Write-Explain @"
The FTDI chip has been switched from the serial (VCP) driver to WinUSB.
In this state:
  · No COM port is assigned. Serial terminal apps will not find the board.
  · WebUSB applications, FPGA programming tools that use WebUSB, and
    Python tools using pyftdi can talk to the chip directly over USB.

This switch is done intentionally by ftdi-unbind.exe (or the Zadig tool).

  If you want to program the FPGA board (via a WebUSB-based programmer
  like fujprog or ecpprog in WebUSB mode): this is the correct state.
  You can leave it here until you're done programming.

  If you need the serial COM port back (e.g. to connect a terminal to
  a running design on the FPGA that sends serial data): run ftdi-bind.exe.
  This requires Administrator. See SUMMARY for the download link.

  If you did NOT intentionally switch the driver — perhaps someone else
  used the Zadig tool or ftdi-unbind.exe on this machine — the fix is
  the same: ftdi-bind.exe 0403:$pid4 (as Administrator).

  Alternatively, the unified-serial-terminal project (serial communication
  without driver swapping) may avoid the need to rebind at all.
"@
                $script:Issues.Add("$VID`:$pid4 — WinUSB driver active, no COM port")
                $script:Actions.Add("To restore the COM port: run ftdi-bind.exe $VID`:$pid4  (as Administrator)")
            }

            default {
                if ($sts -eq 'Error' -or $cls -eq '' -or $cls -eq 'Unknown') {
                    $script:DeviceHasNoDriver = $true
                    Write-Act "Device found but no driver loaded (status: $sts)"
                    Write-Explain @"
Windows found the FTDI chip on USB but cannot load a driver for it.
Typical causes:

  1. The FTDI VCP driver has never been installed on this computer.
     Fix: download and run FTDI's CDM driver package. Search for
     'FTDI CDM driver' or look for a download link in your FPGA board
     documentation. Run the installer as Administrator.

  2. The driver store has stale entries that block a clean install.
     This can happen after many ftdi-unbind / ftdi-bind cycles.
     Diagnosis (no elevation needed):  ftdi-doctor.exe --diagnose
     Fix (elevated):  ftdi-doctor.exe --purge-store  then reinstall CDM.

  3. The device needs a replug after a driver change.
     Try: unplug the board, wait 10 seconds, plug it back in.

See SUMMARY for the ftdi-doctor.exe download link.
"@
                    $script:Issues.Add("$VID`:$pid4 — FTDI device detected but no driver loaded")
                    $script:Actions.Add("Run ftdi-doctor.exe --diagnose to check the driver store, then follow its instructions")
                } else {
                    Write-Note "Device is in class '$cls' — unexpected for an FTDI serial device"
                }
            }
        }
        Write-Host ""
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  3 / 6   COM PORT HEALTH
# ─────────────────────────────────────────────────────────────────────────────

Write-Section 3 6 "COM PORT HEALTH"

Write-Host "  Checking for orphaned (dead) COM port reservations..." -ForegroundColor DarkGray
Write-Host ""

# Active COM ports — what Windows currently has a driver loaded for
$activePorts = @{}
$serialCommData = Get-ItemProperty -Path 'HKLM:\HARDWARE\DEVICEMAP\SERIALCOMM'
if ($serialCommData) {
    $serialCommData.PSObject.Properties |
        Where-Object { $_.Name -notlike 'PS*' } |
        ForEach-Object { $activePorts[$_.Value] = $_.Name }
}

if ($activePorts.Count -gt 0) {
    Write-Host "  Currently active COM ports:" -ForegroundColor DarkGray
    foreach ($port in ($activePorts.Keys | Sort-Object)) {
        $num = [int]($port -replace 'COM','')
        if ($num -le 9) {
            Write-OK "$port  ← $($activePorts[$port])"
        } else {
            Write-Warn "$port  ← $($activePorts[$port])   (high port number)"
        }
    }
} else {
    Write-Note "No active COM ports found on this system."
}
Write-Host ""

# ComDB — the registry bitmask of ALL ever-allocated COM port numbers
$comArbiter = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\COM Name Arbiter' -Name 'ComDB'
if (-not $comArbiter) {
    Write-Note "COM Name Arbiter registry key not found — skipping orphan check."
} else {
    [byte[]]$comDbBytes = $comArbiter.ComDB
    $allocated = [System.Collections.Generic.List[int]]::new()

    for ($b = 0; $b -lt $comDbBytes.Length; $b++) {
        for ($bit = 0; $bit -lt 8; $bit++) {
            if ($comDbBytes[$b] -band (1 -shl $bit)) {
                $allocated.Add($b * 8 + $bit + 1)
            }
        }
    }

    $orphaned = @($allocated | Where-Object { -not $activePorts.ContainsKey("COM$_") })

    if ($orphaned.Count -eq 0) {
        Write-OK "COM port reservations look clean — no orphaned entries"
        if ($allocated.Count -gt 0) {
            $list = ($allocated | Sort-Object | ForEach-Object { "COM$_" }) -join ', '
            Write-Explain "  Allocated: $list"
        }
    } else {
        $orphanList = ($orphaned | Sort-Object | ForEach-Object { "COM$_" }) -join ', '
        Write-Warn "Orphaned COM port reservations: $orphanList"
        Write-Explain @"
Windows uses a registry key called 'ComDB' to track COM port number
allocations. The problem: when a USB serial device is removed and
reinstalled — or when ftdi-unbind.exe / ftdi-bind.exe cycles happen —
Windows allocates a NEW number and NEVER frees the old one.

Over time, this climbs: COM3 → COM4 → … → COM47. High numbers cause:
  · Lab instructions that say 'open COM3' become wrong and confusing.
  · Some terminal apps scan only COM1–COM9 and never find the board.
  · Each cycle wastes a number for every future device on this PC.

The orphaned ports listed above are allocated in the registry but have
no active device behind them. They are safe to clear.

To fix (when you are ready — requires Administrator):
  Step 1:  ftdi-doctor.exe --compact-comdb --dry-run   (preview, no changes)
  Step 2:  ftdi-doctor.exe --compact-comdb             (clears orphaned entries)
  Step 3:  Unplug and replug the FTDI board.
           → It will receive a low, clean port number (usually COM3 or COM4).

Download ftdi-doctor.exe from the Releases page — see SUMMARY.
"@
        $script:Issues.Add("Orphaned COM port reservations: $orphanList  (causes high port numbers)")
        $script:Actions.Add("Run ftdi-doctor.exe --compact-comdb --dry-run first, then without --dry-run (both elevated), then replug the board")
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  4 / 6   DRIVER STORE
# ─────────────────────────────────────────────────────────────────────────────

Write-Section 4 6 "WINDOWS DRIVER STORE"

Write-Host "  Running: pnputil /enum-drivers  (read-only; may take a few seconds)..." -ForegroundColor DarkGray
Write-Host ""

$pnpLines = & pnputil /enum-drivers 2>&1
if ($LASTEXITCODE -ne 0 -or -not $pnpLines) {
    Write-Note "pnputil returned no output — skipping driver store check."
} else {
    # Build blocks: each driver entry is separated by a blank line in the output
    $rawText = $pnpLines -join "`n"
    $blocks  = $rawText -split "`n\s*`n" |
               Where-Object { $_ -match 'FTDI|ftdibus|ftdiport|libwdi|WinUSB' -and $_ -match 'Published' }

    if ($blocks.Count -eq 0) {
        Write-Note "No FTDI-related entries found in the driver store."
        Write-Explain @"
This is normal if:
  · The FTDI VCP driver was delivered by Windows Update (stored differently
    from manually installed drivers).
  · The driver has never been installed on this computer.

If Section 2 shows your device has no driver, you will need to install
the FTDI CDM driver package. Download it from ftdichip.com or look for
a link in your FPGA board documentation.
"@
    } else {
        # Detect libwdi / WinUSB entries — these can conflict with the VCP driver
        $winusbEntries = @($blocks | Where-Object { $_ -match 'libwdi|WinUSB devices|USB devices' })
        $vcpEntries    = @($blocks | Where-Object { $_ -match 'ftdibus|ftdiport|FTDI.*Ports|Ports.*FTDI' })

        Write-Host "  Found $($blocks.Count) driver store entry/entries ($($vcpEntries.Count) VCP, $($winusbEntries.Count) WinUSB/libwdi)." -ForegroundColor DarkGray
        Write-Host ""

        if ($Detailed) {
            foreach ($block in $blocks) {
                $block.Trim() -split "`n" | ForEach-Object {
                    Write-Host "    $_" -ForegroundColor DarkGray
                }
                Write-Host ""
            }
        } else {
            Write-Host "  (Run with -v to see the full driver store listing.)" -ForegroundColor DarkGray
            Write-Host ""
        }

        if ($vcpEntries.Count -gt 0) {
            Write-OK "$($vcpEntries.Count) FTDI VCP (serial driver) store entry/entries found"
            Write-Explain "  These are the normal FTDI serial port driver entries."
        }
        if ($winusbEntries.Count -gt 0) {
            if ($script:DeviceHasNoDriver -and -not $script:DeviceHasVCP) {
                Write-Warn "$($winusbEntries.Count) WinUSB/libwdi store entry/entries found — may be blocking VCP driver"
                Write-Explain @"
WinUSB entries are generated by ftdi-unbind.exe (or Zadig) each time a
device is switched to WinUSB mode. These entries are normally harmless,
but because Section 2 shows your device is currently driverless, they
may be winning the driver-selection race over the FTDI VCP driver.
This is the 'stale oem*.inf' problem.

To investigate (no elevation needed):
  ftdi-doctor.exe --diagnose

To clear stale entries if --diagnose confirms the problem (elevated):
  ftdi-doctor.exe --purge-store --dry-run   ← preview first
  ftdi-doctor.exe --purge-store             ← then clear, then reinstall CDM
"@
                $script:Issues.Add("WinUSB/libwdi entries in driver store — may be blocking VCP driver (device is currently driverless)")
                $script:Actions.Add("Run ftdi-doctor.exe --diagnose to check for conflicting driver store entries")
            } else {
                Write-Note "$($winusbEntries.Count) WinUSB/libwdi store entry/entries found"
                Write-Explain @"
WinUSB entries are generated by ftdi-unbind.exe (or Zadig) each time a
device is switched to WinUSB mode. They are expected leftovers if you
have run ftdi-unbind.exe before — this is normal.

If ftdi-bind.exe ever reports 'RESTORE_ERR_DRIVERLESS' after running
(meaning the COM port does not return after binding), these entries may
then be causing a conflict. At that point, run:
  ftdi-doctor.exe --diagnose  (no elevation needed)
"@
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  5 / 6   WINDOWS SECURITY
# ─────────────────────────────────────────────────────────────────────────────

Write-Section 5 6 "WINDOWS SECURITY (SMART APP CONTROL)"

$sacKey = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name 'VerifiedAndReputablePolicyState'
if ($sacKey) {
    $sacVal   = $sacKey.VerifiedAndReputablePolicyState
    $sacLabel = switch ($sacVal) {
        0 { "Off" }
        1 { "Evaluating (still deciding — may block programs)" }
        2 { "On (blocks programs it does not recognise)" }
        default { "Unknown ($sacVal)" }
    }
    Write-Host "  Smart App Control: $sacLabel"
    Write-Host ""

    if ($sacVal -eq 2) {
        Write-Warn "Smart App Control is ON — may block unsigned .exe files"
        Write-Explain @"
Smart App Control (SAC) is a Windows 11 security feature that blocks
programs it does not recognise as trusted. The ftdi-unbind.exe,
ftdi-bind.exe, and ftdi-doctor.exe tools are currently unsigned (open-
source; signing is work in progress), so SAC may show a block dialog.

How to run a blocked .exe when SAC is On:
  · Right-click the .exe file → Properties → check the 'Unblock' box → OK.
  · Or right-click → Run as administrator → click 'More info' → 'Run anyway'.

If you are on a corporate or university laptop where you cannot unblock
files: ask your IT administrator. See Section 6 for why these tools are
native .exe files and what they actually do — your IT admin can audit
the source code and build from source if needed.

SAC cannot be turned off once enabled without reinstalling Windows.
IT administrators preparing lab computers: disable SAC before installing
lab software, or sign the binaries (a GitHub Actions workflow is included
in the repository for Authenticode signing via Azure Artifact Signing).
"@
        $script:Issues.Add("Smart App Control is ON — unsigned .exe files may be blocked")
        $script:Actions.Add("To run a blocked .exe: right-click → Properties → Unblock → OK; or right-click → Run as admin → More info → Run anyway")
    } elseif ($sacVal -eq 1) {
        Write-Note "Smart App Control is Evaluating — unsigned .exe files may or may not run"
        Write-Explain "  If an ftdi-*.exe is blocked, right-click → Properties → Unblock → OK."
    } else {
        Write-OK "Smart App Control is Off — unsigned .exe files are not blocked by SAC"
    }
} else {
    Write-Note "Smart App Control registry key not found (Windows 10, or feature not present)."
}

# ─────────────────────────────────────────────────────────────────────────────
#  6 / 6   UNDERSTANDING THE TOOLS
# ─────────────────────────────────────────────────────────────────────────────

Write-Section 6 6 "UNDERSTANDING THE TOOLS"

Write-Host ""
Write-Explain @"
When do you need to switch the FTDI driver at all?
────────────────────────────────────────────────────
FTDI chips are used for two separate jobs on FPGA boards like the ULX3S:

  1. Programming the FPGA (uploading a bitstream or new firmware):
     Tools like fujprog, ecpprog, and OpenFPGALoader in WebUSB mode need
     'raw USB' access to the chip. They cannot use the serial (VCP) driver.
     → ftdi-unbind.exe switches the chip to WinUSB so these tools can work.

  2. Talking serial to a running design on the FPGA:
     Once the FPGA is programmed, your design may output data over the
     FTDI serial interface. A terminal app (PuTTY, Tera Term, etc.) needs
     a COM port — which only exists when the VCP driver is active.
     → ftdi-bind.exe switches back to VCP so you get the COM port.

Each time you switch, Windows may assign a new COM port number, which
is why COM port numbers can climb over time (see Section 3).

A simpler alternative for serial communication:
────────────────────────────────────────────────
The unified-serial-terminal project (sister project of this one) provides
a terminal that talks to FTDI serial directly without driver switching.
It works on the VCP driver that Windows already loads, and also works on
centrally-administered university lab computers where students cannot
run administrative tools like ftdi-bind/unbind at all.


Why are the tools .exe files and not PowerShell scripts?
─────────────────────────────────────────────────────────
Installing and switching Windows device drivers requires two system
libraries: SetupAPI and CfgMgr32. These are native Windows C APIs.
The libwdi library (used by ftdi-unbind.exe) is also C-only.

PowerShell does not have built-in cmdlets to:
  · Switch a device between WinUSB and a VCP driver
  · Install a new INF package into the driver store
  · Use the CfgMgr32 re-enumeration API to trigger driver reinstall

The .exe tools are the minimal native programs that call these APIs.

They are open-source (GPLv3). The full source code is in the windows/
subdirectory of this repository. You can read exactly what each function
does before deciding whether to run them. The CMakeLists.txt and docs/
directory explain how to build from source if you prefer that to running
a pre-built binary.
"@

# ─────────────────────────────────────────────────────────────────────────────
#  SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  " + ("═" * 66) -ForegroundColor Cyan
Write-Host "   SUMMARY" -ForegroundColor Cyan
Write-Host "  " + ("═" * 66) -ForegroundColor Cyan
Write-Host ""

if ($script:Issues.Count -eq 0) {
    Write-Host "  Everything looks OK." -ForegroundColor Green
    Write-Host ""
    Write-Explain @"
Your FTDI device appears to be in a normal state. If you are still
having trouble connecting:
  · Double-check baud rate (usually 115200 for FPGA lab boards)
  · Make sure no other app has the COM port open
  · Try unplugging and replugging the USB cable
  · Try a different USB cable (charge-only cables have no data lines)
"@
} else {
    Write-Host "  Issues found:" -ForegroundColor Yellow
    Write-Host ""
    $i = 1
    foreach ($issue in $script:Issues) {
        Write-Host "    $i.  $issue" -ForegroundColor Yellow
        $i++
    }
    Write-Host ""

    if ($script:Actions.Count -gt 0) {
        Write-Host "  Suggested next steps:" -ForegroundColor Cyan
        Write-Host ""
        $i = 1
        foreach ($action in $script:Actions) {
            Write-Host "    $i.  $action" -ForegroundColor White
            $i++
        }
        Write-Host ""
    }
}

Write-Host ("  " + ("─" * 66)) -ForegroundColor DarkCyan
Write-Host "   DOWNLOAD THE FIX TOOLS" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 66)) -ForegroundColor DarkCyan
Write-Host ""
Write-Explain @"
Download pre-built Windows binaries from the Releases page:
  github.com/eriklundh/ftdi-unbind/releases

Available tools (x64, no installer, no DLL dependencies):

  ftdi-unbind.exe   Switch FTDI chip from VCP serial → WinUSB
                    (needed for WebUSB-based FPGA programmers)
                    Requires Administrator.

  ftdi-bind.exe     Switch FTDI chip from WinUSB → VCP serial
                    (restores the COM port after programming)
                    Requires Administrator.

  ftdi-doctor.exe   Diagnose and repair driver store + COM port numbering.
                    --diagnose       read-only, no elevation needed
                    --compact-comdb  fix climbing COM port numbers (elevated)
                    --purge-store    clear stale driver entries (elevated)

All three tools accept --dry-run to preview changes without making them.
All three are safe to run on a machine connected to the internet (they
do not make network connections).
"@
Write-Host ""
