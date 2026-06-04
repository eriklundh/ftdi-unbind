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

/* ---- match_devices: existing VID:PID tests (NULL serial = no filter) ----- */

static void test_match_single(void) {
    device_record recs[] = {
        { 0x0403, 0x6015, "FT231X", "USB\\VID_0403&PID_6015\\1", "ftdibus", "A1B2C3D4" },
        { 0x1234, 0xABCD, "Other",  "USB\\VID_1234&PID_ABCD\\1", NULL,      "" },
    };
    int idx[8];
    assert(match_devices(recs, 2, 0x0403, 0x6015, NULL, idx, 8) == 1);
    assert(idx[0] == 0);
}

static void test_match_none(void) {
    device_record recs[] = {
        { 0x1234, 0xABCD, "Other", "USB\\VID_1234&PID_ABCD\\1", NULL, "" },
    };
    int idx[8];
    assert(match_devices(recs, 1, 0x0403, 0x6015, NULL, idx, 8) == 0);
}

static void test_match_vid_mismatch(void) {
    device_record recs[] = {
        { 0x0403, 0x6001, "FT232R", "USB\\VID_0403&PID_6001\\1", "ftdibus", "" },
    };
    int idx[8];
    assert(match_devices(recs, 1, 0x0403, 0x6015, NULL, idx, 8) == 0);
}

static void test_match_pid_mismatch(void) {
    device_record recs[] = {
        { 0x0404, 0x6015, "Lookalike", "USB\\VID_0404&PID_6015\\1", NULL, "" },
    };
    int idx[8];
    assert(match_devices(recs, 1, 0x0403, 0x6015, NULL, idx, 8) == 0);
}

static void test_match_ambiguous(void) {
    device_record recs[] = {
        { 0x0403, 0x6015, "FT231X #1", "USB\\...\\1", "ftdibus", "A1B2C3D4" },
        { 0x0403, 0x6015, "FT231X #2", "USB\\...\\2", "ftdibus", "E5F6G7H8" },
        { 0x1234, 0xABCD, "Other",     "USB\\...\\3", NULL,      "" },
    };
    int idx[8];
    int n = match_devices(recs, 3, 0x0403, 0x6015, NULL, idx, 8);
    assert(n == 2);
    assert(idx[0] == 0);
    assert(idx[1] == 1);
}

static void test_match_empty_list(void) {
    int idx[8];
    assert(match_devices(NULL, 0, 0x0403, 0x6015, NULL, idx, 8) == 0);
}

static void test_match_returns_count_even_when_buf_full(void) {
    device_record recs[] = {
        { 0x0403, 0x6015, "A", "1", NULL, "SN1" },
        { 0x0403, 0x6015, "B", "2", NULL, "SN2" },
        { 0x0403, 0x6015, "C", "3", NULL, "SN3" },
    };
    int idx[1];
    int n = match_devices(recs, 3, 0x0403, 0x6015, NULL, idx, 1);
    assert(n == 3);     /* count = 3 even though buf holds only 1 */
    assert(idx[0] == 0);
}

/* ---- match_devices: serial filter tests --------------------------- */

static void test_serial_filter_narrows_to_one(void) {
    device_record recs[] = {
        { 0x0403, 0x6015, "FT231X #1", "USB\\...\\A1B2C3D4", "ftdibus", "A1B2C3D4" },
        { 0x0403, 0x6015, "FT231X #2", "USB\\...\\E5F6G7H8", "ftdibus", "E5F6G7H8" },
    };
    int idx[8];
    int n = match_devices(recs, 2, 0x0403, 0x6015, "A1B2C3D4", idx, 8);
    assert(n == 1);
    assert(idx[0] == 0);
}

static void test_serial_filter_no_match(void) {
    device_record recs[] = {
        { 0x0403, 0x6015, "FT231X", "USB\\...\\A1B2C3D4", "ftdibus", "A1B2C3D4" },
    };
    int idx[8];
    assert(match_devices(recs, 1, 0x0403, 0x6015, "ZZZZZZZZ", idx, 8) == 0);
}

static void test_serial_filter_null_matches_all(void) {
    device_record recs[] = {
        { 0x0403, 0x6015, "FT231X #1", "USB\\...\\SN1", NULL, "SN1" },
        { 0x0403, 0x6015, "FT231X #2", "USB\\...\\SN2", NULL, "SN2" },
    };
    int idx[8];
    assert(match_devices(recs, 2, 0x0403, 0x6015, NULL, idx, 8) == 2);
}

static void test_serial_filter_empty_string_matches_all(void) {
    device_record recs[] = {
        { 0x0403, 0x6015, "FT231X #1", "USB\\...\\SN1", NULL, "SN1" },
        { 0x0403, 0x6015, "FT231X #2", "USB\\...\\SN2", NULL, "SN2" },
    };
    int idx[8];
    assert(match_devices(recs, 2, 0x0403, 0x6015, "", idx, 8) == 2);
}

static void test_serial_filter_case_insensitive(void) {
    device_record recs[] = {
        { 0x0403, 0x6015, "FT231X", "USB\\...\\A1B2C3D4", NULL, "A1B2C3D4" },
    };
    int idx[8];
    assert(match_devices(recs, 1, 0x0403, 0x6015, "a1b2c3d4", idx, 8) == 1);
    assert(match_devices(recs, 1, 0x0403, 0x6015, "A1B2C3D4", idx, 8) == 1);
    assert(match_devices(recs, 1, 0x0403, 0x6015, "a1B2c3D4", idx, 8) == 1);
}

static void test_serial_filter_skips_blank_serial_device(void) {
    /* device has no serial (blank) — must not match any non-empty filter */
    device_record recs[] = {
        { 0x0403, 0x6015, "FT231X (no SN)", "USB\\...\\4&3a2b1c&0", NULL, "" },
    };
    int idx[8];
    assert(match_devices(recs, 1, 0x0403, 0x6015, "A1B2C3D4", idx, 8) == 0);
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
    test_serial_filter_narrows_to_one();
    test_serial_filter_no_match();
    test_serial_filter_null_matches_all();
    test_serial_filter_empty_string_matches_all();
    test_serial_filter_case_insensitive();
    test_serial_filter_skips_blank_serial_device();
    printf("All match tests passed.\n");
    return 0;
}
