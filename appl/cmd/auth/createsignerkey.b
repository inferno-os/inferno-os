implement Createsignerkey;

include "sys.m";
	sys: Sys;

include "draw.m";

include "daytime.m";

include "ipints.m";
include "crypt.m";
	crypt: Crypt;

include "oldauth.m";
	oldauth: Oldauth;

include "arg.m";

# signer key never expires
SKexpire:       con 0;

# size in bits of modulus for public keys
PKmodlen:		con 1024;

# size in bits of modulus for diffie hellman
DHmodlen:		con 1024;

algs := array[] of {"rsa", "elgamal"};	# first entry is default

Createsignerkey: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	err: string;

	sys = load Sys Sys->PATH;
	crypt = load Crypt Crypt->PATH;
	oldauth = load Oldauth Oldauth->PATH;
	oldauth->init();
	arg := load Arg Arg->PATH;

	arg->init(args);
	arg->setusage("createsignerkey [-a algorithm] [-f keyfile] [-e ddmmyyyy] [-b size-in-bits] name-of-owner");
	alg := algs[0];
	filename := "/keydb/signerkey";
	expire := SKexpire;
	bits := PKmodlen;
	while((c := arg->opt()) != 0){
		case c {
		'a' =>
			alg = arg->arg();
			if(alg == nil)
				arg->usage();
			for(i:=0;; i++){
				if(i >= len algs)
					error(sys->sprint("unknown algorithm: %s", alg));
				else if(alg == algs[i])
					break;
			}
		'f' or 'k' =>
			filename = arg->earg();
		'e' =>
			s := arg->earg();
			(err, expire) = checkdate(s);
			if(err != nil)
				error(err);
		'b' =>
			s := arg->earg();
			bits = int s;
			if(bits < 32 || bits > 4096)
				error("modulus must be in the range of 32 to 4096 bits");
		* =>
			arg->usage();
		}
	}
	args = arg->argv();
	if(args == nil)
		arg->usage();
	arg = nil;

	owner := hd args;

	# generate a local key, self-signed
	info := ref Oldauth->Authinfo;
	info.mysk = crypt->genSK(alg, bits);
	if(info.mysk == nil)
		error(sys->sprint("algorithm %s not configured in system", alg));
	info.owner = owner;
	info.mypk = crypt->sktopk(info.mysk);
	info.spk = crypt->sktopk(info.mysk);
	myPKbuf := array of byte oldauth->pktostr(info.mypk, owner);
	state := crypt->sha1(myPKbuf, len myPKbuf, nil, nil);
	info.cert = oldauth->sign(info.mysk, owner, expire, state, "sha1");
	(info.alpha, info.p) = crypt->dhparams(DHmodlen);

	if(oldauth->writeauthinfo(filename, info) < 0)
		error(sys->sprint("can't write signerkey file %s: %r", filename));
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "createsignerkey: %s\n", s);
	raise "fail:error";
}

checkdate(word: string): (string, int)
{
	if(len word != 8)
		return ("!date must be in form ddmmyyyy", 0);

	daytime := load Daytime Daytime->PATH;

	now := daytime->now();

	tm := daytime->local(now);
	tm.sec = 59;
	tm.min = 59;
	tm.hour = 24;

	tm.mday = int word[0:2];
	if(tm.mday > 31 || tm.mday < 1)
		return ("!bad day of month", 0);

	tm.mon = int word[2:4] - 1;
	if(tm.mon > 11 || tm.mday < 0)
		return ("!bad month", 0);

	tm.year = int word[4:8] - 1900;
	if(tm.year < 70)
		return ("!bad year", 0);

	newdate := daytime->tm2epoch(tm);
	if(newdate < now)
		return ("!expiration date must be in the future", 0);

	return (nil, newdate);
}
