implement Tarfs;

#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
	Qid: import Sys;

include "draw.m";

include "daytime.m";
	daytime: Daytime;

include "arg.m";

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

include "styxservers.m";
	styxservers: Styxservers;
	Fid, Styxserver, Navigator, Navop: import styxservers;
	Enotfound: import styxservers;

Tarfs: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

File: adt {
	x:	int;
	name:	string;
	mode:	int;
	uid:	int;
	gid:	int;
	mtime:	int;
	length:	big;
	offset:	big;
	parent:	cyclic ref File;
	children:	cyclic list of ref File;

	find:		fn(f: self ref File, name: string): ref File;
	enter:	fn(d: self ref File, f: ref File);
	stat:		fn(d: self ref File): ref Sys->Dir;
};

tarfd: ref Sys->FD;
root: ref File;
files: array of ref File;
pathgen: int;

error(s: string)
{
	sys->fprint(sys->fildes(2), "tarfs: %s\n", s);
	raise "fail:error";
}

checkload[T](m: T, path: string)
{
	if(m == nil)
		error(sys->sprint("can't load %s: %r", path));
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	styx = load Styx Styx->PATH;
	checkload(styx, Styx->PATH);
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	checkload(styxservers, Styxservers->PATH);
	styxservers->init(styx);
	daytime = load Daytime Daytime->PATH;
	checkload(daytime, Daytime->PATH);

	arg := load Arg Arg->PATH;
	checkload(arg, Arg->PATH);
	arg->setusage("tarfs [-a|-b|-ac|-bc] [-D] file mountpoint");
	arg->init(args);
	flags := Sys->MREPL;
	while((o := arg->opt()) != 0)
		case o {
		'a' =>	flags = Sys->MAFTER;
		'b' =>	flags = Sys->MBEFORE;
		'D' =>	styxservers->traceset(1);
		* =>		arg->usage();
		}
	args = arg->argv();
	if(len args != 2)
		arg->usage();
	arg = nil;

	file := hd args;
	args = tl args;
	mountpt := hd args;

	sys->pctl(Sys->FORKFD, nil);

	files = array[100] of ref File;
	root = files[0] = ref File;
	root.x = 0;
	root.name = "/";
	root.mode = Sys->DMDIR | 8r555;
	root.uid = 0;
	root.gid = 0;
	root.length = big 0;
	root.offset = big 0;
	root.mtime = 0;
	pathgen = 1;

	tarfd = sys->open(file, Sys->OREAD);
	if(tarfd == nil)
		error(sys->sprint("can't open %s: %r", file));
	if(readtar(tarfd) < 0)
		error(sys->sprint("error reading %s: %r", file));

	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0)
		error(sys->sprint("can't create pipe: %r"));

	navops := chan of ref Navop;
	spawn navigator(navops);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big 0);
	fds[0] = nil;

	pidc := chan of int;
	spawn server(tchan, srv, pidc, navops);
	<-pidc;

	if(sys->mount(fds[1], nil, mountpt, flags, nil) < 0)
		error(sys->sprint("can't mount tarfs: %r"));
}

server(tchan: chan of ref Tmsg, srv: ref Styxserver, pidc: chan of int, navops: chan of ref Navop)
{
	pidc <-= sys->pctl(Sys->FORKNS|Sys->NEWFD, 1::2::srv.fd.fd::tarfd.fd::nil);
Serve:
	while((gm := <-tchan) != nil){
		root.mtime = daytime->now();
		pick m := gm {
		Readerror =>
			sys->fprint(sys->fildes(2), "tarfs: mount read error: %s\n", m.error);
			break Serve;
		Read =>
			(c, err) := srv.canread(m);
			if(c == nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
				break;
			}
			if(c.qtype & Sys->QTDIR){
				srv.default(m);	# does readdir
				break;
			}
			f := files[int c.path];
			n := m.count;
			if(m.offset + big n > f.length)
				n = int (f.length - m.offset);
			if(n <= 0){
				srv.reply(ref Rmsg.Read(m.tag, nil));
				break;
			}
			a := array[n] of byte;
			sys->seek(tarfd, f.offset+m.offset, 0);
			n = sys->read(tarfd, a, len a);
			if(n < 0)
				srv.reply(ref Rmsg.Error(m.tag, sys->sprint("%r")));
			else
				srv.reply(ref Rmsg.Read(m.tag, a[0:n]));
		* =>
			srv.default(gm);
		}
	}
	navops <-= nil;		# shut down navigator
}

File.enter(dir: self ref File, f: ref File)
{
	if(pathgen >= len files){
		t := array[pathgen+50] of ref File;
		t[0:] = files;
		files = t;
	}
	if(0)
		sys->print("enter %s, %s [#%ux %bd]\n", dir.name, f.name, f.mode, f.length);
	f.x = pathgen;
	f.parent = dir;
	dir.children = f :: dir.children;
	files[pathgen++] = f;
}

File.find(f: self ref File, name: string): ref File
{
	for(g := f.children; g != nil; g = tl g)
		if((hd g).name == name)
			return hd g;
	return nil;
}

File.stat(f: self ref File): ref Sys->Dir
{
	d := ref sys->zerodir;
	d.mode = f.mode;
	d.qid.path = big f.x;
	d.qid.qtype = f.mode>>24;
	d.name = f.name;
	d.uid = string f.uid;
	d.gid = string f.gid;
	d.muid = d.uid;
	d.length = f.length;
	d.mtime = f.mtime;
	d.atime = root.mtime;
	return d;
}

