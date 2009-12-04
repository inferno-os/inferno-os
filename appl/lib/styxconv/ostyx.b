implement OStyx;

#
# Copyright © 1999 Vita Nuova Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
include "osys.m";
include "ostyx.m";

DEBUG: con 0;

CHANHASHSIZE: con 32;

init()
{
	sys = load Sys Sys->PATH;
	gsofar = 0;
	gdata = array[MAXRPC] of {* => byte 0};
}

# note that this implementation fails if we're reading OTmsgs and ORmsgs
# concurrently. luckily we don't need to in styxconv.
gsofar: int;
gdata: array of byte;

ORmsg.read(fd: ref Sys->FD): ref ORmsg
{
	mlen := 0;
	m: ref ORmsg;
	for (;;){
		if(gsofar > 0)
			(mlen, m) = d2rmsg(gdata[0 : gsofar]);
		if(mlen == 0){
			if(gsofar == len gdata){
				ndata := array[MAXRPC] of byte;
				ndata[0:] = gdata;
				gdata = ndata;
			}
			n := sys->read(fd, gdata[gsofar:], len gdata - gsofar);
			if(n <= 0)
				return nil;
			gsofar += n;
		}else if(mlen > 0){
			if(tagof(m) == tagof(OTmsg.Write)) {
				ndata := array[MAXRPC] of byte;
				ndata[0:] = gdata[mlen : gsofar];
				gdata = ndata;
			}else
				gdata[0:] = gdata[mlen : gsofar];
			gsofar -= mlen;
			return m;
		}else
			gsofar = 0;
	}
}

OTmsg.read(fd: ref Sys->FD): ref OTmsg
{
	mlen := 0;
	m: ref OTmsg;
	for (;;){
		if(gsofar > 0)
			(mlen, m) = d2tmsg(gdata[0 : gsofar]);
		if(mlen == 0){
			if(gsofar == len gdata){
				ndata := array[MAXRPC] of byte;
				ndata[0:] = gdata;
				gdata = ndata;
			}
			n := sys->read(fd, gdata[gsofar:], len gdata - gsofar);
			if(n <= 0)
				return nil;
			gsofar += n;
		}else if(mlen > 0){
			if(tagof(m) == tagof(OTmsg.Write)) {
				ndata := array[MAXRPC] of byte;
				ndata[0:] = gdata[mlen : gsofar];
				gdata = ndata;
			}else
				gdata[0:] = gdata[mlen : gsofar];
			gsofar -= mlen;
			return m;
		}else
			gsofar = 0;
	}
}


Styxserver.new(fd: ref Sys->FD): (chan of ref OTmsg, ref Styxserver)
{
	if (sys == nil)
		sys = load Sys Sys->PATH;

	tchan := chan of ref OTmsg;
	srv := ref Styxserver(fd, array[CHANHASHSIZE] of list of ref Chan);

	sync := chan of int;
	spawn tmsgreader(fd, tchan, sync);
	<-sync;
	return (tchan, srv);
}

tmsgreader(fd: ref Sys->FD, tchan: chan of ref OTmsg, sync: chan of int)
{
	sys->pctl(Sys->NEWFD|Sys->NEWNS, fd.fd :: nil);
	sync <-= 1;
	fd = sys->fildes(fd.fd);
	data := array[MAXRPC] of byte;
	sofar := 0;
	for (;;) {
		n := sys->read(fd, data[sofar:], len data - sofar);
		if (n <= 0) {
			m: ref OTmsg = nil;
			if (n < 0)
				m = ref OTmsg.Readerror(-1, sys->sprint("%r"));
			tchan <-= m;
			return;
		}
		sofar += n;
		(cn, m) := d2tmsg(data[0:sofar]);
		if (cn == -1) {
			# on msg format error, flush any data and
			# hope it'll be alright in the future.
			sofar = 0;
		} else if (cn > 0) {
			# if it's a write message, then the buffer is used in
			# the message, so allocate another one to avoid
			# aliasing.
			if (tagof(m) == tagof(OTmsg.Write)) {
				ndata := array[MAXRPC] of byte;
				ndata[0:] = data[cn:sofar];
				data = ndata;
			} else
				data[0:] = data[cn:sofar];
			sofar -= cn;
			tchan <-= m;
			m = nil;
		}
	}
}

