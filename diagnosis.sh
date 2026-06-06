#!/usr/bin/env bash
#
# diagnosis.sh — FTDI USB device diagnostic for Linux and macOS
#
# Read-only.  Makes no changes.  Does not require root or sudo.
#
# Usage:
#   bash diagnosis.sh          (works anywhere, no chmod needed)
#   ./diagnosis.sh             (if you have marked it executable first)
#
# Part of the ftdi-unbind toolkit.
# Repository: gitlab.compelcon.se/unified-serial-terminal/ftdi-unbind
#

# Do not exit on individual command failures — a diagnostic script should
# continue and report what it can, even if one check fails.
set -uo pipefail

OS="$(uname -s)"
[[ "$OS" == "Linux" ]] && shopt -s nullglob 2>/dev/null || true

TOTAL_SECTIONS=5

# ─────────────────────────────────────────────────────────────────────────────
#  Colour helpers (disabled when stdout is not a terminal or TERM is dumb)
# ─────────────────────────────────────────────────────────────────────────────

if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_RESET=$'\033[0m'
    C_CYAN=$'\033[0;36m'
    C_DCYAN=$'\033[1;36m'
    C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[0;33m'
    C_RED=$'\033[0;31m'
    C_GRAY=$'\033[0;90m'
    C_WHITE=$'\033[1;37m'
else
    C_RESET='' C_CYAN='' C_DCYAN='' C_GREEN='' C_YELLOW='' C_RED='' C_GRAY='' C_WHITE=''
fi

ok()       { printf "  ${C_GREEN}[OK]    ${C_RESET} %s\n" "$*"; }
note()     { printf "  ${C_CYAN}[NOTE]  ${C_RESET} %s\n" "$*"; }
warn()     { printf "  ${C_YELLOW}[WARN]  ${C_RESET} %s\n" "$*"; }
act()      { printf "  ${C_RED}[ACTION]${C_RESET} %s\n" "$*"; }

# Indent explanatory text in a distinct colour
explain() {
    local line
    while IFS= read -r line; do
        printf "  ${C_GRAY}  %s${C_RESET}\n" "$line"
    done <<< "$1"
}

section() {
    local num="$1" total="$2" title="$3"
    printf "\n"
    printf "  ${C_DCYAN}%s${C_RESET}\n" "──────────────────────────────────────────────────────────────────"
    printf "  ${C_DCYAN}%s / %s   %s${C_RESET}\n" "$num" "$total" "$title"
    printf "  ${C_DCYAN}%s${C_RESET}\n" "──────────────────────────────────────────────────────────────────"
    printf "\n"
}

# Issue / action lists (populated during checks; printed in SUMMARY)
ISSUES=()
ACTIONS=()

# ─────────────────────────────────────────────────────────────────────────────
#  BANNER
# ─────────────────────────────────────────────────────────────────────────────

printf "\n"
printf "  ${C_DCYAN}╔═══════════════════════════════════════════════════════════════════╗${C_RESET}\n"
printf "  ${C_DCYAN}║   FTDI USB Device Diagnostic — Linux / macOS                      ║${C_RESET}\n"
printf "  ${C_DCYAN}║   Read-only.  Makes no changes.  No sudo needed.                  ║${C_RESET}\n"
printf "  ${C_DCYAN}╚═══════════════════════════════════════════════════════════════════╝${C_RESET}\n"
printf "\n"
printf "  ${C_GRAY}Tip: scroll to SUMMARY at the bottom for what to do next.${C_RESET}\n"
printf "  ${C_GRAY}The numbered sections explain why each finding matters.${C_RESET}\n"
printf "\n"

# ─────────────────────────────────────────────────────────────────────────────
#  0. OS check — must be Linux or macOS
# ─────────────────────────────────────────────────────────────────────────────

case "$OS" in
    Linux|Darwin) ;;
    *)
        printf "  %s\n" "Unsupported OS: $OS"
        printf "  %s\n" "This script supports Linux and macOS only."
        printf "  %s\n" "For Windows, use diagnosis.ps1 or diagnosis.cmd instead."
        exit 1
        ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
#  1 / 5   SYSTEM
# ─────────────────────────────────────────────────────────────────────────────

section 1 "$TOTAL_SECTIONS" "SYSTEM"

