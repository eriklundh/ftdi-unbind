#include <stdio.h>
#include "libwdi.h"

int main(void) {
    printf("libwdi v1.5.0  wdf_version=%d  strerror(0)=%s\n",
           wdi_get_wdf_version(),
           wdi_strerror(0));
    return 0;
}