Styxserver.reply(srv: self ref Styxserver, m: ref ORmsg): int
{
	d := array[MAXRPC] of byte;
	if (DEBUG) 
		sys->fprint(sys->fildes(2), "%s\n", rmsg2s(m));
	n := rmsg2d(m, d);
	return sys->write(srv.fd, d, n);
}

type2tag := array[] of {
	Tnop	=> tagof(OTmsg.Nop),
	Tflush	=> tagof(OTmsg.Flush),
	Tclone	=> tagof(OTmsg.Clone),
	Twalk	=> tagof(OTmsg.Walk),
	Topen	=> tagof(OTmsg.Open),
	Tcreate	=> tagof(OTmsg.Create),
	Tread	=> tagof(OTmsg.Read),
	Twrite	=> tagof(OTmsg.Write),
	Tclunk	=> tagof(OTmsg.Clunk),
	Tremove	=> tagof(OTmsg.Remove),
	Tstat		=> tagof(OTmsg.Stat),
	Twstat	=> tagof(OTmsg.Wstat),
	Tattach	=> tagof(OTmsg.Attach),
	*		=> -1
};

msglen := array[] of {
	Tnop	=> 3,
	Tflush	=> 5,
	Tclone	=> 7,
	Twalk	=> 33,
	Topen	=> 6,
	Tcreate	=> 38,
	Tread	=> 15,
	Twrite	=> 16,	# header only; excludes data
	Tclunk	=> 5,
	Tremove	=> 5,
	Tstat		=> 5,
	Twstat	=> 121,
	Tattach	=> 5+2*OSys->NAMELEN,

	Rnop	=> -3,
	Rerror	=> -67,
	Rflush	=> -3,
	Rclone	=> -5,
	Rwalk	=> -13,
	Ropen	=> -13,
	Rcreate	=> -13,
	Rread	=> -8,	# header only; excludes data
	Rwrite	=> -7,
	Rclunk	=> -5,
	Rremove	=> -5,
	Rstat		=> -121,
	Rwstat	=> -5,
	Rsession	=> -0,
	Rattach	=> -13,
	*		=> 0
};

d2tmsg(d: array of byte): (int, ref OTmsg)
{
	tag: int;
	gmsg: ref OTmsg;

	n := len d;
	if (n < 3)
		return (0, nil);

	t: int;
	(d, t) = gchar(d);
	if (t < 0 || t >= len msglen || msglen[t] <= 0)
		return (-1, nil);

	if (n < msglen[t])
		return (0, nil);

	(d, tag) = gshort(d);
	case t {
	Tnop	=>
			msg := ref OTmsg.Nop;
			gmsg = msg;
	Tflush	=>
			msg := ref OTmsg.Flush;
			(d, msg.oldtag) = gshort(d);
			gmsg = msg;
	Tclone	=>
			msg := ref OTmsg.Clone;
			(d, msg.fid) = gshort(d);
			(d, msg.newfid) = gshort(d);
			gmsg = msg;
	Twalk	=>
			msg := ref OTmsg.Walk;
			(d, msg.fid) = gshort(d);
			(d, msg.name) = gstring(d, OSys->NAMELEN);
			gmsg = msg;
	Topen	=>
			msg := ref OTmsg.Open;
			(d, msg.fid) = gshort(d);
			(d, msg.mode) = gchar(d);
			gmsg = msg;
	Tcreate	=>
			msg := ref OTmsg.Create;
			(d, msg.fid) = gshort(d);
			(d, msg.name) = gstring(d, OSys->NAMELEN);
			(d, msg.perm) = glong(d);
			(d, msg.mode) = gchar(d);
			gmsg = msg;
	Tread	=>
			msg := ref OTmsg.Read;
			(d, msg.fid) = gshort(d);
			(d, msg.offset) = gbig(d);
			if (msg.offset < big 0)
				msg.offset = big 0;
			(d, msg.count) = gshort(d);
			gmsg = msg;
	Twrite	=>
			count: int;
			msg := ref OTmsg.Write;
			(d, msg.fid) = gshort(d);
			(d, msg.offset) = gbig(d);
			if (msg.offset < big 0)
				msg.offset = big 0;
			(d, count) = gshort(d);
			if (count > Sys->ATOMICIO)
				return (-1, nil);
			if (len d < 1 + count)
				return (0, nil);
			d = d[1:];
			msg.data = d[0:count];
			d = d[count:];
			gmsg = msg;
	Tclunk	=>
			msg := ref OTmsg.Clunk;
			(d, msg.fid) = gshort(d);
			gmsg = msg;
	Tremove	=>
			msg := ref OTmsg.Remove;
			(d, msg.fid) = gshort(d);
			gmsg = msg;
	Tstat		=>
			msg := ref OTmsg.Stat;
			(d, msg.fid) = gshort(d);
			gmsg = msg;
	Twstat	=>
			msg := ref OTmsg.Wstat;
			(d, msg.fid) = gshort(d);
			(d, msg.stat) = convM2D(d);
			gmsg = msg;
	Tattach	=>
			msg := ref OTmsg.Attach;
			(d, msg.fid) = gshort(d);
			(d, msg.uname) = gstring(d, OSys->NAMELEN);
			(d, msg.aname) = gstring(d, OSys->NAMELEN);
			gmsg = msg;
	*  =>
			return (-1, nil);
	}
	gmsg.tag = tag;
	return (n - len d, gmsg);
}

