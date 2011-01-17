implement Getpk;
include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
include "ipints.m";
include "crypt.m";
	crypt: Crypt;
include "oldauth.m";
	oldauth: Oldauth;

Getpk: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

badmodule(p: string)
{
	sys->fprint(sys->fildes(2), "getpk: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	crypt = load Crypt Crypt->PATH;
	if(crypt == nil)
		badmodule(Crypt->PATH);
	oldauth = load Oldauth Oldauth->PATH;
	if(oldauth == nil)
		badmodule(Oldauth->PATH);
	oldauth->init();
	arg := load Arg Arg->PATH;
	if(arg == nil)
		badmodule(Arg->PATH);
	arg->init(argv);
	arg->setusage("getpk [-asu] file...");
	aflag := 0;
	sflag := 0;
	uflag := 0;
	while((opt := arg->opt()) != 0){
		case opt {
		's' =>
			sflag++;
		'a' =>
			aflag++;
		'u' =>
			uflag++;
		* =>
			arg->usage();
		}
	}
	argv = arg->argv();
	if(argv == nil)
		arg->usage();
	multi := len argv > 1;
	for(; argv != nil; argv = tl argv){
		info := oldauth->readauthinfo(hd argv);
		if(info == nil){
			sys->fprint(sys->fildes(2), "getpk: cannot read %s: %r\n", hd argv);
			continue;
		}
		pk := info.mypk;
		if(sflag)
			pk = info.spk;
		s := oldauth->pktostr(pk, info.owner);
		if(!aflag)
			s = hex(hash(s));
		if(multi)
			s = hd argv + ": " + s;
		if(uflag)
			s += " " + info.owner;
		sys->print("%s\n", s);
	}
}

hash(s: string): array of byte
{
	d := array of byte s;
	digest := array[Crypt->SHA1dlen] of byte;
	crypt->sha1(d, len d, digest, nil);
	return digest;
}

hex(a: array of byte): string
{
	s := "";
	for(i := 0; i < len a; i++)
		s += sys->sprint("%2.2ux", int a[i]);
	return s;
}
