#include "restore.h"
#include "match.h"
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <setupapi.h>
#include <cfgmgr32.h>
#include <newdev.h>
#include <stdio.h>
#include <string.h>

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
        for (const char *s = hwids; *s; s += strlen(s) + 1) {
            if (hwid_matches_vidpid(s, vid, pid))
                return TRUE;
        }
    }
    return FALSE;
}

/*
 * Read the OEM inf filename (e.g. "oem42.inf") from the device's class key
 * under HKLM\SYSTEM\CurrentControlSet\Control\Class\{GUID}\NNNN.
 */
static BOOL get_device_inf_name(HDEVINFO hDev, SP_DEVINFO_DATA *pData,
                                 char *buf, size_t buflen)
{
    char driver_key[256] = {0};
    if (!SetupDiGetDeviceRegistryPropertyA(hDev, pData, SPDRP_DRIVER, NULL,
            (PBYTE)driver_key, (DWORD)(sizeof(driver_key) - 1), NULL)
            || driver_key[0] == '\0')
        return FALSE;

    char reg_path[512];
    snprintf(reg_path, sizeof(reg_path),
             "SYSTEM\\CurrentControlSet\\Control\\Class\\%s", driver_key);

    HKEY hKey;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, reg_path, 0, KEY_READ, &hKey)
            != ERROR_SUCCESS)
        return FALSE;

    DWORD cb = (DWORD)buflen;
    LONG rc = RegQueryValueExA(hKey, "InfPath", NULL, NULL, (LPBYTE)buf, &cb);
    RegCloseKey(hKey);
    return rc == ERROR_SUCCESS && buf[0] != '\0';
}

/*
 * Check whether the device is on a VCP driver after re-enumeration.
 * Returns RESTORE_OK if it has a non-WinUSB driver (VCP restored),
 * RESTORE_ERR_STILL_WINUSB if it re-enumerated but landed on WinUSB again,
 * RESTORE_ERR_DRIVERLESS if it has no driver.
 */
static int check_restored_driver(HDEVINFO hDev, SP_DEVINFO_DATA *pData)
{
    char driver[256] = {0};
    if (!SetupDiGetDeviceRegistryPropertyA(hDev, pData, SPDRP_DRIVER, NULL,
            (PBYTE)driver, (DWORD)(sizeof(driver) - 1), NULL)
            || driver[0] == '\0')
        return RESTORE_ERR_DRIVERLESS;

    char service[64] = {0};
    SetupDiGetDeviceRegistryPropertyA(hDev, pData, SPDRP_SERVICE, NULL,
        (PBYTE)service, (DWORD)(sizeof(service) - 1), NULL);

    return (_stricmp(service, "WinUSB") == 0)
           ? RESTORE_ERR_STILL_WINUSB
           : RESTORE_OK;
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

    /*
     * If the device is currently on WinUSB, read the OEM inf name now so
     * we can remove it from the driver store before re-enumeration.
     * Without this step Windows finds the libwdi inf in the store and
     * reinstalls WinUSB instead of the FTDI VCP driver.
     */
    char inf_name[MAX_PATH] = {0};
    char service[64] = {0};
    SetupDiGetDeviceRegistryPropertyA(hDev, &devData, SPDRP_SERVICE, NULL,
        (PBYTE)service, (DWORD)(sizeof(service) - 1), NULL);
    if (_stricmp(service, "WinUSB") == 0)
        get_device_inf_name(hDev, &devData, inf_name, sizeof(inf_name));

    /*
     * Remove the WinUSB OEM inf from the driver store before touching the
     * device node.  SUOI_FORCEDELETE removes it even while a device still
     * references it; after DiUninstallDevice the node is gone anyway.
     */
    if (inf_name[0])
        SetupUninstallOEMInfA(inf_name, SUOI_FORCEDELETE, NULL);

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
     * Poll for the device to re-appear with a VCP driver.
     * 20 attempts x 500 ms = 10 s total.
     *
     * If the device reappears driverless, keep polling: Windows may still be
     * installing the FTDI driver in the background (e.g. via Windows Update).
     * Only commit to DRIVERLESS or NOENUM after all attempts are exhausted.
     */
    int last_rc = RESTORE_ERR_NOENUM;
    for (int attempt = 0; attempt < 20; attempt++) {
        Sleep(500);

        hDev = SetupDiGetClassDevsA(NULL, "USB", NULL,
                                    DIGCF_ALLCLASSES | DIGCF_PRESENT);
        if (hDev == INVALID_HANDLE_VALUE)
            continue;

        SP_DEVINFO_DATA found;
        if (find_devinfo(hDev, vid, pid, &found)) {
            int rc = check_restored_driver(hDev, &found);
            SetupDiDestroyDeviceInfoList(hDev);
            /* Definitive success or WinUSB reinstalled: stop now. */
            if (rc == RESTORE_OK || rc == RESTORE_ERR_STILL_WINUSB)
                return rc;
            /* Driverless: driver may still be installing; keep polling. */
            last_rc = rc;
            continue;
        }
        SetupDiDestroyDeviceInfoList(hDev);
    }

    return last_rc;
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
        case RESTORE_ERR_STILL_WINUSB:
            return "device re-enumerated but WinUSB was reinstalled; "
                   "run 'ftdi-doctor --purge-store' to remove stale WinUSB "
                   "driver entries, then replug and retry";
        default:
            return "unknown restore error";
    }
}
