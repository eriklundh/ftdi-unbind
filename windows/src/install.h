#pragma once

/*
 * install_winusb — install WinUSB on the device identified by vid:pid and
 * device_id. device_id must match the value returned by enum_devices (exact
 * string comparison).
 *
 * Re-enumerates via wdi_create_list internally so the caller need not keep
 * a wdi_device_info* alive. Returns WDI_SUCCESS (0) on success; a negative
 * WDI_ERROR_* code on failure. Requires the process be running elevated.
 */
int install_winusb(unsigned short vid, unsigned short pid,
                   const char *device_id);

/* install_strerror — human-readable string for a WDI_ERROR_* code. */
const char *install_strerror(int rc);
