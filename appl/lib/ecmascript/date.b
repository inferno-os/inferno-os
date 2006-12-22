# the Date object is founded on the Daytime module

UTC: con 1;
msPerSec: con big 1000;

# based on Daytime->Tm with big fields
bigTm: adt {
	ms:	big;
	sec:	big;
	min:	big;
	hour:	big;
	mday:	big;
	mon:	big;
	year:	big;
	tzoff:	int;
};

isfinite(r: real): int
{
	if(math->isnan(r) || r == +Infinity || r == -Infinity)
		return 0;
	return 1;
}

time2Tm(t: real, utc: int): ref Daytime->Tm
{
	secs := int(big t / msPerSec);
	if(big t % msPerSec < big 0)	# t<0?
		secs -= 1;
	if(utc)
		tm := daytime->gmt(secs);
	else
		tm = daytime->local(secs);
	return tm;
}

time2bigTm(t: real, utc: int): ref bigTm
{
	tm := time2Tm(t, utc);
	btm := ref bigTm;
	btm.ms = big t % msPerSec;
	if(btm.ms < big 0)
		btm.ms += msPerSec;
	btm.sec = big tm.sec;
	btm.min = big tm.min;
	btm.hour = big tm.hour;
	btm.mday = big tm.mday;
	btm.mon = big tm.mon;
	btm.year = big tm.year;
	btm.tzoff = tm.tzoff;
	return btm;
}

bigTm2time(btm: ref bigTm): real
{
	# normalize
	if(btm.mon / big 12 != big 0){
		btm.year += btm.mon / big 12;
		btm.mon %= big 12;
	}
	if(btm.ms / msPerSec != big 0){
		btm.sec += btm.ms / msPerSec;
		btm.ms %= msPerSec;
	}
	if(btm.sec / big 60 != big 0){
		btm.min += btm.sec / big 60;
		btm.sec %= big 60;
	}
	if(btm.min / big 60 != big 0){
		btm.hour += btm.hour / big 60;
		btm.min %= big 60;
	}
	if(btm.hour / big 24 != big 0){
		btm.mday += btm.mday / big 24;
		btm.hour %= big 24;
	}

	tm := ref Tm;
	tm.sec = int btm.sec;
	tm.min = int btm.min;
	tm.hour = int btm.hour;
	tm.mday = int btm.mday;
	tm.mon = int btm.mon;
	tm.year = int btm.year;
	tm.tzoff = btm.tzoff;
	secs := daytime->tm2epoch(tm);
	# check for out-of-band times
	if(secs == daytime->tm2epoch(daytime->gmt(secs)))
		r := real(big secs * msPerSec + btm.ms);
	else
		r = Math->NaN;
	return r;
}

str2time(s: string): real
{
	tm := daytime->string2tm(s);
	if(tm == nil)
		r := Math->NaN;
	else
		r = real (big daytime->tm2epoch(tm) * msPerSec);
	return r;
}

cdate(nil: ref Exec, nil, nil: ref Ecmascript->Obj, nil: array of ref Val): ref Val
{
	return strval(daytime->time());
}

# process arguments of Date() [called as constructor] and Date.UTC()
datectorargs(ex: ref Exec, args: array of ref Val): (int, ref bigTm)
{
	x := array[7] of { * => big 0 };
	ok := 1;
	for(i := 0; i < 7 && i < len args; i++){
		if(!isfinite(toNumber(ex, biarg(args, i))))
			ok = 0;
		else
			x[i] = big toInteger(ex, biarg(args, i));
	}
	btm := ref bigTm;
	yr := x[0];
	if(yr >= big 0 && yr <= big 99)
		btm.year = yr;
	else
		btm.year = yr - big 1900;
	btm.mon = x[1];
	btm.mday = x[2];
	btm.hour = x[3];
	btm.min = x[4];
	btm.sec = x[5];
	btm.ms = x[6];
	return (ok, btm);
}

