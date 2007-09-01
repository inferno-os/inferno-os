implement Daytime;
#
# These routines convert time as follows:
#
# The epoch is 0000 Jan 1 1970 GMT.
# The argument time is in microseconds since then.
# The local(t) entry returns a reference to an ADT
# containing
#
#	seconds (0-59)
#	minutes (0-59)
#	hours (0-23)
#	day of month (1-31)
#	month (0-11)
#	year-1900
#	weekday (0-6, Sun is 0)
#	day of the year
#	daylight savings flag
#
# The routine gets the daylight savings time from the file /locale/timezone.
#
# text(tvec)
# where tvec is produced by local
# returns a string that has the time in the form
#
#	Thu Jan 01 00:00:00 GMT 1970n0
#	012345678901234567890123456789
#	0	  1	    2
#
# time() just reads the time from /dev/time
# and then calls localtime, then asctime.
#
# The sign bit of second times will turn on 68 years from the epoch ->2038
#
include	"sys.m";
include	"string.m";
include "daytime.m";

S: String;
sys: Sys;

dmsize := array[] of {
	31, 28, 31, 30, 31, 30,
	31, 31, 30, 31, 30, 31
};
ldmsize := array[] of {
	31, 29, 31, 30, 31, 30,
	31, 31, 30, 31, 30, 31
};

Timezone: adt
{
	stname: string;
	dlname: string;
	stdiff:	int;
	dldiff: int;
	dlpairs: array of int;
};

timezone: ref Timezone;

now(): int
{
	if(sys == nil)
		sys = load Sys Sys->PATH;

	fd := sys->open("/dev/time", sys->OREAD);
	if(fd == nil)
		return 0;
	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return 0;

	t := (big string buf[0:n]) / big 1000000;
	return int t;
}

time(): string
{
	t := now();
	tm := local(t);
	return text(tm);
}

local(tim: int): ref Tm
{
	ct: ref Tm;

	if(timezone == nil)
		timezone = readtimezone(nil);

	t := tim + timezone.stdiff;
	dlflag := 0;
	for(i := 0; i+1 < len timezone.dlpairs; i += 2) {
		if(t >= timezone.dlpairs[i] && t < timezone.dlpairs[i+1]) {
			t = tim + timezone.dldiff;
			dlflag++;
			break;
		}
	}
	ct = gmt(t);
	if(dlflag) {
		ct.zone = timezone.dlname;
		ct.tzoff = timezone.dldiff;
	}
	else {
		ct.zone = timezone.stname;
		ct.tzoff = timezone.stdiff;
	}
	return ct;
}

gmt(tim: int): ref Tm
{
	xtime := ref Tm;

	# break initial number into days
	hms := tim % 86400;
	day := tim / 86400;
	if(hms < 0) {
		hms += 86400;
		day -= 1;
	}

	# generate hours:minutes:seconds
	xtime.sec = hms % 60;
	d1 := hms / 60;
	xtime.min = d1 % 60;
	d1 /= 60;
	xtime.hour = d1;

	# day is the day number.
	# generate day of the week.
	# The addend is 4 mod 7 (1/1/1970 was Thursday)
	xtime.wday = (day + 7340036) % 7;

	# year number
	if(day >= 0)
		for(d1 = 70; day >= dysize(d1+1900); d1++)
			day -= dysize(d1+1900);
	else
		for (d1 = 70; day < 0; d1--)
			day += dysize(d1+1900-1);
	xtime.year = d1;
	d0 := day;
	xtime.yday = d0;

	# generate month
	if(dysize(d1+1900) == 366)
		dmsz := ldmsize;
	else
		dmsz = dmsize;
	for(d1 = 0; d0 >= dmsz[d1]; d1++)
		d0 -= dmsz[d1];
	xtime.mday = d0 + 1;
	xtime.mon = d1;
	xtime.zone = "GMT";
	xtime.tzoff = 0;
	return xtime;
}

wkday := array[] of {
	"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
};

weekday := array[] of {
	"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
};

month := array[] of {
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
};

