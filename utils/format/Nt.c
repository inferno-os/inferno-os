#include <lib9.h>

int
initfflag()
{
	return 1;
}

Tm *
getlocaltime()
{
	static Tm tmstruct;

	time_t t = time((time_t *)0);
	struct tm *ts = localtime(&t);
	Tm *tt = &tmstruct;

	tt->hour = ts->tm_hour;
	tt->min = ts->tm_min;
	tt->sec = ts->tm_sec;
	tt->year = ts->tm_year;
	tt->mon = ts->tm_mon;
	tt->mday = ts->tm_mday;
	tt->wday = ts->tm_wday;
	tt->yday = ts->tm_yday;
	return tt;
}

int
openfloppy(char *dev)
{
	char buf[16];

	/* if dev is of the form "x:" use "\\.\x:" instead */
	if (strlen(dev) == 2 && dev[1] == ':') {
		if (dev[0] == 'a' || dev[0] == 'A') {
			strcpy(buf, "\\\\.\\");
			strcat(buf, dev);
			return open(buf, ORDWR);
		}
		else {
			print("can only open A: drive\n");
			return -1;
		}
	}
	return open(dev, ORDWR);
}
