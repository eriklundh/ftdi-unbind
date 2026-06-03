#include "comdb_win.h"
#include "comdb.h"
#include "match.h"      /* hwid_matches_vidpid */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <setupapi.h>
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
 * open_device_params_key — find the first device node matching vid:pid and
 * open its "Device Parameters" registry key with the given access.
 * Returns ERROR_SUCCESS and sets *phk on success.
 */
static LONG open_device_params_key(unsigned short vid, unsigned short pid,
                                   REGSAM access, HKEY *phk)
{
    HDEVINFO hDev = SetupDiGetClassDevsA(NULL, "USB", NULL,
                                         DIGCF_ALLCLASSES | DIGCF_PRESENT);
    if (hDev == INVALID_HANDLE_VALUE)
        return (LONG)GetLastError();

    SP_DEVINFO_DATA info;
    info.cbSize = sizeof(info);
    LONG result = ERROR_NOT_FOUND;

    for (DWORD i = 0; SetupDiEnumDeviceInfo(hDev, i, &info); i++) {
        char hwids[1024] = {0};
        if (!SetupDiGetDeviceRegistryPropertyA(
                hDev, &info, SPDRP_HARDWAREID,
                NULL, (PBYTE)hwids, (DWORD)(sizeof(hwids) - 2), NULL))
            continue;
        int matched = 0;
        for (const char *s = hwids; *s; s += strlen(s) + 1) {
            if (hwid_matches_vidpid(s, vid, pid)) { matched = 1; break; }
        }
        if (!matched) continue;

        HKEY hk = SetupDiOpenDevRegKey(hDev, &info,
                                        DICS_FLAG_GLOBAL, 0,
                                        DIREG_DEV, access);
        if (hk == INVALID_HANDLE_VALUE) {
            result = (LONG)GetLastError();
        } else {
            *phk = hk;
            result = ERROR_SUCCESS;
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
