#pragma once
#include "comdb.h"

/*
 * comdb_read — read ComDB from the COM Name Arbiter registry key into buf
 * (COMDB_SIZE bytes). Returns 0 on success, non-zero (Windows error) on
 * failure.
 */
int comdb_read(unsigned char *buf);

/*
 * comdb_write — write buf back to the COM Name Arbiter key. Requires
 * elevation. Returns 0 on success, non-zero (Windows error) on failure.
 */
int comdb_write(const unsigned char *buf);

/*
 * comdb_active_ports — read HARDWARE\DEVICEMAP\SERIALCOMM and return the
 * set of COM port numbers currently active (one per active serial device).
 * Writes up to max port numbers into ports[]. Returns the count found.
 */
int comdb_active_ports(int *ports, int max);

/*
 * comdb_device_portname — find the PortName assigned to the device matching
 * vid:pid via SetupAPI + hwid_matches_vidpid, then read PortName from its
 * Device Parameters registry key. Writes at most out_len bytes into out.
 * Returns 0 on success, non-zero on failure (device not found, no PortName).
 */
int comdb_device_portname(unsigned short vid, unsigned short pid,
                          char *out, int out_len);

/*
 * comdb_clear_device_portname — delete the PortName value from the matching
 * device's Device Parameters key. Requires elevation.
 * Returns 0 on success, non-zero on failure.
 */
int comdb_clear_device_portname(unsigned short vid, unsigned short pid);
