implement Logfile;

#
# Copyright © 1999 Vita Nuova Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;
include "draw.m";

Logfile: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

Fidrec: adt {
	fid: 	int;		# fid of read
	rq: 	list of (int, Sys->Rread);	# outstanding read requests
	pos:	int;		# current position in the logfile
};

Circbuf: adt {
	start: int;
	data: array of byte;
	new: fn(size: int): ref Circbuf;
	put: fn(b: self ref Circbuf, d: array of byte): int;
	get: fn(b: self ref Circbuf, s, n: int): (int, array of byte);
};

Fidhash: adt
{
	table: array of list of ref Fidrec;
	get: fn(ht: self ref Fidhash, fid: int): ref Fidrec;
	put: fn(ht: self ref Fidhash, fidrec: ref Fidrec);
	del: fn(ht: self ref Fidhash, fidrec: ref Fidrec);
	new: fn(): ref Fidhash;
};

usage()
{
	sys->fprint(stderr, "usage: logfile [-size] file\n");
	raise "fail: usage";
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	bufsize := Sys->ATOMICIO * 4;

	if (argv != nil)
		argv = tl argv;
	if (argv != nil && len hd argv && (hd argv)[0] == '-' && len hd argv > 1) {
		if ((bufsize = int ((hd argv)[1:])) <= 0) {
			sys->fprint(stderr, "logfile: can't have a zero buffer size\n");
			usage();
		}
		argv = tl argv;
	}
	if (argv == nil || tl argv != nil)
		usage();
	path := hd argv;

	(dir, f) := pathsplit(path);
	if (sys->bind("#s", dir, Sys->MBEFORE|Sys->MCREATE) == -1) {
		sys->fprint(stderr, "logfile: bind #s failed: %r\n");
		return;
	}
	fio := sys->file2chan(dir, f);
	if (fio == nil) {
		sys->fprint(stderr, "logfile: couldn't make %s: %r\n", path);
		return;
	}

	spawn logserver(fio, bufsize);
}

logserver(fio: ref Sys->FileIO, bufsize: int)
{
	waitlist: list of ref Fidrec;
	readers := Fidhash.new();
	availcount := 0;
	availchan := chan of int;
	workchan := chan of (Sys->Rread, array of byte);
	buf := Circbuf.new(bufsize);
	for (;;) alt {
	<-availchan =>
		availcount++;
	(off, count, fid, rc) := <-fio.read =>
		r := readers.get(fid);
		if (rc == nil) {
			if (r != nil)
				readers.del(r);
			continue;
		}
		if (r == nil) {
			r = ref Fidrec(fid, nil, buf.start);
			if (r.pos < len buf.data)
				r.pos = len buf.data;		# first buffer's worth is garbage
			readers.put(r);
		}

		(s, d) := buf.get(r.pos, count);
		r.pos = s + len d;

		if (d != nil) {
			rc <-= (d, nil);
		} else {
			if (r.rq == nil)
				waitlist = r :: waitlist;
			r.rq = (count, rc) :: r.rq;
		}

	(off, data, fid, wc) := <-fio.write =>
		if (wc == nil)
			continue;
		if ((n := buf.put(data)) < len data)
			wc <-= (n, "write too long for buffer");
		else
			wc <-= (n, nil);

		wl := waitlist;
		for (waitlist = nil; wl != nil; wl = tl wl) {
			r := hd wl;
			if (availcount == 0) {
				spawn worker(workchan, availchan);
				availcount++;
			}
			(count, rc) := hd r.rq;
			r.rq = tl r.rq;

			# optimisation: if the read request wants exactly the data provided
			# in the write request, then use the original data buffer.
			s: int;
			d: array of byte;
			if (count >= n && r.pos == buf.start + len buf.data - n)
				(s, d) = (r.pos, data);
			else
				(s, d) = buf.get(r.pos, count);
			r.pos = s + len d;
			workchan <-= (rc, d);
			availcount--;
			if (r.rq != nil)
				waitlist = r :: waitlist;
			d = nil;
		}
		data = nil;
		wl = nil;
	}
}

worker(work: chan of (Sys->Rread, array of byte), ready: chan of int)
{
	for (;;) {
		(rc, data) := <-work;	# blocks forever if the reading process is killed
		rc <-= (data, nil);
		(rc, data) = (nil, nil);
		ready <-= 1;
	}
}
		
Circbuf.new(size: int): ref Circbuf
{
	return ref Circbuf(0, array[size] of byte);
}

# return number of bytes actually written
Circbuf.put(b: self ref Circbuf, d: array of byte): int
{
	blen := len b.data;
	# if too big to fit in buffer, truncate the write.
	if (len d > blen)
		d = d[0:blen];
	dlen := len d;

	offset := b.start % blen;
	if (offset + dlen <= blen) {
		b.data[offset:] = d;
	} else {
		b.data[offset:] = d[0:blen - offset];
		b.data[0:] = d[blen - offset:];
	}
	b.start += dlen;
	return dlen;
}

# return (start, data)
Circbuf.get(b: self ref Circbuf, s, n: int): (int, array of byte)
{
	# if the beginning's been overrun, start from the earliest place we can.
	# we could put some indication of elided bytes in the buffer.
	if (s < b.start)
		s = b.start;
	blen := len b.data;
	if (s + n > b.start + blen)
		n = b.start + blen - s;
	if (n <= 0)
		return (s, nil);
	o := s % blen;
	d := array[n] of byte;
	if (o + n <= blen)
		d[0:] = b.data[o:o+n];
	else {
		d[0:] = b.data[o:];
		d[blen - o:] = b.data[0:o+n-blen];
	}
	return (s, d);
}

FIDHASHSIZE: con 32;

Fidhash.new(): ref Fidhash
{
	return ref Fidhash(array[FIDHASHSIZE] of list of ref Fidrec);
}

# put an entry in the hash table.
# assumes there is no current entry for the fid.
Fidhash.put(ht: self ref Fidhash, f: ref Fidrec)
{
	slot := f.fid & (FIDHASHSIZE-1);
	ht.table[slot] = f :: ht.table[slot];
}

Fidhash.get(ht: self ref Fidhash, fid: int): ref Fidrec
{
	for (l := ht.table[fid & (FIDHASHSIZE-1)]; l != nil; l = tl l)
		if ((hd l).fid == fid)
			return hd l;
	return nil;
}

Fidhash.del(ht: self ref Fidhash, f: ref Fidrec)
{
	slot := f.fid & (FIDHASHSIZE-1);
	nl: list of ref Fidrec;
	for (l := ht.table[slot]; l != nil; l = tl l)
		if ((hd l).fid != f.fid)
			nl = (hd l) :: nl;
	ht.table[slot] = nl;
}

pathsplit(p: string): (string, string)
{
	for (i := len p - 1; i >= 0; i--)
		if (p[i] != '/')
			break;
	if (i < 0)
		return (p, nil);
	p = p[0:i+1];
	for (i = len p - 1; i >=0; i--)
		if (p[i] == '/')
			break;
	if (i < 0)
		return (".", p);
	return (p[0:i+1], p[i+1:]);
}

