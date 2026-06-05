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

/* ── hwid_matches_vidpid ─────────────────────────────────────── */

static int is_hex_char(char c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

static unsigned int hex_digit_val(char c) {
    if (c >= '0' && c <= '9') return (unsigned int)(c - '0');
    if (c >= 'a' && c <= 'f') return (unsigned int)(c - 'a') + 10u;
    return (unsigned int)(c - 'A') + 10u;
}

static char to_lower(char c) {
    return (c >= 'A' && c <= 'Z') ? (char)(c + 32) : c;
}

/* Find tag (e.g. "VID_") in s, case-insensitively. Returns pointer to the
 * character after the tag on success, NULL if not found. */
static const char *find_tag(const char *s, const char *tag) {
    size_t tlen = 0;
    for (const char *t = tag; *t; t++) tlen++;
    for (; *s; s++) {
        int ok = 1;
        for (size_t i = 0; i < tlen && ok; i++)
            ok = (to_lower(s[i]) == to_lower(tag[i]));
        if (ok) return s + tlen;
    }
    return NULL;
}

/* Read exactly 4 hex digits from p; the 5th char must not be a hex digit.
 * Returns 1 and writes to *out on success, 0 on failure. */
static int read_4hex(const char *p, unsigned short *out) {
    if (!p) return 0;
    unsigned int v = 0;
    for (int i = 0; i < 4; i++) {
        if (!is_hex_char(p[i])) return 0;
        v = v * 16u + hex_digit_val(p[i]);
    }
    if (is_hex_char(p[4])) return 0;   /* more than 4 digits */
    *out = (unsigned short)v;
    return 1;
}

int hwid_matches_vidpid(const char *hwid, unsigned short vid, unsigned short pid) {
    if (!hwid) return 0;
    const char *p;
    unsigned short v, pv;
    p = find_tag(hwid, "VID_");
    if (!p || !read_4hex(p, &v) || v != vid) return 0;
    p = find_tag(hwid, "PID_");
    if (!p || !read_4hex(p, &pv) || pv != pid) return 0;
    return 1;
}

/* ── match_devices ───────────────────────────────────────────── */

static int str_iequal(const char *a, const char *b) {
    if (!a || !b) return (a == b);
    while (*a && *b) {
        char ca = (*a >= 'A' && *a <= 'Z') ? (char)(*a + 32) : *a;
        char cb = (*b >= 'A' && *b <= 'Z') ? (char)(*b + 32) : *b;
        if (ca != cb) return 0;
        a++; b++;
    }
    return (*a == '\0') && (*b == '\0');
}

int match_devices(const device_record *recs, int n,
                  unsigned short vid, unsigned short pid,
                  const char *serial,
                  int *out_idx, int out_cap) {
    int count = 0;
    int filter_serial = (serial && *serial);
    for (int i = 0; i < n; i++) {
        if (recs[i].vid != vid || recs[i].pid != pid) continue;
        if (filter_serial) {
            const char *sn = recs[i].serial;
            if (!sn || !*sn) continue;
            if (!str_iequal(sn, serial)) continue;
        }
        if (count < out_cap)
            out_idx[count] = i;
        count++;
    }
    return count;
}
