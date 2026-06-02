#pragma once
#include <stddef.h>

/*
 * device_record — platform-neutral device descriptor.
 *
 * All pointer fields are borrowed (not owned); lifetime is at least as
 * long as the wdi_device_info list they came from (Phase 2 will populate
 * these from wdi_create_list).  In unit tests the pointers point into
 * static string literals.
 */
typedef struct {
    unsigned short  vid;
    unsigned short  pid;
    const char     *desc;       /* human-readable description, never NULL */
    const char     *device_id;  /* Windows instance ID, never NULL */
    const char     *driver;     /* current driver name, or NULL if none */
} device_record;

/*
 * vidpid_parse — parse "VID:PID" into two 16-bit values.
 *
 * Accepted forms (case-insensitive):
 *   "0403:6015"       plain 4-digit hex
 *   "0x0403:0x6015"   0x/0X prefix
 *   "403:6015"        leading zeros optional; 1–4 hex digits each
 *
 * Rejects: missing colon, empty field, non-hex chars, >4 hex digits per
 * field after stripping any 0x prefix.
 *
 * Returns 0 on success; non-zero on any parse error.
 */
int vidpid_parse(const char *arg, unsigned short *vid, unsigned short *pid);

/*
 * hwid_matches_vidpid — test whether a Windows hardware-ID string contains
 * VID_XXXX and PID_XXXX that match vid and pid (case-insensitive).
 *
 * Hardware IDs have the form "USB\VID_0403&PID_6015[&REV_...]"; this
 * function finds the VID_ and PID_ fields anywhere in the string and checks
 * them for strict equality (exactly 4 hex digits each). Returns 1 on match,
 * 0 otherwise (including NULL or missing tags).
 */
int hwid_matches_vidpid(const char *hwid, unsigned short vid, unsigned short pid);

/*
 * match_devices — collect indices of records matching vid AND pid exactly.
 *
 * Scans recs[0..n) for strict equality on both vid and pid.  Writes up to
 * out_cap matching indices into out_idx[].  Always returns the true total
 * match count even when it exceeds out_cap, so callers can detect ambiguity
 * (count > 1) without needing a large buffer.
 *
 * Safety invariant: only records where BOTH vid and pid match are included.
 * A VID-only or PID-only match is not a match.
 */
int match_devices(const device_record *recs, int n,
                  unsigned short vid, unsigned short pid,
                  int *out_idx, int out_cap);