d2rmsg(d: array of byte): (int, ref ORmsg)
{
	tag: int;
	gmsg: ref ORmsg;

	n := len d;
	if (n < 3)
		return (0, nil);

	t: int;
	(d, t) = gchar(d);
	if (t < 0 || t >= len msglen || msglen[t] >= 0)
		return (-1, nil);

	if (n < -msglen[t])
		return (0, nil);

	(d, tag) = gshort(d);
	case t {
	Rerror 	=>
			msg := ref ORmsg.Error;
			(d, msg.err) = gstring(d, OSys->ERRLEN);
			gmsg = msg;
	Rnop	=>
			msg := ref ORmsg.Nop;
			gmsg = msg;
	Rflush	=>
			msg := ref ORmsg.Flush;
			gmsg = msg;
	Rclone	=>
			msg := ref ORmsg.Clone;
			(d, msg.fid) = gshort(d);
			gmsg = msg;
	Rwalk	=>
			msg := ref ORmsg.Walk;
			(d, msg.fid) = gshort(d);
			(d, msg.qid.path) = glong(d);
			(d, msg.qid.vers) = glong(d);
			gmsg = msg;
	Ropen	=>
			msg := ref ORmsg.Open;
			(d, msg.fid) = gshort(d);
			(d, msg.qid.path) = glong(d);
			(d, msg.qid.vers) = glong(d);
			gmsg = msg;
	Rcreate	=>
			msg := ref ORmsg.Create;
			(d, msg.fid) = gshort(d);
			(d, msg.qid.path) = glong(d);
			(d, msg.qid.vers) = glong(d);
			gmsg = msg;
	Rread	=>
			count: int;
			msg := ref ORmsg.Read;
			(d, msg.fid) = gshort(d);
			(d, count) = gshort(d);
			if (count > Sys->ATOMICIO)
				return (-1, nil);
			if (len d < 1 + count)
				return (0, nil);
			d = d[1:];
			msg.data = d[0:count];
			d = d[count:];
			gmsg = msg;
	Rwrite	=>
			msg := ref ORmsg.Write;
			(d, msg.fid) = gshort(d);
			(d, msg.count) = gshort(d);
			gmsg = msg;
	Rclunk	=>
			msg := ref ORmsg.Clunk;
			(d, msg.fid) = gshort(d);
			gmsg = msg;
	Rremove	=>
			msg := ref ORmsg.Remove;
			(d, msg.fid) = gshort(d);
			gmsg = msg;
	Rstat		=>
			msg := ref ORmsg.Stat;
			(d, msg.fid) = gshort(d);
			(d, msg.stat) = convM2D(d);
			gmsg = msg;
	Rwstat	=>
			msg := ref ORmsg.Wstat;
			(d, msg.fid) = gshort(d);
			gmsg = msg;
	Rattach	=>
			msg := ref ORmsg.Attach;
			(d, msg.fid) = gshort(d);
			(d, msg.qid.path) = glong(d);
			(d, msg.qid.vers) = glong(d);
			gmsg = msg;
	*  =>
			return (-1, nil);
	}
	gmsg.tag = tag;
	return (n - len d, gmsg);
}

