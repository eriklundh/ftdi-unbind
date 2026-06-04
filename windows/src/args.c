#include "args.h"
#include <string.h>

int parse_args(int argc, char **argv, action_t action, options *opt) {
    if (!opt) return EXIT_USAGE;
    opt->action  = action;
    opt->vidpid  = NULL;
    opt->serial  = NULL;
    opt->dry_run = 0;
    opt->all     = 0;
    opt->help    = 0;
    opt->list    = 0;
    opt->about   = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--dry-run") == 0) {
            opt->dry_run = 1;
        } else if (strcmp(argv[i], "--all") == 0) {
            opt->all = 1;
        } else if (strcmp(argv[i], "--list") == 0) {
            opt->list = 1;
        } else if (strcmp(argv[i], "-h") == 0 ||
                   strcmp(argv[i], "--help") == 0) {
            opt->help = 1;
        } else if (strcmp(argv[i], "--about") == 0) {
            opt->about = 1;
        } else if (argv[i][0] == '-') {
            return EXIT_USAGE;  /* unknown flag */
        } else if (!opt->vidpid) {
            opt->vidpid = argv[i];
        } else {
            return EXIT_USAGE;  /* extra positional argument */
        }
    }

    if (opt->help || opt->list || opt->about) return EXIT_OK;
    if (!opt->vidpid) return EXIT_USAGE;
    return EXIT_OK;
}
