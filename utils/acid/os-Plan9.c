/*
 * Plan9
 */

#include <lib9.h>
#include <bio.h>
#include <ctype.h>
#include "mach.h"
#define Extern extern
#include "acid.h"

int
opentty(char *tty, int baud)
{
	int fd, cfd;
	char ctty[100];

	if(tty == 0)
		tty = "/dev/eia0";
	sprint(ctty, "%sctl", tty);
	fd = open(tty, 2);
	if(fd < 0)
		return -1;
	if(baud){
		cfd = open(ctty, 1);
		if(cfd < 0)
			return fd;
		fprint(cfd, "b%d", baud);
		close(cfd);
	}
	return fd;
}

void
detach(void)
{
	rfork(RFNAMEG|RFNOTEG|RFREND);
}

char *
waitfor(int pid)
{
	Waitmsg *w;
	static char buf[ERRMAX];

	for(;;) {
		w = wait();
		if(w == nil)
			error("wait %r");
		if(w->pid == pid){
			strecpy(buf, buf+ERRMAX, w->msg);
			free(w);
			return buf;
		}
		free(w);
	}
	return nil;
}

char *
runcmd(char *cmd)
{
	char *argv[4];
	int pid;

	argv[0] = "/bin/rc";
	argv[1] = "-c";
	argv[2] = cmd;
	argv[3] = 0;

	pid = fork();
	switch(pid) {
	case -1:
		error("fork %r");
	case 0:
		exec("/bin/rc", argv);
		exits(0);
	default:
		return waitfor(pid);
	}
	return 0;
}

void
catcher(void *junk, char *s)
{
	USED(junk);

	if(strstr(s, "interrupt")) {
		gotint = 1;
		noted(NCONT);
	}
	noted(NDFLT);
}

void (*notefunc)(void *, char *);

void
setup_os_notify(void)
{
	notify(catcher);
}

int
nproc(char **argv)
{
	char buf[128];
	int pid, i, fd;

	pid = fork();
	switch(pid) {
	case -1:
		error("new: fork %r");
	case 0:
		rfork(RFNAMEG|RFNOTEG);

		sprint(buf, "/proc/%d/ctl", getpid());
		fd = open(buf, ORDWR);
		if(fd < 0)
			fatal("new: open %s: %r", buf);
		write(fd, "hang", 4);
		close(fd);

		close(0);
		close(1);
		close(2);
		for(i = 3; i < NFD; i++)
			close(i);

		open("/dev/cons", OREAD);
		open("/dev/cons", OWRITE);
		open("/dev/cons", OWRITE);
		exec(argv[0], argv);
		fatal("new: exec %s: %r");
	default:
		install(pid);
		msg(pid, "waitstop");
		notes(pid);
		sproc(pid);
		dostop(pid);
		break;
	}

	return pid;
}

int
remote_read(int fd, char *buf, int bytes)
{
	return read(fd, buf, bytes);
}

int
remote_write(int fd, char *buf, int bytes)
{
	return write(fd, buf, bytes);
}