split(s: string): (string, string)
{
	for(i := 0; i < len s; i++)
		if(s[i] == '/'){
			for(j := i+1; j < len s && s[j] == '/';)
				j++;
			return (s[0:i], s[j:]);
		}
	return (nil, s);
}

putfile(f: ref File)
{
	n := f.name;
	df := root;
	for(;;){
		(d, rest) := split(n);
		if(d == nil || rest == nil){
			f.name = n;
			break;
		}
		g := df.find(d);
		if(g == nil){
			g = ref *f;
			g.name = d;
			g.mode |= Sys->DMDIR;
			df.enter(g);
		}
		n = rest;
		df = g;
	}
	df.enter(f);
}

navigator(navops: chan of ref Navop)
{
	while((m := <-navops) != nil){
		pick n := m {
		Stat =>
			n.reply <-= (files[int n.path].stat(), nil);
		Walk =>
			f := files[int n.path];
			if((f.mode & Sys->DMDIR) == 0){
				n.reply <-= (nil, "not a directory");
				break;
			}
			case n.name {
			".." =>
				if(f.parent != nil)
					f = f.parent;
				n.reply <-= (f.stat(), nil);
			* =>
				f = f.find(n.name);
				if(f != nil)
					n.reply <-= (f.stat(), nil);
				else
					n.reply <-= (nil, Enotfound);
			}
		Readdir =>
			f := files[int n.path];
			if((f.mode & Sys->DMDIR) == 0){
				n.reply <-= (nil, "not a directory");
				break;
			}
			g := f.children;
			for(i := n.offset; i > 0 && g != nil; i--)
				g = tl g;
			for(; --n.count >= 0 && g != nil; g = tl g)
				n.reply <-= ((hd g).stat(), nil);
			n.reply <-= (nil, nil);
		}
	}
}

Blocksize: con 512;
Namelen: con 100;
Userlen: con 32;

Oname: con 0;
Omode: con Namelen;
Ouid: con Omode+8;
Ogid: con Ouid+8;
Osize: con Ogid+8;
Omtime: con Osize+12;
Ochksum: con Omtime+12;
Olinkflag: con Ochksum+8;
Olinkname: con Olinkflag+1;
# POSIX extensions follow
Omagic: con Olinkname+Namelen;	# ustar
Ouname: con Omagic+8;
Ogname: con Ouname+Userlen;
Omajor: con Ogname+Userlen;
Ominor: con Omajor+8;
Oend: con Ominor+8;

readtar(fd: ref Sys->FD): int
{
	buf := array[Blocksize] of byte;
	offset := big 0;
	for(;;){
		sys->seek(fd, offset, 0);
		n := sys->read(fd, buf, len buf);
		if(n == 0)
			break;
		if(n < 0)
			return -1;
		if(n < len buf){
			sys->werrstr(sys->sprint("short read: expected %d, got %d", len buf, n));
			return -1;
		}
		if(buf[0] == byte 0)
			break;
		offset += big Blocksize;
		mode := int octal(buf[Omode:Ouid]);
		linkflag := int buf[Olinkflag];
		# don't use linkname
		if((mode & 8r170000) == 8r40000)
			linkflag = '5';
		mode &= 8r777;
		case linkflag {
		'1' or '2' or 's' =>		# ignore links and symbolic links
			continue;
		'3' or '4' or '6' =>	# special file or fifo (leave them, but empty)
			;
		'5' =>
			mode |= Sys->DMDIR;
		}
		f := ref File;
		f.name = ascii(buf[Oname:Omode]);
		while(len f.name > 0 && f.name[0] == '/')
			f.name = f.name[1:];
		while(len f.name > 0 && f.name[len f.name-1] == '/'){
			mode |= Sys->DMDIR;
			f.name = f.name[:len f.name-1];
		}
		f.mode = mode;
		f.uid = int octal(buf[Ouid:Ogid]);
		f.gid = int octal(buf[Ogid:Osize]);
		f.length = octal(buf[Osize:Omtime]);
		if(f.length < big 0)
			error(sys->sprint("tar file size is negative: %s", f.name));
		if(mode & Sys->DMDIR)
			f.length = big 0;
		f.mtime = int octal(buf[Omtime:Ochksum]);
		sum := int octal(buf[Ochksum:Olinkflag]);
		if(sum != checksum(buf))
			error(sys->sprint("checksum error on %s", f.name));
		f.offset = offset;
		offset += f.length;
		v := int (f.length % big Blocksize);
		if(v != 0)
			offset += big (Blocksize-v);
		putfile(f);
	}
	return 0;
}

ascii(b: array of byte): string
{
	top := 0;
	for(i := 0; i < len b && b[i] != byte 0; i++)
		if(int b[i] >= 16r80)
			top = 1;
	if(top)
		;	# TO DO: do it by hand if not utf-8
	return string b[0:i];
}

octal(b: array of byte): big
{
	v := big 0;
	for(i := 0; i < len b && b[i] == byte ' '; i++)
		;
	for(; i < len b && b[i] != byte 0 && b[i] != byte ' '; i++){
		c := int b[i];
		if(!(c >= '0' && c <= '7'))
			error(sys->sprint("bad octal value in tar header: %s (%c)", string b, c));
		v = (v<<3) | big (c-'0');
	}
	return v;
}

checksum(b: array of byte): int
{
	c := 0;
	for(i := 0; i < Ochksum; i++)
		c += int b[i];
	for(; i < Olinkflag; i++)
		c += ' ';
	for(; i < len b; i++)
		c += int b[i];
	return c;
}
