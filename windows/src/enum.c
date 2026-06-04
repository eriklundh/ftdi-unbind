#include "enum.h"
#include <libwdi.h>
#include <stdlib.h>
#include <string.h>

static char *dup_str(const char *s) {
    return _strdup(s ? s : "");
}

/* Extract the USB serial number from a Windows instance ID.
 * Instance IDs have the form "USB\VID_XXXX&PID_XXXX\<suffix>".
 * The suffix is the serial when it contains no '&'; otherwise Windows
 * generated a location-based ID (e.g. "4&3a2b1c0&0&1") — treat as blank. */
static char *extract_serial(const char *device_id) {
    if (!device_id) return dup_str("");
    const char *last_bs = strrchr(device_id, '\\');
    if (!last_bs) return dup_str("");
    const char *suffix = last_bs + 1;
    if (strchr(suffix, '&')) return dup_str("");  /* location-based, no serial */
    return dup_str(suffix);
}

int enum_devices(device_record **out, int *out_n) {
    *out   = NULL;
    *out_n = 0;

    struct wdi_device_info *list = NULL;
    struct wdi_options_create_list opts = { 0 };
    opts.list_all        = TRUE;   /* include devices that already have a driver */
    opts.list_hubs       = FALSE;
    opts.trim_whitespaces = TRUE;

    int rc = wdi_create_list(&list, &opts);
    if (rc != WDI_SUCCESS)
        return rc;

    int n = 0;
    for (struct wdi_device_info *d = list; d; d = d->next)
        n++;

    device_record *recs = calloc((size_t)n, sizeof(device_record));
    if (!recs) {
        wdi_destroy_list(list);
        return WDI_ERROR_RESOURCE;
    }

    int i = 0;
    for (struct wdi_device_info *d = list; d; d = d->next, i++) {
        recs[i].vid       = d->vid;
        recs[i].pid       = d->pid;
        recs[i].desc      = dup_str(d->desc);
        recs[i].device_id = dup_str(d->device_id);
        recs[i].driver    = d->driver ? _strdup(d->driver) : NULL;
        recs[i].serial    = extract_serial(d->device_id);
    }

    wdi_destroy_list(list);
    *out   = recs;
    *out_n = n;
    return WDI_SUCCESS;
}

void free_device_records(device_record *recs, int n) {
    if (!recs) return;
    for (int i = 0; i < n; i++) {
        free((char *)recs[i].desc);
        free((char *)recs[i].device_id);
        free((char *)recs[i].driver);
        free((char *)recs[i].serial);
    }
    free(recs);
}

const char *enum_strerror(int rc) {
    return wdi_strerror(rc);
}
