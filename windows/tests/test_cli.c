/*
 * test_cli.c -- exit-code contract for the three tool binaries.
 *
 * Spawns each exe as a child process and asserts the exit code matches the
 * documented Linux-parity contract (EXIT_OK=0, EXIT_USAGE=2).  No hardware
 * and no elevation are needed; all tested paths short-circuit at arg parsing.
 *
 * Exe paths are injected by CMake via UNBIND_EXE, BIND_EXE, DOCTOR_EXE.
 */
#include <assert.h>
#include <process.h>   /* _spawnv, _P_WAIT */
#include <stdio.h>

#ifndef UNBIND_EXE
#  error "UNBIND_EXE must be defined by the build system"
#endif
#ifndef BIND_EXE
#  error "BIND_EXE must be defined by the build system"
#endif
#ifndef DOCTOR_EXE
#  error "DOCTOR_EXE must be defined by the build system"
#endif

static int run(const char *exe, const char * const *argv)
{
    intptr_t rc = _spawnv(_P_WAIT, exe, (char * const *)argv);
    if (rc == -1) {
        perror(exe);
        return -1;
    }
    return (int)rc;
}

/* ---- ftdi-unbind -------------------------------------------------------- */

static void test_unbind_help_long(void)
{
    const char *av[] = { UNBIND_EXE, "--help", NULL };
    assert(run(UNBIND_EXE, av) == 0);
}

static void test_unbind_help_short(void)
{
    const char *av[] = { UNBIND_EXE, "-h", NULL };
    assert(run(UNBIND_EXE, av) == 0);
}

static void test_unbind_about(void)
{
    const char *av[] = { UNBIND_EXE, "--about", NULL };
    assert(run(UNBIND_EXE, av) == 0);
}

static void test_unbind_no_args(void)
{
    const char *av[] = { UNBIND_EXE, NULL };
    assert(run(UNBIND_EXE, av) == 2);
}

static void test_unbind_unknown_flag(void)
{
    const char *av[] = { UNBIND_EXE, "--frobnicate", "0403:6015", NULL };
    assert(run(UNBIND_EXE, av) == 2);
}

static void test_unbind_extra_positional(void)
{
    const char *av[] = { UNBIND_EXE, "0403:6015", "extra", NULL };
    assert(run(UNBIND_EXE, av) == 2);
}

/* ---- ftdi-bind ---------------------------------------------------------- */

static void test_bind_help(void)
{
    const char *av[] = { BIND_EXE, "--help", NULL };
    assert(run(BIND_EXE, av) == 0);
}

static void test_bind_about(void)
{
    const char *av[] = { BIND_EXE, "--about", NULL };
    assert(run(BIND_EXE, av) == 0);
}

static void test_bind_no_args(void)
{
    const char *av[] = { BIND_EXE, NULL };
    assert(run(BIND_EXE, av) == 2);
}

static void test_bind_unknown_flag(void)
{
    const char *av[] = { BIND_EXE, "--frobnicate", "0403:6015", NULL };
    assert(run(BIND_EXE, av) == 2);
}

/* ---- ftdi-doctor -------------------------------------------------------- */

static void test_doctor_help(void)
{
    const char *av[] = { DOCTOR_EXE, "--help", NULL };
    assert(run(DOCTOR_EXE, av) == 0);
}

static void test_doctor_about(void)
{
    const char *av[] = { DOCTOR_EXE, "--about", NULL };
    assert(run(DOCTOR_EXE, av) == 0);
}

static void test_doctor_no_args(void)
{
    const char *av[] = { DOCTOR_EXE, NULL };
    assert(run(DOCTOR_EXE, av) == 2);
}

static void test_doctor_unknown_flag(void)
{
    const char *av[] = { DOCTOR_EXE, "--frobnicate", NULL };
    assert(run(DOCTOR_EXE, av) == 2);
}

/* ---- main -------------------------------------------------------------- */

int main(void)
{
    test_unbind_help_long();
    test_unbind_help_short();
    test_unbind_about();
    test_unbind_no_args();
    test_unbind_unknown_flag();
    test_unbind_extra_positional();

    test_bind_help();
    test_bind_about();
    test_bind_no_args();
    test_bind_unknown_flag();

    test_doctor_help();
    test_doctor_about();
    test_doctor_no_args();
    test_doctor_unknown_flag();

    printf("All CLI exit-code tests passed.\n");
    return 0;
}
