implement Fsmodule;
include "sys.m";
	sys: Sys;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;
include "bundle.m";
	bundle: Bundle;
include "draw.m";
include "sh.m";
include "alphabet/fs.m";
	fslib: Fs;
	Report, Value,quit, report: import fslib;
	Fschan, Fsdata, Entrychan, Entry,
	Quit, Next, Skip, Down,
	Option: import Fs;

to do...
read file. if non-seekable, make temporary copy.
record offsets of all files
sort by filename
output in proper order.


types(): string
{
	return "xs";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: exec: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	fslib = load Fs Fs->PATH;
	if(fslib == nil)
		badmod(Fs->PATH);
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		badmod(Bufio->PATH);
	str = load String String->PATH;
	if(str == nil)
		badmod(String->PATH);
	bundle = load Bundle Bundle->PATH;
	if(bundle == nil)
		badmod(Bundle->PATH);
	bundle->init();
}

run(nil: ref Draw->Context, report: ref Report,
			nil: list of Option, args: list of ref Value): ref Value
{
	p := (hd args).s().i;
	iob: ref Bufio->Iobuf;
	if(p == "-")
		iob = bufio->fopen(sys->fildes(0), Sys->OREAD);
	else
		iob = bufio->open(p, Sys->OREAD);
	if(iob == nil){
		sys->fprint(sys->fildes(2), "fs: unbundle: cannot open %q: %r\n", p);
		return nil;
	}
	seekable := p != "-";
	if(seekable)
		seekable = isseekable(iob.fd);
	if(
	return ref Value.Vx(mkext(report, iob, seekable, Sys->ATOMICIO));
}

# dodgy heuristic... avoid, or using the stat-length of pipes and net connections
isseekable(fd: ref Sys->FD): int
{
	(ok, stat) := sys->fstat(fd);
	if(ok != -1 && stat.dtype == '|' || stat.dtype == 'I')
		return 0;
	return 1;
}

mkext(r: ref Report, iob: ref Iobuf, seekable, blocksize: int): Fschan
{
	c := chan of (Fsdata, chan of int);
	spawn unbundleproc(iob, c, seekable, blocksize, r.start("bundle"));
	return c;
}

EOF: con "end of archive\n";

unbundleproc(iob: ref Iobuf, c: Fschan, seekable, blocksize: int, errorc: chan of string)
{
	reply := chan of int;
	p := iob.gets('\n');
	# XXX overall header?
	if(p == nil || p == EOF){
		fslib->sendnulldir(c);
		quit(errorc);
	}
	d := header2dir(p);
	if(d == nil){
		fslib->sendnulldir(c);
		report(errorc, "invalid first header");
		quit(errorc);
	}
	if((d.mode & Sys->DMDIR) == 0){
		fslib->sendnulldir(c);
		report(errorc, "first entry is not a directory");
		quit(errorc);
	}
	c <-= ((d, nil), reply);
	case r := <-reply {
	Down =>
		unbundledir(iob, c, 0, seekable, blocksize, errorc);
		c <-= ((nil, nil), reply);
		<-reply;
	Skip or
	Next =>
		unbundledir(iob, c, 1, seekable, blocksize, errorc);
	Quit =>
		break;
	}
	quit(errorc);
}

unbundledir(iob: ref Iobuf, c: Fschan,
			skipping, seekable, blocksize: int, errorc: chan of string): int
{
	reply := chan of int;
	while((p := iob.gets('\n')) != nil){
		if(p == EOF)
			break;
		if(p[0] == '\n')
			break;
		d := header2dir(p);
		if(d == nil){
			report(errorc, sys->sprint("invalid bundle header %q", p[0:len p - 1]));
			return -1;
		}
		if(d.mode & Sys->DMDIR){
			if(skipping)
				continue;
			c <-= ((d, nil), reply);
			case <-reply {
			Quit =>
				quit(errorc);
			Down =>
				r := unbundledir(iob, c, 0, seekable, blocksize, errorc);
				c <-= ((nil, nil), reply);
				if(<-reply == Quit)
					quit(errorc);
				if(r == -1)
					return -1;
			Skip =>
				if(unbundledir(iob, c, 1, seekable, blocksize, errorc) == -1)
					return -1;
				skipping = 1;
			Next =>
				if(unbundledir(iob, c, 1, seekable, blocksize, errorc) == -1)
					return -1;
			}
		}else{
			if(skipping){
				if(skipdata(iob, d.length, seekable) == -1)
					return -1;
			}else{
				case unbundlefile(iob, d, c, errorc, seekable, blocksize) {
				-1 =>
					return -1;
				Skip =>
					skipping = 1;
				}
			}
		}
	}
	if(p == nil)
		report(errorc, "unexpected eof");
	return 0;
}

skipdata(iob: ref Iobuf, length: big, seekable: int): int
{
	if(seekable){
		iob.seek(big length, Sys->SEEKRELA);
		return 0;
	}
	buf := array[Sys->ATOMICIO] of byte;
	for(n := big 0; n < length; ){
		nb := Sys->ATOMICIO;
		if(length - n < big Sys->ATOMICIO)
			nb = int (length - n);
		nb = iob.read(buf, nb);
		if(nb <= 0)
			return -1;
		n += big nb;
	}
	return 0;
}

unbundlefile(iob: ref Iobuf, d: ref Sys->Dir,
	c: Fschan, errorc: chan of string, seekable, blocksize: int): int
{
	reply := chan of int;
	c <-= ((d, nil), reply);
	case <-reply {
	Quit =>
		quit(errorc);
	Skip =>
		if(skipdata(iob, d.length, seekable) == -1)
			return -1;
		return Skip;
	Next =>
		if(skipdata(iob, d.length, seekable) == -1)
			return -1;
		return Next;
	}
	length := d.length;
	for(n := big 0; n < length; ){
		nr := blocksize;
		if(n + big blocksize > length)
			nr = int (length - n);
		buf := array[nr] of byte;
		nr = iob.read(buf, nr);
		if(nr <= 0){
			if(nr < 0)
				report(errorc, sys->sprint("read error: %r"));
			else
				report(errorc, sys->sprint("premature eof"));
			return -1;
		}else if(nr < len buf)
			buf = buf[0:nr];
		c <-= ((nil, buf), reply);
		n += big nr;
		case <-reply {
		Quit =>
			quit(errorc);
		Skip =>
			if(skipdata(iob, length - n, seekable) == -1)
				return -1;
			return Next;
		}
	}
	c <-= ((nil, nil), reply);
	if(<-reply == Quit)
		quit(errorc);
	return Next;
}

header2dir(s: string): ref Sys->Dir
{
	toks := str->unquoted(s);
	nf := len toks;
	if(nf != 6)
		return nil;
	d := ref Sys->nulldir;
	(d.name, toks) = (hd toks, tl toks);
	(d.mode, toks) = (str->toint(hd toks, 8).t0, tl toks);
	(d.uid, toks) = (hd toks, tl toks);
	(d.gid, toks) = (hd toks, tl toks);
	(d.mtime, toks) = (int hd toks, tl toks);
	(d.length, toks) = (big hd toks, tl toks);
	return d;
}