ttag2type := array[] of {
tagof(OTmsg.Readerror) => Terror,
tagof(OTmsg.Nop) => Tnop,
tagof(OTmsg.Flush) => Tflush,
tagof(OTmsg.Clone) => Tclone,
tagof(OTmsg.Walk) => Twalk,
tagof(OTmsg.Open) => Topen,
tagof(OTmsg.Create) => Tcreate,
tagof(OTmsg.Read) => Tread,
tagof(OTmsg.Write) => Twrite,
tagof(OTmsg.Clunk) => Tclunk,
tagof(OTmsg.Stat) => Tstat,
tagof(OTmsg.Remove) => Tremove,
tagof(OTmsg.Wstat) => Twstat,
tagof(OTmsg.Attach) => Tattach,
};

tag2type := array[] of {
tagof ORmsg.Nop	=> Rnop,
tagof ORmsg.Flush	=> Rflush,
tagof ORmsg.Error	=> Rerror,
tagof ORmsg.Clone	=> Rclone,
tagof ORmsg.Walk	=> Rwalk,
tagof ORmsg.Open	=> Ropen,
tagof ORmsg.Create	=> Rcreate,
tagof ORmsg.Read	=> Rread,
tagof ORmsg.Write	=> Rwrite,
tagof ORmsg.Clunk	=> Rclunk,
tagof ORmsg.Remove	=> Rremove,
tagof ORmsg.Stat	=> Rstat,
tagof ORmsg.Wstat	=> Rwstat,
tagof ORmsg.Attach	=> Rattach,
};

tmsg2d(gm: ref OTmsg, d: array of byte): int
{
	n := len d;
	d = pchar(d, ttag2type[tagof gm]);
	d = pshort(d, gm.tag);
	pick m := gm {
	Nop =>
	Flush =>
		d = pshort(d, m.oldtag);
	Clone =>
		d = pshort(d, m.fid);
		d = pshort(d, m.newfid);
	Walk =>
		d = pshort(d, m.fid);
		d = pstring(d, m.name, OSys->NAMELEN);
	Open =>
		d = pshort(d, m.fid);
		d = pchar(d, m.mode);
	Create =>
		d = pshort(d, m.fid);
		d = pstring(d, m.name, OSys->NAMELEN);
		d = plong(d, m.perm);
		d = pchar(d, m.mode);
	Read =>
		d = pshort(d, m.fid);
		d = pbig(d, m.offset);
		d = pshort(d, m.count);
	Write =>
		data := m.data;
		if (len data > Sys->ATOMICIO)
			data = data[0:Sys->ATOMICIO];
		d = pshort(d, m.fid);
		d = pbig(d, m.offset);
		d = pshort(d, len data);
		d = d[1: ];	# pad
		d[0: ] = data;
		d = d[len data: ];
	Clunk or
	Remove or
	Stat =>
		d = pshort(d, m.fid);
	Wstat =>
		d = pshort(d, m.fid);
		d = convD2M(d, m.stat);
	Attach =>
		d = pshort(d, m.fid);
		d = pstring(d, m.uname, OSys->NAMELEN);
		d = pstring(d, m.aname, OSys->NAMELEN);
	}
	return n - len d;
}

rmsg2d(gm: ref ORmsg, d: array of byte): int
{
	n := len d;
	d = pchar(d, tag2type[tagof gm]);
	d = pshort(d, gm.tag);
	pick m := gm {
	Nop or
	Flush =>
	Error	=>
		d = pstring(d, m.err, OSys->ERRLEN);
	Clunk or
	Remove or
	Clone or
	Wstat	=>
		d = pshort(d, m.fid);
	Walk or
	Create or
	Open or
	Attach =>
		d = pshort(d, m.fid);
		d = plong(d, m.qid.path);
		d = plong(d, m.qid.vers);
	Read =>
		d = pshort(d, m.fid);
		data := m.data;
		if (len data > Sys->ATOMICIO)
			data = data[0:Sys->ATOMICIO];
		d = pshort(d, len data);
		d = d[1:];			# pad
		d[0:] = data;
		d = d[len data:];
	Write =>
		d = pshort(d, m.fid);
		d = pshort(d, m.count);
	Stat =>
		d = pshort(d, m.fid);
		d = convD2M(d, m.stat);
	}
	return n - len d;
}

gchar(a: array of byte): (array of byte, int)
{
	return (a[1:], int a[0]);
}

gshort(a: array of byte): (array of byte, int)
{
	return (a[2:], int a[1]<<8 | int a[0]);
}

glong(a: array of byte): (array of byte, int)
{
	return (a[4:], int a[0] | int a[1]<<8 | int a[2]<<16 | int a[3]<<24);
}

