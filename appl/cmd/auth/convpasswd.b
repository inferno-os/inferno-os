implement Convpasswd;

include "sys.m";
	sys: Sys;
include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "keyring.m";
	keyring: Keyring;
	IPint: import keyring;

include "security.m";

include "arg.m";

Convpasswd: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

PW: adt {
	id:	string;			# user id
	pw:	array of byte;	# password hashed by SHA
	expire:	int;		# expiration time (epoch seconds)
	other:	string;		# about the account	
};

mntpt := "/mnt/keys";

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	keyring = load Keyring Keyring->PATH;
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		noload(Arg->PATH);
	arg := load Arg Arg->PATH;
	if(arg == nil)
		noload(Arg->PATH);
	force := 0;
	verbose := 0;
	arg->init(args);
	arg->setusage("convpasswd [-f] [-v] [-m /mnt/keys] [passwordfile]");
	while((o := arg->opt()) != 0)
		case o {
		'f' =>		force = 1;
		'm' =>	mntpt = arg->earg();
		'v' =>	verbose = 1;
		* =>		arg->usage();
		}
	args = arg->argv();
	arg = nil;

	f := "/keydb/password";
	if(args != nil)
		f = hd args;
	iob := bufio->open(f, Bufio->OREAD);
	if(iob == nil)
		error(sys->sprint("%s: %r", f));
	for(line := 1; (s := iob.gets('\n')) != nil; line++) {
		(n, tokl) := sys->tokenize(s, ":\n");
		if (n < 3){
			sys->fprint(sys->fildes(2), "convpasswd: %s:%d: invalid format\n", f, line);
			continue;
		}
		pw := ref PW;
		pw.id = hd tokl;
		pw.pw = IPint.b64toip(hd tl tokl).iptobytes();
		pw.expire = int hd tl tl tokl;
		if (n==3)
			pw.other = nil;
		else
			pw.other = hd tl tl tl tokl;
		err := writekey(pw, force);
		if(err != nil)
			error(sys->sprint("error writing /mnt/keys entry for %s: %s", pw.id, err));
		if(verbose)
			sys->print("%s\n", pw.id);
	}
}

noload(p: string)
{
	error(sys->sprint("can't load %s: %r", p));
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "convpasswd: %s\n", s);
	raise "fail:error";
}

writekey(pw: ref PW, force: int): string
{
	dir := mntpt+"/"+pw.id;
	if(sys->open(dir, Sys->OREAD) == nil){
		# make it
		d := sys->create(dir, Sys->OREAD, Sys->DMDIR|8r600);
		if(d == nil)
			return sys->sprint("can't create %s: %r", dir);
	}else if(!force)
		return nil;		# leave existing entry alone
	secret := dir+"/secret";
	fd := sys->open(secret, Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("can't open %s: %r", secret);
	if(sys->write(fd, pw.pw, len pw.pw) != len pw.pw)
		return sys->sprint("error writing %s: %r", secret);
	expire := dir+"/expire";
	fd = sys->open(expire, Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("can't open %s: %r", expire);
	if(sys->fprint(fd, "%d", pw.expire) < 0)
		return sys->sprint("error writing %s: %r", expire);
	# no equivalent of `other'
	return nil;
}
