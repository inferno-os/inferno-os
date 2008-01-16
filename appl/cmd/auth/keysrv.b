implement Keysrv;

#
# remote access to keys (currently only to change secret)
#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "security.m";
	auth: Auth;

include "arg.m";

keydb := "/mnt/keys";

Keysrv: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

usage()
{
	sys->fprint(sys->fildes(2), "usage: keysrv\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	if(sys->pctl(Sys->FORKNS|Sys->NEWPGRP, nil) < 0)
		err(sys->sprint("can't fork name space: %r"));

	keyfile := "/usr/"+user()+"/keyring/default";

	arg := load Arg Arg->PATH;
	if(arg == nil)
		err("can't load Arg");
	arg->init(args);
	while((o := arg->opt()) != 0)
		case o {
		'k' =>
			keyfile = arg->arg();
		* =>
			usage();
		}
	args = arg->argv();
	arg = nil;

	kr = load Keyring Keyring->PATH;
	if(kr == nil)
		err("can't load Keyring");

	auth = load Auth Auth->PATH;
	if(auth == nil)
		err("can't load Auth");
	auth->init();

	ai := kr->readauthinfo(keyfile);
	if(ai == nil)
		err(sys->sprint("can't read server key file %s: %r", keyfile));

	(fd, id_or_err) := auth->server("sha1" :: "rc4_256" :: nil, ai, sys->fildes(0), 0);
	if(fd == nil)
		err(sys->sprint("can't authenticate: %s", id_or_err));

	if(sys->bind("#s", "/mnt/keysrv", Sys->MREPL) < 0)
		err(sys->sprint("can't bind #s on /mnt/keysrv: %r"));
	srv := sys->file2chan("/mnt/keysrv", "secret");
	if(srv == nil)
		err(sys->sprint("can't create file2chan on /mnt/keysrv: %r"));
	exitc := chan of int;
	spawn worker(srv, id_or_err, exitc);
	if(sys->export(fd, "/mnt/keysrv", Sys->EXPWAIT) < 0){
		exitc <-= 1;
		err(sys->sprint("can't export %s: %r", "/mnt/keysrv"));
	}
	exitc <-= 1;
}

err(s: string)
{
	sys->fprint(sys->fildes(2), "keysrv: %s\n", s);
	raise "fail:error";
}

user(): string
{
	fd := sys->open("/dev/user", Sys->OREAD);
	if(fd == nil)
		err(sys->sprint("can't open /dev/user: %r"));

	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		err(sys->sprint("error reading /dev/user: %r"));

	return string buf[0:n];	
}

worker(file: ref Sys->FileIO, user: string, exitc: chan of int)
{
	(keydir, secret, err) := getuser(user);
	if(keydir == nil || secret == nil){
		if(err == nil)
			err = "no existing secret";		# can't change it remotely until set
	}
	(nil, hash) := hashkey(secret);
	for(;;)alt{
	<-exitc =>
		exit;
	(nil, nil, nil, rc) := <-file.read =>
		if(rc == nil)
			break;
		if(err != nil){
			rc <-= (nil, err);
			break;
		}
		rc <-= (nil, nil);
	(nil, data, nil, wc) := <-file.write =>
		if(wc == nil)
			break;
		if(err != nil){
			wc <-= (0, err);
			break;
		}
		for(i := 0; i < len data; i++)
			if(data[i] == byte ' ')
				break;
		if(string data[0:i] != hash){
			wc <-= (0, "wrong secret");
			break;
		}
		if(++i >= len data){
			wc <-= (0, nil);
			break;
		}
		if(len data - i < 8){
			wc <-= (0, "unacceptable secret");
			break;
		}
		if(putsecret(keydir, data[i:]) < 0){
			wc <-= (0, sys->sprint("can't update secret: %r"));
			break;
		}
		wc <-= (len data, nil);
	}
}

hashkey(a: array of byte): (array of byte, string)
{
	hash := array[Keyring->SHA1dlen] of byte;
	kr->sha1(a, len a, hash, nil);
	s := "";
	for(i := 0; i < len hash; i++)
		s += sys->sprint("%2.2ux", int hash[i]);
	return (hash, s);
}

getuser(id: string): (string, array of byte, string)
{
	(ok, nil) := sys->stat(keydb);
	if(ok < 0)
		return (nil, nil, sys->sprint("can't stat %s: %r", id));
	dbdir := keydb+"/"+id;
	(ok, nil) = sys->stat(dbdir);
	if(ok < 0)
		return (nil, nil, sys->sprint("user not registered: %s", id));
	fd := sys->open(dbdir+"/secret", Sys->OREAD);
	if(fd == nil)
		return (nil, nil, sys->sprint("can't open %s/secret: %r", id));
	d: Sys->Dir;
	(ok, d) = sys->fstat(fd);
	if(ok < 0)
		return (nil, nil, sys->sprint("can't stat %s/secret: %r", id));
	l := int d.length;
	secret: array of byte;
	if(l > 0){
		secret = array[l] of byte;
		if(sys->read(fd, secret, len secret) != len secret)
			return (nil, nil, sys->sprint("error reading %s/secret: %r", id));
	}
	return (dbdir, secret, nil);
}

putsecret(dir: string, secret: array of byte): int
{
	fd := sys->create(dir+"/secret", Sys->OWRITE, 8r600);
	if(fd == nil)
		return -1;
	return sys->write(fd, secret, len secret);
}
