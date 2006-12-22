implement Wfind;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "arg.m";
	arg: Arg;
include "wrap.m";
	wrap : Wrap;
include "sh.m";
include "keyring.m";
	keyring : Keyring;
include "readdir.m";
	readdir : Readdir;

Wfind: module{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

fatal(err : string)
{
	sys->fprint(sys->fildes(2), "%s\n", err);
	exit;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	arg = load Arg Arg->PATH;
	keyring = load Keyring Keyring->PATH;
	readdir = load Readdir Readdir->PATH;
	wrap = load Wrap Wrap->PATH;
	wrap->init(bufio);

	pkgs: list of string;
	indir := "/install";
	arg->init(args);
	while ((c := arg->opt()) != 0) {
		case c {
			'p' =>
				pkg := arg->arg();
				if (pkg == nil)
					fatal("missing package name");
				pkgs = pkg :: pkgs;
			* =>
				fatal(sys->sprint("bad argument -%c", c));
		}
	}
	args = arg->argv();
	if (args == nil)
		fatal("usage: install/wfind [-p package ... ] file ...");
	# (ok, dir) := sys->stat(indir);
	# if (ok < 0)
	#	fatal(sys->sprint("cannot open install directory %s", indir));
	if(pkgs != nil){
		npkgs: list of string;
		for(pkg := pkgs; pkg != nil; pkg = tl pkg)
			npkgs = hd pkg :: npkgs;
		pkgs = npkgs;
		for(pkg = pkgs; pkg != nil; pkg = tl pkg)
			scanpkg(hd pkg, indir+"/"+hd pkg, args);
	}
	else
		scanpkgs(indir, args);
	prfiles();
}

scanpkgs(d : string, files: list of string)
{
	(dir, n) := readdir->init(d, Readdir->NAME|Readdir->COMPACT);
	for (i := 0; i < n; i++) {
		if (dir[i].mode & Sys->DMDIR)
			scanpkg(dir[i].name, d + "/" + dir[i].name, files);
	}
}

scanpkg(pkg : string, d : string, files: list of string)
{
	# base package, updates and update packages have the name
	# <timestamp> or <timestamp.gz>
	(dir, n) := readdir->init(d, Readdir->NAME|Readdir->COMPACT);
	for (i := 0; i < n; i++) {
		f := dir[i].name;
		l := len f;
		if (l >= 4 && f[l-3:l] == ".gz")
			f = f[0:l-3];
		scanfile(f, pkg, d+"/"+dir[i].name, files);
	}
	w := wrap->openwrap(pkg, "/", 0);
	if(w == nil)
		return;
	for(i = 0; i < w.nu; i++)
		scanw(w, i, files, WRAP, pkg);
}

scanfile(f: string, pkg: string, d: string, files: list of string)
{
	f = nil;
	# sys->print("%s	%s	%s\n", f, pkg, d);
	w := wrap->openwraphdr(d, "/", nil, 0);
	if(w == nil)
		return;
	if(w.nu != 1)
		fatal("strange package: more than one piece");
	# sys->print("	%s %d %s %d %d %d\n", w.name, w.tfull, w.u[0].desc, w.u[0].time, w.u[0].utime, w.u[0].typ);
	scanw(w, 0, files, INSTALL, pkg);
}

scanw(w: ref Wrap->Wrapped, i: int, files: list of string, where: int, pkg: string)
{
	w.u[i].bmd5.seek(big 0, Bufio->SEEKSTART);
	while ((p := w.u[i].bmd5.gets('\n')) != nil){
		# sys->print("%s", p);
		(n, l) := sys->tokenize(p, " \n");
		if(n != 2)
			fatal(sys->sprint("bad md5 file in %s\n", wtype(where)+"/"+w.name+"/"+wrap->now2string(w.u[i].time, 0)));
		file := hd l;
		md5 := hd tl l;
		for(fs := files; fs != nil; fs = tl fs){
			if(strsuffix(file, hd fs)){
				# sys->print("%s %s %s %d\n", pkg, file, md5, where);
				addfile(file, w, i, md5, where, pkg);
			}
		}
	}
}

Stat: adt{
	name: string;
	occs: list of (ref Wrap->Wrapped, int, string, int, string);
	md5: string;
};

stats: list of ref Stat;
	
addfile(file: string, w: ref Wrap->Wrapped, i: int, md5: string, where: int, pkg: string)
{
	for(sts := stats; sts != nil; sts = tl sts){
		st := hd sts;
		if(st.name == file){
			st.occs = (w, i, md5, where, pkg) :: st.occs;
			return;
		}
	}
	digest := array[keyring->MD5dlen] of { * => byte 0 };
	if (wrap->md5file(file, digest) < 0)
		str := "non-existent"+blanks(32-12);
	else
		str = wrap->md5conv(digest);
	st := ref Stat;
	st.name = file;
	st.occs = (w, i, md5, where, pkg) :: nil;
	st.md5 = str;
	stats = st :: stats;
}

prfiles()
{
	for(sts := stats; sts != nil; sts = tl sts){
		st := hd sts;
		sys->print("%s\n", st.name);
		proccs(st.occs);
		sys->print("\t%s %s\n", st.md5, st.name);
	}
}

proccs(ocs: list of (ref Wrap->Wrapped, int, string, int, string))
{
	if(ocs != nil){
		proccs(tl ocs);
		(w, i, md5, where, pkg) := hd ocs;
		sys->print("\t%s %s/%s(%s)\t%s\n", md5, w.name, wrap->now2string(w.u[i].time, 0), ptype(w.u[i].typ), wtype(where)+"/"+pkg);
	}
}
		
ptype(p: int): string
{
	return (array[] of { "???", "package ", "update  ", "full upd" })[p];
}

INSTALL: con 0;
WRAP: con 1;

wtype(w: int): string
{
	return (array[] of { "/install", "/wrap" })[w];
}

strsuffix(s: string, suf: string): int
{
	return (l1 := len s) >= (l2 := len suf) && s[l1-l2: l1] == suf;
}

blanks(n: int): string
{
	s := "";
	for(i := 0; i < n; i++)
		s += " ";
	return s;
}
