implement Ai2fact;

# authinfo to factotum key set
#	intermediate version, for use until revised Inferno authentication is ready


# converts an old authinfo entry in keyring directory to a key for factotum
#
# keys are in proto=infauth, and include the data for the signed certificate, and the diffie-helman parameters

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	keyring: Keyring;
	Certificate, IPint, PK, SK: import keyring;

include "daytime.m";
	daytime: Daytime;

include "arg.m";

Ai2fact: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	keyring = load Keyring Keyring->PATH;
	daytime = load Daytime Daytime->PATH;

	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("ai2key [-t 'attr=value attr=value ...'] keyfile ...");
	tag: string;
	while((o := arg->opt()) != 0)
		case o {
		't' =>
			tag = arg->earg();
		* =>
			arg->usage();
		}
	args = arg->argv();
	if(args == nil)
		arg->usage();
	arg = nil;

	now := daytime->now();
	for(; args != nil; args = tl args){
		keyfile := hd args;
		ai := keyring->readauthinfo(keyfile);
		if(ai == nil)
			error(sys->sprint("cannot read %s: %r", keyfile));
		if(ai.cert.exp != 0 && ai.cert.exp <= now){
			sys->fprint(sys->fildes(2), "ai2key: %s: certificate expired -- key ignored\n", keyfile);
			continue;
		}

		if(ai.cert.exp != 0)
			expires := sys->sprint(" expires=%ud", ai.cert.exp);
		ha := ai.cert.ha;
		if(ha == "sha")
			ha = "sha1";

		if(tag != nil)
			tag = " "+tag;

		sys->print("key proto=infauth%s %s sigalg=%s-%s user=%q signer=%q pk=%s !sk=%s spk=%s cert=%s dh-alpha=%s dh-p=%s%s\n",
			tag, locations(filename(keyfile)), ai.cert.sa.name, ha, ai.mypk.owner, ai.spk.owner, pktostr(ai.mypk), sktostr(ai.mysk),
			pktostr(ai.spk), certtostr(ai.cert), ai.alpha.iptostr(16), ai.p.iptostr(16), expires);
	}
}

error(e: string)
{
	sys->fprint(sys->fildes(2), "ai2key: %s\n", e);
	raise "fail:error";
}

filename(s: string): string
{
	(nil, fld) := sys->tokenize(s, "/");
	for(; fld != nil && tl fld != nil; fld = tl fld){
		# skip
	}
	return hd fld;
}

# guess plausible domain, server and service attributes from the file name
locations(file: string): string
{
	if(file == "default")
		return "dom=* server=*";
	(nf, flds) := sys->tokenize(file, "!");
	case nf {
	* =>
		return sys->sprint("%s", server(file));
	2 =>
		return sys->sprint("%s", server(hd tl flds));
	3 =>
		# ignore network component
		return sys->sprint("%s service=%q", server(hd tl flds), hd tl tl flds);
	}
}

server(name: string): string
{
	# if the name contains dot(s), we'll treat it as a domain name
	if(sys->tokenize(name, ".").t0 > 1)
		return sys->sprint("dom=%q server=%q", name, name);
	return sys->sprint("server=%q", name);
}

certtostr(c: ref Certificate): string
{
	return dnl(keyring->certtostr(c));
}

pktostr(pk: ref PK): string
{
	return dnl(keyring->pktostr(pk));
}

sktostr(sk: ref SK): string
{
	return dnl(keyring->sktostr(sk));
}

dnl(s: string): string
{
	for(i := 0; i < len s; i++)
		if(s[i] == '\n')
			s[i] = '^';
	while(--i > 0 && s[i] == '^'){
		# skip
	}
	if(i != len s)
		return s[0: i+1];
	return s;
}
