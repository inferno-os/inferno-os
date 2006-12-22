implement Bundle, Fsmodule;
include "sys.m";
	sys: Sys;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "readdir.m";
	readdir: Readdir;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	reports: Reports;
	Report, quit, report: import reports;
include "alphabet/fs.m";
	fs: Fs;
	Value: import fs;
	Fschan, Fsdata, Entrychan, Entry,
	Gatechan, Gatequery, Nilentry, Option,
	Next, Down, Skip, Quit: import Fs;

Bundle: module {};

# XXX if we can't open a directory, is it ever worth passing its metadata
# through anyway?

EOF: con "end of archive\n";

types(): string
{
	return "fx";
}
badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: bundle: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	readdir = load Readdir Readdir->PATH;
	if(readdir == nil)
		badmod(Readdir->PATH);
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		badmod(Readdir->PATH);
	bufio->fopen(nil, Sys->OREAD);		# XXX no bufio->init!
	fs = load Fs Fs->PATH;
	if(fs == nil)
		badmod(Readdir->PATH);
	fs->init();
	reports = load Reports Reports->PATH;
	if(reports == nil)
		badmod(Reports->PATH);
}

run(nil: ref Draw->Context, r: ref Report,
			nil: list of Option, args: list of ref Value): ref Value
{
	f := chan of ref Sys->FD;
	spawn bundleproc((hd args).x().i, f, r.start("bundle"));
	return ref Value.Vf(f);
}

#bundle(r: ref Report, iob: ref Iobuf, c: Fschan): chan of string
bundle(nil: ref Report, nil: ref Iobuf, nil: Fschan): chan of string
{
	return nil;
#	sync := chan[1] of string;
#	spawn bundleproc(c, sync, iob, r.start("bundle"));
#	return sync;
}

bundleproc(c: Fschan, f: chan of ref Sys->FD, errorc: chan of string)
{
	f <-= nil;
	if((fd := <-f) == nil){
		(<-c).t1 <-= Quit;
		quit(errorc);
	}
	iob := bufio->fopen(fd, Sys->OWRITE);
	fd = nil;
	(d, reply) := <-c;
	if(d.dir == nil){
		report(errorc, "no root directory");
		endarchive(iob, errorc);
	}
	if(puts(iob, dir2header(d.dir), errorc) == -1){
		reply <-= Quit;
		quit(errorc);
	}
	reply <-= Down;
	bundledir(d.dir.name, d, c, iob, errorc);
	endarchive(iob, errorc);
}

endarchive(iob: ref Iobuf, errorc: chan of string)
{
	{
		if(puts(iob, EOF, errorc) != -1)
			iob.flush();
		sys->fprint(iob.fd, "");
	} exception {
	"write on closed pipe" =>
		;
	}
	quit(errorc);
}

bundledir(path: string, d: Fsdata,
		c: Fschan,
		iob: ref Iobuf, errorc: chan of string)
{
	if(d.dir.mode & Sys->DMDIR){
		path[len path] = '/';
		for(;;){
			(ent, reply) := <-c;
			if(ent.dir == nil){
				reply <-= Skip;
				break;
			}
			if(puts(iob, dir2header(ent.dir), errorc) == -1){
				reply <-= Quit;
				quit(errorc);
			}
			reply <-= Down;
			bundledir(path + ent.dir.name, ent, c, iob, errorc);
		}
		iob.putc('\n');
	}else{
		buf: array of byte;
		reply: chan of int;
		length := big d.dir.length;
		n := big 0;
		for(;;){
			((nil, buf), reply) = <-c;
			if(buf == nil){
				reply <-= Skip;
				break;
			}
			if(write(iob, buf, len buf, errorc) != len buf){
				reply <-= Quit;
				quit(errorc);
			}
			n += big len buf;
			if(n > length){		# should never happen
				report(errorc, sys->sprint("%q is longer than expected (fatal)", path));
				reply <-= Quit;
				quit(errorc);
			}
			if(n == length){
				reply <-= Skip;
				break;
			}
			reply <-= Next;
		}
		if(n < length){
			report(errorc, sys->sprint("%q is shorter than expected (%bd/%bd); adding null bytes", path, n, length));
			buf = array[Sys->ATOMICIO] of {* => byte 0};
			while(n < length){
				nb := len buf;
				if(length - n < big len buf)
					nb = int (length - n);
				if(write(iob, buf, nb, errorc) != nb){
					(<-c).t1 <-= Quit;
					quit(errorc);
				}
				report(errorc, sys->sprint("added %d null bytes", nb));
				n += big nb;
			}
		}
	}
}

dir2header(d: ref Sys->Dir): string
{
	return sys->sprint("%q %uo %q %q %ud %bd\n", d.name, d.mode, d.uid, d.gid, d.mtime, d.length);
}

puts(iob: ref Iobuf, s: string, errorc: chan of string): int
{
	{
		if(iob.puts(s) == -1)
			report(errorc, sys->sprint("write error: %r"));
		return 0;
	} exception {
	"write on closed pipe" =>
		report(errorc, sys->sprint("write on closed pipe"));
		return -1;
	}
}

write(iob: ref Iobuf, buf: array of byte, n: int, errorc: chan of string): int
{
	{
		nw := iob.write(buf, n);
		if(nw < n){
			if(nw >= 0)
				report(errorc, "short write");
			else{
				report(errorc, sys->sprint("write error: %r"));
			}
		}
		return nw;
	} exception {
	"write on closed pipe" =>
		report(errorc, "write on closed pipe");
		return -1;
	}
}
