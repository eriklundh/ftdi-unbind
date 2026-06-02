#include "match.h"

/* stub — replaced in feat(match): implement vidpid_parse */
int vidpid_parse(const char *arg, unsigned short *vid, unsigned short *pid) {
    (void)arg; (void)vid; (void)pid;
    return -1;
}

/* stub — replaced in feat(match): implement device matching */
int match_devices(const device_record *recs, int n,
                  unsigned short vid, unsigned short pid,
                  int *out_idx, int out_cap) {
    (void)recs; (void)n; (void)vid; (void)pid; (void)out_idx; (void)out_cap;
    return 0;
}
