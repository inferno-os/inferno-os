implement Changelogin;

include "sys.m";
	sys: Sys;

include "daytime.m";
	daytime: Daytime;

include "draw.m";

include "keyring.m";
	kr: Keyring;

Changelogin: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

stderr, stdin, stdout: ref Sys->FD;
keydb := "/mnt/keys";

init(nil: ref Draw->Context, args: list of string)
{
	ok: int;
	word: string;

	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;

	stdin = sys->fildes(0);
	stdout = sys->fildes(1);
	stderr = sys->fildes(2);

	argv0 := hd args;
	args = tl args;

	if(args == nil){
		sys->fprint(stderr, "usage: %s userid\n", argv0);
		raise "fail:usage";
	}

	daytime = load Daytime Daytime->PATH;
	if(daytime == nil) {
		sys->fprint(stderr, "%s: can't load Daytime: %r\n", argv0);
		raise "fail:load";
	}

	# get password
	id := hd args;
	(dbdir, secret, expiry, err) := getuser(id);
	if(dbdir == nil){
		if(err != nil){
			sys->fprint(stderr, "%s: can't get auth info for %s in %s: %s\n", argv0, id, keydb, err);
			raise "fail:no key";
		}
		sys->print("new account\n");
	}
	for(;;){
		if(secret != nil)
			sys->print("secret [default = don't change]: ");
		else
			sys->print("secret: ");
		(ok, word) = readline(stdin, "rawon");
		if(!ok)
			exit;
		if(word == "" && secret != nil)
			break;
		if(len word >= 8)
			break;
		sys->print("!secret must be at least 8 characters\n");
	}
	newsecret: array of byte;
	if(word != ""){
		# confirm password change
		word1 := word;
		sys->print("confirm: ");
		(ok, word) = readline(stdin, "rawon");
		if(!ok || word != word1) {
			sys->print("Entries do not match. Authinfo record unchanged.\n"); 
			raise "fail:mismatch";
		}

		pwbuf := array of byte word;
		newsecret = array[Keyring->SHA1dlen] of byte;
		kr->sha1(pwbuf, len pwbuf, newsecret, nil);
	}

	# get expiration time (midnight of date specified)
	maxdate := "17012038";			# largest date possible without incurring integer overflow
	now := daytime->now();
	tm := daytime->local(now);
	tm.sec = 59;
	tm.min = 59;
	tm.hour = 23;
	tm.year += 1;
	if(dbdir == nil)
		expsecs := daytime->tm2epoch(tm);	# set expiration date to 23:59:59 one year from today
	else
		expsecs = expiry;
	for(;;){
		defexpdate := "permanent";
		if(expsecs != 0) {
			otm := daytime->local(expsecs);
			defexpdate = sys->sprint("%2.2d%2.2d%4.4d", otm.mday, otm.mon+1, otm.year+1900);
		}
		sys->print("expires [DDMMYYYY/permanent, return = %s]: ", defexpdate);
		(ok, word) = readline(stdin, "rawoff");
		if(!ok)
			exit;
		if(word == "")
			word = defexpdate;
		if(word == "permanent"){
			expsecs = 0;
			break;
		}
		if(len word != 8){
			sys->print("!bad date format %s\n", word);
			continue;
		}
		tm.mday = int word[0:2];
		if(tm.mday > 31 || tm.mday < 1){
			sys->print("!bad day of month %d\n", tm.mday);
			continue;
		}
		tm.mon = int word[2:4] - 1;
		if(tm.mon > 11 || tm.mday < 0){
			sys->print("!bad month %d\n", tm.mon + 1);
			continue;
		}
		tm.year = int word[4:8] - 1900;
		if(tm.year < 70){
			sys->print("!bad year %d (year may be no earlier than 1970)\n", tm.year + 1900);
			continue;
		}
		expsecs = daytime->tm2epoch(tm);
		if(expsecs > now)
			break;
		else {
			newexpdate := sys->sprint("%2.2d%2.2d%4.4d", tm.mday, tm.mon+1, tm.year+1900);
			tm          = daytime->local(daytime->now());
			today      := sys->sprint("%2.2d%2.2d%4.4d", tm.mday, tm.mon+1, tm.year+1900);
			sys->print("!bad expiration date %s (must be between %s and %s)\n", newexpdate, today, maxdate);
			expsecs = now;
		}
	}
	newexpiry := expsecs;

#	# get the free form field
#	if(pw != nil)
#		npw.other = pw.other;
#	else
#		npw.other = "";
#	sys->print("free form info [return = %s]: ", npw.other);
#	(ok, word) = readline(stdin,"rawoff");
#	if(!ok)
#		exit;
#	if(word != "")
#		npw.other = word;

	if(dbdir == nil){
		dbdir = keydb+"/"+id;
		fd := sys->create(dbdir, Sys->OREAD, Sys->DMDIR|8r700);
		if(fd == nil){
			sys->fprint(stderr, "%s: can't create account %s: %r\n", argv0, id);
			raise "fail:create user";
		}
	}
	changed := 0;
	if(!eq(newsecret, secret)){
		if(putsecret(dbdir, newsecret) < 0){
			sys->fprint(stderr, "%s: can't update secret for %s: %r\n", argv0, id);
			raise "fail:update";
		}
		changed = 1;
	}
	if(newexpiry != expiry){
		if(putexpiry(dbdir, newexpiry) < 0){
			sys->fprint(stderr, "%s: can't update expiry time for %s: %r\n", argv0, id);
			raise "fail:update";
		}
		changed = 1;
	}
	sys->print("change written\n");
}

