#include "restore.h"
#include "match.h"
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <setupapi.h>
#include <cfgmgr32.h>
#include <newdev.h>
#include <stdio.h>

/*
 * find_devinfo — locate the first device node whose hardware-ID multi-sz
 * string contains VID_XXXX&PID_XXXX matching vid and pid.
 *
 * On success fills *pData and returns TRUE; the caller owns hDev.
 */
static BOOL find_devinfo(HDEVINFO hDev, unsigned short vid, unsigned short pid,
                          SP_DEVINFO_DATA *pData)
{
    pData->cbSize = sizeof(*pData);
    for (DWORD i = 0; SetupDiEnumDeviceInfo(hDev, i, pData); i++) {
        char hwids[1024] = {0};
        if (!SetupDiGetDeviceRegistryPropertyA(
                hDev, pData, SPDRP_HARDWAREID,
                NULL, (PBYTE)hwids, (DWORD)(sizeof(hwids) - 2), NULL))
            continue;
        /* Multi-sz: walk NUL-separated strings until double-NUL. */
        for (const char *s = hwids; *s; s += strlen(s) + 1) {
            if (hwid_matches_vidpid(s, vid, pid))
                return TRUE;
        }
    }
    return FALSE;
}

/* Returns TRUE if the device has a driver key installed (non-empty). */
static BOOL device_has_driver(HDEVINFO hDev, SP_DEVINFO_DATA *pData) {
    char buf[256] = {0};
    return SetupDiGetDeviceRegistryPropertyA(
               hDev, pData, SPDRP_DRIVER,
               NULL, (PBYTE)buf, (DWORD)(sizeof(buf) - 1), NULL)
           && buf[0] != '\0';
}

int restore_vcp(unsigned short vid, unsigned short pid, const char *device_id)
{
    (void)device_id;    /* reserved for disambiguation; unused in v1 */

    HDEVINFO hDev = SetupDiGetClassDevsA(NULL, "USB", NULL,
                                         DIGCF_ALLCLASSES | DIGCF_PRESENT);
    if (hDev == INVALID_HANDLE_VALUE)
        return RESTORE_ERR_NOTFOUND;

    SP_DEVINFO_DATA devData;
    if (!find_devinfo(hDev, vid, pid, &devData)) {
        SetupDiDestroyDeviceInfoList(hDev);
        return RESTORE_ERR_NOTFOUND;
    }

    /*
     * Capture the parent DEVINST before removal: the device node itself
     * vanishes when DiUninstallDevice removes it.
     */
    DEVINST parentInst = 0;
    CM_Get_Parent(&parentInst, devData.DevInst, 0);

    /* Remove the device node — drops the WinUSB driver binding. */
    BOOL needReboot = FALSE;
    if (!DiUninstallDevice(NULL, hDev, &devData, 0, &needReboot)) {
        SetupDiDestroyDeviceInfoList(hDev);
        return RESTORE_ERR_REMOVE;
    }
    SetupDiDestroyDeviceInfoList(hDev);

    /* Ask the parent hub/controller to re-enumerate its ports. */
    if (parentInst)
        CM_Reenumerate_DevNode(parentInst, CM_REENUMERATE_NORMAL);

    /*
     * Poll for the device to re-appear with a driver.  Windows Update or
     * the in-box FTDI VCP driver should reinstall within a few seconds on
     * a normal lab machine.  10 attempts x 500 ms = 5 s total.
     */
    for (int attempt = 0; attempt < 10; attempt++) {
        Sleep(500);

        hDev = SetupDiGetClassDevsA(NULL, "USB", NULL,
                                    DIGCF_ALLCLASSES | DIGCF_PRESENT);
        if (hDev == INVALID_HANDLE_VALUE)
            continue;

        SP_DEVINFO_DATA found;
        if (find_devinfo(hDev, vid, pid, &found)) {
            BOOL has = device_has_driver(hDev, &found);
            SetupDiDestroyDeviceInfoList(hDev);
            return has ? RESTORE_OK : RESTORE_ERR_DRIVERLESS;
        }
        SetupDiDestroyDeviceInfoList(hDev);
    }

    return RESTORE_ERR_NOENUM;
}

const char *restore_strerror(int rc) {
    switch (rc) {
        case RESTORE_OK:
            return "success";
        case RESTORE_ERR_NOTFOUND:
            return "device not found (is it currently bound as WinUSB?)";
        case RESTORE_ERR_REMOVE:
            return "DiUninstallDevice failed; try running elevated";
        case RESTORE_ERR_NOENUM:
            return "device did not re-enumerate within 5 s; "
                   "try replugging or 'Scan for hardware changes' in Device Manager";
        case RESTORE_ERR_DRIVERLESS:
            return "device re-enumerated but has no driver; "
                   "install the FTDI VCP driver (ftdichip.com CDM package or "
                   "connect to Windows Update), then replug or run "
                   "'Scan for hardware changes' in Device Manager";
        default:
            return "unknown restore error";
    }
}
