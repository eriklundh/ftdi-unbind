#pragma once

/* Exit codes — match the Linux ftdi-bind/ftdi-unbind scripts. */
#define EXIT_OK      0
#define EXIT_NOMATCH 1   /* no matching device, or ambiguous without --all */
#define EXIT_USAGE   2   /* bad arguments */

typedef enum { ACTION_UNBIND, ACTION_BIND } action_t;

typedef struct {
    action_t    action;
    const char *vidpid;   /* points into argv; not owned */
    int         dry_run;
    int         all;
    int         help;
} options;

/*
 * Parse argv[1..argc) into *opt.  action is the verb baked into the binary
 * (ACTION_UNBIND for ftdi-unbind.exe, ACTION_BIND for ftdi-bind.exe).
 * Returns EXIT_OK, EXIT_USAGE, or EXIT_NOMATCH.
 */
int parse_args(int argc, char **argv, action_t action, options *opt);
