#include "comdb_win.h"
#include "comdb.h"
#include "match.h"      /* hwid_matches_vidpid */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <setupapi.h>
#include <cfgmgr32.h>
#include <string.h>
#include <stdio.h>

#define ARBITER_KEY \
    "SYSTEM\\CurrentControlSet\\Control\\COM Name Arbiter"
#define SERIALCOMM_KEY \
    "HARDWARE\\DEVICEMAP\\SERIALCOMM"

int comdb_read(unsigned char *buf) {
    HKEY hk;
    LONG rc = RegOpenKeyExA(HKEY_LOCAL_MACHINE, ARBITER_KEY,
                            0, KEY_READ, &hk);
    if (rc != ERROR_SUCCESS) return (int)rc;

    DWORD type, size = COMDB_SIZE;
    rc = RegQueryValueExA(hk, "ComDB", NULL, &type, buf, &size);
    RegCloseKey(hk);
    if (rc != ERROR_SUCCESS) return (int)rc;
    /* Pad to COMDB_SIZE if the stored value is shorter. */
    if (size < COMDB_SIZE)
        memset(buf + size, 0, COMDB_SIZE - size);
    return 0;
}

int comdb_write(const unsigned char *buf) {
    HKEY hk;
    LONG rc = RegOpenKeyExA(HKEY_LOCAL_MACHINE, ARBITER_KEY,
                            0, KEY_SET_VALUE, &hk);
    if (rc != ERROR_SUCCESS) return (int)rc;
    rc = RegSetValueExA(hk, "ComDB", 0, REG_BINARY, buf, COMDB_SIZE);
    RegCloseKey(hk);
    return (int)rc;
}

int comdb_active_ports(int *ports, int max) {
    HKEY hk;
    LONG rc = RegOpenKeyExA(HKEY_LOCAL_MACHINE, SERIALCOMM_KEY,
                            0, KEY_READ, &hk);
    if (rc != ERROR_SUCCESS) return 0;

    int count = 0;
    DWORD idx = 0;
    char name[256], data[64];
    DWORD nlen, dlen, type;
    while (count < max) {
        nlen = sizeof(name);
        dlen = sizeof(data);
        rc = RegEnumValueA(hk, idx++, name, &nlen, NULL, &type,
                           (LPBYTE)data, &dlen);
        if (rc == ERROR_NO_MORE_ITEMS) break;
        if (rc != ERROR_SUCCESS || type != REG_SZ) continue;
        data[dlen < sizeof(data) ? dlen : sizeof(data) - 1] = '\0';
        int p = comdb_port_from_name(data);
        if (p) ports[count++] = p;
    }
    RegCloseKey(hk);
    return count;
}

/*
 * GUID_DEVCLASS_PORTS {4D36E978-E325-11CE-BFC1-08002BE10318}
 * For FTDI VCP devices the device tree is:
 *   USB\VID_0403&PID_6015\...       (USB parent — hardware-ID match)
 *     FTDIBUS\VID_0403+PID_6015+... (Ports class child — PortName lives here)
 * We must open the child's Device Parameters, not the parent's.
 */
static const GUID s_PortsClassGuid = {
    0x4D36E978, 0xE325, 0x11CE,
    {0xBF, 0xC1, 0x08, 0x00, 0x2B, 0xE1, 0x03, 0x18}
};

/*
 * open_device_params_key — enumerate Ports class devices and find the one
 * whose USB parent matches vid:pid; open its "Device Parameters" key.
 * Returns ERROR_SUCCESS and sets *phk on success.
 */
static LONG open_device_params_key(unsigned short vid, unsigned short pid,
                                   REGSAM access, HKEY *phk)
{
    HDEVINFO hDev = SetupDiGetClassDevsA(&s_PortsClassGuid, NULL, NULL,
                                          DIGCF_PRESENT);
    if (hDev == INVALID_HANDLE_VALUE)
        return (LONG)GetLastError();

    SP_DEVINFO_DATA info;
    info.cbSize = sizeof(info);
    LONG result = ERROR_NOT_FOUND;

    for (DWORD i = 0; SetupDiEnumDeviceInfo(hDev, i, &info); i++) {
        DEVINST parent = 0;
        if (CM_Get_Parent(&parent, info.DevInst, 0) != CR_SUCCESS) continue;

        char parent_hwids[1024] = {0};
        ULONG sz = sizeof(parent_hwids);
        if (CM_Get_DevNode_Registry_PropertyA(parent, CM_DRP_HARDWAREID,
                NULL, parent_hwids, &sz, 0) != CR_SUCCESS) continue;

        int matched = 0;
        for (const char *s = parent_hwids; *s; s += strlen(s) + 1) {
            if (hwid_matches_vidpid(s, vid, pid)) { matched = 1; break; }
        }
        if (!matched) continue;

        HKEY hk = SetupDiOpenDevRegKey(hDev, &info,
                                        DICS_FLAG_GLOBAL, 0,
                                        DIREG_DEV, access);
        if (hk != INVALID_HANDLE_VALUE) {
            *phk = hk;
            result = ERROR_SUCCESS;
        } else {
            result = (LONG)GetLastError();
        }
        break;
    }
    SetupDiDestroyDeviceInfoList(hDev);
    return result;
}

int comdb_device_portname(unsigned short vid, unsigned short pid,
                          char *out, int out_len)
{
    HKEY hk;
    LONG rc = open_device_params_key(vid, pid, KEY_READ, &hk);
    if (rc != ERROR_SUCCESS) return (int)rc;

    DWORD type, size = (DWORD)(out_len - 1);
    rc = RegQueryValueExA(hk, "PortName", NULL, &type, (LPBYTE)out, &size);
    RegCloseKey(hk);
    if (rc == ERROR_SUCCESS) out[size] = '\0';
    return (int)rc;
}

int comdb_clear_device_portname(unsigned short vid, unsigned short pid) {
    HKEY hk;
    LONG rc = open_device_params_key(vid, pid, KEY_SET_VALUE, &hk);
    if (rc != ERROR_SUCCESS) return (int)rc;
    rc = RegDeleteValueA(hk, "PortName");
    RegCloseKey(hk);
    /* ERROR_FILE_NOT_FOUND means PortName wasn't there — treat as success. */
    return (rc == ERROR_SUCCESS || rc == ERROR_FILE_NOT_FOUND) ? 0 : (int)rc;
}
