#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "match.h"
#include "comdb.h"
#include "comdb_win.h"
#include "elevate.h"

#define MAX_PORTS 256

static void print_usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s <command> [options]\n"
        "\n"
        "Commands:\n"
        "  --compact-comdb          prune orphaned COM port bits from ComDB\n"
        "  --reset-comport VID:PID  clear a device's PortName and ComDB bit\n"
        "\n"
        "Options:\n"
        "  --dry-run   show what would change; mutate nothing\n"
        "  -h/--help   show this help\n"
        "\n"
        "  VID:PID  accepted forms: 0403:6015  0x0403:0x6015  403:6015\n",
        prog);
}

/* ── --compact-comdb ─────────────────────────────────────────────────── */

static int cmd_compact_comdb(int dry_run) {
    unsigned char buf[COMDB_SIZE];
    int rc = comdb_read(buf);
    if (rc != 0) {
        fprintf(stderr, "error: cannot read ComDB (error %d)\n", rc);
        return 1;
    }

    /* Collect active COM port numbers from HARDWARE\DEVICEMAP\SERIALCOMM. */
    int active[MAX_PORTS];
    int nactive = comdb_active_ports(active, MAX_PORTS);

    /* Find orphaned bits: allocated in ComDB but not in the active set. */
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

    /* Find the new lowest free port. */
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

    /* Find the device's current PortName. */
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
     * HARDWARE\DEVICEMAP\SERIALCOMM lists every live serial port.
     * If the port is active we must NOT clear the ComDB bit while it is in
     * use — that creates a window where another device could be assigned the
     * same number.  Instead, only delete PortName so the next replug gets a
     * new assignment; the ComDB bit cleans up naturally via --compact-comdb
     * after replug.
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

    /* Always delete PortName so the next enumeration picks a fresh number. */
    rc = comdb_clear_device_portname(vid, pid);
    if (rc != 0) {
        fprintf(stderr, "error: could not delete PortName from device "
                "registry (error %d)\n", rc);
        return 1;
    }

    if (currently_active) {
        /*
         * Leave the ComDB bit set while the port is live to prevent
         * double-assignment.  The bit becomes orphaned after replug and
         * will be swept by the next --compact-comdb run.
         */
        printf("Deleted PortName for %s. ComDB bit kept while port is active.\n"
               "Unplug and replug the device — it will get a lower port number.\n"
               "Run --compact-comdb afterwards to free the old %s slot.\n",
               portname, portname);
    } else {
        /* Device is not active: safe to clear the ComDB bit immediately. */
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
    const char *command = NULL;
    const char *vidpid  = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--dry-run") == 0) {
            dry_run = 1;
        } else if (strcmp(argv[i], "--compact-comdb") == 0) {
            command = "compact-comdb";
        } else if (strcmp(argv[i], "--reset-comport") == 0) {
            command = "reset-comport";
            if (i + 1 < argc) vidpid = argv[++i];
        } else if (strcmp(argv[i], "-h") == 0 ||
                   strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
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
