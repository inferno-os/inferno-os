implement Styxchat;

#
# Copyright © 2002,2003 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

include "string.m";
	str: String;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "dial.m";
	dial: Dial;

include "arg.m";

Styxchat: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

msgsize := 64*1024;
nexttag := 1;
verbose := 0;

stdin: ref Sys->FD;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	styx = load Styx Styx->PATH;
	str = load String String->PATH;
	bufio = load Bufio Bufio->PATH;
	dial = load Dial Dial->PATH;
	styx->init();

	client := 1;
	addr := 0;
	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("styxchat [-nsv] [-m messagesize] [dest]");
	while((o := arg->opt()) != 0)
		case o {
		'm' =>
			msgsize = atoi(arg->earg());
		's' =>
			client = 0;
		'n' =>
			addr = 1;
		'v' =>
			verbose++;
		* =>
			arg->usage();
		}
	args = arg->argv();
	arg = nil;
	fd: ref Sys->FD;
	if(args == nil){
		fd = sys->fildes(0);
		stdin = sys->open("/dev/cons", Sys->ORDWR);
		if (stdin == nil)
			err(sys->sprint("can't open /dev/cons: %r"));
		sys->dup(stdin.fd, 1);
	}else{
		if(tl args != nil)
			arg->usage();
		stdin = sys->fildes(0);
		dest := hd args;
		if(addr){
			dest = dial->netmkaddr(dest, "net", "styx");
			if (client){
				c := dial->dial(dest, nil);
				if(c == nil)
					err(sys->sprint("can't dial %s: %r", dest));
				fd = c.dfd;
			}else{
				lc := dial->announce(dest);
				if(lc == nil)
					err(sys->sprint("can't announce %s: %r", dest));
				c := dial->listen(lc);
				if(c == nil)
					err(sys->sprint("can't listen on %s: %r", dest));
				fd = dial->accept(c);
				if(fd == nil)
					err(sys->sprint("can't open %s/data: %r", c.dir));
			}
		}else{
			fd = sys->open(dest, Sys->ORDWR);
			if(fd == nil)
				err(sys->sprint("can't open %s: %r", dest));
		}
	}
	sys->pctl(Sys->NEWPGRP, nil);
	if(client){
		spawn Rreader(fd);
		Twriter(fd);
	}else{
		spawn Treader(fd);
		Rwriter(fd);
	}
}