ndate(ex: ref Exec, nil: ref Ecmascript->Obj, args: array of ref Val): ref Ecmascript->Obj
{
	o := mkobj(ex.dateproto, "Date");
	r := Math->NaN;
	case len args{
	0 =>
		r = real(big daytime->now() * msPerSec);
	1 =>
		v := toPrimitive(ex, biarg(args, 0), NoHint);
		if(isstr(v))
			r = str2time(v.str);
		else if(isfinite(toNumber(ex, v))){
			t := big toInteger(ex, v);
			secs := t / msPerSec;
			if(big t % msPerSec < big 0)
				secs -= big 1;
			if(secs == big int secs)
				r = real t;
		}
	* =>
		(ok, btm) := datectorargs(ex, args);
		if(ok){
			tm := daytime->local(daytime->now());
			btm.tzoff = tm.tzoff;
			r = bigTm2time(btm);
		}
	}
	o.val = numval(r);
	return o;
}

cdateparse(ex: ref Exec, nil, nil: ref Ecmascript->Obj, args: array of ref Val): ref Val
{
	s := toString(ex, biarg(args, 0));
	return numval(str2time(s));
}

cdateUTC(ex: ref Exec, nil, nil: ref Ecmascript->Obj, args: array of ref Val): ref Val
{
	r := Math->NaN;
	if(len args == 0)
		r = real(big daytime->now() * msPerSec);
	else{
		(ok, btm) := datectorargs(ex, args);
		if(ok){
			btm.tzoff = 0;
			r = bigTm2time(btm);
		}
	}
	return numval(r);
}

datecheck(ex: ref Exec, o: ref Ecmascript->Obj, f: string)
{
	if(!isdateobj(o))
		runtime(ex, TypeError, "Date.prototype." + f + " called on non-Date object");
}

cdateprototoString(ex: ref Exec, f, this: ref Ecmascript->Obj, nil: array of ref Val): ref Val
{
	datecheck(ex, this, f.val.str);
	secs := 0;
	t := this.val.num;
	if(!math->isnan(t)){
		secs = int(big t / msPerSec);
		if(big t % msPerSec < big 0)
			secs -= 1;
	}
	return strval(daytime->text(daytime->local(secs)));
}

cdateprototoDateString(ex: ref Exec, f, this: ref Ecmascript->Obj, nil: array of ref Val): ref Val
{
	datecheck(ex, this, f.val.str);
	secs := 0;
	t := this.val.num;
	if(!math->isnan(t)){
		secs = int(big t / msPerSec);
		if(big t % msPerSec < big 0)
			secs -= 1;
	}
	s := daytime->text(daytime->local(secs));
	(n, ls) := sys->tokenize(s, " ");
	if(n < 3)
		return strval("");
	return strval(hd ls + " " + hd tl ls + " " + hd tl tl ls);
}

cdateprototoTimeString(ex: ref Exec, f, this: ref Ecmascript->Obj, nil: array of ref Val): ref Val
{
	datecheck(ex, this, f.val.str);
	secs := 0;
	t := this.val.num;
	if(!math->isnan(t)){
		secs = int(big t / msPerSec);
		if(big t % msPerSec < big 0)
			secs -= 1;
	}
	s := daytime->text(daytime->local(secs));
	(n, ls) := sys->tokenize(s, " ");
	if(n < 4)
		return strval("");
	return strval(hd tl tl tl ls);
}

cdateprotovalueOf(ex: ref Exec, f, this: ref Ecmascript->Obj, nil: array of ref Val): ref Val
{
	datecheck(ex, this, f.val.str);
	return this.val;
}

