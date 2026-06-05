/*
 * Unit tests for the pure hardware-id matching logic used in the restore
 * direction.  No Win32 driver APIs; runs without admin or hardware.
 */
#include <assert.h>
#include <stdio.h>
#include "match.h"

/* ── hwid_matches_vidpid ─────────────────────────────────────── */

static void test_basic_match(void) {
    assert(hwid_matches_vidpid("USB\\VID_0403&PID_6015", 0x0403, 0x6015));
}

static void test_extra_rev_field(void) {
    assert(hwid_matches_vidpid("USB\\VID_0403&PID_6015&REV_1000", 0x0403, 0x6015));
}

static void test_wrong_pid(void) {
    assert(!hwid_matches_vidpid("USB\\VID_0403&PID_6001", 0x0403, 0x6015));
}

static void test_wrong_vid(void) {
    assert(!hwid_matches_vidpid("USB\\VID_0000&PID_6015", 0x0403, 0x6015));
}

static void test_case_insensitive_lower(void) {
    assert(hwid_matches_vidpid("usb\\vid_0403&pid_6015", 0x0403, 0x6015));
}

static void test_case_insensitive_mixed(void) {
    assert(hwid_matches_vidpid("USB\\Vid_0403&Pid_6015&REV_1000", 0x0403, 0x6015));
}

static void test_null_hwid(void) {
    assert(!hwid_matches_vidpid(NULL, 0x0403, 0x6015));
}

static void test_empty_hwid(void) {
    assert(!hwid_matches_vidpid("", 0x0403, 0x6015));
}

static void test_vid_five_digits_no_match(void) {
    /* VID_40399 has 5 hex digits — must not match 0x0403 or 0x4039 */
    assert(!hwid_matches_vidpid("USB\\VID_40399&PID_6015", 0x0403, 0x6015));
}

static void test_pid_five_digits_no_match(void) {
    assert(!hwid_matches_vidpid("USB\\VID_0403&PID_60150", 0x0403, 0x6015));
}

static void test_no_vid_tag(void) {
    assert(!hwid_matches_vidpid("USB\\0403&6015", 0x0403, 0x6015));
}

static void test_no_pid_tag(void) {
    /* VID_ present but PID_ absent */
    assert(!hwid_matches_vidpid("USB\\VID_0403&6015", 0x0403, 0x6015));
}

static void test_all_zeros(void) {
    assert(hwid_matches_vidpid("USB\\VID_0000&PID_0000", 0x0000, 0x0000));
}

static void test_max_values(void) {
    assert(hwid_matches_vidpid("USB\\VID_FFFF&PID_FFFF", 0xFFFF, 0xFFFF));
}

int main(void) {
    test_basic_match();
    test_extra_rev_field();
    test_wrong_pid();
    test_wrong_vid();
    test_case_insensitive_lower();
    test_case_insensitive_mixed();
    test_null_hwid();
    test_empty_hwid();
    test_vid_five_digits_no_match();
    test_pid_five_digits_no_match();
    test_no_vid_tag();
    test_no_pid_tag();
    test_all_zeros();
    test_max_values();
    printf("all test_restore assertions passed\n");
    return 0;
}
