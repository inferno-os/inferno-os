implement Getauthinfo;

#
# get and save a certificate from a signer in exchange for a valid secret
#

include "sys.m";
	sys: Sys;
	stdin, stdout, stderr: ref Sys->FD;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "security.m";
	login: Login;

include "string.m";
	str: String;

include "promptstring.b";

Getauthinfo: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(stderr, "usage: getauthinfo {net!hostname | default | /file}\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stdin = sys->fildes(0);
	stdout = sys->fildes(1);
	stderr = sys->fildes(2);

	# Disable echoing in RAWON mode
	RAWON_STR = nil;

	argv = tl argv;
	if(argv == nil)
		usage();
	keyname := hd argv;
	if(keyname == nil)
		usage();

	kr = load Keyring Keyring->PATH;
	if(kr == nil)
		nomod(Keyring->PATH);

	str = load String String->PATH;
	if(str == nil)
		nomod(String->PATH);

	login = load Login Login->PATH;
	if(login == nil)
		nomod(Login->PATH);

	user := user();
	path := keyname;
	if(path[0] != '/' && (len path < 2 || path[0:2] != "./"))
		path = "/usr/" + user + "/keyring/" + keyname;

	signer := defaultsigner();
	if(signer == nil){
		sys->fprint(stderr, "getauthinfo: warning: can't get default signer server name\n");
		signer = "$SIGNER";
	}

	passwd := "";
	save := "yes";
	for(;;) {
		signer = promptstring("use signer", signer, RAWOFF);
		user = promptstring("remote user name", user, RAWOFF);
		passwd = promptstring("password", passwd, RAWON);

		info := logon(user, passwd, signer, path, save);
		if(info != nil)
			break;
	}
}

logon(user, passwd, server, path, save: string): ref Keyring->Authinfo
{
	(err, info) := login->login(user, passwd, "net!"+server+"!inflogin");
	if(err != nil){
		sys->fprint(stderr, "getauthinfo: failed to authenticate: %s\n", err);
		return nil;
	}

	# save the info somewhere for later access
	save = promptstring("save in file", save, RAWOFF);
	if(save[0] != 'y'){
		(dir, file) := str->splitr(path, "/");
		if(sys->bind("#s", dir, Sys->MBEFORE) < 0){
			sys->fprint(stderr, "getauthinfo: can't bind file channel on %s: %r\n", dir);
			return nil;
		}
		filio := sys->file2chan(dir, file);
		if(filio == nil) {
			sys->fprint(stderr, "getauthinfo: can't make file2chan %s: %r\n", path);
			return nil;
		}
		sync := chan of int;
		spawn infofile(filio, sync);
		<-sync;
	}

	if(kr->writeauthinfo(path, info) < 0) {
		sys->fprint(stderr, "getauthinfo: can't write certificate to %s: %r\n", path);
		return nil;
	}

	return info;
}

user(): string
{
	sys = load Sys Sys->PATH;

	fd := sys->open("/dev/user", sys->OREAD);
	if(fd == nil)
		return "";

	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return "";

	return string buf[0:n];	
}

infofile(fileio: ref Sys->FileIO, sync: chan of int)
{
	infodata := array[0] of byte;

	sys->pctl(Sys->NEWPGRP|Sys->NEWFD, nil);
	sync <-= 1;

	for(;;) alt {
	(off, nbytes, nil, rc) := <-fileio.read =>
		if(rc == nil)
			break;
		if(off > len infodata){
			rc <-= (nil, nil);
		} else {
			if(off + nbytes > len infodata)
				nbytes = len infodata - off;
			rc <-= (infodata[off:off+nbytes], nil);
		}

	(off, data, nil, wc) := <-fileio.write =>
		if(wc == nil)
			break;

		if(off != len infodata){
			wc <-= (0, "cannot be rewritten");
		} else {
			nid := array[len infodata+len data] of byte;
			nid[0:] = infodata;
			nid[len infodata:] = data;
			infodata = nid;
			wc <-= (len data, nil);
		}
		data = nil;
	}
}

# get default signer server name
defaultsigner(): string
{
	return "$SIGNER";
}

nomod(s: string)
{
	sys->fprint(stderr, "getauthinfo: can't load %s: %r\n", s);
	raise "fail:load";
}