cdateprotoget(ex: ref Exec, f, this: ref Ecmascript->Obj, nil: array of ref Val, utc: int): ref Val
{
	datecheck(ex, this, f.val.str);
	t := this.val.num;
	if(!math->isnan(t)){
		tm := time2Tm(t, utc);
		case f.val.str{
		"Date.prototype.getYear" =>
			if (tm.year < 0 || tm.year > 99)
				t = real(tm.year + 1900);
			else
				t = real tm.year;
		"Date.prototype.getFullYear" or
		"Date.prototype.getUTCFullYear" =>
			t = real(tm.year + 1900);
		"Date.prototype.getMonth" or
		"Date.prototype.getUTCMonth" =>
			t = real tm.mon;
		"Date.prototype.getDate" or
		"Date.prototype.getUTCDate" =>
			t = real tm.mday;
		"Date.prototype.getDay" or
		"Date.prototype.getUTCDay" =>
			t = real tm.wday;
		"Date.prototype.getHours" or
		"Date.prototype.getUTCHours" =>
			t = real tm.hour;
		"Date.prototype.getMinutes" or
		"Date.prototype.getUTCMinutes" =>
			t = real tm.min;
		"Date.prototype.getSeconds" or
		"Date.prototype.getUTCSeconds" =>
			t = real tm.sec;
		}
	}
	return numval(t);
}

cdateprotogetMilliseconds(ex: ref Exec, f, this: ref Ecmascript->Obj, nil: array of ref Val): ref Val
{
	datecheck(ex, this, f.val.str);
	t := this.val.num;
	if(!math->isnan(t)){
		ms := big t % msPerSec;
		if(ms < big 0)
			ms += msPerSec;
		t = real ms;
	}
	return numval(t);
}

cdateprotogetTimezoneOffset(ex: ref Exec, f, this: ref Ecmascript->Obj, nil: array of ref Val): ref Val
{
	datecheck(ex, this, f.val.str);
	t := this.val.num;
	if(!math->isnan(t)){
		tm := time2Tm(t, !UTC);
		t = real(tm.tzoff / 60);
	}
	return numval(t);
}

# process arguments of Date.prototype.set*() functions
dateprotosetargs(ex: ref Exec, this: ref Ecmascript->Obj, args: array of ref Val, n: int): (int, big, big, big, big)
{
	x := array[4] of { * => big 0 };
	ok := 1;
	if(this != nil && !isfinite(this.val.num))
		ok = 0;
	for(i := 0; i < n && i < len args; i++){
		if(!isfinite(toNumber(ex, biarg(args, i))))
			ok = 0;
		else
			x[i] = big toInteger(ex, biarg(args, i));
	}
	return (ok, x[0], x[1], x[2], x[3]);
}

cdateprotosetTime(ex: ref Exec, f, this: ref Ecmascript->Obj, args: array of ref Val): ref Val
{
	datecheck(ex, this, f.val.str);
	r := Math->NaN;
	(ok, t, nil, nil, nil) := dateprotosetargs(ex, nil, args, 1);
	if(ok){
		secs := t / msPerSec;
		if(big t % msPerSec < big 0)
			secs -= big 1;
		if(secs == big int secs)
			r = real t;
	}
	this.val.num = r;
	return numval(r);
}

cdateprotosetMilliseconds(ex: ref Exec, f, this: ref Ecmascript->Obj, args: array of ref Val, utc: int): ref Val
{
	datecheck(ex, this, f.val.str);
	r := Math->NaN;
	(ok, ms, nil, nil, nil) := dateprotosetargs(ex, this, args, 1);
	if(ok){
		btm := time2bigTm(this.val.num, utc);
		btm.ms = ms;
		r = bigTm2time(btm);
	}
	this.val.num = r;
	return numval(r);
}

cdateprotosetSeconds(ex: ref Exec, f, this: ref Ecmascript->Obj, args: array of ref Val, utc: int): ref Val
{
	datecheck(ex, this, f.val.str);
	r := Math->NaN;
	(ok, sec, ms, nil, nil) := dateprotosetargs(ex, this, args, 2);
	if(ok){
		btm := time2bigTm(this.val.num, utc);
		btm.sec = sec;
		if(len args > 1)
			btm.ms = ms;
		r = bigTm2time(btm);
	}
	this.val.num = r;
	return numval(r);
}