gbig(a: array of byte): (array of byte, big)
{
	return (a[8:],
			big a[0] | big a[1] << 8 |
			big a[2] << 16 | big a[3] << 24 |
			big a[4] << 32 | big a[5] << 40 |
			big a[6] << 48 | big a[7] << 56);
}

gstring(a: array of byte, n: int): (array of byte, string)
{
	i: int;
	for (i = 0; i < n; i++)
		if (a[i] == byte 0)
			break;
	return (a[n:], string a[0:i]);
}

pchar(a: array of byte, v: int): array of byte
{
	a[0] = byte v;
	return a[1:];
}

pshort(a: array of byte, v: int): array of byte
{
	a[0] = byte v;
	a[1] = byte (v >> 8);
	return a[2:];
}

plong(a: array of byte, v: int): array of byte
{
	a[0] = byte v;
	a[1] = byte (v >> 8);
	a[2] = byte (v >> 16);
	a[3] = byte (v >> 24);
	return a[4:];
}

pbig(a: array of byte, v: big): array of byte
{
	a[0] = byte v;
	a[1] = byte (v >> 8);
	a[2] = byte (v >> 16);
	a[3] = byte (v >> 24);
	a[4] = byte (v >> 32);
	a[5] = byte (v >> 40);
	a[6] = byte (v >> 58);
	a[7] = byte (v >> 56);
	return a[8:];
}

pstring(a: array of byte, s: string, n: int): array of byte
{
	sd := array of byte s;
	if (len sd > n - 1)
		sd = sd[0:n-1];
	a[0:] = sd;
	for (i := len sd; i < n; i++)
		a[i] = byte 0;
	return a[n:];
}

# convert from Dir to bytes
convD2M(d: array of byte, f: OSys->Dir): array of byte
{
	d = pstring(d, f.name, OSys->NAMELEN);
	d = pstring(d, f.uid, OSys->NAMELEN);
	d = pstring(d, f.gid, OSys->NAMELEN);
	d = plong(d, f.qid.path);
	d = plong(d, f.qid.vers);
	d = plong(d, f.mode);
	d = plong(d, f.atime);
	d = plong(d, f.mtime);
	d = pbig(d, big f.length);	# the length field in OSys->Dir should really be big.
	d = pshort(d, f.dtype);
	d = pshort(d, f.dev);
	return d;
}

# convert from bytes to Dir
convM2D(d: array of byte): (array of byte, OSys->Dir)
{
	f: OSys->Dir;
	(d, f.name) = gstring(d, OSys->NAMELEN);
	(d, f.uid) = gstring(d, OSys->NAMELEN);
	(d, f.gid) = gstring(d, OSys->NAMELEN);
	(d, f.qid.path) = glong(d);
	(d, f.qid.vers) = glong(d);
	(d, f.mode) = glong(d);
	(d, f.atime) = glong(d);
	(d, f.mtime) = glong(d);
	length: big;
	(d, length) = gbig(d);
	f.length = int length;
	(d, f.dtype) = gshort(d);
	(d, f.dev) = gshort(d);
	return (d, f);
}


tmsgtags := array[] of {
tagof(OTmsg.Readerror) => "Readerror",
tagof(OTmsg.Nop) => "Nop",
tagof(OTmsg.Flush) => "Flush",
tagof(OTmsg.Clone) => "Clone",
tagof(OTmsg.Walk) => "Walk",
tagof(OTmsg.Open) => "Open",
tagof(OTmsg.Create) => "Create",
tagof(OTmsg.Read) => "Read",
tagof(OTmsg.Write) => "Write",
tagof(OTmsg.Clunk) => "Clunk",
tagof(OTmsg.Stat) => "Stat",
tagof(OTmsg.Remove) => "Remove",
tagof(OTmsg.Wstat) => "Wstat",
tagof(OTmsg.Attach) => "Attach",
};

rmsgtags := array[] of {
tagof(ORmsg.Nop) => "Nop",
tagof(ORmsg.Flush) => "Flush",
tagof(ORmsg.Error) => "Error",
tagof(ORmsg.Clunk) => "Clunk",
tagof(ORmsg.Remove) => "Remove",
tagof(ORmsg.Clone) => "Clone",
tagof(ORmsg.Wstat) => "Wstat",
tagof(ORmsg.Walk) => "Walk",
tagof(ORmsg.Create) => "Create",
tagof(ORmsg.Open) => "Open",
tagof(ORmsg.Attach) => "Attach",
tagof(ORmsg.Read) => "Read",
tagof(ORmsg.Write) => "Write",
tagof(ORmsg.Stat) => "Stat",
};

