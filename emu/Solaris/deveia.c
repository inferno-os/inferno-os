/*
 * Solaris serial port definitions
 */

static char *sysdev[] = {
        "/dev/term/a",
        "/dev/term/b"
};

#include "deveia-posix.c"
#include "deveia-bsd.c"

static struct tcdef_t bps[] = {
	{0,		B0},
	{50,		B50},
	{75,		B75},
	{110,		B110},
	{134,		B134},
	{150,		B150},
	{200,		B200},
	{300,		B300},
	{600,		B600},
	{1200,	B1200},
	{1800,	B1800},
	{2400,	B2400},
	{4800,	B4800},
	{9600,	B9600},
	{19200,	B19200},
	{38400,	B38400},
	{57600,	B57600},
	{76800,	B76800},
	{115200,	B115200},
	{153600,	B153600},
	{230400,	B230400},
	{307200,	B307200},
	{460800,	B460800},
	{-1,		-1}
};