text(t: ref Tm): string
{
	if(sys == nil)
		sys = load Sys Sys->PATH;

	year := 1900+t.year;

	return sys->sprint("%s %s %.2d %.2d:%.2d:%.2d %s %d",
		wkday[t.wday],
		month[t.mon],
		t.mday,
		t.hour,
		t.min,
		t.sec,
		t.zone,
		year);
}

filet(now: int, file: int): string
{
	if(sys == nil)
		sys = load Sys Sys->PATH;

	t := local(file);
	if(now - file < 6*30*24*3600)
		return sys->sprint("%s %.2d %.2d:%.2d",
			month[t.mon], t.mday, t.hour, t.min);

	year := 1900+t.year;

	return sys->sprint("%s %.2d  %d", month[t.mon], t.mday, year);
}

dysize(y: int): int
{
	if(y%4 == 0 && (y%100 != 0 || y%400 == 0))
		return 366;
	return 365;
}

readtimezone(fname: string): ref Timezone
{
	if(sys == nil)
		sys = load Sys Sys->PATH;

	tz := ref Timezone;
	tz.stdiff = 0;
	tz.stname = "GMT";

	fd: ref Sys->FD;
	if(fname == nil){
		fd = sys->open("/env/timezone", Sys->OREAD);
		if(fd == nil)
			fd = sys->open("/locale/timezone", Sys->OREAD);
	}else
		fd = sys->open("/locale/" + fname, sys->OREAD);
	if(fd == nil)
		return tz;
	buf := array[2048] of byte;
	cnt := sys->read(fd, buf, len buf);
	if(cnt <= 0)
		return tz;

	(n, val) := sys->tokenize(string buf[0:cnt], "\t \n\r");
	if(n < 4)
		return tz;

	tz.stname = hd val;
	val = tl val;
	tz.stdiff = int hd val;
	val = tl val;
	tz.dlname = hd val;
	val = tl val;
	tz.dldiff = int hd val;
	val = tl val;

	tz.dlpairs = array[n-4] of {* => 0};
	for(j := 0; val != nil; val = tl val)
		tz.dlpairs[j++] = int hd val;
	return tz;
}

SEC2MIN:	con 60;
SEC2HOUR:	con 60*SEC2MIN;
SEC2DAY:	con 24*SEC2HOUR;

tm2epoch(tm: ref Tm): int
{
	secs := 0;

	#
	#  seconds per year
	#
	yr := tm.year + 1900;
	if(yr < 1970)
		for(i := yr; i < 1970; i++)
			secs -= dysize(i) * SEC2DAY;
	else
		for(i = 1970; i < yr; i++)
			secs += dysize(i) * SEC2DAY;
	#
	#  seconds per month
	#
	if(dysize(yr) == 366)
		dmsz := ldmsize;
	else
		dmsz = dmsize;
	for(i = 0; i < tm.mon; i++)
		secs += dmsz[i] * SEC2DAY;

	#
	# secs in last month
	#
	secs += (tm.mday-1) * SEC2DAY;

	#
	# hours, minutes, seconds
	#
	secs += tm.hour * SEC2HOUR;
	secs += tm.min * SEC2MIN;
	secs += tm.sec;

	#
	#  time zone offset includes daylight savings time
	#
	return secs - tm.tzoff;
}

