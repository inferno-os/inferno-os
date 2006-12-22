implement Ramfile;
include "sys.m";
	sys: Sys;
include "draw.m";

# synthesise a file that can be treated just like any other
# file. limitations of file2chan mean that it's not possible
# to know when an open should have truncated the file, so
# we do the only possible thing, and truncate it when we get
# a write at offset 0. thus it can be edited with an editor,
# but can't be used to store seekable, writable data records
# (unless the first record is never written)

# there should be some way to determine when the file should
# go away - file2chan sends a nil channel whenever the file
# is closed by anyone, which is not good enough.

stderr: ref Sys->FD;

Ramfile: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	if (len argv < 2 || len argv > 3) {
		sys->fprint(stderr, "usage: ramfile path [data]\n");
		return;
	}
	path := hd tl argv;
	(dir, f) := pathsplit(path);

	if (sys->bind("#s", dir, Sys->MBEFORE|Sys->MCREATE) == -1) {
		sys->fprint(stderr, "ramfile: %r\n");
		return;
	}
	fio := sys->file2chan(dir, f);
	if (fio == nil) {
		sys->fprint(stderr, "ramfile: file2chan failed: %r\n");
		return;
	}
	data := array[0] of byte;
	if (tl tl argv != nil)
		data = array of byte hd tl tl argv;

	spawn server(fio, data);
	data = nil;
}

server(fio: ref Sys->FileIO, data: array of byte)
{
	for (;;) alt {
	(offset, count, fid, rc) := <-fio.read =>
		if (rc != nil) {
			if (offset > len data)
				rc <-= (nil, nil);
			else {
				end := offset + count;
				if (end > len data)
					end = len data;
				rc <-= (data[offset:end], nil);
			}
		}
	(offset, d, fid, wc) := <-fio.write =>
		if (wc != nil) {
			if (offset == 0)
				data = array[0] of byte;
			end := offset + len d;
			if (end > len data) {
				ndata := array[end] of byte;
				ndata[0:] = data;
				data = ndata;
				ndata = nil;
			}
			data[offset:] = d;
			wc <-= (len d, nil);
		}
	}
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
