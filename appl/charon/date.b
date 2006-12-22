implement Date;

include "common.m";
include "date.m";
include "daytime.m";
	daytime: Daytime;
	Tm: import daytime;

sys: Sys;
CU: CharonUtils;

wdayname := array[] of {
	"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
};

monname := array[] of {
	"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
};

init(cu: CharonUtils)
{
	sys = load Sys Sys->PATH;
	CU = cu;
	daytime = load Daytime Daytime->PATH;
	if (daytime==nil)
		CU->raisex(sys->sprint("EXInternal: can't load Daytime: %r"));
}

# print dates in the format
# Wkd, DD Mon YYYY HH:MM:SS GMT

dateconv(t: int): string
{
	tm : ref Tm;
	tm = daytime->gmt(t);
	return sys->sprint("%s, %.2d %s %.4d %.2d:%.2d:%.2d GMT",
		wdayname[tm.wday], tm.mday, monname[tm.mon], tm.year+1900,
		tm.hour, tm.min, tm.sec);
}

# parse a date and return the seconds since the epoch
# return 0 for a failure
#
# need to handle three formats (we'll be a bit more tolerant)
#  Sun, 06 Nov 1994 08:49:37 GMT  (rfc822+rfc1123; preferred)
#  Sunday, 06-Nov-94 08:49:37 GMT (rfc850, obsoleted by rfc1036)
#  Sun Nov  6 08:49:37 1994	  (ANSI C's asctime() format; GMT assumed)

date2sec(date : string): int
{
	tm := daytime->string2tm(date);
	if(tm == nil || tm.year < 70 || tm.zone != "GMT")
		t := 0;
	else
		t = daytime->tm2epoch(tm);
	return t;
}

now(): int
{
	return daytime->now();
}