case "$OS" in
    Linux)
        DISTRO="$(grep -m1 'PRETTY_NAME' /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Linux")"
        KERNEL="$(uname -r)"
        ARCH="$(uname -m)"
        printf "  Operating system : %s\n" "$DISTRO"
        printf "  Kernel           : %s\n" "$KERNEL"
        printf "  Architecture     : %s\n" "$ARCH"
        MACOS_MAJOR=0  # not used on Linux but needs a value for the later check
        ;;
    Darwin)
        MACOS_VER="$(sw_vers -productVersion 2>/dev/null || echo "unknown")"
        MACOS_NAME="$(sw_vers -productName  2>/dev/null || echo "macOS")"
        ARCH="$(uname -m)"
        printf "  Operating system : %s %s\n" "$MACOS_NAME" "$MACOS_VER"
        printf "  Architecture     : %s\n" "$ARCH"
        MACOS_MAJOR="$(echo "$MACOS_VER" | cut -d. -f1)"
        ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
#  2 / 5   FTDI USB DEVICES
# ─────────────────────────────────────────────────────────────────────────────

section 2 "$TOTAL_SECTIONS" "FTDI USB DEVICES"

printf "  ${C_GRAY}Scanning for USB devices with FTDI Vendor ID 0x0403...${C_RESET}\n\n"

FTDI_VID="0403"
FTDI_FOUND=0

case "$OS" in

    # ── Linux ────────────────────────────────────────────────────────────────
    Linux)
        for devdir in /sys/bus/usb/devices/*; do
            [ -r "$devdir/idVendor" ] || continue
            vid="$(tr -d '[:space:]' < "$devdir/idVendor" 2>/dev/null || true)"
            [ "$vid" = "$FTDI_VID" ] || continue

            FTDI_FOUND=$((FTDI_FOUND + 1))
            pid="$(tr -d '[:space:]' < "$devdir/idProduct"    2>/dev/null || echo "????")  "
            desc="$(tr  -d '\n'      < "$devdir/product"      2>/dev/null || echo "(unknown)")"
            serial="$(tr -d '\n'     < "$devdir/serial"       2>/dev/null || echo "(none)")"
            dev="${devdir##*/}"

            # Find the bound driver (first interface that has one)
            driver=""
            for intf in /sys/bus/usb/devices/"$dev":*; do
                [ -L "$intf/driver" ] || continue
                driver="$(basename "$(readlink "$intf/driver")" 2>/dev/null || true)"
                break
            done

            printf "  ┌─ %s\n" "$desc"
            printf "  │  VID:PID    : %s:%s\n" "$vid" "${pid%% *}"
            printf "  │  USB serial : %s\n" "$serial"
            printf "  │  Bus device : %s\n" "$dev"
            printf "  │  Driver     : %s\n" "${driver:-(none)}"
            printf "  └─\n\n"

            DEV_VID_PID="$vid:${pid%% *}"

            if [ "${driver:-}" = "ftdi_sio" ]; then
                # Find the /dev/ttyUSB* node via sysfs
                tty_list=""
                for intf in /sys/bus/usb/devices/"$dev":*; do
                    for ttydir in "$intf"/tty/tty*; do
                        [ -e "$ttydir" ] && tty_list="$tty_list /dev/$(basename "$ttydir")"
                    done
                done

                if [ -n "$tty_list" ]; then
                    ok "ftdi_sio driver active — tty device(s):$tty_list"
                    explain "The FTDI chip is running the serial driver.
Your terminal app should be able to open${tty_list}.
Typical settings for FPGA lab work: 115200 baud, 8N1.

If the terminal app says 'Permission denied': see Section 4 (user groups).
If the terminal app says 'Device or resource busy': another app has the port open.
If you need a terminal that works without driver switching at all, the
unified-serial-terminal (sister project) talks over this driver directly."
                else
                    ok "ftdi_sio driver active (tty node not yet visible in sysfs — try ls /dev/ttyUSB*)"
                fi

                # Group check for the tty node
                first_tty="${tty_list%% *}"
                first_tty="${first_tty# }"   # trim leading space
                if [ -n "$first_tty" ] && [ -c "$first_tty" ]; then
                    tty_group="$(stat -c '%G' "$first_tty" 2>/dev/null || echo "")"
                    if [ -n "$tty_group" ]; then
                        if id -Gn 2>/dev/null | grep -qw "$tty_group"; then
                            ok "Your user is in group '$tty_group' — can open$tty_list without sudo"
                        else
                            warn "Your user is NOT in group '$tty_group' — serial port access blocked"
                            explain "Most terminal apps will get 'Permission denied' on$tty_list.
