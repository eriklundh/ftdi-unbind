#include <assert.h>
#include <stdio.h>
#include "match.h"

/* ---- vidpid_parse: accepted forms --------------------------------- */

static void test_parse_plain(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("0403:6015", &vid, &pid) == 0);
    assert(vid == 0x0403 && pid == 0x6015);
}

static void test_parse_0x_prefix(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("0x0403:0x6015", &vid, &pid) == 0);
    assert(vid == 0x0403 && pid == 0x6015);
}

static void test_parse_0X_prefix(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("0X0403:0X6015", &vid, &pid) == 0);
    assert(vid == 0x0403 && pid == 0x6015);
}

static void test_parse_no_leading_zero(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("403:6015", &vid, &pid) == 0);
    assert(vid == 0x0403 && pid == 0x6015);
}

static void test_parse_single_digit(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("1:2", &vid, &pid) == 0);
    assert(vid == 1 && pid == 2);
}

static void test_parse_max_value(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("FFFF:FFFF", &vid, &pid) == 0);
    assert(vid == 0xFFFF && pid == 0xFFFF);
}

static void test_parse_lowercase_hex(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("abcd:ef01", &vid, &pid) == 0);
    assert(vid == 0xABCD && pid == 0xEF01);
}

static void test_parse_uppercase_hex(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("ABCD:EF01", &vid, &pid) == 0);
    assert(vid == 0xABCD && pid == 0xEF01);
}

static void test_parse_mixed_case_hex(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("AbCd:eF01", &vid, &pid) == 0);
    assert(vid == 0xABCD && pid == 0xEF01);
}

/* ---- vidpid_parse: rejected forms --------------------------------- */

static void test_reject_no_colon(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("04036015", &vid, &pid) != 0);
}

static void test_reject_empty(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("", &vid, &pid) != 0);
}

static void test_reject_empty_vid(void) {
    unsigned short vid, pid;
    assert(vidpid_parse(":6015", &vid, &pid) != 0);
}

static void test_reject_empty_pid(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("0403:", &vid, &pid) != 0);
}

static void test_reject_non_hex_vid(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("04GH:6015", &vid, &pid) != 0);
    assert(vidpid_parse("040G:6015", &vid, &pid) != 0);
}

static void test_reject_non_hex_pid(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("0403:601Z", &vid, &pid) != 0);
}

static void test_reject_too_many_digits_vid(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("00403:6015", &vid, &pid) != 0);  /* 5 hex digits */
}

static void test_reject_too_many_digits_pid(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("0403:60150", &vid, &pid) != 0);
}

static void test_reject_too_many_digits_with_0x(void) {
    unsigned short vid, pid;
    assert(vidpid_parse("0x00403:0x6015", &vid, &pid) != 0);
}

/* ---- match_devices ------------------------------------------------ */

static void test_match_single(void) {
    device_record recs[] = {
        { 0x0403, 0x6015, "FT231X", "USB\\VID_0403&PID_6015\\1", "ftdibus" },
        { 0x1234, 0xABCD, "Other",  "USB\\VID_1234&PID_ABCD\\1", NULL },
    };
    int idx[8];
    assert(match_devices(recs, 2, 0x0403, 0x6015, idx, 8) == 1);
    assert(idx[0] == 0);
}

static void test_match_none(void) {
    device_record recs[] = {
        { 0x1234, 0xABCD, "Other", "USB\\VID_1234&PID_ABCD\\1", NULL },
    };
    int idx[8];
    assert(match_devices(recs, 1, 0x0403, 0x6015, idx, 8) == 0);
}

static void test_match_vid_mismatch(void) {
    device_record recs[] = {
        { 0x0403, 0x6001, "FT232R", "USB\\VID_0403&PID_6001\\1", "ftdibus" },
    };
    int idx[8];
    assert(match_devices(recs, 1, 0x0403, 0x6015, idx, 8) == 0);
}

static void test_match_pid_mismatch(void) {
    device_record recs[] = {
        { 0x0404, 0x6015, "Lookalike", "USB\\VID_0404&PID_6015\\1", NULL },
    };
    int idx[8];
    assert(match_devices(recs, 1, 0x0403, 0x6015, idx, 8) == 0);
}

static void test_match_ambiguous(void) {
    device_record recs[] = {
        { 0x0403, 0x6015, "FT231X #1", "USB\\...\\1", "ftdibus" },
        { 0x0403, 0x6015, "FT231X #2", "USB\\...\\2", "ftdibus" },
        { 0x1234, 0xABCD, "Other",     "USB\\...\\3", NULL },
    };
    int idx[8];
    int n = match_devices(recs, 3, 0x0403, 0x6015, idx, 8);
    assert(n == 2);
    assert(idx[0] == 0);
    assert(idx[1] == 1);
}

static void test_match_empty_list(void) {
    int idx[8];
    assert(match_devices(NULL, 0, 0x0403, 0x6015, idx, 8) == 0);
}

static void test_match_returns_count_even_when_buf_full(void) {
    device_record recs[] = {
        { 0x0403, 0x6015, "A", "1", NULL },
        { 0x0403, 0x6015, "B", "2", NULL },
        { 0x0403, 0x6015, "C", "3", NULL },
    };
    int idx[1];
    int n = match_devices(recs, 3, 0x0403, 0x6015, idx, 1);
    assert(n == 3);     /* count = 3 even though buf holds only 1 */
    assert(idx[0] == 0);
}

/* ------------------------------------------------------------------ */

int main(void) {
    test_parse_plain();
    test_parse_0x_prefix();
    test_parse_0X_prefix();
    test_parse_no_leading_zero();
    test_parse_single_digit();
    test_parse_max_value();
    test_parse_lowercase_hex();
    test_parse_uppercase_hex();
    test_parse_mixed_case_hex();
    test_reject_no_colon();
    test_reject_empty();
    test_reject_empty_vid();
    test_reject_empty_pid();
    test_reject_non_hex_vid();
    test_reject_non_hex_pid();
    test_reject_too_many_digits_vid();
    test_reject_too_many_digits_pid();
    test_reject_too_many_digits_with_0x();
    test_match_single();
    test_match_none();
    test_match_vid_mismatch();
    test_match_pid_mismatch();
    test_match_ambiguous();
    test_match_empty_list();
    test_match_returns_count_even_when_buf_full();
    printf("All match tests passed.\n");
    return 0;
}
