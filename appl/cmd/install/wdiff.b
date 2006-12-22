implement Wdiff;

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


Wdiff: module{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

root := "/";
bflag : int;
listing : int;
package: int;

diff(w : ref Wrap->Wrapped, name : string, c : chan of int)
{
	sys->pctl(Sys->FORKFD, nil);
	wrapped := w.root+"/"+name;
	local := root+"/"+name;
	(ok, dir) := sys->stat(local);
	if (ok < 0) {
		sys->print("cannot stat %s\n", local);
		c <-= -1;
		return;
	}
	(ok, dir) = sys->stat(wrapped);
	if (ok < 0) {
		sys->print("cannot stat %s\n", wrapped);
		c <-= -1;
		return;
	}
	cmd := "/dis/diff.dis";
	m := load Command cmd;
	if(m == nil) {
		c <-= -1;
		return;
	}
	if (bflag)
		m->init(nil, cmd :: "-b" :: wrapped :: local :: nil);
	else
		m->init(nil, cmd :: wrapped :: local :: nil);
	c <-= 0;
}
	
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
	wrap = load Wrap Wrap->PATH;
	wrap->init(bufio);

	arg->init(args);
	while ((c := arg->opt()) != 0) {
		case c {
			'b' =>
				bflag = 1;
			'l' =>
				listing = 1;
			'p' =>
				package = 1;
			'r' =>
				root = arg->arg();
				if (root == nil)
					fatal("missing root name");
			* =>
				fatal(sys->sprint("bad argument -%c", c));
		}
	}
	args = arg->argv();
	if (args == nil || tl args != nil)
		fatal("usage: install/wdiff [-blp] [-r root] package");
	(ok, dir) := sys->stat(hd args);
	if (ok < 0)
		fatal(sys->sprint("no such file %s", hd args));
	w := wrap->openwraphdr(hd args, root, nil, !listing);
	if (w == nil)
		fatal("no such package found");

	if(package){
		while(w.nu > 0 && w.u[w.nu-1].typ == wrap->UPD)
			w.nu--;
	}

	digest := array[keyring->MD5dlen] of { * => byte 0 };
	digest0 := array[keyring->MD5dlen] of { * => byte 0 };

	# loop through each md5sum file of each package in increasing time order
	for(i := 0; i < w.nu; i++){
		b := bufio->open(w.u[i].dir+"/md5sum", Sys->OREAD);
		if (b == nil)
			fatal("md5sum file not found");
		while ((p := b.gets('\n')) != nil) {
			(n, lst) := sys->tokenize(p, " \t\n");
			if (n != 2)
				fatal("error in md5sum file");
			p = hd lst;
			q := root+"/"+p;
			(ok, dir) = sys->stat(q);
			if (ok >= 0 && (dir.mode & Sys->DMDIR))
				continue;
			t: int;
			(ok, t) = wrap->getfileinfo(w, p, nil, digest0, nil);
			if(ok < 0){
				sys->print("cannot happen\n");
				continue;
			}
			if(t != w.u[i].time)	# covered by later update
				continue;
			if (wrap->md5file(q, digest) < 0) {
				sys->print("%s removed\n", p);
				continue;
			}
			str := wrap->md5conv(digest);
			str0 := wrap->md5conv(digest0);
			# if (str == hd tl lst)
			if(str == str0)
				continue;
			if (listing)
				sys->print("%s modified\n", p);
			else {
				endc := chan of int;
				spawn diff(w, p, endc);
				<- endc;
			}
		}
	}
	wrap->end();
}
