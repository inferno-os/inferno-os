/*
 * Solaris serial port definitions
 */

static char *sysdev[] = {
        "/dev/cua/a",
        "/dev/cua/b"
};

#include "deveia-posix.c"
#include "deveia-bsd.c"