Fix (then log out and back in):
  sudo usermod -aG $tty_group \$(whoami)"
                            ISSUES+=("User not in '$tty_group' group — opening${tty_list} will fail")
                            ACTIONS+=("Run: sudo usermod -aG $tty_group \$(whoami)  then log out and back in")
                        fi
                    fi
                fi

            elif [ -z "${driver:-}" ]; then
                # No driver bound — is ftdi_sio even loaded?
                if [ -d "/sys/bus/usb/drivers/ftdi_sio" ]; then
                    warn "$DEV_VID_PID — ftdi_sio loaded but NOT bound to this device"
                    explain "The ftdi_sio module is present, but it has not claimed this device.
This usually means the device was unbound by ftdi-unbind, or the
VID:PID is not in ftdi_sio's default match list.

To rebind the serial driver (restores /dev/ttyUSB*):
  sudo ftdi-bind $DEV_VID_PID
Or simpler: unplug the board and plug it back in."
                    ISSUES+=("$DEV_VID_PID — not bound to ftdi_sio (no tty node)")
                    ACTIONS+=("Run: sudo ftdi-bind $DEV_VID_PID  (or unplug and replug the board)")
                else
                    act "$DEV_VID_PID — ftdi_sio module NOT loaded, no serial driver active"
                    explain "The ftdi_sio kernel module is not loaded. It should load automatically
when an FTDI device is plugged in. If it doesn't:

  sudo modprobe ftdi_sio        # load the module
  sudo ftdi-bind $DEV_VID_PID  # bind the driver to this device

Or simply unplug and replug the board — the kernel should load ftdi_sio
and claim the device automatically on re-enumeration."
                    ISSUES+=("ftdi_sio module not loaded — no serial driver for any FTDI device")
                    ACTIONS+=("Run: sudo modprobe ftdi_sio  and  sudo ftdi-bind $DEV_VID_PID  (or replug)")
                fi
            else
                note "$DEV_VID_PID — bound to driver '$driver' (not ftdi_sio)"
                explain "The FTDI device is using a different driver: $driver
This may be intentional (e.g. usbfs for direct USB access).
If you need the serial port: sudo ftdi-bind $DEV_VID_PID"
            fi
            printf "\n"
        done

        if [ "$FTDI_FOUND" -eq 0 ]; then
            note "No FTDI USB devices found."
            printf "\n"
            explain "Linux does not see any device with FTDI's Vendor ID (0x0403).
Possible reasons:
  · Board is not connected, or USB cable carries power only (no data lines).
    Try a different cable — many USB-C cables are charge-only.
  · USB port is faulty — try a different port or connect directly (not via hub).
  · The device needs a replug: unplug, wait 5 seconds, plug back in.
  · On some boards a jumper or switch selects USB vs JTAG — check the docs.

Run this script again after replugging."
            ISSUES+=("No FTDI USB device detected — board may not be connected")
        fi
        ;;

    # ── macOS ────────────────────────────────────────────────────────────────
    Darwin)
        FTDI_VID_DEC=1027   # 0x0403

        # ioreg enumeration via python3 (same helper used in ftdi-unbind)
        IOREG_OUT="$(python3 - "$FTDI_VID_DEC" 2>/dev/null <<'PYEOF'
import sys, subprocess, plistlib

ftdi_vid = int(sys.argv[1]) if len(sys.argv) > 1 else 1027
try:
    raw = subprocess.check_output(
        ['ioreg', '-r', '-c', 'IOUSBDevice', '-a'], stderr=subprocess.DEVNULL)
    devices = plistlib.loads(raw)
except Exception as e:
    print("error:" + str(e))
    sys.exit(1)

