implement Fslib;

#
# Copyright © 2003 Vita Nuova Holdings Limited
#

include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "fslib.m";

# Fsdata stream conventions:
# 
# Fsdata: adt {
#	dir: ref Sys->Dir;
#	data: array of byte;
# };
# Fschan: type chan of (Fsdata, chan of int);
# c: Fschan;
# 
# a stream of values sent on c represent the contents of a directory
# hierarchy. after each value has been received, the associated reply
# channel must be used to prompt the sender how next to proceed.
# 
# the first item sent on an fsdata channel represents the root directory
# (it must be a directory), and its name holds the full path of the
# hierarchy that's being transferred.  the items that follow represent
# the contents of the root directory.
# 
# the set of valid sequences of values can be described by a yacc-style
# grammar, where the terminal tokens describe data values (Fsdata adts)
# passed down the channel.  this grammar describes the case where the
# entire fs tree is traversed in its entirety:
# 
# dir:	DIR dircontents NIL
# 	|	DIR NIL
# dircontents: entry
# 	|	dircontents entry
# entry: FILE filecontents NIL
# 	| FILE NIL
# 	| dir
# filecontents: DATA
# 	| filecontents DATA
# 
# the tests for the various terminal token types, given a token (of type
# Fsdata) t:
# 
# 	FILE		t.dir != nil && (t.dir.mode & Sys->DMDIR) == 0
# 	DIR		t.dir != nil && (t.dir.mode & Sys->DMDIR)
# 	DATA	t.data != nil
# 	NIL		t.data == nil && t.dir == nil
# 
# when a token is received, there are four possible replies:
# 	Quit
# 		terminate the stream immediately.  no more tokens will
# 		be on the channel.
# 
# 	Down
# 		descend one level in the hierarchy, if possible.  the next tokens
# 		will represent the contents of the current entry.
# 
# 	Next
# 		get the next entry in a directory, or the next data
# 		block in a file, or travel one up the hierarchy if
#		it's the last entry or data block in that directory or file.
# 
# 	Skip
# 		skip to the end of a directory or file's contents.
#		if we're already at the end, this is a no-op (same as Next)
# 
# grammar including replies is different.  a token is the tuple (t, reply),
# where reply is the value that was sent over the reply channel.  Quit
# always causes the grammar to terminate, so it is omitted for clarity.
# thus there are 12 possible tokens (DIR_DOWN, DIR_NEXT, DIR_SKIP, FILE_DOWN, etc...)
#
# dir: DIR_DOWN dircontents NIL_NEXT
# 	| DIR_DOWN dircontents NIL_SKIP
# 	| DIR_DOWN dircontents NIL_DOWN
# 	| DIR_NEXT
# dircontents:
# 	| FILE_SKIP
# 	| DIR_SKIP
# 	| file dircontents
# 	| dir dircontents
# file: FILE_DOWN filecontents NIL_NEXT
# 	| FILE_DOWN filecontents NIL_SKIP
# 	| FILE_DOWN filecontents NIL_DOWN
# 	| FILE_NEXT
# filecontents:
# 	| data
# 	| data DATA_SKIP
# data: DATA_NEXT
# 	| data DATA_NEXT
# 
# both the producer and consumer of fs data on the channel must between
# them conform to the second grammar. if a stream of fs data
# is sent with no reply channel, the stream must conform to the first grammar.

valuec := array[] of {
	tagof(Value.V) => 'v',
	tagof(Value.X) => 'x',
	tagof(Value.P) => 'p',
	tagof(Value.S) => 's',
	tagof(Value.C) => 'c',
	tagof(Value.T) => 't',
	tagof(Value.M) => 'm',
};

init()
{
	sys = load Sys Sys->PATH;
}

# copy the contents (not the entry itself) of a directory from src to dst.
copy(src, dst: Fschan): int
{
	indent := 1;
	myreply := chan of int;
	for(;;){
		(d, reply) := <-src;
		dst <-= (d, myreply);
		r := <-myreply;
		case reply <-= r {
		Quit =>
			return Quit;
		Next =>
			if(d.dir == nil && d.data == nil)
				if(--indent == 0)
					return Next;
		Skip =>
			if(--indent == 0)
				return Next;
		Down =>
			if(d.dir != nil || d.data != nil)
				indent++;
		}
	}
}

Report.new(): ref Report
{
	r := ref Report(chan of string, chan of (string, chan of string), chan of int);
	spawn reportproc(r.startc, r.enablec, r.reportc);
	return r;
}

Report.start(r: self ref Report, name: string): chan of string
{
	if(r == nil)
		return nil;
	errorc := chan of string;
	r.startc <-= (name, errorc);
	return errorc;
}

Report.enable(r: self ref Report)
{
	r.enablec <-= 0;
}

reportproc(startc: chan of (string, chan of string), startreports: chan of int, errorc: chan of string)
{
	realc := array[2] of chan of string;
	p := array[len realc] of string;
	a := array[0] of chan of string;;

	n := 0;
	for(;;) alt{
	(prefix, c) := <-startc =>
		if(n == len realc){
			realc = (array[n * 2] of chan of string)[0:] = realc;
			p = (array[n * 2] of string)[0:] = p;
		}
		realc[n] = c;
		p[n] = prefix;
		n++;
	<-startreports =>
		if(n == 0){
			errorc <-= nil;
			exit;
		}
		a = realc;
	(x, report) := <-a =>
		if(report == nil){
#			errorc <-= "exit " + p[x];
			--n;
			if(n != x){
				a[x] = a[n];
				a[n] = nil;
				p[x] = p[n];
				p[n] = nil;
			}
			if(n == 0){
				errorc <-= nil;
				exit;
			}
		}else if(a == realc)
			errorc <-= p[x] + ": " + report;
	}
}

