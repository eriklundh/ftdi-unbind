#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include "elevate.h"

int is_elevated(void) {
    HANDLE token = NULL;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
        return 0;
    TOKEN_ELEVATION elev = {0};
    DWORD sz = sizeof(elev);
    BOOL ok = GetTokenInformation(token, TokenElevation, &elev, sz, &sz);
    CloseHandle(token);
    return ok && elev.TokenIsElevated;
}
