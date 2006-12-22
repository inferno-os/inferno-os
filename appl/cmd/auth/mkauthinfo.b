implement Mkauthinfo;

#
#  sign a new key to produce a certificate
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;
	IPint: import kr;

include "security.m";
	auth: Auth;

include "daytime.m";
	daytime: Daytime;

include "arg.m";

Mkauthinfo: module{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->open("/dev/cons", sys->OWRITE);

	kr = load Keyring Keyring->PATH;

	auth = load Auth Auth->PATH;
	if(auth == nil)
		nomod(Auth->PATH);

	daytime = load Daytime Daytime->PATH;
	if(daytime == nil) 
		nomod(Daytime->PATH);

	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	arg->init(args);
	arg->setusage("auth/mkauthinfo [-k keyspec] [-e ddmmyyyy] user [keyfile]");
	keyspec := "key=default";
	expiry := 0;
	while((o := arg->opt()) != 0)
		case o {
		'k' =>
			keyspec = arg->earg();
		'e' =>
			expiry = parsedate(arg->earg());
		* =>
			arg->usage();
		}
	args = arg->argv();
	if(args == nil)
		arg->usage();
	user := hd args;
	args = tl args;
	dstfile := "/fd/1";
	if(args != nil)
		dstfile = hd args;
	arg = nil;

	sai := auth->key(keyspec);
	if(sai == nil){
		sys->fprint(stderr, "sign: can't find key matching %q: %r\n", keyspec);
		raise "fail:no key";
	}

	info := ref Keyring->Authinfo;
	info.alpha = sai.alpha;
	info.p = sai.p;
	info.mysk = kr->genSKfromPK(sai.spk, user);
	info.mypk = kr->sktopk(info.mysk);
	info.spk = sai.mypk;
	pkbuf := array of byte kr->pktostr(info.mypk);
	state := kr->sha1(pkbuf, len pkbuf, nil, nil);
	info.cert = kr->sign(sai.mysk, expiry, state, "sha1");
	if(kr->writeauthinfo("/fd/1", info) < 0){
		sys->fprint(stderr, "sign: error writing certificate: %r\n");
		raise "fail:write error";
	}
}

parsedate(s: string): int
{
	now := daytime->now();
	tm := daytime->local(now);
	if(s == "permanent")
		return 0;
	if(len s != 8)
		fatal("bad date format "+s+" (expected DDMMYYYY)");
	tm.mday = int s[0:2];
	if(tm.mday > 31 || tm.mday < 1)
		fatal(sys->sprint("bad day of month %d", tm.mday));
	tm.mon = int s[2:4] - 1;
	if(tm.mon > 11 || tm.mday < 0)
		fatal(sys->sprint("bad month %d\n", tm.mon + 1));
	tm.year = int s[4:8] - 1900;
	if(tm.year < 70)
		fatal(sys->sprint("bad year %d (year may be no earlier than 1970)", tm.year + 1900));
	expiry := daytime->tm2epoch(tm);
	expiry += 60;
	if(expiry <= now)
		fatal("expiry date has already passed");
	return expiry;
}

nomod(mod: string)
{
	fatal(sys->sprint("can't load %s: %r",mod));
}

fatal(msg: string)
{
	sys->fprint(stderr, "mkauthinfo: %s\n", msg);
	raise "fail:error";
}
