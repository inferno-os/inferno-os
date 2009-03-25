/*
 * BSD serial port control features not found in POSIX
 * including modem line control and hardware flow control
 */

static struct flagmap lines[] = {
        {"cts",         TIOCM_CTS},
        {"dsr",         TIOCM_DSR},
        {"ring",        TIOCM_RI},
        {"dcd",         TIOCM_CD},
        {"dtr",         TIOCM_DTR},
        {"rts",         TIOCM_RTS},
	{0,		-1}
};

static void
resxtra(int port, struct termios *ts)
{
        int fd = eia[port].fd;

	USED(ts);

        if(eia[port].dtr)
	        ioctl(fd, TIOCM_DTR, eia[port].dtr);
	if(eia[port].rts)
	        ioctl(fd, TIOCM_RTS, eia[port].rts);
	if(eia[port].cts)
	        ioctl(fd, TIOCM_CTS, eia[port].cts);
}

static char *
rdxtra(int port, struct termios *ts, char *str)
{
	int fd = eia[port].fd;
	int line;
//	struct flagmap *lp;
	char *s = str;

	USED(ts);

	if(ioctl(fd, TIOCMGET, &line) < 0)
		oserror();

//	for(lp = lines; lp->str; lp++)
//	        if(line&lp->flag)
//		        s += sprint(s, " %s", lp->str);

	return s;
}

static char *
wrxtra(int port, struct termios *ts, char *cmd)
{
	int fd = eia[port].fd;
	int n, r, flag, iocmd, *l;

	USED(ts);

	switch(*cmd) {
	case 'D':
	case 'd':
		flag = TIOCM_DTR;
		l = &eia[port].dtr;
		break;
	case 'R':
	case 'r':
		flag = TIOCM_RTS;
		l = &eia[port].rts;
		break;
	case 'M':
	case 'm':
		flag = TIOCM_CTS;
		l = &eia[port].cts;
		break;
	default:
		return nil;
	}

	n = atoi(cmd+1);
	if(n)
		iocmd = TIOCMBIS;
	else
		iocmd = TIOCMBIC;

	osenter();
	r = ioctl(fd, iocmd, &flag);
	osleave();
	if(r < 0)	
		oserror();
	
	eia[port].restore = 1;
	*l = iocmd;

	return nil;
}
