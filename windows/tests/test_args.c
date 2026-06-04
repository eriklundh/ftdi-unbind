#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "args.h"

static void test_minimal(void) {
    char *argv[] = { "ftdi-unbind", "0403:6015" };
    options opt;
    assert(parse_args(2, argv, ACTION_UNBIND, &opt) == EXIT_OK);
    assert(opt.action  == ACTION_UNBIND);
    assert(opt.vidpid  != NULL);
    assert(strcmp(opt.vidpid, "0403:6015") == 0);
    assert(opt.dry_run == 0);
    assert(opt.all     == 0);
    assert(opt.help    == 0);
}

static void test_dry_run(void) {
    char *argv[] = { "ftdi-unbind", "--dry-run", "0403:6015" };
    options opt;
    assert(parse_args(3, argv, ACTION_UNBIND, &opt) == EXIT_OK);
    assert(opt.dry_run == 1);
}

static void test_all(void) {
    char *argv[] = { "ftdi-unbind", "--all", "0403:6015" };
    options opt;
    assert(parse_args(3, argv, ACTION_UNBIND, &opt) == EXIT_OK);
    assert(opt.all == 1);
}

static void test_help_short(void) {
    char *argv[] = { "ftdi-unbind", "-h" };
    options opt;
    assert(parse_args(2, argv, ACTION_UNBIND, &opt) == EXIT_OK);
    assert(opt.help == 1);
}

static void test_help_long(void) {
    char *argv[] = { "ftdi-unbind", "--help" };
    options opt;
    assert(parse_args(2, argv, ACTION_UNBIND, &opt) == EXIT_OK);
    assert(opt.help == 1);
}

static void test_flags_before_vidpid(void) {
    char *argv[] = { "ftdi-unbind", "--dry-run", "--all", "0403:6015" };
    options opt;
    assert(parse_args(4, argv, ACTION_UNBIND, &opt) == EXIT_OK);
    assert(opt.dry_run == 1 && opt.all == 1);
    assert(strcmp(opt.vidpid, "0403:6015") == 0);
}

static void test_flags_after_vidpid(void) {
    char *argv[] = { "ftdi-unbind", "0403:6015", "--dry-run" };
    options opt;
    assert(parse_args(3, argv, ACTION_UNBIND, &opt) == EXIT_OK);
    assert(opt.dry_run == 1);
    assert(strcmp(opt.vidpid, "0403:6015") == 0);
}

static void test_unknown_flag(void) {
    char *argv[] = { "ftdi-unbind", "--frobnicate", "0403:6015" };
    options opt;
    assert(parse_args(3, argv, ACTION_UNBIND, &opt) == EXIT_USAGE);
}

static void test_missing_vidpid(void) {
    char *argv[] = { "ftdi-unbind" };
    options opt;
    assert(parse_args(1, argv, ACTION_UNBIND, &opt) == EXIT_USAGE);
}

static void test_bind_action(void) {
    char *argv[] = { "ftdi-bind", "0403:6015" };
    options opt;
    assert(parse_args(2, argv, ACTION_BIND, &opt) == EXIT_OK);
    assert(opt.action == ACTION_BIND);
}

static void test_list_alone(void) {
    char *argv[] = { "ftdi-rebind", "--list" };
    options opt;
    assert(parse_args(2, argv, ACTION_UNBIND, &opt) == EXIT_OK);
    assert(opt.list   == 1);
    assert(opt.vidpid == NULL);
}

static void test_list_with_all(void) {
    char *argv[] = { "ftdi-rebind", "--list", "--all" };
    options opt;
    assert(parse_args(3, argv, ACTION_UNBIND, &opt) == EXIT_OK);
    assert(opt.list == 1 && opt.all == 1);
}

static void test_minimal_has_list_zero(void) {
    char *argv[] = { "ftdi-unbind", "0403:6015" };
    options opt;
    assert(parse_args(2, argv, ACTION_UNBIND, &opt) == EXIT_OK);
    assert(opt.list == 0);
}

static void test_exit_codes_are_correct_values(void) {
    assert(EXIT_OK      == 0);
    assert(EXIT_NOMATCH == 1);
    assert(EXIT_USAGE   == 2);
}

static void test_serial_flag(void) {
    char *argv[] = { "ftdi-unbind", "--serial", "A1B2C3D4", "0403:6015" };
    options opt;
    assert(parse_args(4, argv, ACTION_UNBIND, &opt) == EXIT_OK);
    assert(opt.serial != NULL);
    assert(strcmp(opt.serial, "A1B2C3D4") == 0);
    assert(opt.vidpid != NULL);
    assert(strcmp(opt.vidpid, "0403:6015") == 0);
}

static void test_serial_after_vidpid(void) {
    char *argv[] = { "ftdi-unbind", "0403:6015", "--serial", "A1B2C3D4" };
    options opt;
    assert(parse_args(4, argv, ACTION_UNBIND, &opt) == EXIT_OK);
    assert(opt.serial != NULL);
    assert(strcmp(opt.serial, "A1B2C3D4") == 0);
}

static void test_serial_no_value(void) {
    /* --serial at end of args with no value */
    char *argv[] = { "ftdi-unbind", "--serial" };
    options opt;
    assert(parse_args(2, argv, ACTION_UNBIND, &opt) == EXIT_USAGE);
}

static void test_serial_all_conflict(void) {
    char *argv[] = { "ftdi-unbind", "--serial", "A1B2C3D4", "--all", "0403:6015" };
    options opt;
    assert(parse_args(5, argv, ACTION_UNBIND, &opt) == EXIT_USAGE);
}

static void test_minimal_has_serial_null(void) {
    char *argv[] = { "ftdi-unbind", "0403:6015" };
    options opt;
    assert(parse_args(2, argv, ACTION_UNBIND, &opt) == EXIT_OK);
    assert(opt.serial == NULL);
}

int main(void) {
    test_minimal();
    test_dry_run();
    test_all();
    test_help_short();
    test_help_long();
    test_flags_before_vidpid();
    test_flags_after_vidpid();
    test_unknown_flag();
    test_missing_vidpid();
    test_bind_action();
    test_list_alone();
    test_list_with_all();
    test_minimal_has_list_zero();
    test_exit_codes_are_correct_values();
    test_serial_flag();
    test_serial_after_vidpid();
    test_serial_no_value();
    test_serial_all_conflict();
    test_minimal_has_serial_null();
    printf("All args tests passed.\n");
    return 0;
}
