implement Getpk;
include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
include "keyring.m";
	keyring: Keyring;

Getpk: module {
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
	keyring = load Keyring Keyring->PATH;
	if(keyring == nil)
		badmodule(Keyring->PATH);
	arg := load Arg Arg->PATH;
	if(arg == nil)
		badmodule(Arg->PATH);
	arg->init(argv);
	arg->setusage("usage: getpk [-asu] file...");
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
		info := keyring->readauthinfo(hd argv);
		if(info == nil){
			sys->fprint(sys->fildes(2), "getpk: cannot read %s: %r\n", hd argv);
			continue;
		}
		pk := info.mypk;
		if(sflag)
			pk = info.spk;
		s := keyring->pktostr(pk);
		if(!aflag)
			s = hex(hash(s));
		if(multi)
			s = hd argv + ": " + s;
		if(uflag)
			s += " " + pk.owner;
		sys->print("%s\n", s);
	}
}

hash(s: string): array of byte
{
	d := array of byte s;
	digest := array[Keyring->SHA1dlen] of byte;
	keyring->sha1(d, len d, digest, nil);
	return digest;
}

hex(a: array of byte): string
{
	s := "";
	for(i := 0; i < len a; i++)
		s += sys->sprint("%2.2ux", int a[i]);
	return s;
}
