#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <setupapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "match.h"
#include "comdb.h"
#include "comdb_win.h"
#include "elevate.h"

#define MAX_PORTS    256
#define MAX_INF      128

/* ── INF entry ───────────────────────────────────────────────────────── */

typedef struct {
    char name[64];          /* "oem42.inf" */
    char provider[256];
    char driver_ver[64];    /* "date,version" */
    char class_name[64];
} ftdi_inf_t;

/* Raw-text search for needle in a file; case-insensitive. */
static int file_contains_nocase(const char *path, const char *needle)
{
    static char buf[65536];
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[n] = '\0';

    size_t nlen = strlen(needle);
    for (size_t i = 0; i + nlen <= n; i++) {
        if (_strnicmp(buf + i, needle, nlen) == 0) return 1;
    }
    return 0;
}

/* Read [Version] Provider/DriverVer/Class from an INF; returns 0 on success. */
static int read_inf_version(const char *full_path, ftdi_inf_t *out)
{
    HINF hinf = SetupOpenInfFileA(full_path, NULL, INF_STYLE_WIN4, NULL);
    if (hinf == INVALID_HANDLE_VALUE) return -1;

    INFCONTEXT ctx;
    char date[32] = {0}, ver[32] = {0};

    if (SetupFindFirstLineA(hinf, "Version", "Provider", &ctx))
        SetupGetStringFieldA(&ctx, 1, out->provider,   sizeof(out->provider),   NULL);
    if (SetupFindFirstLineA(hinf, "Version", "DriverVer", &ctx)) {
        SetupGetStringFieldA(&ctx, 1, date, sizeof(date), NULL);
        SetupGetStringFieldA(&ctx, 2, ver,  sizeof(ver),  NULL);
        if (date[0] && ver[0])
            snprintf(out->driver_ver, sizeof(out->driver_ver), "%s,%s", date, ver);
        else if (date[0])
            snprintf(out->driver_ver, sizeof(out->driver_ver), "%s", date);
    }
    if (SetupFindFirstLineA(hinf, "Version", "Class", &ctx))
        SetupGetStringFieldA(&ctx, 1, out->class_name, sizeof(out->class_name), NULL);

    SetupCloseInfFile(hinf);
    return 0;
}

/*
 * Walk %SystemRoot%\INF\oem*.inf; collect entries that mention VID_0403.
 * Returns the count written into entries[].
 */
static int scan_ftdi_oem_infs(ftdi_inf_t *entries, int max)
{
    char inf_dir[MAX_PATH];
    DWORD n = GetEnvironmentVariableA("SystemRoot", inf_dir, sizeof(inf_dir));
    if (!n || n >= sizeof(inf_dir)) {
        fprintf(stderr, "error: cannot determine %%SystemRoot%%\n");
        return 0;
    }
    strncat_s(inf_dir, sizeof(inf_dir), "\\INF", _TRUNCATE);

    char pattern[MAX_PATH];
    snprintf(pattern, sizeof(pattern), "%s\\oem*.inf", inf_dir);

    WIN32_FIND_DATAA fd;
    HANDLE hf = FindFirstFileA(pattern, &fd);
    if (hf == INVALID_HANDLE_VALUE) return 0;

    int count = 0;
    do {
        if (count >= max) break;
        char full[MAX_PATH];
        snprintf(full, sizeof(full), "%s\\%s", inf_dir, fd.cFileName);
        if (!file_contains_nocase(full, "VID_0403")) continue;

        ftdi_inf_t *e = &entries[count];
        memset(e, 0, sizeof(*e));
        snprintf(e->name, sizeof(e->name), "%s", fd.cFileName);
        read_inf_version(full, e);
        count++;
    } while (FindNextFileA(hf, &fd));
    FindClose(hf);
    return count;
}

#define ABOUT_TEXT "(c) 2026 Erik Lundh - The Joy of Engineering Compelcon AB\n"

/* ── print_usage ─────────────────────────────────────────────────────── */

static void print_usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s <command> [options]\n"
        "\n"
        "Commands:\n"
        "  --diagnose               list FTDI oem*.inf driver store entries (no mutations)\n"
        "  --purge-store            remove stale FTDI oem*.inf entries (requires --yes)\n"
        "  --compact-comdb          prune orphaned COM port bits from ComDB\n"
        "  --reset-comport VID:PID  clear a device's PortName and ComDB bit\n"
        "\n"
        "Options:\n"
        "  --dry-run   show what would change; mutate nothing\n"
        "  --yes       confirm destructive operations (required by --purge-store)\n"
        "  -h/--help   show this help\n"
        "  --about     show copyright information\n"
        "\n"
        "  VID:PID  accepted forms: 0403:6015  0x0403:0x6015  403:6015\n",
        prog);
}

/* ── --diagnose ──────────────────────────────────────────────────────── */

