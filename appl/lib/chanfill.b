implement ChanFill;

#
#	Iobuf fill routine to serve a file2chan.
#

include	"sys.m";
include	"bufio.m";

myfill:	BufioFill;
bufio:	Bufio;
fid:	int;
wc:	Sys->Rwrite;
fio:	ref Sys->FileIO;

Iobuf:	import bufio;

init(data: array of byte, f: int, c: Sys->Rwrite, r: ref Sys->FileIO, b: Bufio): ref Iobuf
{
	if (myfill == nil)
		myfill = load BufioFill SELF;
	bufio = b;
	i := bufio->sopen(string data);
	fid = f;
	wc = c;
	fio = r;
	i.setfill(myfill);
	wc <-= (len data, nil);
	return i;
}

fill(b: ref Iobuf): int
{
	for (;;) {
		(nil, data, f, c) := <-fio.write;
		if (f != fid) {
			if (c != nil)
				c <-= (0, "file busy");
			continue;
		}
		if (c == nil)
			return Bufio->EOF;
		c <-= (len data, nil);
		i := len data;
		if (i == 0)
			continue;
		b.buffer[b.size:] = data;
		b.size += i;
		b.filpos += big i;
		return i;
	}
}
