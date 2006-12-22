implement Cal;

#
# Copyright © 1995-2002 Lucent Technologies Inc.  All rights reserved.
# Limbo transliteration 2003 by Vita Nuova
# This software is subject to the Plan 9 Open Source Licence.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "daytime.m";
	daytime: Daytime;
	Tm: import daytime;

Cal: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

dayw :=	" S  M Tu  W Th  F  S";
smon := array[] of {
	"January", "February", "March", "April",
	"May", "June", "July", "August",
	"September", "October", "November", "December",
};

mon := array[] of {
	0,
	31, 29, 31, 30,
	31, 30, 31, 31,
	30, 31, 30, 31,
};

bout: ref Iobuf;

init(nil: ref Draw->Context, args: list of string)
{
	y, m: int;

	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	daytime = load Daytime Daytime->PATH;

	argc := len args;
	if(argc > 3){
		sys->fprint(sys->fildes(2), "usage: cal [month] [year]\n");
		raise "fail:usage";
	}
	bout = bufio->fopen(sys->fildes(1), Bufio->OWRITE);

#
# no arg, print current month
#
	if(argc <= 1) {
		m = curmo();
		y = curyr();
		return xshort(m, y);
	}
	args = tl args;

#
# one arg
#	if looks like a month, print month
#	else print year
#
	if(argc == 2) {
		y = number(hd args);
		if(y < 0)
			y = -y;
		if(y >= 1 && y <= 12)
			return xshort(y, curyr());
		return xlong(y);
	}

#
# two arg, month and year
#
	m = number(hd args);
	if(m < 0)
		m = -m;
	y = number(hd tl args);
	return xshort(m, y);
}

#
#	print out just month
#
xshort(m: int, y: int)
{
	if(m < 1 || m > 12)
		badarg();
	if(y < 1 || y > 9999)
		badarg();
	bout.puts(sys->sprint("   %s %ud\n", smon[m-1], y));
	bout.puts(sys->sprint("%s\n", dayw));
	lines := cal(m, y);
	for(i := 0; i < len lines; i++){
		bout.puts(lines[i]);
		bout.putc('\n');
	}
	bout.flush();
}

#
#	print out complete year
#
xlong(y: int)
{
	if(y<1 || y>9999)
		badarg();
	bout.puts("\n\n\n");
	bout.puts(sys->sprint("                                %ud\n", y));
	bout.putc('\n');
	months := array[3] of array of string;
	for(i:=0; i<12; i+=3) {
		bout.puts(sys->sprint("         %.3s", smon[i]));
		bout.puts(sys->sprint("                    %.3s", smon[i+1]));
		bout.puts(sys->sprint("                    %.3s\n", smon[i+2]));
		bout.puts(sys->sprint("%s   %s   %s\n", dayw, dayw, dayw));
		for(j := 0; j < 3; j++)
			months[j] = cal(i+j+1, y);
		for(l := 0; l < 6; l++){
			s := "";
			for(j = 0; j < 3; j++)
				s += sys->sprint("%-20.20s   ", months[j][l]);
			for(j = len s; j > 0 && s[j-1] == ' ';)
				j--;
			bout.puts(s[0:j]);
			bout.putc('\n');
		}
	}
	bout.flush();
}

badarg()
{
	sys->fprint(sys->fildes(2), "cal: bad argument\n");
	raise "fail:bad argument";
}

dict := array[] of {
	("january",	1),
	("february",	2),
	("march",	3),
	("april",	4),
	("may",		5),
	("june",		6),
	("july",		7),
	("august",	8),
	("sept",		9),
	("september",	9),
	("october",	10),
	("november",	11),
	("december",	12),
};

#
# convert to a number.
# if its a dictionary word,
# return negative  number
#
number(s: string): int
{
	if(len s >= 3){
		for(n:=0; n < len dict; n++){
			(word, val) := dict[n];
			if(s == word || s == word[0:3])
				return -val;
		}
	}
	n := 0;
	for(i := 0; i < len s; i++){
		c := s[i];
		if(c<'0' || c>'9')
			badarg();
		n = n*10 + c-'0';
	}
	return n;
}

pstr(str: string, n: int)
{
	bout.puts(sys->sprint("%-*.*s\n", n, n, str));
}

cal(m: int, y: int): array of string
{
	d := jan1(y);
	mon[9] = 30;

	case (jan1(y+1)+7-d)%7 {

	#
	#	non-leap year
	#
	1 =>
		mon[2] = 28;

	#
	#	leap year
	#
	2 =>
		mon[2] = 29;

	#
	#	1752
	#
	* =>
		mon[2] = 29;
		mon[9] = 19;
	}
	for(i:=1; i<m; i++)
		d += mon[i];
	d %= 7;
	lines := array[6] of string;
	l := 0;
	s := "";
	for(i = 0; i < d; i++)
		s += "   ";
	for(i=1; i<=mon[m]; i++) {
		if(i==3 && mon[m]==19) {
			i += 11;
			mon[m] += 11;
		}
		s += sys->sprint("%2d", i);
		if(++d == 7) {
			d = 0;
			lines[l++] = s;
			s = "";
		}else
			s[len s] = ' ';
	}
	if(s != nil){
		while(s[len s-1] == ' ')
			s = s[:len s-1];
		lines[l] = s;
	}
	return lines;
}

#
#	return day of the week
#	of jan 1 of given year
#
jan1(y: int): int
{
#
#	normal gregorian calendar
#	one extra day per four years
#

	d := 4+y+(y+3)/4;

#
#	julian calendar
#	regular gregorian
#	less three days per 400
#

	if(y > 1800) {
		d -= (y-1701)/100;
		d += (y-1601)/400;
	}

#
#	great calendar changeover instant
#

	if(y > 1752)
		d += 3;

	return d%7;
}

#
# get current month and year
#
curmo(): int
{
	tm := daytime->local(daytime->now());
	return tm.mon+1;
}

curyr(): int
{
	tm := daytime->local(daytime->now());
	return tm.year+1900;
}