tmsg2s(gm: ref OTmsg): string
{
	if (gm == nil)
		return "OTmsg.nil";

	s := "OTmsg."+tmsgtags[tagof(gm)]+"("+string gm.tag;
	pick m:= gm {
	Readerror =>
		s += ", \""+m.error+"\"";
	Nop =>
	Flush =>
		s += ", " + string m.oldtag;
	Clone =>
		s += ", " + string m.fid + ", " + string m.newfid;
	Walk =>
		s += ", " + string m.fid + ", \""+m.name+"\"";
	Open =>
		s += ", " + string m.fid + ", " + string m.mode;
	Create =>
		s += ", " + string m.fid + ", " + string m.perm + ", "
			+ string m.mode + ", \""+m.name+"\"";
	Read =>
		s += ", " + string m.fid + ", " + string m.count + ", " + string m.offset;
	Write =>
		s += ", " + string m.fid + ", " + string m.offset
			+ ", data["+string len m.data+"]";
	Clunk or
	Stat or
	Remove =>
		s += ", " + string m.fid;
	Wstat =>
		s += ", " + string m.fid;
	Attach =>
		s += ", " + string m.fid + ", \""+m.uname+"\", \"" + m.aname + "\"";
	}
	return s + ")";
}

rmsg2s(gm: ref ORmsg): string
{
	if (sys == nil)
		sys = load Sys Sys->PATH;
	if (gm == nil)
		return "ORmsg.nil";

	s := "ORmsg."+rmsgtags[tagof(gm)]+"("+string gm.tag;
	pick m := gm {	
	Nop or
	Flush =>
	Error =>
		s +=", \""+m.err+"\"";
	Clunk or
	Remove or
	Clone or
	Wstat =>
		s += ", " + string m.fid;
	Walk	 or
	Create or
	Open or
	Attach =>
		s += ", " + string m.fid + sys->sprint(", %ux.%d", m.qid.path, m.qid.vers);
	Read =>
		s += ", " + string m.fid + ", data["+string len m.data+"]";
	Write =>
		s += ", " + string m.fid + ", " + string m.count;
	Stat =>
		s += ", " + string m.fid;
	}
	return s + ")";
}

Styxserver.fidtochan(srv: self ref Styxserver, fid: int): ref Chan
{
	for (l := srv.chans[fid & (CHANHASHSIZE-1)]; l != nil; l = tl l)
		if ((hd l).fid == fid)
			return hd l;
	return nil;
}

Styxserver.newchan(srv: self ref Styxserver, fid: int): ref Chan
{
	# fid already in use
	if ((c := srv.fidtochan(fid)) != nil)
		return nil;
	c = ref Chan;
	c.qid = OSys->Qid(0, 0);
	c.open = 0;
	c.mode = 0;
	c.fid = fid;
	slot := fid & (CHANHASHSIZE-1);
	srv.chans[slot] = c :: srv.chans[slot];
	return c;
}

Styxserver.chanfree(srv: self ref Styxserver, c: ref Chan)
{
	slot := c.fid & (CHANHASHSIZE-1);
	nl: list of ref Chan;
	for (l := srv.chans[slot]; l != nil; l = tl l)
		if ((hd l).fid != c.fid)
			nl = (hd l) :: nl;
	srv.chans[slot] = nl;
}

Styxserver.devclone(srv: self ref Styxserver, m: ref OTmsg.Clone): ref Chan
{
	oc := srv.fidtochan(m.fid);
	if (oc == nil) {
		srv.reply(ref ORmsg.Error(m.tag, Ebadfid));
		return nil;
	}
	if (oc.open) {
		srv.reply(ref ORmsg.Error(m.tag, Eopen));
		return nil;
	}
	c := srv.newchan(m.newfid);
	if (c == nil) {
		srv.reply(ref ORmsg.Error(m.tag, Einuse));
		return nil;
	}
	c.qid = oc.qid;
	c.uname  = oc.uname;
	c.open = oc.open;
	c.mode = oc.mode;
	c.path = oc.path;
	c.data = oc.data;
	srv.reply(ref ORmsg.Clone(m.tag, m.fid));
	return c;
}