static int cmd_diagnose(void) {
    ftdi_inf_t entries[MAX_INF];
    int n = scan_ftdi_oem_infs(entries, MAX_INF);

    if (n == 0) {
        printf("No FTDI driver store entries found (VID_0403).\n");
        return 0;
    }

    printf("Found %d FTDI driver store entr%s:\n\n", n, n == 1 ? "y" : "ies");
    for (int i = 0; i < n; i++) {
        printf("  %-14s  provider: %-24s  ver: %-22s  class: %s\n",
               entries[i].name,
               entries[i].provider[0]   ? entries[i].provider   : "(none)",
               entries[i].driver_ver[0] ? entries[i].driver_ver : "(none)",
               entries[i].class_name[0] ? entries[i].class_name : "(none)");
    }
    printf("\nRun 'ftdi-doctor --purge-store --dry-run' to preview removal.\n");
    return 0;
}

/* ── --purge-store ───────────────────────────────────────────────────── */

static int cmd_purge_store(int dry_run, int yes) {
    ftdi_inf_t entries[MAX_INF];
    int n = scan_ftdi_oem_infs(entries, MAX_INF);

    if (n == 0) {
        printf("No FTDI driver store entries found. Nothing to purge.\n");
        return 0;
    }

    printf("Found %d FTDI driver store entr%s to remove:\n\n",
           n, n == 1 ? "y" : "ies");
    for (int i = 0; i < n; i++) {
        printf("  %-14s  provider: %-24s  ver: %-22s  class: %s\n",
               entries[i].name,
               entries[i].provider[0]   ? entries[i].provider   : "(none)",
               entries[i].driver_ver[0] ? entries[i].driver_ver : "(none)",
               entries[i].class_name[0] ? entries[i].class_name : "(none)");
    }
    printf("\n");

    if (dry_run) {
        printf("[dry-run] no changes made.\n");
        return 0;
    }

    if (!yes) {
        printf(
            "WARNING: This removes ALL FTDI VCP oem*.inf entries, including\n"
            "any that work for other FTDI devices on this system. After purging,\n"
            "reinstall the FTDI CDM package (ftdichip.com) before replugging.\n"
            "Pass --yes to confirm deletion.\n");
        return 1;
    }

    if (!is_elevated()) {
        fprintf(stderr,
            "error: administrator privileges required to remove driver store entries.\n");
        return 1;
    }

    int removed = 0, failed = 0;
    for (int i = 0; i < n; i++) {
        if (SetupUninstallOEMInfA(entries[i].name, SUOI_FORCEDELETE, NULL)) {
            printf("  Removed: %s\n", entries[i].name);
            removed++;
        } else {
            fprintf(stderr, "  Failed:  %s (error %lu)\n",
                    entries[i].name, (unsigned long)GetLastError());
            failed++;
        }
    }

    printf("\nRemoved %d, failed %d.\n", removed, failed);
    if (removed > 0) {
        printf("Reinstall the FTDI CDM package (ftdichip.com), then replug\n"
               "the device and run 'ftdi-bind 0403:6015' to restore the COM port.\n");
    }
    return failed ? 1 : 0;
}

/* ── --compact-comdb ─────────────────────────────────────────────────── */

static int cmd_compact_comdb(int dry_run) {
    unsigned char buf[COMDB_SIZE];
    int rc = comdb_read(buf);
    if (rc != 0) {
        fprintf(stderr, "error: cannot read ComDB (error %d)\n", rc);
        return 1;
    }

    int active[MAX_PORTS];
    int nactive = comdb_active_ports(active, MAX_PORTS);

    int orphaned[MAX_PORTS];
    int norphaned = 0;
    for (int port = 1; port <= COMDB_MAX_PORT; port++) {
        if (!comdb_is_allocated(buf, port)) continue;
        int live = 0;
        for (int j = 0; j < nactive; j++) {
            if (active[j] == port) { live = 1; break; }
        }
        if (!live) orphaned[norphaned++] = port;
    }

    if (norphaned == 0) {
        printf("ComDB is clean: %d port(s) allocated, all active.\n",
               comdb_count_allocated(buf));
        return 0;
    }

    printf("[%s] %d orphaned COM port(s) found:\n",
           dry_run ? "dry-run" : "compact", norphaned);
    for (int i = 0; i < norphaned; i++)
        printf("  COM%d\n", orphaned[i]);

    if (dry_run) {
        printf("[dry-run] no changes made.\n");
        return 0;
    }

    if (!is_elevated()) {
        fprintf(stderr, "error: administrator privileges required to write ComDB.\n");
        return 1;
    }

    for (int i = 0; i < norphaned; i++)
        comdb_clear_port(buf, orphaned[i]);

    rc = comdb_write(buf);
    if (rc != 0) {
        fprintf(stderr, "error: cannot write ComDB (error %d)\n", rc);
        return 1;
    }

    int lowest_free = 0;
    for (int p = 1; p <= COMDB_MAX_PORT; p++) {
        if (!comdb_is_allocated(buf, p)) { lowest_free = p; break; }
    }

    printf("Freed %d orphaned COM port(s). "
           "Next assignment starts at COM%d.\n",
           norphaned, lowest_free);
    return 0;
}

