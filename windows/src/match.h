#pragma once
#include <stddef.h>

typedef struct {
    unsigned short  vid;
    unsigned short  pid;
    const char     *desc;       /* borrowed */
    const char     *device_id;  /* borrowed */
    const char     *driver;     /* borrowed, may be NULL */
} device_record;

/*
 * Parse a VID:PID string into 16-bit integers.
 * Accepts: "0403:6015", "0x0403:0x6015", "403:6015" (leading zeros optional).
 * Case-insensitive hex.  Each part must be 1–4 hex digits after stripping 0x.
 * Returns 0 on success, non-zero on any parse error.
 */
int vidpid_parse(const char *arg, unsigned short *vid, unsigned short *pid);

/*
 * Fill out_idx[0..out_cap) with the indices (into recs[0..n)) of every
 * record whose vid AND pid equal the requested pair.
 * Returns the total match count (may exceed out_cap if the buffer is small).
 */
int match_devices(const device_record *recs, int n,
                  unsigned short vid, unsigned short pid,
                  int *out_idx, int out_cap);
