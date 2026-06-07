#include <stdio.h>
#include <stdlib.h>
#include "args.h"
#include "match.h"
#include "enum.h"
#include "elevate.h"
#include "install.h"
#include "restore.h"

#ifndef ACTION_THIS
#  error "ACTION_THIS must be defined by the build system (ACTION_UNBIND or ACTION_BIND)"
#endif

#define MAX_MATCHES  64

#define ABOUT_TEXT "(c) 2026 Erik Lundh \xe2\x80\x94 The Joy of Engineering, Compelcon AB\n" \
                   "https://github.com/eriklundh/ftdi-unbind\n"

static void print_usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s [--list] [--dry-run] [--serial SN] [--all] [-h] [--about] VID:PID\n"
        "\n"
        "  --list          list all USB devices, their serial, and current driver\n"
        "  --dry-run       show which device(s) would be acted on; change nothing\n"
        "  --serial SN     select the device with this USB serial number\n"
        "  --all           act on all matching devices (overrides ambiguity check)\n"
        "  -h/--help       show this help\n"
        "  --about         show copyright information\n"
        "\n"
        "  VID:PID  accepted forms: 0403:6015  0x0403:0x6015  403:6015\n"
        "\n"
        "  --serial and --all are mutually exclusive.\n",
        prog);
}

static int cmd_list(void) {
    device_record *recs;
    int n;
    int rc = enum_devices(&recs, &n);
    if (rc != 0) {
        fprintf(stderr, "error: enumeration failed: %s\n", enum_strerror(rc));
        return 1;
    }
    if (n == 0) {
        printf("(no USB devices found)\n");
    } else {
        printf("%-9s  %-40s  %-20s  [driver]\n",
               "VID:PID", "description", "serial");
        printf("%-9s  %-40s  %-20s  --------\n",
               "---------", "----------------------------------------", "--------------------");
        for (int i = 0; i < n; i++) {
            const char *sn = (recs[i].serial && recs[i].serial[0])
                             ? recs[i].serial : "";
            printf("%04x:%04x  %-40s  %-20s  [%s]\n",
                   recs[i].vid, recs[i].pid,
                   recs[i].desc, sn,
                   recs[i].driver ? recs[i].driver : "(none)");
        }
    }
    free_device_records(recs, n);
    return EXIT_OK;
}

int main(int argc, char **argv) {
    options opt;
    int rc = parse_args(argc, argv, ACTION_THIS, &opt);

    if (opt.help) {
        print_usage(argv[0]);
        return EXIT_OK;
    }
    if (opt.about) {
        printf(ABOUT_TEXT);
        return EXIT_OK;
    }
    if (rc == EXIT_USAGE) {
        print_usage(argv[0]);
        return EXIT_USAGE;
    }

    if (opt.list)
        return cmd_list();

    /* VID:PID required beyond this point */
    unsigned short vid, pid;
    if (vidpid_parse(opt.vidpid, &vid, &pid) != 0) {
        fprintf(stderr, "error: invalid VID:PID '%s'\n", opt.vidpid);
        return EXIT_USAGE;
    }

    device_record *recs;
    int n;
    rc = enum_devices(&recs, &n);
    if (rc != 0) {
        fprintf(stderr, "error: enumeration failed: %s\n", enum_strerror(rc));
        return 1;
    }

    int idx[MAX_MATCHES];
    int count = match_devices(recs, n, vid, pid, opt.serial, idx, MAX_MATCHES);

    if (count == 0) {
        if (opt.serial && *opt.serial)
            fprintf(stderr, "no device matching %04x:%04x with serial '%s'\n",
                    vid, pid, opt.serial);
        else
            fprintf(stderr, "no device matching %04x:%04x\n", vid, pid);
        free_device_records(recs, n);
        return EXIT_NOMATCH;
    }

    /* Ambiguity check: refuse unless --all */
    if (count > 1 && !opt.all) {
        int show = (count < MAX_MATCHES) ? count : MAX_MATCHES;
        int any_serial = 0;
        for (int i = 0; i < show; i++) {
            int j = idx[i];
            if (recs[j].serial && recs[j].serial[0]) { any_serial = 1; break; }
        }
        if (any_serial)
            fprintf(stderr,
                "error: %d devices match %04x:%04x; use --serial SN to select one,"
                " --all to act on all,\n"
                "       or unplug the others.\n",
                count, vid, pid);
        else
            fprintf(stderr,
                "error: %d devices match %04x:%04x; use --all or unplug the others\n",
                count, vid, pid);
        for (int i = 0; i < show; i++) {
            int j = idx[i];
            const char *sn = (recs[j].serial && recs[j].serial[0])
                             ? recs[j].serial : "(none)";
            fprintf(stderr, "  %04x:%04x  %-40s  serial: %s\n             %s\n",
                    recs[j].vid, recs[j].pid,
                    recs[j].desc, sn, recs[j].device_id);
        }
        free_device_records(recs, n);
        return EXIT_NOMATCH;
    }

    int show = (count < MAX_MATCHES) ? count : MAX_MATCHES;
    const char *verb = (opt.action == ACTION_UNBIND)
        ? "install WinUSB on" : "restore VCP on";

    if (opt.dry_run) {
        printf("[dry-run] would %s:\n", verb);
        for (int i = 0; i < show; i++) {
            int j = idx[i];
            const char *sn = (recs[j].serial && recs[j].serial[0])
                             ? recs[j].serial : "(none)";
            printf("  %04x:%04x  %s\n"
                   "  serial:    %s\n"
                   "  instance:  %s\n"
                   "  driver:    %s\n\n",
                   recs[j].vid, recs[j].pid,
                   recs[j].desc, sn, recs[j].device_id,
                   recs[j].driver ? recs[j].driver : "(none)");
        }
        free_device_records(recs, n);
        return EXIT_OK;
    }

    /* Elevation required for all driver-mutating operations. */
    if (!is_elevated()) {
        fprintf(stderr, "error: administrator privileges required.\n");
        fprintf(stderr, "Re-run from an elevated prompt:\n  %s", argv[0]);
        for (int i = 1; i < argc; i++)
            fprintf(stderr, " %s", argv[i]);
        fprintf(stderr, "\n");
        free_device_records(recs, n);
        return EXIT_USAGE;
    }

    if (opt.action == ACTION_UNBIND) {
        for (int i = 0; i < show; i++) {
            int j = idx[i];
            printf("installing WinUSB on %04x:%04x  %s ...\n",
                   recs[j].vid, recs[j].pid, recs[j].desc);
            int wrc = install_winusb(recs[j].vid, recs[j].pid,
                                     recs[j].device_id);
            if (wrc != 0) {
                fprintf(stderr, "  error: %s\n", install_strerror(wrc));
                free_device_records(recs, n);
                return 1;
            }
            printf("  ok; device now presents as WinUSB\n");
        }
        free_device_records(recs, n);
        return EXIT_OK;
    }

    if (opt.action == ACTION_BIND) {
        for (int i = 0; i < show; i++) {
            int j = idx[i];
            printf("restoring VCP driver on %04x:%04x  %s ...\n",
                   recs[j].vid, recs[j].pid, recs[j].desc);
            int rrc = restore_vcp(recs[j].vid, recs[j].pid,
                                  recs[j].device_id);
            if (rrc != RESTORE_OK) {
                fprintf(stderr, "  error: %s\n", restore_strerror(rrc));
                free_device_records(recs, n);
                return 1;
            }
            printf("  ok; FTDI VCP driver restored, COM port should be back\n");
        }
        free_device_records(recs, n);
        return EXIT_OK;
    }
}
