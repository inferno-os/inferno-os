implement Passwd;

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "dial.m";
	dial: Dial;

include "security.m";
	auth: Auth;

include "arg.m";

Passwd: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

stderr, stdin, stdout: ref Sys->FD;
keysrv := "/mnt/keysrv";
signer := "$SIGNER";

usage()
{
	sys->fprint(sys->fildes(2), "usage: passwd [-u user] [-s signer] [keyfile]\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	stdin = sys->fildes(0);
	stdout = sys->fildes(1);
	stderr = sys->fildes(2);

	kr = load Keyring Keyring->PATH;
	if(kr == nil)
		noload(Keyring->PATH);
	dial = load Dial Dial->PATH;
	if(dial == nil)
		noload(Dial->PATH);
	auth = load Auth Auth->PATH;
	if(auth == nil)
		noload(Auth->PATH);
	auth->init();

	keyfile, id: string;
	arg := load Arg Arg->PATH;
	if(arg == nil)
		noload(Arg->PATH);
	arg->init(args);
	while((o := arg->opt()) != 0)
		case o {
		's' =>
			signer = arg->arg();
		'u' =>
			id = arg->arg();
		* =>
			usage();
		}
	args = arg->argv();
	arg = nil;

	if(args == nil)
		args = "default" :: nil;

	if(id == nil)
		id= user();

	if(args != nil)
		keyfile = hd args;
	else
		keyfile = "default";
	if(len keyfile > 0 && keyfile[0] != '/')
		keyfile = "/usr/" + id + "/keyring/" + keyfile;

	ai := kr->readauthinfo(keyfile);
	if(ai == nil)
		err(sys->sprint("can't read certificate from %s: %r", keyfile));
sys->print("key owner: %s\n", ai.mypk.owner);

	sys->pctl(Sys->FORKNS|Sys->FORKFD, nil);
	mountsrv(ai);

	# get password
	ok: int;
	secret: array of byte;
	oldhash: array of byte;
	word: string;
	for(;;){
		sys->print("Inferno secret: ");
		(ok, word) = readline(stdin, "rawon");
		if(!ok || word == nil)
			exit;
		secret = array of byte word;
		(nil, s) := hashkey(secret);
		for(i := 0; i < len word; i++)
			word[i] = ' ';
		oldhash = array of byte s;
		e := putsecret(oldhash, nil);
		if(e != "wrong secret"){
			if(e == nil)
				break;
			err(e);
		}
		sys->fprint(stderr, "!wrong secret\n");
	}
	newsecret: array of byte;
	for(;;){
		for(;;){
			sys->print("new secret [default = don't change]: ");
			(ok, word) = readline(stdin, "rawon");
			if(!ok)
				exit;
			if(word == "" && secret != nil)
				break;
			if(len word >= 8)
				break;
			sys->print("!secret must be at least 8 characters\n");
		}
		if(word != ""){
			# confirm password change
			word1 := word;
			sys->print("confirm: ");
			(ok, word) = readline(stdin, "rawon");
			if(!ok || word != word1){
				sys->fprint(stderr, "!entries didn't match\n");
				continue;
			}
			# TO DO...
			#pwbuf := array of byte word;
			#newsecret = array[Keyring->SHA1dlen] of byte;
			#kr->sha1(pwbuf, len pwbuf, newsecret, nil);
			newsecret = array of byte word;
		}
		if(!eq(newsecret, secret)){
			if((e := putsecret(oldhash, newsecret)) != nil){
				sys->fprint(stderr, "passwd: can't update secret for %s: %s\n", id, e);
				continue;
			}
		}
		break;
	}
}

noload(s: string)
{
	err(sys->sprint("can't load %s: %r", s));
}

err(s: string)
{
	sys->fprint(sys->fildes(2), "passwd: %s\n", s);
	raise "fail:error";
}

mountsrv(ai: ref Keyring->Authinfo): string
{
	c := dial->dial(dial->netmkaddr(signer, "net", "infkey"), nil);
	if(c == nil)
		err(sys->sprint("can't dial %s: %r", signer));
	(fd, id_or_err) := auth->client("sha1/rc4_256", ai, c.dfd);
	if(fd == nil)
		err(sys->sprint("can't authenticate with %s: %r", signer));
	if(sys->mount(fd, nil, keysrv, Sys->MREPL, nil) < 0)
		err(sys->sprint("can't mount %s on %s: %r", signer, keysrv));
	return id_or_err;
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

eq(a, b: array of byte): int
{
	if(len a != len b)
		return 0;
	for(i := 0; i < len a; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
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

putsecret(oldhash: array of byte, secret: array of byte): string
{
	fd := sys->create(keysrv+"/secret", Sys->OWRITE, 8r600);
	if(fd == nil)
		return sys->sprint("%r");
	n := len oldhash;
	if(secret != nil)
		n += 1 + len secret;
	buf := array[n] of byte;
	buf[0:] = oldhash;
	if(secret != nil){
		buf[len oldhash] = byte ' ';
		buf[len oldhash+1:] = secret;
	}
	if(sys->write(fd, buf, len buf) < 0)
		return sys->sprint("%r");
	return nil;
}

readline(io: ref Sys->FD, mode: string): (int, string)
{
	r : int;
	line : string;
	buf := array[8192] of byte;
	fdctl : ref Sys->FD;
	rawoff := array of byte "rawoff";

	if(mode == "rawon"){
		fdctl = sys->open("/dev/consctl", sys->OWRITE);
		if(fdctl == nil || sys->write(fdctl,array of byte mode,len mode) != len mode){
			sys->fprint(stderr, "unable to change console mode");
			return (0,nil);
		}
	}

	line = "";
	for(;;) {
		r = sys->read(io, buf, len buf);
		if(r <= 0){
			sys->fprint(stderr, "error read from console mode");
			if(mode == "rawon")
				sys->write(fdctl,rawoff,6);
			return (0, nil);
		}

		line += string buf[0:r];
		if ((len line >= 1) && (line[(len line)-1] == '\n')){
			if(mode == "rawon"){
				r = sys->write(stdout,array of byte "\n",1);
				if(r <= 0) {
					sys->write(fdctl,rawoff,6);
					return (0, nil);
				}
			}
			break;
		}
		else {
			if(mode == "rawon"){
				#r = sys->write(stdout, array of byte "*",1);
				if(r <= 0) {
					sys->write(fdctl,rawoff,6);
					return (0, nil);
				}
			}
		}
	}

	if(mode == "rawon")
		sys->write(fdctl,rawoff,6);

	return (1, line[0:len line - 1]);
}