/* ── --reset-comport ─────────────────────────────────────────────────── */

static int cmd_reset_comport(const char *vidpid_str, int dry_run) {
    unsigned short vid, pid;
    if (vidpid_parse(vidpid_str, &vid, &pid) != 0) {
        fprintf(stderr, "error: invalid VID:PID '%s'\n", vidpid_str);
        return 2;
    }

    char portname[64] = {0};
    int rc = comdb_device_portname(vid, pid, portname, sizeof(portname));
    if (rc != 0) {
        fprintf(stderr,
            "error: device %04x:%04x not found or has no PortName "
            "(is it plugged in and using a VCP driver?)\n", vid, pid);
        return 1;
    }

    int port = comdb_port_from_name(portname);
    if (port == 0) {
        fprintf(stderr,
            "error: PortName '%s' is not a valid COM port number\n",
            portname);
        return 1;
    }

    /*
     * Check whether the device's COM port is currently active.
     * If active, do NOT clear the ComDB bit — that creates a window where
     * another device could be assigned the same number. Delete PortName
     * only; the ComDB bit becomes orphaned after replug and is swept by
     * the next --compact-comdb run.
     */
    int active_ports[MAX_PORTS];
    int nactive = comdb_active_ports(active_ports, MAX_PORTS);
    int currently_active = 0;
    for (int i = 0; i < nactive; i++) {
        if (active_ports[i] == port) { currently_active = 1; break; }
    }

    printf("[%s] %04x:%04x  current port: %s  status: %s\n",
           dry_run ? "dry-run" : "reset", vid, pid, portname,
           currently_active ? "active (device is plugged in)"
                            : "inactive (device is unplugged)");

    if (dry_run) {
        if (currently_active)
            printf("[dry-run] would delete PortName only (ComDB bit kept "
                   "while active). Replug to complete.\n");
        else
            printf("[dry-run] would clear COM%d from ComDB and delete "
                   "PortName from device registry.\n", port);
        printf("[dry-run] no changes made.\n");
        return 0;
    }

    if (!is_elevated()) {
        fprintf(stderr, "error: administrator privileges required.\n");
        return 1;
    }

    rc = comdb_clear_device_portname(vid, pid);
    if (rc != 0) {
        fprintf(stderr, "error: could not delete PortName from device "
                "registry (error %d)\n", rc);
        return 1;
    }

    if (currently_active) {
        printf("Deleted PortName for %s. ComDB bit kept while port is active.\n"
               "Unplug and replug the device -- it will get a lower port number.\n"
               "Run --compact-comdb afterwards to free the old %s slot.\n",
               portname, portname);
    } else {
        unsigned char buf[COMDB_SIZE];
        rc = comdb_read(buf);
        if (rc != 0) {
            fprintf(stderr, "error: cannot read ComDB (error %d)\n", rc);
            return 1;
        }
        comdb_clear_port(buf, port);
        rc = comdb_write(buf);
        if (rc != 0) {
            fprintf(stderr, "error: cannot write ComDB (error %d)\n", rc);
            return 1;
        }
        printf("Cleared %s from ComDB and device registry. "
               "Next replug will get a lower port number.\n", portname);
    }
    return 0;
}

/* ── main ────────────────────────────────────────────────────────────── */

int main(int argc, char **argv) {
    int dry_run = 0;
    int yes     = 0;
    const char *command = NULL;
    const char *vidpid  = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--dry-run") == 0) {
            dry_run = 1;
        } else if (strcmp(argv[i], "--yes") == 0) {
            yes = 1;
        } else if (strcmp(argv[i], "--diagnose") == 0) {
            command = "diagnose";
        } else if (strcmp(argv[i], "--purge-store") == 0) {
            command = "purge-store";
        } else if (strcmp(argv[i], "--compact-comdb") == 0) {
            command = "compact-comdb";
        } else if (strcmp(argv[i], "--reset-comport") == 0) {
            command = "reset-comport";
            if (i + 1 < argc) vidpid = argv[++i];
        } else if (strcmp(argv[i], "-h") == 0 ||
                   strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else if (strcmp(argv[i], "--about") == 0) {
            printf(ABOUT_TEXT);
            return 0;
        } else {
            fprintf(stderr, "error: unknown argument '%s'\n", argv[i]);
            print_usage(argv[0]);
            return 2;
        }
    }

    if (!command) {
        print_usage(argv[0]);
        return 2;
    }

    if (strcmp(command, "diagnose") == 0)
        return cmd_diagnose();

    if (strcmp(command, "purge-store") == 0)
        return cmd_purge_store(dry_run, yes);

    if (strcmp(command, "compact-comdb") == 0)
        return cmd_compact_comdb(dry_run);

    if (strcmp(command, "reset-comport") == 0) {
        if (!vidpid) {
            fprintf(stderr, "error: --reset-comport requires a VID:PID argument\n");
            return 2;
        }
        return cmd_reset_comport(vidpid, dry_run);
    }

    return 2;
}
