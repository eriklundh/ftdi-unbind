#include "match.h"
#include <stddef.h>
#include <string.h>

/* Parse one hex field (1–4 digits, case-insensitive, no prefix). */
static int parse_hex16(const char *s, size_t len, unsigned short *out) {
    if (len == 0 || len > 4) return -1;
    unsigned int v = 0;
    for (size_t i = 0; i < len; i++) {
        unsigned int digit;
        char c = s[i];
        if      (c >= '0' && c <= '9') digit = (unsigned int)(c - '0');
        else if (c >= 'a' && c <= 'f') digit = (unsigned int)(c - 'a') + 10u;
        else if (c >= 'A' && c <= 'F') digit = (unsigned int)(c - 'A') + 10u;
        else return -1;
        v = v * 16u + digit;
    }
    *out = (unsigned short)v;
    return 0;
}

int vidpid_parse(const char *arg, unsigned short *vid, unsigned short *pid) {
    if (!arg || !*arg) return -1;

    /* Locate the colon separator. */
    const char *colon = strchr(arg, ':');
    if (!colon || colon == arg) return -1;

    /* VID: strip optional 0x/0X prefix. */
    const char *vp = arg;
    if (vp[0] == '0' && (vp[1] == 'x' || vp[1] == 'X')) vp += 2;
    size_t vlen = (size_t)(colon - vp);

    /* PID: strip optional 0x/0X prefix. */
    const char *pp = colon + 1;
    if (!*pp) return -1;
    if (pp[0] == '0' && (pp[1] == 'x' || pp[1] == 'X')) pp += 2;
    size_t plen = strlen(pp);

    return parse_hex16(vp, vlen, vid) || parse_hex16(pp, plen, pid);
}

int match_devices(const device_record *recs, int n,
                  unsigned short vid, unsigned short pid,
                  int *out_idx, int out_cap) {
    int count = 0;
    for (int i = 0; i < n; i++) {
        if (recs[i].vid == vid && recs[i].pid == pid) {
            if (count < out_cap)
                out_idx[count] = i;
            count++;
        }
    }
    return count;
}
