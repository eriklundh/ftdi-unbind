#pragma once
#include <stddef.h>

#define COMDB_SIZE      32    /* 32 bytes = 256 bits */
#define COMDB_MAX_PORT 256

/*
 * Bit layout (LSB first per byte):
 *   port N (1-based) -> byte (N-1)/8, bit (N-1)%8
 *   COM1 = byte 0 bit 0 ... COM8 = byte 0 bit 7
 *   COM9 = byte 1 bit 0 ... COM25 = byte 3 bit 0
 */

/* 1 if port is allocated in buf, 0 if free or out of range [1..COMDB_MAX_PORT]. */
int  comdb_is_allocated(const unsigned char *buf, int port);

/* Clear the bit for port.  No-op if out of range. */
void comdb_clear_port(unsigned char *buf, int port);

/*
 * Parse "COMn" (case-insensitive) -> n.
 * Returns 0 on failure: NULL, empty, non-"COM" prefix, non-numeric suffix,
 * n == 0, or n > COMDB_MAX_PORT.
 */
int  comdb_port_from_name(const char *name);

/* Count total allocated bits in buf. */
int  comdb_count_allocated(const unsigned char *buf);
