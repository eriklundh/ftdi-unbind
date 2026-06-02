#include <stdio.h>
#include "libwdi.h"

int main(void) {
    printf("libwdi %s\n", wdi_get_version());
    return 0;
}
