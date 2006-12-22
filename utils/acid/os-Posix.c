#include <lib9.h>
#include <bio.h>
#include <sys/types.h>
#include <termios.h>
#undef getwd
#undef getwd
#include <unistd.h>
#include "mach.h"
#define	Extern extern
#include "acid.h"
#include <signal.h>

static void
setraw(int fd, int baud)
{
	struct termios sg;

	switch(baud){
	case 1200:	baud = B1200; break;
	case 2400:	baud = B2400; break;
	case 4800:	baud = B4800; break;
	case 9600:	baud = B9600; break;
	case 19200:	baud = B19200; break;
	case 38400:	baud = B38400; break;
	default:
		werrstr("unknown speed %d", baud);
		return;
	}
	if(tcgetattr(fd, &sg) >= 0) {
		sg.c_iflag = sg.c_oflag = sg.c_lflag = 0;
		sg.c_cflag &= ~CSIZE;
		sg.c_cflag |= CS8 | CREAD;
		sg.c_cflag &= ~(PARENB|PARODD);
		sg.c_cc[VMIN] = 1;
		sg.c_cc[VTIME] = 0;
		if(baud) {
			cfsetispeed(&sg, baud);
			cfsetospeed(&sg, baud);
		}
		tcsetattr(fd, TCSANOW, &sg);
	}
}

int
opentty(char *tty, int baud)
{
	int fd;

	if(baud == 0)
		baud = 19200;
	fd = open(tty, 2);
	if(fd < 0)
		return -1;
	setraw(fd, baud);
	return fd;
}

void
detach(void)
{
	setpgid(0, 0);
}

char *
waitfor(int pid)
{
	int n, status;
	static char buf[32];

	for(;;) {
		n = wait(&status);
		if(n < 0)
			error("wait %r");
		if(n == pid) {
			sprint(buf, "%d", status);
			return buf;
		}
	}
}

char *
runcmd(char *cmd)
{
	char *argv[4];
	int pid;

	argv[0] = "/bin/sh";
	argv[1] = "-c";
	argv[2] = cmd;
	argv[3] = 0;

	pid = fork();
	switch(pid) {
	case -1:
		error("fork %r");
	case 0:
		execv("/bin/sh", argv);
		exits(0);
	default:
		return waitfor(pid);
	}
	return 0;
}

void (*notefunc)(int);

os_notify(void (*func)(int))
{
	notefunc = func;
	signal(SIGINT, func);
}

void
catcher(int sig)
{
	if(sig==SIGINT) {
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
	char buf[128];
	int pid, i, fd;

	if(rdebug)
		error("can't newproc in remote mode");

	pid = fork();
	switch(pid) {
	case -1:
		error("new: fork %r");
	case 0:
		detach();

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
		execvp(argv[0], argv);
		fatal("new: execvp %s: %r");
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

int remote_write(int fd, char *buf, int bytes)
{
	return write(fd, buf, bytes);
}