# handle three formats (we'll be a bit more tolerant)
#  Sun, 06 Nov 1994 08:49:37 TZ  (rfc822+rfc1123)
#  Sunday, 06-Nov-94 08:49:37 TZ (rfc850, obsoleted by rfc1036)
#  Sun Nov  6 08:49:37 1994	 (ANSI C's asctime() format, assume GMT)
#
# return nil on parsing error
#
string2tm(date: string): ref Tm
{
	buf: string;
	ok: int;
	tm := ref Tm;

	if(S == nil)
		S = load String String->PATH;

	# Weekday|Wday
	(date, buf) = dateword(date);
	tm.wday = strlookup(wkday, buf);
	if(tm.wday < 0)
		tm.wday = strlookup(weekday, buf);
	if(tm.wday < 0)
		return nil;

	# Try Mon
	odate := date;
	(date, buf) = dateword(date);
	tm.mon = strlookup(month, buf);
	if(tm.mon >= 0) {
		# Mon was OK, so asctime() format
		# DD
		(date, tm.mday) = datenum(date);
		if(tm.mday < 1 || tm.mday > 31)
			return nil;

		# HH:MM:SS
		(ok, date) = hhmmss(date, tm);
		if(!ok)
			return nil;

		# optional time zone
		while(date != nil && date[0] == ' ')
			date = date[1:];
		if(date != nil && !(date[0] >= '0' && date[0] <= '9')){
			for(i := 0; i < len date; i++)
				if(date[i] == ' '){
					(tm.zone, tm.tzoff) = tzinfo(date[0: i]);
					date = date[i:];
					break;
				}
		}

		# YY|YYYY
		(nil, tm.year) = datenum(date);
		if(tm.year > 1900)
			tm.year -= 1900;
		if(tm.zone == ""){
			tm.zone = "GMT";
			tm.tzoff = 0;
		}
	} else {
		# Mon was not OK
		date = odate;
		# DD Mon YYYY or DD-Mon-(YY|YYYY)
		(date, tm.mday) = datenum(date);
		if(tm.mday < 1 || tm.mday > 31)
			return nil;
		(date, buf) = dateword(date);
		tm.mon = strlookup(month, buf);
		if(tm.mon < 0 || tm.mon >= 12)
			return nil;
		(date, tm.year) = datenum(date);
		if(tm.year > 1900)
			tm.year -= 1900;

		# HH:MM:SS
		(ok, buf) = hhmmss(date, tm);
		if(!ok)
			return nil;
		(tm.zone, tm.tzoff) = tzinfo(buf);
		if(tm.zone == "")
			return nil;
	}

	return tm;
}

dateword(date: string): (string, string)
{
	notalnum: con "^A-Za-z0-9";

	date = S->drop(date, notalnum);
	(w, rest) := S->splitl(date, notalnum);
	return (rest, w);
}

datenum(date: string): (string, int)
{
	notdig: con "^0-9";

	date = S->drop(date, notdig);
	(num, rest) := S->splitl(date, notdig);
	return (rest, int num);
}

strlookup(a: array of string, s: string): int
{
	n := len a;
	for(i := 0; i < n; i++) {
		if(s == a[i])
			return i;
	}
	return -1;
}

hhmmss(date: string, tm: ref Tm): (int, string)
{
	err := (0, "");

	(date, tm.hour) = datenum(date);
	if(tm.hour < 0 || tm.hour >= 24)
		return err;
	(date, tm.min) = datenum(date);
	if(tm.min < 0 || tm.min >= 60)
		return err;
	(date, tm.sec) = datenum(date);
	if(tm.sec < 0 || tm.sec >= 60)
		return err;

	return (1, date);
}

tzinfo(tz: string): (string, int)
{
	# strip leading and trailing whitespace
	WS: con " \t";
	tz = S->drop(tz, WS);
	for(n := len tz; n > 0; n--) {
		if(S->in(tz[n-1], WS) == 0)
			break;
	}
	if(n < len tz)
		tz = tz[:n];

	# if no timezone, default to GMT
	if(tz == nil)
		return ("GMT", 0);

	# GMT aliases
	case tz {
	"GMT" or
	"UT" or
	"UTC" or
	"Z" =>
		return ("GMT", 0);
	}

	# [+-]hhmm (hours and minutes offset from GMT)
	if(len tz == 5 && (tz[0] == '+' || tz[0] == '-')) {
		h := int tz[1:3];
		m := int tz[3:5];
		if(h > 23 || m > 59)
			return ("", 0);
		tzoff := h*SEC2HOUR + m*SEC2MIN;
		if(tz[0] == '-')
			tzoff = -tzoff;
		return ("GMT", tzoff);
	}

	# try continental US timezones
	filename: string;
	case tz {
	"CST" or "CDT" =>
		filename = "CST.CDT";
	"EST" or "EDT" =>
		filename = "EST.EDT";
	"MST" or "MDT" =>
		filename = "MST.MDT";
	"PST" or "PDT" =>
		filename = "PST.PDT";
	* =>
		;	# default to local timezone
	}
	tzdata := readtimezone(filename);
	if(tzdata.stname == tz)
		return (tzdata.stname, tzdata.stdiff);
	if(tzdata.dlname == tz)
		return (tzdata.dlname, tzdata.dldiff);

	return ("", 0);
}