ftdi_devs = [d for d in devices if d.get('idVendor', 0) == ftdi_vid]
print(len(ftdi_devs))
for d in ftdi_devs:
    vid  = d.get('idVendor',  0)
    pid  = d.get('idProduct', 0)
    name = (d.get('USB Product Name') or d.get('kUSBProductString') or '(unknown)')
    sn   = (d.get('USB Serial Number') or '').strip() or '(none)'
    print(f"{vid:04x}:{pid:04x}\t{name}\t{sn}")
PYEOF
        )"

        if echo "$IOREG_OUT" | grep -q "^error:"; then
            warn "ioreg/python3 query failed — cannot enumerate USB devices"
            explain "python3 is required for macOS USB enumeration.
If it is not installed, run: xcode-select --install"
        else
            FTDI_COUNT="$(echo "$IOREG_OUT" | head -1)"
            FTDI_COUNT="${FTDI_COUNT:-0}"

            if [ "${FTDI_COUNT:-0}" -eq 0 ] 2>/dev/null; then
                note "No FTDI USB devices found."
                printf "\n"
                explain "macOS does not see any device with FTDI's Vendor ID (0x0403).
Possible reasons:
  · Board is not connected, or USB cable is charge-only (no data lines).
  · USB port issue — try a different port or connect directly (no hub).
  · Needs a replug: unplug, wait 5 seconds, plug back in.

Run this script again after replugging."
                ISSUES+=("No FTDI USB device detected — board may not be connected")
            else
                FTDI_FOUND="$FTDI_COUNT"
                printf "  Found %s FTDI device(s):\n\n" "$FTDI_COUNT"

                while IFS=$'\t' read -r vpid name sn; do
                    printf "  ┌─ %s\n"  "$name"
                    printf "  │  VID:PID    : %s\n" "$vpid"
                    printf "  │  USB serial : %s\n" "$sn"
                    printf "  └─\n\n"
                done <<< "$(echo "$IOREG_OUT" | tail -n +2)"

                ok "$FTDI_COUNT FTDI device(s) visible to macOS"
            fi
        fi
        ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
#  3 / 5   DRIVER STATE
# ─────────────────────────────────────────────────────────────────────────────

section 3 "$TOTAL_SECTIONS" "DRIVER STATE"

