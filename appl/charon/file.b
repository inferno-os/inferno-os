implement Transport;

include "common.m";
include "transport.m";

# local copies from CU
sys: Sys;
U: Url;
	Parsedurl: import U;
CU: CharonUtils;
	Netconn, ByteSource, Header, config : import CU;

dbg := 0;

init(c: CharonUtils)
{
	CU = c;
	sys = load Sys Sys->PATH;
	U = load Url Url->PATH;
	if (U != nil)
		U->init();
	dbg = int (CU->config).dbg['n'];
}

connect(nc: ref Netconn, nil: ref ByteSource)
{
	nc.connected = 1;
	nc.state = CU->NCgethdr;
	return;
}

writereq(nil: ref Netconn, nil: ref ByteSource)
{
	return;
}

gethdr(nc: ref Netconn, bs: ref ByteSource)
{
	u := bs.req.url;
	f := u.path;
	hdr := Header.new();
	nc.conn.dfd = sys->open(f, sys->OREAD);
	if(nc.conn.dfd == nil) {
		if(dbg)
			sys->print("file %d: can't open %s: %r\n", nc.id, f);
		# Could examine %r to distinguish between NotFound
		# and Forbidden and other, but string is OS-dependent.
		hdr.code = CU->HCNotFound;
		bs.hdr = hdr;
		nc.connected = 0;
		return;
	}

	(ok, statbuf) := sys->fstat(nc.conn.dfd);
	if(ok < 0) {
		bs.err = "stat error";
		return;
	}

	if (statbuf.mode & Sys->DMDIR) {
		bs.err = "Directories not implemented";
		return;
	}

	# assuming file (not directory)
	n := int statbuf.length;
	hdr.length = n;
	if(n > sys->ATOMICIO)
		n = sys->ATOMICIO;
	a := array[n] of byte;
	n = sys->read(nc.conn.dfd, a, n);
	if(dbg)
		sys->print("file %d: initial read %d bytes\n", nc.id, n);
	if(n < 0) {
		bs.err = "read error";
		return;
	}
	hdr.setmediatype(f, a[0:n]);
	hdr.base = hdr.actual = bs.req.url;
	if(dbg)
		sys->print("file %d: hdr has mediatype=%s, length=%d\n",
			nc.id, CU->mnames[hdr.mtype], hdr.length);
	bs.hdr = hdr;
	if(n == len a)
		nc.tbuf = a;
	else
		nc.tbuf = a[0:n];
}

getdata(nc: ref Netconn, bs: ref ByteSource): int
{
	dfd := nc.conn.dfd;
	if (dfd == nil)
		return -1;
	if (bs.data == nil || bs.edata >= len bs.data) {
		closeconn(nc);
		return 0;
	}
	buf := bs.data[bs.edata:];
	n := len buf;
	if (nc.tbuf != nil) {
		# initial overread of header
		if (n >= len nc.tbuf) {
			n = len nc.tbuf;
			buf[:] = nc.tbuf;
			nc.tbuf = nil;
			return n;
		}
		buf[:] = nc.tbuf[:n];
		nc.tbuf = nc.tbuf[n:];
		return n;
	}
	n = sys->read(dfd, buf, n);
	if(dbg > 1)
		sys->print("ftp %d: read %d bytes\n", nc.id, n);
	if(n <= 0) {
		bs.err = sys->sprint("%r");
		closeconn(nc);
	}
	return n;
}

defaultport(nil: string) : int
{
	return 0;
}

closeconn(nc: ref Netconn)
{
	nc.conn.dfd = nil;
	nc.conn.cfd = nil;
	nc.conn.dir = "";
	nc.connected = 0;
}
