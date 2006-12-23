implement Date;

include "sys.m";
	sys: Sys;

include "daytime.m";
	daytime : Daytime;

Tm: import daytime;

include "date.m";

 # print dates in the format
 # Wkd, DD Mon YYYY HH:MM:SS GMT
 # parse dates of formats
 # Wkd, DD Mon YYYY HH:MM:SS GMT
 # Weekday, DD-Mon-YY HH:MM:SS GMT
 # Wkd Mon ( D|DD) HH:MM:SS YYYY
 # plus anything similar

SEC2MIN: con 60;
SEC2HOUR: con (60*SEC2MIN);
SEC2DAY: con (24*SEC2HOUR);

#  days per month plus days/year

dmsize := array[] of {
	365, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
};

ldmsize := array[] of {
	366, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
};


#  return the days/month for the given year


weekdayname := array[] of {
	"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
};

wdayname := array[] of {
	"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
};


monname := array[] of {
	"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
};

init()
{
	daytime = load Daytime Daytime->PATH;
	sys = load Sys "$Sys";
	if (daytime==nil)
		sys->print("daytime load: %r\n");
}

# internals....
dateindex : fn(nil: string, nill:array of string): int; 
gmtm2sec  : fn(tm: Tm): int;


yrsize(yr : int): array of int
{
	if(yr % 4 == 0 && (yr % 100 != 0 || yr % 400 == 0))
		return ldmsize;
	else
		return dmsize;
}

tolower(c: int): int
{
	if(c >= 'A' && c <= 'Z')
		return c - 'A' + 'a';
	return c;
}


isalpha(c: int): int
{
	return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z';
}


isdig(c: int): int
{
	return c >= '0' && c <= '9';
}


dateconv(t: int): string
{
	tm : ref Tm;
	tm = daytime->gmt(t);
	return sys->sprint("%s, %.2d %s %.4d %.2d:%.2d:%.2d GMT",
		wdayname[tm.wday], tm.mday, monname[tm.mon], tm.year+1900,
		tm.hour, tm.min, tm.sec);	
}


dateword(date : string): (string,string) {
	p : string;
	i:=0;
	p = "";
	while((i<len date) && !isalpha(date[i]) && !isdig(date[i]))
		i++;
	while((i<len date) && isalpha(date[i])){		
		p[len p] = tolower(date[i]);
		i++;
	}
	rest := "";
	if(i < len date)
		rest = date[i:];
	return (rest,p);
}


datenum(date : string): (string, int){
	n, i : int;
	i=0;
	while((i<len date) && !isdig(date[i]))
		i++;
	if(i == len date)
		return (nil, -1);
	n = 0;
	while((i<len date) && isdig(date[i])){
		n = n * 10 + date[i] - '0';
		i++;
	}
	return (date[i:], n);
}


 # parse a date and return the seconds since the epoch
 # return 0 for a failure
 
# could be big?
date2sec(date : string): int
{
	tm : Tm;
	buf : string;

	 # Weekday|Wday
	 
	(date,buf) = dateword(date);
	tm.wday = dateindex(buf, wdayname);
	if(tm.wday < 0)
		tm.wday = dateindex(buf, weekdayname);

	if(tm.wday < 0)
		return 0;

	 # check for the two major formats
	
	(date,buf) = dateword(date);
	tm.mon = dateindex(buf, monname);
	if(tm.mon >= 0){
		 # MM
		(date, tm.mday) = datenum(date);
		if(tm.mday < 1 || tm.mday > 31)
			return 0;

		 # HH:MM:SS
		(date, tm.hour) = datenum(date);
		if(tm.hour < 0 || tm.hour >= 24)
			return 0;
		(date, tm.min) = datenum(date);
		if(tm.min < 0 || tm.min >= 60)
			return 0;
		(date, tm.sec) = datenum(date);
		if(tm.sec < 0 || tm.sec >= 60)
			return 0;

		
		 # YYYY 
		(nil, tm.year) = datenum(date);
		if(tm.year < 70 || tm.year > 99 && tm.year < 1970)
			return 0;
		if(tm.year >= 1970)
			tm.year -= 1900;
	}else{
		# MM-Mon-(YY|YYYY)
		(date, tm.mday) = datenum(date);
		if(tm.mday < 1 || tm.mday > 31)
			return 0;
		(date,buf) = dateword(date);
		tm.mon = dateindex(buf, monname);
		if(tm.mon < 0 || tm.mon >= 12)
			return 0;
		(date, tm.year) = datenum(date);
		if(tm.year < 70 || tm.year > 99 && tm.year < 1970)
			return 0;
		if(tm.year >= 1970)
			tm.year -= 1900;
		
		 # HH:MM:SS
		(date, tm.hour) = datenum(date);
		if(tm.hour < 0 || tm.hour >= 24)
			return 0;
		(date, tm.min) = datenum(date);
		if(tm.min < 0 || tm.min >= 60)
			return 0;
		(date, tm.sec) = datenum(date);
		if(tm.sec < 0 || tm.sec >= 60)
			return 0;

		 # timezone
		(date,buf)=dateword(date);
		if(len buf >= 3 && lowercase(buf[0:3])!="gmt")
			return 0;
	}

	tm.zone="GMT";
	return gmtm2sec(tm);
}

lowercase(name:string): string
{
	p: string;
	for(i:=0;i<len name;i++)
		p[i]=tolower(name[i]);
	return p;
}

dateindex(d : string, tab : array of string): int
{
	for(i := 0; i < len tab; i++)
		if (lowercase(tab[i]) == d)
			return i;
	return -1;
}


# compute seconds since Jan 1 1970 GMT

gmtm2sec(tm:Tm): int 
{
	secs,i : int;
	d2m: array of int;
	sys = load Sys "$Sys";
	secs=0;

	#seconds per year
	tm.year += 1900;
	if(tm.year < 1970)
		return 0;
	for(i = 1970; i < tm.year; i++){
		d2m = yrsize(i);
		secs += d2m[0] * SEC2DAY;
	}


	#seconds per month
	d2m = yrsize(tm.year);
	for(i = 0; i < tm.mon; i++)
		secs += d2m[i+1] * SEC2DAY;

	#secs in last month
	secs += (tm.mday-1) * SEC2DAY;

	#hours, minutes, seconds	
	secs += tm.hour * SEC2HOUR;
	secs += tm.min * SEC2MIN;
	secs += tm.sec;

	return secs;
}

now(): int
{
	return daytime->now();
}