getuser(id: string): (string, array of byte, int, string)
{
	(ok, nil) := sys->stat(keydb);
	if(ok < 0)
		return (nil, nil, 0, sys->sprint("can't stat %s: %r", id));
	dbdir := keydb+"/"+id;
	(ok, nil) = sys->stat(dbdir);
	if(ok < 0)
		return (nil, nil, 0, nil);
	fd := sys->open(dbdir+"/secret", Sys->OREAD);
	if(fd == nil)
		return (nil, nil, 0, sys->sprint("can't open %s/secret: %r", id));
	d: Sys->Dir;
	(ok, d) = sys->fstat(fd);
	if(ok < 0)
		return (nil, nil, 0, sys->sprint("can't stat %s/secret: %r", id));
	l := int d.length;
	secret: array of byte;
	if(l > 0){
		secret = array[l] of byte;
		if(sys->read(fd, secret, len secret) != len secret)
			return (nil, nil, 0, sys->sprint("error reading %s/secret: %r", id));
	}
	fd = sys->open(dbdir+"/expire", Sys->OREAD);
	if(fd == nil)
		return (nil, nil, 0, sys->sprint("can't open %s/expiry: %r", id));
	b := array[32] of byte;
	n := sys->read(fd, b, len b);
	if(n <= 0)
		return (nil, nil, 0, sys->sprint("error reading %s/expiry: %r", id));
	return (dbdir, secret, int string b[0:n], nil);
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

putsecret(dir: string, secret: array of byte): int
{
	fd := sys->create(dir+"/secret", Sys->OWRITE, 8r600);
	if(fd == nil)
		return -1;
	return sys->write(fd, secret, len secret);
}

putexpiry(dir: string, expiry: int): int
{
	fd := sys->open(dir+"/expire", Sys->OWRITE);
	if(fd == nil)
		return -1;
	return sys->fprint(fd, "%d", expiry);
}

readline(io: ref Sys->FD, mode: string): (int, string)
{
	r : int;
	line : string;
	buf := array[8192] of byte;
	fdctl : ref Sys->FD;
	rawoff := array of byte "rawoff";

	#
	# Change console mode to rawon
	#
	if(mode == "rawon"){
		fdctl = sys->open("/dev/consctl", sys->OWRITE);
		if(fdctl == nil || sys->write(fdctl,array of byte mode,len mode) != len mode){
			sys->fprint(stderr, "unable to change console mode");
			return (0,nil);
		}
	}

	#
	# Read up to the CRLF
	#
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

	# Total success!
	return (1, line[0:len line - 1]);
}
