#include "comdb.h"
#include <stddef.h>
#include <string.h>

int comdb_is_allocated(const unsigned char *buf, int port) {
    if (port < 1 || port > COMDB_MAX_PORT) return 0;
    int idx  = (port - 1) / 8;
    int bit  = (port - 1) % 8;
    return (buf[idx] >> bit) & 1;
}

void comdb_clear_port(unsigned char *buf, int port) {
    if (port < 1 || port > COMDB_MAX_PORT) return;
    int idx = (port - 1) / 8;
    int bit = (port - 1) % 8;
    buf[idx] &= (unsigned char)~(1u << bit);
}

int comdb_port_from_name(const char *name) {
    if (!name || !*name) return 0;

    /* Case-insensitive match of leading "COM" */
    const char prefix[] = "COM";
    for (int i = 0; i < 3; i++) {
        char c = name[i];
        if (c >= 'a' && c <= 'z') c = (char)(c - 32);
        if (c != prefix[i]) return 0;
    }

    /* Parse decimal digits after "COM" */
    const char *p = name + 3;
    if (!*p) return 0;
    int n = 0;
    for (; *p; p++) {
        if (*p < '0' || *p > '9') return 0;
        n = n * 10 + (*p - '0');
        if (n > COMDB_MAX_PORT) return 0;
    }
    return (n >= 1) ? n : 0;
}

int comdb_count_allocated(const unsigned char *buf) {
    int count = 0;
    for (int i = 0; i < COMDB_SIZE; i++) {
        unsigned char b = buf[i];
        while (b) {
            count += b & 1;
            b >>= 1;
        }
    }
    return count;
}
