implement Mashbuiltin;

#
#	"history" builtin, defines:
#

include	"mash.m";
include	"mashparse.m";

mashlib:	Mashlib;
chanfill:	ChanFill;

Env:		import mashlib;
sys, bufio:	import mashlib;

Iobuf:	import bufio;

Hcmd: adt
{
	seek:	int;
	text:	array of byte;
};

Reader: adt
{
	fid:	int;
	offset:	int;
	hint:	int;
	next:	cyclic ref Reader;
};

history:	array of ref Hcmd;
lhist:		int;
nhist:		int;
seek:		int;
readers:	ref Reader;
eof :=		array[0] of byte;

#
#	Interface to catch the use as a command.
#
init(nil: ref Draw->Context, args: list of string)
{
	raise "fail: " + hd args + " not loaded";
}

#
#	Used by whatis.
#
name(): string
{
	return "history";
}

#
#	Install commands.
#
mashinit(nil: list of string, lib: Mashlib, nil: Mashbuiltin, e: ref Env)
{
	mashlib = lib;
	if (mashlib->histchan != nil)
		return;
	mashlib->startserve = 1;
	nhist = 0;
	lhist = 256;
	history = array[lhist] of ref Hcmd;
	seek = 0;
	(f, c) := e.servefile(mashlib->HISTF);
	spawn servehist(f, c);
	(f, c) = e.servefile(mashlib->MASHF);
	spawn servemash(f, c);
}

mashcmd(nil: ref Env, nil: list of string)
{
}

addhist(b: array of byte)
{
	if (nhist == lhist) {
		n := 3 * nhist / 4;
		part := history[:n];
		part[:] = history[nhist - n:];
		nhist = n;
	}
	history[nhist] = ref Hcmd(seek, b);
	nhist++;
	seek += len b;
}

getfid(fid: int, del: int): ref Reader
{
	prev: ref Reader;
	for (r := readers; r != nil; r = r.next) {
		if (r.fid == fid) {
			if (del) {
				if (prev == nil)
					readers = r.next;
				else
					prev.next = r.next;
				return nil;
			}
			return r;
		}
		prev = r;
	}
	o := 0;
	if (nhist > 0)
		o = history[0].seek;
	return readers = ref Reader(fid, o, 0, readers);
}

readhist(off, count, fid: int): (array of byte, string)
{
	r := getfid(fid, 0);
	off += r.offset;
	if (nhist == 0 || off >= seek)
		return (eof, nil);
	i := r.hint;
	if (i >= nhist)
		i = nhist - 1;
	s := history[i].seek;
	if (off == s) {
		r.hint = i + 1;
		return (history[i].text, nil);
	}
	if (off > s) {
		do {
			if (++i == nhist)
				break;
			s = history[i].seek;
		} while (off >= s);
		i--;
	} else {
		do {
			if (--i < 0)
				return (eof, "data truncated");
			s = history[i].seek;
		} while (off < s);
	}
	r.hint = i + 1;
	b := history[i].text;
	if (off != s)
		b = b[off - s:];
	return (b, nil);
}

loadhist(data: array of byte, fid: int, wc: Sys->Rwrite, c: ref Sys->FileIO)
{
	in: ref Iobuf;
	if (chanfill == nil)
		chanfill = load ChanFill ChanFill->PATH;
	if (chanfill != nil)
		in = chanfill->init(data, fid, wc, c, mashlib->bufio);
	if (in == nil) {
		in = bufio->sopen(string data);
		if (in == nil) {
			wc <-= (0, mashlib->errstr());
			return;
		}
		wc <-= (len data, nil);
	}
	while ((s := in.gets('\n')) != nil)
		addhist(array of byte s);
	in.close();
}

servehist(f: string, c: ref Sys->FileIO)
{
	mashlib->reap();
	h := chan of array of byte;
	mashlib->histchan = h;
	for (;;) {
		alt {
		b := <-h =>
			addhist(b);
		(off, count, fid, rc) := <-c.read =>
			if (rc == nil) {
				getfid(fid, 1);
				continue;
			}
			rc <-= readhist(off, count, fid);
		(off, data, fid, wc) := <-c.write =>
			if (wc != nil)
				loadhist(data, fid, wc, c);
		}
	}
}

servemash(f: string, c: ref Sys->FileIO)
{
	mashlib->reap();
	for (;;) {
		alt {
		(off, count, fid, rc) := <-c.read =>
			if (rc != nil)
				rc <-= (nil, "not supported");
		(off, data, fid, wc) := <-c.write =>
			if (wc != nil) {
				wc <-= (len data, nil);
				if (mashlib->servechan != nil && len data > 0)
					mashlib->servechan <-= data;
			}
		}
	}
}