case "$OS" in

    # ── Linux ────────────────────────────────────────────────────────────────
    Linux)
        printf "  ${C_GRAY}Checking ftdi_sio kernel module...${C_RESET}\n\n"

        if [ -d "/sys/bus/usb/drivers/ftdi_sio" ]; then
            # Count bound interfaces
            bound=0
            for entry in /sys/bus/usb/drivers/ftdi_sio/*; do
                [ -L "$entry" ] && bound=$((bound + 1)) || true
            done

            if [ "$bound" -gt 0 ]; then
                ok "ftdi_sio module loaded, $bound USB interface(s) currently bound"
                explain "Each bound interface corresponds to one /dev/ttyUSB* serial port.
The driver is active and ready."
            else
                note "ftdi_sio module loaded, but no interfaces are currently bound"
                explain "The module is present but no FTDI device is plugged in and claimed."
            fi
        else
            if lsmod 2>/dev/null | grep -q "^ftdi_sio" 2>/dev/null; then
                note "ftdi_sio shows in lsmod but /sys/bus/usb/drivers/ftdi_sio not found (unusual)"
            else
                warn "ftdi_sio module is NOT loaded"
                explain "The ftdi_sio kernel module is not currently running.
It should auto-load when an FTDI device is plugged in on any standard
Linux distribution. If it does not: sudo modprobe ftdi_sio"
                ISSUES+=("ftdi_sio kernel module not loaded")
            fi
        fi

        printf "\n"
        printf "  ${C_GRAY}Looking for /dev/ttyUSB* and /dev/ttyACM* device nodes...${C_RESET}\n\n"

        found_ttys=0
        for tty in /dev/ttyUSB* /dev/ttyACM*; do
            [ -c "$tty" ] || continue
            grp="$(stat -c '%G' "$tty" 2>/dev/null || echo "(unknown group)")"
            perms="$(stat -c '%A' "$tty" 2>/dev/null || echo "")"
            printf "    %s   group=%s   %s\n" "$tty" "$grp" "$perms"
            found_ttys=$((found_ttys + 1))
        done

        if [ "$found_ttys" -eq 0 ]; then
            if [ "$FTDI_FOUND" -gt 0 ]; then
                warn "FTDI device found in sysfs, but no /dev/ttyUSB* nodes exist"
                explain "The FTDI device is connected but ftdi_sio has not created a tty node.
This could mean:
  · The device was unbound by ftdi-unbind (check Section 2)
  · ftdi_sio is not bound to this VID:PID — try: sudo ftdi-bind 0403:XXXX
  · Replug the board to trigger auto-enumeration"
            else
                note "No /dev/ttyUSB* or /dev/ttyACM* nodes found"
            fi
        else
            ok "$found_ttys serial device node(s) present (see above)"
        fi
        ;;

    # ── macOS ────────────────────────────────────────────────────────────────
    Darwin)
        APPLE_KEXT="com.apple.driver.AppleUSBFTDI"
        FTDI_VCP_KEXT="com.FTDI.driver.FTDIUSBSerialDriver"

        printf "  ${C_GRAY}Checking FTDI kernel extension (kext) state...${C_RESET}\n\n"

        apple_loaded=0
        ftdi_loaded=0

        if kextstat 2>/dev/null | grep -qF "$APPLE_KEXT"; then
            apple_loaded=1
            ok "Apple built-in FTDI kext loaded: $APPLE_KEXT"
            explain "Apple's built-in FTDI driver is active. Connected FTDI devices should
appear as /dev/cu.usbserial-* ports."
        else
            warn "Apple built-in FTDI kext NOT loaded: $APPLE_KEXT"
            explain "Apple's FTDI driver is not running.
Possible causes:
  · ftdi-unbind was run earlier (intentional — needed for FPGA programming)
  · On macOS 13+, this kext may be blocked by SIP (see Section 4)
If you need the serial port back: sudo ftdi-bind 0403:XXXX  or unplug/replug."
            ISSUES+=("$APPLE_KEXT not loaded — FTDI serial driver is not active")
        fi
        printf "\n"

        if kextstat 2>/dev/null | grep -qF "$FTDI_VCP_KEXT"; then
            ftdi_loaded=1
            ok "FTDI official VCP kext loaded: $FTDI_VCP_KEXT"
            explain "FTDI's own VCP driver is installed and active.
FTDI devices should appear as /dev/cu.usbserial-* ports."
        else
            if [ -d "/Library/Extensions/FTDIUSBSerialDriver.kext" ]; then
                note "FTDI official VCP kext installed but NOT loaded: $FTDI_VCP_KEXT"
                explain "The kext is on disk but not running.
To load it: sudo kextload -b $FTDI_VCP_KEXT"
            else
                note "FTDI official VCP kext not installed (normal — the Apple built-in is usually enough)"
            fi
        fi
        printf "\n"

        # /dev/cu.usbserial-* nodes
        printf "  ${C_GRAY}Checking for serial device nodes (/dev/cu.usbserial-*)...${C_RESET}\n\n"

        found_nodes=0
        for node in /dev/cu.usbserial-* /dev/cu.usbmodem* /dev/tty.usbserial-*; do
            [ -c "$node" ] || continue
            printf "    %s\n" "$node"
            found_nodes=$((found_nodes + 1))
        done

        if [ "$found_nodes" -gt 0 ]; then
            printf "\n"
            ok "$found_nodes serial device node(s) present"
            explain "Use the /dev/cu.* node (not /dev/tty.*) in your terminal app.
The cu.* (call-up) node does not block on open; tty.* waits for carrier detect.
Typical settings: 115200 baud, 8N1."
        else
            if [ "$apple_loaded" -eq 0 ] && [ "$ftdi_loaded" -eq 0 ]; then
                note "No /dev/cu.usbserial-* nodes (expected — no FTDI kext is loaded)"
            else
                warn "FTDI kext is loaded but no /dev/cu.usbserial-* node appeared"
                explain "Try unplugging and replugging the board.
If the node still does not appear, run ftdi-bind to reload the kext."
                ISSUES+=("FTDI kext loaded but no /dev/cu.usbserial-* device node")
                ACTIONS+=("Unplug and replug the board; if that fails: sudo ftdi-bind 0403:XXXX")
            fi
        fi
        ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
#  4 / 5   PLATFORM-SPECIFIC CHECKS
# ─────────────────────────────────────────────────────────────────────────────

case "$OS" in

    # ── Linux: user group access ──────────────────────────────────────────────
    Linux)
        section 4 "$TOTAL_SECTIONS" "USER GROUP ACCESS"

        printf "  ${C_GRAY}Checking whether your user can open serial ports without sudo...${C_RESET}\n\n"

        ME="$(id -un 2>/dev/null || echo "unknown")"
        MY_GROUPS="$(id -Gn 2>/dev/null || groups 2>/dev/null || echo "")"

        in_dialout=0
        in_plugdev=0
        echo "$MY_GROUPS" | grep -qw "dialout" && in_dialout=1 || true
        echo "$MY_GROUPS" | grep -qw "plugdev" && in_plugdev=1 || true

        if [ "$in_dialout" -eq 1 ] || [ "$in_plugdev" -eq 1 ]; then
            ok "User '$ME' is in the correct serial-port group(s):"
            [ "$in_dialout" -eq 1 ] && printf "    dialout\n"
            [ "$in_plugdev" -eq 1 ] && printf "    plugdev\n"
            explain "You can open /dev/ttyUSB* ports without sudo.
Your terminal app should be able to connect directly."
        else
            act "User '$ME' is NOT in 'dialout' or 'plugdev' group"
            printf "\n"
            explain "On most Linux distributions, /dev/ttyUSB* is owned by the 'dialout'
group (mode 0660 — owner root, group dialout). Without membership in
that group, any terminal app will receive 'Permission denied' when it
tries to open the port.

Fix — add your user to the dialout group:
  sudo usermod -aG dialout \$(whoami)

Then LOG OUT and LOG BACK IN. The change takes effect at the next login.
(Running 'newgrp dialout' in the current shell also works as a temporary fix.)

Some distributions use 'plugdev' instead of (or in addition to) 'dialout'.
Check the actual group on your tty node with:  ls -l /dev/ttyUSB0"
            ISSUES+=("User '$ME' not in 'dialout' group — serial ports will return Permission denied")
            ACTIONS+=("Run: sudo usermod -aG dialout \$(whoami)  then log out and back in")
        fi

        printf "\n"
        printf "  ${C_GRAY}Checking for FTDI-specific udev rules...${C_RESET}\n\n"

        udev_dirs="/etc/udev/rules.d /lib/udev/rules.d /usr/lib/udev/rules.d /run/udev/rules.d"
        ftdi_rules=""
        for d in $udev_dirs; do
            if [ -d "$d" ]; then
                found="$(grep -rl -i 'idVendor.*0403\|0403.*idVendor\|VID_0403\|ftdi' "$d" 2>/dev/null || true)"
                [ -n "$found" ] && ftdi_rules="$ftdi_rules$found"$'\n'
            fi
        done

        if [ -n "$ftdi_rules" ]; then
            note "FTDI-specific udev rules found:"
            echo "$ftdi_rules" | while IFS= read -r f; do
                [ -n "$f" ] && printf "    %s\n" "$f"
            done
            explain "These rules may customise group ownership, permissions, or create
symlinks for FTDI devices. If they set GROUP=dialout or GROUP=plugdev,
ensure your user is in that group."
        else
            note "No FTDI-specific udev rules found — system defaults apply"
            explain "The tty node will have the default group (usually 'dialout' or 'tty')."
        fi
        ;;

    # ── macOS: SIP and kext version restrictions ───────────────────────────
    Darwin)
        section 4 "$TOTAL_SECTIONS" "macOS SECURITY AND KEXT RESTRICTIONS"

        printf "  ${C_GRAY}Checking macOS version and System Integrity Protection (SIP)...${C_RESET}\n\n"

        # csrutil status does not require sudo (read-only query)
        SIP_STATUS="$(csrutil status 2>/dev/null || echo "unknown (csrutil not found)")"
        printf "  SIP: %s\n\n" "$SIP_STATUS"

        if echo "$SIP_STATUS" | grep -qi "disabled"; then
            note "SIP is disabled — kext operations are unrestricted"
            explain "System Integrity Protection is off. This is an unusual configuration.
kextunload and kextload will work without the restrictions described below."
        elif echo "$SIP_STATUS" | grep -qi "enabled"; then
            ok "SIP is enabled (standard configuration)"
        fi

        # macOS 13+ kext restriction
        if [ "${MACOS_MAJOR:-0}" -ge 13 ] 2>/dev/null; then
            printf "\n"
            warn "macOS $MACOS_VER detected — Apple's built-in FTDI kext is restricted by SIP"
            printf "\n"
            explain "On macOS 13 (Ventura) and later, the Apple built-in FTDI kext
(com.apple.driver.AppleUSBFTDI) is part of the sealed system volume.
Running 'sudo kextunload' on it will fail with 'Operation not permitted'
even as root — this is by design.

This means ftdi-unbind will not be able to release the device for
WebUSB or libusb-based FPGA programming tools on macOS 13+, unless
you have reduced SIP (see below).

────────────────────────────────────────────────────────────────
What are your options for FPGA programming and serial on macOS 13+?
────────────────────────────────────────────────────────────────

Option 1 — Use a WebUSB-based terminal app for serial (recommended):
  The unified-serial-terminal project (sister project of this repo)
  can talk to FTDI serial over the VCP driver (/dev/cu.usbserial-*)
  without needing to unload any kext. No driver changes needed at all.

Option 2 — If FTDI's own VCP kext is installed:
  Third-party kexts CAN be unloaded even under standard SIP.
  sudo kextunload -b com.FTDI.driver.FTDIUSBSerialDriver
  ftdi-unbind will try this automatically if the FTDI kext is installed.

Option 3 — Reduce Security (decreases system security):
  Boot into Recovery OS → Startup Security Utility →
  choose 'Reduced Security' (Intel) or allow user-approved kernel
  extensions (Apple Silicon) → reboot → then ftdi-unbind will work.
  Only recommended for dedicated development machines.

For programming the FPGA specifically, check whether your programming
tool supports Web Serial (which works through the VCP driver) in
addition to WebUSB. Many modern tools do."
            ISSUES+=("macOS $MACOS_VER: kextunload of Apple's built-in FTDI kext is blocked by SIP")

        elif [ "${MACOS_MAJOR:-0}" -le 12 ] && [ "${MACOS_MAJOR:-0}" -ge 1 ] 2>/dev/null; then
            printf "\n"
            ok "macOS $MACOS_VER: kextunload of Apple's FTDI kext is permitted"
            explain "On macOS 12 and earlier, ftdi-unbind can unload the FTDI kext with sudo.
This is needed for WebUSB or pyftdi direct-USB access to the FPGA board."
        fi
        ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
#  5 / 5   UNDERSTANDING THE TOOLS
# ─────────────────────────────────────────────────────────────────────────────

section 5 "$TOTAL_SECTIONS" "UNDERSTANDING THE TOOLS"

printf "\n"
explain "When do you need to switch the FTDI driver at all?
────────────────────────────────────────────────────────────────────
FTDI chips on FPGA boards like the ULX3S serve two separate roles:

  1. Programming the FPGA (uploading a bitstream):
     Tools like fujprog, ecpprog, and openFPGALoader in 'raw USB' mode
     need direct access to the FTDI chip. They cannot use the serial
     driver (ftdi_sio on Linux, AppleUSBFTDI on macOS) — they need the
     chip to be free of any kernel driver.
     → ftdi-unbind detaches the driver so these tools can claim the chip.

  2. Running a serial terminal to talk to your FPGA design:
     Once the FPGA is running your design, it may communicate over the
     FTDI serial interface. A terminal app needs the VCP driver active
     and a /dev/ttyUSB* (Linux) or /dev/cu.usbserial-* (macOS) node.
     → ftdi-bind re-attaches the driver and the port reappears.

On Linux, these are per-device operations — other USB devices are not
affected. On macOS, kext load/unload is global: ALL attached FTDI
devices are affected at once.

A simpler alternative for serial communication:
────────────────────────────────────────────────────────────────────
If you only need a serial terminal to your FPGA design and want to
avoid the bind/unbind cycle, the unified-serial-terminal project (the
sister project of this one) provides a terminal that connects over the
VCP driver directly.

This is especially important on university lab computers where IT
policy does not allow running sudo or administrative tools. On those
machines, unified-serial-terminal is the only option for serial
communication — ftdi-unbind/ftdi-bind require sudo.

What do the scripts actually do?
────────────────────────────────────────────────────────────────────"

case "$OS" in
    Linux)
        explain "ftdi-unbind 0403:6015
  Finds all USB interfaces of the matching device that are bound to
  the ftdi_sio driver. For each, writes the interface ID to:
    /sys/bus/usb/drivers/ftdi_sio/unbind
  This is the standard Linux kernel sysfs interface for detaching a
  driver from a device. It is completely reversible. The /dev/ttyUSBx
  node disappears. The chip is now free for libusb / WebUSB.
  Requires root (the sysfs write is privileged).

ftdi-bind 0403:6015
  Writes interface IDs back to:
    /sys/bus/usb/drivers/ftdi_sio/bind
  The driver re-attaches. The /dev/ttyUSBx node reappears.
  Requires root. Simplest alternative: unplug and replug the board.

These scripts are plain bash — you can read every line:
  cat macos-linux/ftdi-unbind
  cat macos-linux/ftdi-bind"
        ;;
    Darwin)
        explain "ftdi-unbind 0403:6015
  Finds which FTDI kexts are loaded and unloads them:
    sudo kextunload -b com.apple.driver.AppleUSBFTDI
  Unloading the kext releases ALL attached FTDI devices (kext
  operations are global on macOS, not per-device).
  /dev/cu.usbserial-* nodes disappear. The chip is free for WebUSB.
  Requires sudo.

ftdi-bind 0403:6015
  Reloads the kext. All FTDI devices are reclaimed by the driver.
  The simpler alternative: unplug and replug the board.
  Requires sudo.

On macOS 13+, the Apple built-in kext is protected by SIP.
See Section 4 for details and alternatives.

These scripts are plain bash — you can read every line:
  cat macos-linux/ftdi-unbind
  cat macos-linux/ftdi-bind"
        ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
#  SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

printf "\n"
printf "  ${C_DCYAN}%s${C_RESET}\n" "═══════════════════════════════════════════════════════════════════"
printf "  ${C_DCYAN} SUMMARY${C_RESET}\n"
printf "  ${C_DCYAN}%s${C_RESET}\n\n" "═══════════════════════════════════════════════════════════════════"

if [ "${#ISSUES[@]}" -eq 0 ]; then
    printf "  ${C_GREEN}Everything looks OK.${C_RESET}\n\n"
    explain "Your FTDI device appears to be in a normal state.
If you are still having trouble connecting:
  · Double-check baud rate (usually 115200 for FPGA lab work)
  · Make sure no other app has the port open
  · Try unplugging and replugging the USB cable
  · Try a different USB cable (many are charge-only — no data lines)"
else
    printf "  ${C_YELLOW}Issues found:${C_RESET}\n\n"
    i=1
    for issue in "${ISSUES[@]}"; do
        printf "  ${C_YELLOW}  %d.  %s${C_RESET}\n" "$i" "$issue"
        i=$((i + 1))
    done
    printf "\n"

    if [ "${#ACTIONS[@]}" -gt 0 ]; then
        printf "  ${C_CYAN}Suggested next steps:${C_RESET}\n\n"
        i=1
        for action in "${ACTIONS[@]}"; do
            printf "  ${C_WHITE}  %d.  %s${C_RESET}\n" "$i" "$action"
            i=$((i + 1))
        done
        printf "\n"
    fi
fi

printf "  ${C_DCYAN}%s${C_RESET}\n" "───────────────────────────────────────────────────────────────────"
printf "  ${C_DCYAN} WHERE TO GET THE FIX SCRIPTS${C_RESET}\n"
printf "  ${C_DCYAN}%s${C_RESET}\n\n" "───────────────────────────────────────────────────────────────────"

explain "The ftdi-unbind and ftdi-bind scripts are in the macos-linux/
directory of this repository. They are plain bash scripts — read
them before running if you want to verify what they do:
  cat macos-linux/ftdi-unbind
  cat macos-linux/ftdi-bind

For a versioned download (recommended — same as the .exe release page):
  gitlab.compelcon.se/unified-serial-terminal/ftdi-unbind/-/releases"

printf "\n"
