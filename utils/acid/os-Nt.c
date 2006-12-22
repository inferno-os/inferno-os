/*
 * Windows Nt
 */

#include <lib9.h>
#include <bio.h>
#include <ctype.h>
#include "mach.h"
#define Extern extern
#include "acid.h"
#include <signal.h>

#include <windows.h>

#define MAXBUFSIZ 16640 /* 2 STYX messages plus headers  */
#define NT_DEBUG
int	nt_debug = 0;

int
opentty(char *tty, int baud)
{
	HANDLE	comport;
	DCB	dcb;
	COMMTIMEOUTS	timeouts;

	comport = CreateFile(tty, GENERIC_READ|GENERIC_WRITE,
				0, 0, OPEN_EXISTING,
				FILE_ATTRIBUTE_NORMAL, 0);
	if (comport == INVALID_HANDLE_VALUE) {
		werrstr("could not create port %s", tty);
		return -1;
	}

	if (SetupComm(comport, MAXBUFSIZ, MAXBUFSIZ) != TRUE) {
		werrstr("could not set up %s Comm port", tty);
		CloseHandle(comport);
		return -1;
	}

	if (GetCommState(comport, &dcb) != TRUE) {
		werrstr("could not get %s comstate", tty);
		CloseHandle(comport);
		return -1;
	}

	if (baud == 0) {
		dcb.BaudRate = 19200;
	} else {
		dcb.BaudRate = baud;
	}
	dcb.ByteSize = 8;
	dcb.fParity = 0;
	dcb.Parity = NOPARITY;
	dcb.StopBits = ONESTOPBIT;
	dcb.fInX = 0;
	dcb.fOutX = 0;
	dcb.fAbortOnError = 1;

	if (SetCommState(comport, &dcb) != TRUE) {
		werrstr("could not set %s comstate", tty);
		CloseHandle(comport);
		return -1;
	}
	
	timeouts.ReadIntervalTimeout = 2;
	/* char time in milliseconds, at 19.2K char time is .4 ms */
	timeouts.ReadTotalTimeoutMultiplier = 0; /* was 100; */
	timeouts.ReadTotalTimeoutConstant = 200; /* was 500; */
	timeouts.WriteTotalTimeoutMultiplier = 0; /* was 10; */
	timeouts.WriteTotalTimeoutConstant = 400; /* was 20; */

	SetCommTimeouts(comport, &timeouts);

	EscapeCommFunction(comport, SETDTR);

	return (int) comport;
}

int
remote_read(int fd, char *buf, int bytes)
{
	DWORD numread = 0;
	BOOL rtn;

#ifdef NT_DEBUG
	if (nt_debug) {
		print("NT:rread fd %x bytes: %d", fd, bytes);
	}
#endif
	rtn = ReadFile((HANDLE) fd, buf, bytes, &numread, 0);
#ifdef NT_DEBUG
	if (nt_debug) {
		print(" numread: %d rtn: %x\n", numread, rtn);
		if (numread) {
			char *cp;
			int i;
	
			cp = (char *) buf;
			for (i=0; i < numread; i++) {
				print(" %2.2x", *cp++);
			}
			print("\n");
		}
	}
#endif
	if (!rtn) 
		return -1;
	else
		return numread;
}

int
remote_write(int fd, char *buf, int bytes)
{
	DWORD numwrt = 0;
	BOOL	rtn;
	char	*cp;
	int	i;

#ifdef NT_DEBUG
	if (nt_debug) {
		print("NT:rwrite fd %x bytes: %d", fd, bytes);
		print("\n");
		cp = (char *) buf;
		for (i=0; i < bytes; i++) {
			print(" %2.2x", *cp++);
		}
		print("\n");
	}
#endif
	while (bytes > 0) {
		rtn = WriteFile((HANDLE) fd, buf, bytes, &numwrt, 0);
		if (!rtn) {
			break;
		}
		buf += numwrt;
		bytes -= numwrt;
	}
	return numwrt;
}

void
detach(void)
{
	/* ??? */
}

char *
waitfor(int pid)
{
	fprint(2, "wait unimplemented");
	return 0;
}

int
fork(void)
{
	fprint(2, "fork unimplemented");
	return -1;
}

char *
runcmd(char *cmd)
{
	fprint(2, "runcmd unimplemented");
	return 0;
}

void (*notefunc)(int);

os_notify(void (*func)(int))
{
	notefunc = func;
	signal(SIGINT, func);
	return 0;
}

void
catcher(int sig)
{
	if (sig == SIGINT) {
		gotint = 1;
		signal(SIGINT, notefunc);
	}
}

void
setup_os_notify(void)
{
	os_notify(catcher);
}

int
nproc(char **argv)
{
	fprint(2, "nproc not implemented\n");
	return -1;
}
