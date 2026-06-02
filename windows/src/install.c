#include "install.h"
#include <libwdi.h>
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>

#define INF_NAME "ftdi_winusb.inf"

int install_winusb(unsigned short vid, unsigned short pid,
                   const char *device_id)
{
    struct wdi_device_info *list = NULL;
    struct wdi_options_create_list list_opts = {0};
    list_opts.list_all         = TRUE;
    list_opts.list_hubs        = FALSE;
    list_opts.trim_whitespaces = TRUE;

    int rc = wdi_create_list(&list, &list_opts);
    if (rc != WDI_SUCCESS)
        return rc;

    /* Find the matching wdi_device_info node by vid, pid, and device_id. */
    struct wdi_device_info *dev = NULL;
    for (struct wdi_device_info *d = list; d; d = d->next) {
        if (d->vid == vid && d->pid == pid
                && d->device_id != NULL
                && strcmp(d->device_id, device_id) == 0) {
            dev = d;
            break;
        }
    }

    if (dev == NULL) {
        wdi_destroy_list(list);
        return WDI_ERROR_NO_DEVICE;
    }

    /*
     * Build a temp dir: %TEMP%\ftdi_winusb_<pid>
     * GetTempPathA returns the path with a trailing backslash; append the
     * subdir name directly after it.
     */
    char tmp[MAX_PATH];
    DWORD tlen = GetTempPathA(MAX_PATH, tmp);
    if (tlen == 0 || tlen + 24 >= MAX_PATH) {
        wdi_destroy_list(list);
        return WDI_ERROR_RESOURCE;
    }
    snprintf(tmp + tlen, MAX_PATH - tlen, "ftdi_winusb_%lu",
             (unsigned long)GetCurrentProcessId());
    CreateDirectoryA(tmp, NULL);   /* no-op if it already exists */

    struct wdi_options_prepare_driver prep = {0};
    prep.driver_type = WDI_WINUSB;

    rc = wdi_prepare_driver(dev, tmp, INF_NAME, &prep);
    if (rc != WDI_SUCCESS) {
        wdi_destroy_list(list);
        return rc;
    }

    rc = wdi_install_driver(dev, tmp, INF_NAME, NULL);
    wdi_destroy_list(list);
    return rc;
}

const char *install_strerror(int rc) {
    return wdi_strerror(rc);
}
