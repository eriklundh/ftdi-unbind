#pragma once
#include "match.h"

/*
 * enum_devices — enumerate all USB devices via libwdi and return a
 * heap-allocated array of device_record copies owned by the caller.
 * Call free_device_records when done.
 *
 * Returns WDI_SUCCESS (0) on success; a negative WDI_ERROR_* code otherwise.
 */
int  enum_devices(device_record **out, int *out_n);

/*
 * free_device_records — release the array allocated by enum_devices.
 * Safe to call with (NULL, 0).
 */
void free_device_records(device_record *recs, int n);

/*
 * enum_strerror — human-readable description of a WDI_ERROR_* code.
 * Wraps wdi_strerror so callers need not include libwdi.h directly.
 */
const char *enum_strerror(int rc);