quit(e: int)
{
	fd := sys->open("/prog/"+string sys->pctl(0, nil)+"/ctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "killgrp");
	if(e)
		raise "fail:error";
	exit;
}

Rreader(fd: ref Sys->FD)
{
	while((m := Rmsg.read(fd, msgsize)) != nil){
		sys->print("<- %s\n%s", m.text(), Rdump(m));
		if(tagof m == tagof Rmsg.Readerror)
			quit(1);
	}
	sys->print("styxchat: server hungup\n");
}

Twriter(fd: ref Sys->FD)
{
	in := bufio->fopen(stdin, Sys->OREAD);
	while((l := in.gets('\n')) != nil){
		if(l != nil && l[0] == '#')
			continue;
		(t, err) := Tparse(l);
		if(t == nil){
			if(err != nil)
				sys->print("?%s\n", err);
		}else{
			if(t.tag == 0)
				t.tag = nexttag;
			a := t.pack();
			if(a != nil){
				sys->print("-> %s\n%s", t.text(), Tdump(t));
				n := len a;
				if(n <= msgsize){
					if(sys->write(fd, a, len a) != len a)
						sys->print("?write error to server: %r\n");
					if(t.tag != Styx->NOTAG && t.tag != ~0)
						nexttag++;
				}else
					sys->print("?message bigger than agreed: %d bytes\n", n);
			}else
				sys->fprint(sys->fildes(2), "styxchat: T-message conversion failed\n");
		}
	}
}

Rdump(m: ref Rmsg): string
{
	if(!verbose)
		return "";
	pick r :=m {
	Read =>
		return dump(r.data, len r.data, verbose>1);
	* =>
		return "";
	}
}

Tdump(m: ref Tmsg): string
{
	if(!verbose)
		return "";
	pick t := m {
	Write =>
		return dump(t.data, len t.data, verbose>1);
	* =>
		return "";
	}
}

isprint(c: int): int
{
	return c >= 16r20 && c < 16r7F || c == '\n' || c == '\t' || c == '\r';
}

textdump(a: array of byte, lim: int): string
{
	s := "\ttext(\"";
	for(i := 0; i < lim; i++)
		case c := int a[i] {
		'\t' =>
			s += "\\t";
		'\n' =>
			s += "\\n";
		'\r' =>
			s += "\\r";
		'"' =>
			s += "\\\"";
		* =>
			if(isprint(c))
				s[len s] = c;
			else
				s += sys->sprint("\\u%4.4ux", c);
		}
	s += "\")\n";
	return s;
}

dump(a: array of byte, lim: int, text: int): string
{
	if(a == nil)
		return "";
	if(len a < lim)
		lim = len a;
	printable := 1;
	for(i := 0; i < lim; i++)
		if(!isprint(int a[i])){
			printable = 0;
			break;
		}
	if(printable)
		return textdump(a, lim);
	s := "\tdump(";
	for(i = 0; i < lim; i++)
		s += sys->sprint("%2.2ux", int a[i]);
	s += ")\n";
	if(text)
		s += textdump(a, lim);
	return s;
}

val(s: string): int
{
	if(s == "~0")
		return ~0;
	return atoi(s);
}

bigval(s: string): big
{
	if(s == "~0")
		return ~ big 0;
	return atob(s);
}

fid(s: string): int
{
	if(s == "nofid" || s == "NOFID")
		return Styx->NOFID;
	return val(s);
}

tag(s: string): int
{
	if(s == "~0" || s == "notag" || s == "NOTAG")
		return Styx->NOTAG;
	return atoi(s);
}

dir(name: string, uid: string, gid: string, mode: int, mtime: int, length: big): Sys->Dir
{
	d := sys->zerodir;
	d.name = name;
	d.uid = uid;
	d.gid = gid;
	d.mode = mode;
	d.mtime = mtime;
	d.length = length;
	return d;
}

Tparse(s: string): (ref Tmsg, string)
{
	args := str->unquoted(s);
	if(args == nil)
		return (nil, nil);
	argc := len args;
	av := array[argc] of string;
	for(i:=0; args != nil; args = tl args)
		av[i++] = hd args;
	case av[0] {
	"Tversion" =>
		if(argc != 3)
			return (nil, "usage: Tversion messagesize version");
		return (ref Tmsg.Version(Styx->NOTAG, atoi(av[1]), av[2]), nil);
	"Tauth" =>
		if(argc != 4)
			return (nil, "usage: Tauth afid uname aname");
		return (ref Tmsg.Auth(0, fid(av[1]), av[2], av[3]), nil);
	"Tflush" =>
		if(argc != 2)
			return (nil, "usage: Tflush oldtag");
		return (ref Tmsg.Flush(0, tag(av[1])), nil);
	"Tattach" =>
		if(argc != 5)
			return (nil, "usage: Tattach fid afid uname aname");
		return (ref Tmsg.Attach(0, fid(av[1]), fid(av[2]), av[3], av[4]), nil);
	"Twalk" =>
		if(argc < 3)
			return (nil, "usage: Twalk fid newfid [name...]");
		names: array of string;
		if(argc > 3)
			names = av[3:];
		return (ref Tmsg.Walk(0, fid(av[1]), fid(av[2]), names), nil);
	"Topen" =>
		if(argc != 3)
			return (nil, "usage: Topen fid mode");
		return (ref Tmsg.Open(0, fid(av[1]), atoi(av[2])), nil);
	"Tcreate" =>
		if(argc != 5)
			return (nil, "usage: Tcreate fid name perm mode");
		return (ref Tmsg.Create(0, fid(av[1]), av[2], atoi(av[3]), atoi(av[4])), nil);
	"Tread" =>
		if(argc != 4)
			return (nil, "usage: Tread fid offset count");
		return (ref Tmsg.Read(0, fid(av[1]), atob(av[2]), atoi(av[3])), nil);
	"Twrite" =>
		if(argc != 4)
			return (nil, "usage: Twrite fid offset data");
		return (ref Tmsg.Write(0, fid(av[1]), atob(av[2]), array of byte av[3]), nil);
	"Tclunk" =>
		if(argc != 2)
			return (nil, "usage: Tclunk fid");
		return (ref Tmsg.Clunk(0, fid(av[1])), nil);
	"Tremove" =>
		if(argc != 2)
			return (nil, "usage: Tremove fid");
		return (ref Tmsg.Remove(0, fid(av[1])), nil);
	"Tstat" =>
		if(argc != 2)
			return (nil, "usage: Tstat fid");
		return (ref Tmsg.Stat(0, fid(av[1])), nil);
	"Twstat" =>
		if(argc != 8)
			return (nil, "usage: Twstat fid name uid gid mode mtime length");
		return (ref Tmsg.Wstat(0, fid(av[1]), dir(av[2], av[3], av[4], val(av[5]), val(av[6]), bigval(av[7]))), nil);
	"nexttag" =>
		if(argc < 2)
			return (nil, sys->sprint("next tag is %d", nexttag));
		nexttag = tag(av[1]);
		return (nil, nil);
	"dump" =>
		verbose++;
		return (nil, nil);
	* =>
		return (nil, "unknown message type");
	}
}

#
# server side
#

Treader(fd: ref Sys->FD)
{
	while((m := Tmsg.read(fd, msgsize)) != nil){
		sys->print("<- %s\n", m.text());
		if(tagof m == tagof Tmsg.Readerror)
			quit(1);
	}
	sys->print("styxchat: clients hungup\n");
}

Rwriter(fd: ref Sys->FD)
{
	in := bufio->fopen(stdin, Sys->OREAD);
	while((l := in.gets('\n')) != nil){
		if(l != nil && l[0] == '#')
			continue;
		(r, err) := Rparse(l);
		if(r == nil){
			if(err != nil)
				sys->print("?%s\n", err);
		}else{
			a := r.pack();
			if(a != nil){
				sys->print("-> %s\n", r.text());
				n := len a;
				if(n <= msgsize){
					if(sys->write(fd, a, len a) != len a)
						sys->print("?write error to clients: %r\n");
				}else
					sys->print("?message bigger than agreed: %d bytes\n", n);
			}else
				sys->fprint(sys->fildes(2), "styxchat: R-message conversion failed\n");
		}
	}
}

qid(s: string): Sys->Qid
{
	(nf, flds) := sys->tokenize(s, ".");
	q := Sys->Qid(big 0, 0, 0);
	if(nf < 1)
		return q;
	q.path = atob(hd flds);
	if(nf < 2)
		return q;
	q.vers = atoi(hd tl flds);
	if(nf < 3)
		return q;
	q.qtype = mode(hd tl tl flds);
	return q;
}

mode(s: string): int
{
	if(len s > 0 && s[0] >= '0' && s[0] <= '9')
		return atoi(s);
	mode := 0;
	for(i := 0; i < len s; i++){
		case s[i] {
		'd' =>
			mode |= Sys->QTDIR;
		'a' =>
			mode |= Sys->QTAPPEND;
		'u' =>
			mode |= Sys->QTAUTH;
		'l' =>
			mode |= Sys->QTEXCL;
		'f' =>
			;
		* =>
			sys->fprint(sys->fildes(2), "styxchat: unknown mode character %c, ignoring\n", s[i]);
		}
	}
	return mode;
}

rdir(a: array of string): Sys->Dir
{
	d := sys->zerodir;
	d.qid = qid(a[0]);
	d.mode = atoi(a[1]) | (d.qid.qtype<<24);
	d.atime = atoi(a[2]);
	d.mtime = atoi(a[3]);
	d.length = atob(a[4]);
	d.name = a[5];
	d.uid = a[6];
	d.gid = a[7];
	d.muid = a[8];
	return d;
}

Rparse(s: string): (ref Rmsg, string)
{
	args := str->unquoted(s);
	if(args == nil)
		return (nil, nil);
	argc := len args;
	av := array[argc] of string;
	for(i:=0; args != nil; args = tl args)
		av[i++] = hd args;
	case av[0] {
	"Rversion" =>
		if(argc != 4)
			return (nil, "usage: Rversion tag messagesize version");
		return (ref Rmsg.Version(tag(av[1]), atoi(av[2]), av[3]), nil);
	"Rauth" =>
		if(argc != 3)
			return (nil, "usage: Rauth tag aqid");
		return (ref Rmsg.Auth(tag(av[1]), qid(av[2])), nil);
	"Rflush" =>
		if(argc != 2)
			return (nil, "usage: Rflush tag");
		return (ref Rmsg.Flush(tag(av[1])), nil);
	"Rattach" =>
		if(argc != 3)
			return (nil, "usage: Rattach tag qid");
		return (ref Rmsg.Attach(tag(av[1]), qid(av[2])), nil);
	"Rwalk" =>
		if(argc < 2)
			return (nil, "usage: Rwalk tag [qid ...]");
		qids := array[argc-2] of Sys->Qid;
		for(i = 0; i < len qids; i++)
			qids[i] = qid(av[i+2]);
		return (ref Rmsg.Walk(tag(av[1]), qids), nil);
	"Ropen" =>
		if(argc != 4)
			return (nil, "usage: Ropen tag qid iounit");
		return (ref Rmsg.Open(tag(av[1]), qid(av[2]), atoi(av[3])), nil);
	"Rcreate" =>
		if(argc != 4)
			return (nil, "usage: Rcreate tag qid iounit");
		return (ref Rmsg.Create(tag(av[1]), qid(av[2]), atoi(av[3])), nil);
	"Rread" =>
		if(argc != 3)
			return (nil, "usage: Rread tag data");
		return (ref Rmsg.Read(tag(av[1]), array of byte av[2]), nil);
	"Rwrite" =>
		if(argc != 3)
			return (nil, "usage: Rwrite tag count");
		return (ref Rmsg.Write(tag(av[1]), atoi(av[2])), nil);
	"Rclunk" =>
		if(argc != 2)
			return (nil, "usage: Rclunk tag");
		return (ref Rmsg.Clunk(tag(av[1])), nil);
	"Rremove" =>
		if(argc != 2)
			return (nil, "usage: Rremove tag");
		return (ref Rmsg.Remove(tag(av[1])), nil);
	"Rstat" =>
		if(argc != 11)
			return (nil, "usage: Rstat tag qid mode atime mtime length name uid gid muid");
		return (ref Rmsg.Stat(tag(av[1]), rdir(av[2:])), nil);
	"Rwstat" =>
		if(argc != 8)
			return (nil, "usage: Rwstat tag");
		return (ref Rmsg.Wstat(tag(av[1])), nil);
	"Rerror" =>
		if(argc != 3)
			return (nil, "usage: Rerror tag ename");
		return (ref Rmsg.Error(tag(av[1]), av[2]), nil);
	"dump" =>
		verbose++;
		return (nil, nil);
	* =>
		return (nil, "unknown message type");
	}
}

atoi(s: string): int
{
	(i, nil) := str->toint(s, 0);
	return i;
}

# atoi with traditional unix semantics for octal and hex.
atob(s: string): big
{
	(b, nil) := str->tobig(s, 0);
	return b;
}

err(s: string)
{
	sys->fprint(sys->fildes(2), "styxchat: %s\n", s);
	raise "fail:error";
}