cdateprotosetMinutes(ex: ref Exec, f, this: ref Ecmascript->Obj, args: array of ref Val, utc: int): ref Val
{
	datecheck(ex, this, f.val.str);
	r := Math->NaN;
	(ok, min, sec, ms, nil) := dateprotosetargs(ex, this, args, 3);
	if(ok){
		btm := time2bigTm(this.val.num, utc);
		btm.min = min;
		if(len args > 1){
			btm.sec = sec;
			if(len args > 2)
				btm.ms = ms;
		}
		r = bigTm2time(btm);
	}
	this.val.num = r;
	return numval(r);
}

cdateprotosetHours(ex: ref Exec, f, this: ref Ecmascript->Obj, args: array of ref Val, utc: int): ref Val
{
	datecheck(ex, this, f.val.str);
	r := Math->NaN;
	(ok, hour, min, sec, ms) := dateprotosetargs(ex, this, args, 4);
	if(ok){
		btm := time2bigTm(this.val.num, utc);
		btm.hour = hour;
		if(len args > 1){
			btm.min = min;
			if(len args > 2){
				btm.sec = sec;
				if(len args > 3)
					btm.ms = ms;
			}
		}
		r = bigTm2time(btm);
	}
	this.val.num = r;
	return numval(r);
}

cdateprotosetDate(ex: ref Exec, f, this: ref Ecmascript->Obj, args: array of ref Val, utc: int): ref Val
{
	datecheck(ex, this, f.val.str);
	r := Math->NaN;
	(ok, day, nil, nil, nil) := dateprotosetargs(ex, this, args, 1);
	if(ok){
		btm := time2bigTm(this.val.num, utc);
		btm.mday = day;
		r = bigTm2time(btm);
	}
	this.val.num = r;
	return numval(r);
}

cdateprotosetMonth(ex: ref Exec, f, this: ref Ecmascript->Obj, args: array of ref Val, utc: int): ref Val
{
	datecheck(ex, this, f.val.str);
	r := Math->NaN;
	(ok, mon, day, nil, nil) := dateprotosetargs(ex, this, args, 2);
	if(ok){
		btm := time2bigTm(this.val.num, utc);
		btm.mon = mon;
		if(len args > 1)
			btm.mday = day;
		r = bigTm2time(btm);
	}
	this.val.num = r;
	return numval(r);
}

cdateprotosetFullYear(ex: ref Exec, f, this: ref Ecmascript->Obj, args: array of ref Val, utc: int): ref Val
{
	datecheck(ex, this, f.val.str);
	r := Math->NaN;
	(ok, year, mon, day, nil) := dateprotosetargs(ex, nil, args, 3);
	if(ok){
		t := this.val.num;
		if(!isfinite(t))
			t = 0.;
		btm := time2bigTm(t, utc);
		btm.year = (year - big 1900);
		if(len args > 1){
			btm.mon = mon;
			if(len args > 2)
				btm.mday = day;
		}
		r = bigTm2time(btm);
	}
	this.val.num = r;
	return numval(r);
}

cdateprotosetYear(ex: ref Exec, f, this: ref Ecmascript->Obj, args: array of ref Val): ref Val
{
	datecheck(ex, this, f.val.str);
	r := Math->NaN;
	(ok, year, nil, nil, nil) := dateprotosetargs(ex, nil, args, 1);
	if(ok){
		t := this.val.num;
		if(!isfinite(t))
			t = 0.;
		btm := time2bigTm(t, !UTC);
		if(year >= big 0 && year <= big 99)
			btm.year = year;
		else
			btm.year = year - big 1900;
		r = bigTm2time(btm);
	}
	this.val.num = r;
	return numval(r);
}

cdateprototoUTCString(ex: ref Exec, f, this: ref Ecmascript->Obj, nil: array of ref Val): ref Val
{
	datecheck(ex, this, f.val.str);
	secs := 0;
	t := this.val.num;
	if(!math->isnan(t)){
		secs = int(big t / msPerSec);
		if(big t % msPerSec < big 0)
			secs -= 1;
	}
	return strval(daytime->text(daytime->gmt(secs)));
}