type2s(c: int): string
{
	case c{
	'a' =>
		return "any";
	'x' =>
		return "fs";
	's' =>
		return "string";
	'v' =>
		return "void";
	'p' =>
		return "gate";
	'c' =>
		return "command";
	't' =>
		return "entries";
	'm' =>
		return "selector";
	* =>
		return sys->sprint("unknowntype('%c')", c);
	}
}

typeerror(tc: int, v: ref Value): string
{
	sys->fprint(sys->fildes(2), "fs: bad type conversion, expected %s, was actually %s\n", type2s(tc), type2s(valuec[tagof v]));
	return "type conversion error";
}

Value.t(v: self ref Value): ref Value.T
{
	pick xv :=v {T => return xv;}
	raise typeerror('t', v);
}
Value.c(v: self ref Value): ref Value.C
{
	pick xv :=v {C => return xv;}
	raise typeerror('c', v);
}
Value.s(v: self ref Value): ref Value.S
{
	pick xv :=v {S => return xv;}
	raise typeerror('s', v);
}
Value.p(v: self ref Value): ref Value.P
{
	pick xv :=v {P => return xv;}
	raise typeerror('p', v);
}
Value.x(v: self ref Value): ref Value.X
{
	pick xv :=v {X => return xv;}
	raise typeerror('x', v);
}
Value.v(v: self ref Value): ref Value.V
{
	pick xv :=v {V => return xv;}
	raise typeerror('v', v);
}
Value.m(v: self ref Value): ref Value.M
{
	pick xv :=v {M => return xv;}
	raise typeerror('m', v);
}

Value.typec(v: self ref Value): int
{
	return valuec[tagof v];
}

Value.discard(v: self ref Value)
{
	if(v == nil)
		return;
	pick xv := v {
	X =>
		(<-xv.i).t1 <-= Quit;
	P =>
		xv.i <-= (Nilentry, nil);
	M =>
		xv.i <-= (nil, nil, nil);
	V =>
		xv.i <-= 0;
	T =>
		xv.i.sync <-= 0;
	}
}

sendnulldir(c: Fschan): int
{
	reply := chan of int;
	c <-= ((ref Sys->nulldir, nil), reply);
	if((r := <-reply) == Down){
		c <-= ((nil, nil), reply);
		if(<-reply != Quit)
			return Quit;
		return Next;
	}
	return r;
}

quit(errorc: chan of string)
{
	if(errorc != nil)
		errorc <-= nil;
	exit;
}

report(errorc: chan of string, err: string)
{
	if(errorc != nil)
		errorc <-= err;
}

# true if a module with type sig t1 is compatible with a caller that expects t0
typecompat(t0, t1: string): int
{
	(rt0, at0, ot0) := splittype(t0);
	(rt1, at1, ot1) := splittype(t1);
	if((rt0 != rt1 && rt0 != 'a') || at0 != at1)		# XXX could do better for repeated args.
		return 0;
	for(i := 1; i < len ot0; i++){
		for(j := i; j < len ot0; j++)
			if(ot0[j] == '-')
				break;
		(ok, t) := opttypes(ot0[i], ot1);
		if(ok == -1 || ot0[i:j] != t)
			return 0;
		i = j + 1;
	}
	return 1;
}

splittype(t: string): (int, string, string)
{
	if(t == nil)
		return (-1, nil, nil);
	for(i := 1; i < len t; i++)
		if(t[i] == '-')
			break;
	return (t[0], t[1:i], t[i:]);
}

opttypes(opt: int, opts: string): (int, string)
{
	for(i := 1; i < len opts; i++){
		if(opts[i] == opt && opts[i-1] == '-'){
			for(j := i+1; j < len opts; j++)
				if(opts[j] == '-')
					break;
			return (0, opts[i+1:j]);
		}
	}
	return (-1, nil);
}

cmdusage(s, t: string): string
{
	if(s == nil)
		return nil;
	for(oi := 0; oi < len t; oi++)
		if(t[oi] == '-')
			break;
	if(oi < len t){
		single, multi: string;
		for(i := oi; i < len t - 1;){
			for(j := i + 1; j < len t; j++)
				if(t[j] == '-')
					break;

			optargs := t[i+2:j];
			if(optargs == nil)
				single[len single] = t[i+1];
			else{
				multi += sys->sprint(" [-%c", t[i+1]);
				for (k := 0; k < len optargs; k++)
					multi += " " + type2s(optargs[k]);
				multi += "]";
			}
			i = j;
		}
		if(single != nil)
			s += " [-" + single + "]";
		s += multi;
	}
	multi := 0;
	if(oi > 2 && t[oi - 1] == '*'){
		multi = 1;
		oi -= 2;
	}
	for(k := 1; k < oi; k++)
		s += " " + type2s(t[k]);
	if(multi)
		s += " [" + type2s(t[k]) + "...]";
	s += " -> " + type2s(t[0]);
	return s;
}
