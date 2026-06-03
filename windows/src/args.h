#pragma once

/*
 * Exit codes — identical to the Linux ftdi-bind / ftdi-unbind scripts so
 * shell callers and CI scripts behave the same on both platforms.
 */
#define EXIT_OK      0   /* success */
#define EXIT_NOMATCH 1   /* no matching device, or ambiguous without --all */
#define EXIT_USAGE   2   /* bad / missing arguments */

/*
 * action_t — the verb baked into each binary at link time.
 * ftdi-unbind.exe passes ACTION_UNBIND; ftdi-bind.exe passes ACTION_BIND.
 * Keeping it out of the argv parse means neither exe accepts the other's
 * verb as a flag — wrong tool, wrong device class, loud error.
 */
typedef enum { ACTION_UNBIND, ACTION_BIND } action_t;

typedef struct {
    action_t    action;   /* set from the caller, not from argv */
    const char *vidpid;   /* points into argv — not owned, not copied */
    int         dry_run;  /* --dry-run: resolve + report, change nothing */
    int         all;      /* --all: act on every matching device */
    int         help;     /* -h / --help */
    int         list;     /* --list: enumerate devices, no VID:PID needed */
    int         about;    /* --about: print copyright and exit */
} options;

/*
 * parse_args — populate *opt from argc/argv.
 *
 * Flags accepted: --dry-run  --all  -h  --help
 * One positional argument (VID:PID string) is required unless --help.
 * Any unrecognised flag returns EXIT_USAGE immediately.
 *
 * Returns EXIT_OK on success, EXIT_USAGE on bad/missing arguments.
 */
int parse_args(int argc, char **argv, action_t action, options *opt);
