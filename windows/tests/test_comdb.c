/*
 * Unit tests for pure ComDB bit-manipulation logic.
 * No registry access, no admin, no hardware required.
 *
 * Bit layout: port N (1-based) → byte (N-1)/8, bit (N-1)%8 (LSB first).
 *   COM1  = byte 0 bit 0   COM8  = byte 0 bit 7
 *   COM9  = byte 1 bit 0   COM16 = byte 1 bit 7
 *   COM25 = byte 3 bit 0
 */
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include "comdb.h"

/* ── comdb_is_allocated ─────────────────────────────────────────────── */

static void test_allzero_nothing_allocated(void) {
    unsigned char buf[COMDB_SIZE] = {0};
    for (int p = 1; p <= COMDB_MAX_PORT; p++)
        assert(!comdb_is_allocated(buf, p));
}

static void test_com1_bit0(void) {
    unsigned char buf[COMDB_SIZE] = {0};
    buf[0] = 0x01;
    assert( comdb_is_allocated(buf, 1));
    assert(!comdb_is_allocated(buf, 2));
}

static void test_com8_bit7(void) {
    unsigned char buf[COMDB_SIZE] = {0};
    buf[0] = 0x80;
    assert( comdb_is_allocated(buf, 8));
    assert(!comdb_is_allocated(buf, 7));
    assert(!comdb_is_allocated(buf, 9));
}

static void test_com9_byte1_bit0(void) {
    unsigned char buf[COMDB_SIZE] = {0};
    buf[1] = 0x01;
    assert( comdb_is_allocated(buf, 9));
    assert(!comdb_is_allocated(buf, 8));
    assert(!comdb_is_allocated(buf, 10));
}

static void test_com25_byte3_bit0(void) {
    unsigned char buf[COMDB_SIZE] = {0};
    buf[3] = 0x01;
    assert( comdb_is_allocated(buf, 25));
    assert(!comdb_is_allocated(buf, 24));
    assert(!comdb_is_allocated(buf, 26));
}

static void test_out_of_range_returns_zero(void) {
    unsigned char buf[COMDB_SIZE];
    memset(buf, 0xFF, sizeof(buf));
    assert(!comdb_is_allocated(buf, 0));
    assert(!comdb_is_allocated(buf, COMDB_MAX_PORT + 1));
}

/* ── comdb_clear_port ───────────────────────────────────────────────── */

static void test_clear_com1(void) {
    unsigned char buf[COMDB_SIZE] = {0};
    buf[0] = 0xFF;
    comdb_clear_port(buf, 1);
    assert(!comdb_is_allocated(buf, 1));
    assert( comdb_is_allocated(buf, 2));  /* others untouched */
}

static void test_clear_com25(void) {
    unsigned char buf[COMDB_SIZE] = {0};
    buf[3] = 0x01;
    comdb_clear_port(buf, 25);
    assert(!comdb_is_allocated(buf, 25));
    assert(buf[3] == 0x00);
}

static void test_clear_idempotent(void) {
    unsigned char buf[COMDB_SIZE] = {0};
    comdb_clear_port(buf, 5);  /* already 0 — must not corrupt anything */
    assert(!comdb_is_allocated(buf, 5));
}

static void test_clear_out_of_range_safe(void) {
    unsigned char buf[COMDB_SIZE];
    memset(buf, 0xAA, sizeof(buf));
    comdb_clear_port(buf, 0);              /* must not crash or corrupt */
    comdb_clear_port(buf, COMDB_MAX_PORT + 1);
    /* buffer must be unchanged */
    for (int i = 0; i < COMDB_SIZE; i++)
        assert(buf[i] == 0xAA);
}

/* ── comdb_port_from_name ───────────────────────────────────────────── */

static void test_port_from_name_com1(void) {
    assert(comdb_port_from_name("COM1") == 1);
}

static void test_port_from_name_com25(void) {
    assert(comdb_port_from_name("COM25") == 25);
}

static void test_port_from_name_com256(void) {
    assert(comdb_port_from_name("COM256") == 256);
}

static void test_port_from_name_lowercase(void) {
    assert(comdb_port_from_name("com3") == 3);
}

static void test_port_from_name_mixed_case(void) {
    assert(comdb_port_from_name("Com11") == 11);
}

static void test_port_from_name_empty(void) {
    assert(comdb_port_from_name("") == 0);
}

static void test_port_from_name_null(void) {
    assert(comdb_port_from_name(NULL) == 0);
}

static void test_port_from_name_non_com(void) {
    assert(comdb_port_from_name("LPT1") == 0);
    assert(comdb_port_from_name("COM") == 0);   /* no digits */
    assert(comdb_port_from_name("COMX") == 0);  /* non-numeric */
}

static void test_port_from_name_com0_invalid(void) {
    /* COM0 is not a real port; return 0 to signal invalid */
    assert(comdb_port_from_name("COM0") == 0);
}

static void test_port_from_name_out_of_range(void) {
    /* COM257 exceeds COMDB_MAX_PORT */
    assert(comdb_port_from_name("COM257") == 0);
}

/* ── comdb_count_allocated ──────────────────────────────────────────── */

static void test_count_all_zero(void) {
    unsigned char buf[COMDB_SIZE] = {0};
    assert(comdb_count_allocated(buf) == 0);
}

static void test_count_all_ff(void) {
    unsigned char buf[COMDB_SIZE];
    memset(buf, 0xFF, sizeof(buf));
    assert(comdb_count_allocated(buf) == 256);
}

static void test_count_live_example(void) {
    /*
     * Real ComDB from the development machine after many reinstalls:
     *   0xFC 0xFF 0xFF 0x01 ... = COM3-COM25 allocated (23 ports)
     *   COM1 and COM2 free (bits 0,1 of byte 0 are 0).
     */
    unsigned char buf[COMDB_SIZE] = {0};
    buf[0] = 0xFC;  /* COM3-COM8:  bits 2-7 = 6 ports */
    buf[1] = 0xFF;  /* COM9-COM16: bits 0-7 = 8 ports */
    buf[2] = 0xFF;  /* COM17-COM24: bits 0-7 = 8 ports */
    buf[3] = 0x01;  /* COM25: bit 0 = 1 port */
    assert(comdb_count_allocated(buf) == 23);
    assert(!comdb_is_allocated(buf, 1));
    assert(!comdb_is_allocated(buf, 2));
    assert( comdb_is_allocated(buf, 3));
    assert( comdb_is_allocated(buf, 25));
    assert(!comdb_is_allocated(buf, 26));
}

int main(void) {
    test_allzero_nothing_allocated();
    test_com1_bit0();
    test_com8_bit7();
    test_com9_byte1_bit0();
    test_com25_byte3_bit0();
    test_out_of_range_returns_zero();

    test_clear_com1();
    test_clear_com25();
    test_clear_idempotent();
    test_clear_out_of_range_safe();

    test_port_from_name_com1();
    test_port_from_name_com25();
    test_port_from_name_com256();
    test_port_from_name_lowercase();
    test_port_from_name_mixed_case();
    test_port_from_name_empty();
    test_port_from_name_null();
    test_port_from_name_non_com();
    test_port_from_name_com0_invalid();
    test_port_from_name_out_of_range();

    test_count_all_zero();
    test_count_all_ff();
    test_count_live_example();

    printf("all test_comdb assertions passed\n");
    return 0;
}
