#pragma once

/* Return codes for restore_vcp. */
#define RESTORE_OK              0
#define RESTORE_ERR_NOTFOUND   -1   /* no matching device found */
#define RESTORE_ERR_REMOVE     -2   /* DiUninstallDevice failed */
#define RESTORE_ERR_NOENUM     -3   /* device did not re-enumerate in time */
#define RESTORE_ERR_DRIVERLESS -4   /* re-enumerated but has no driver */

/*
 * restore_vcp — remove the WinUSB driver from the device matching vid:pid
 * and re-trigger enumeration so Windows reinstalls the FTDI VCP driver.
 *
 * Polls up to ~5 s for the device to re-appear with a driver.  Returns
 * RESTORE_OK on success; one of the RESTORE_ERR_* codes otherwise.
 * Requires the process be running elevated.
 */
int restore_vcp(unsigned short vid, unsigned short pid, const char *device_id);

/* restore_strerror — human-readable description of a RESTORE_* code. */
const char *restore_strerror(int rc);
