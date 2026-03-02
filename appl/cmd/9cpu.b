implement P9cpu;

include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
include "sh.m";
	sh: Sh;
include "fdrun.m";
	fdrun: FDrun;
include "factotum.m";
include "encoding.m";
	b64: Encoding;
include "keyring.m";
include "security.m";

# to do/test:
# - inferno command
# - garbage process collection

# issues around factotum with inferno:
#
# key retention - adding keys to secstore is not easy, as it
# 		has to be done manually, and keys obtained with
#		getauthinfo are somewhat unwieldy.
#		we don't want to have to do a getauthinfo
#		every time we start factotum.
#
# algorithm negotiation - would it be reasonable to
#	add algorithm specification to keyspec?
#	e.g. proto=infauth role=server 'algs=rc4_256 sha1 md5'
#	or proto=infauth role=client 'alg=rc4_256/sha1'
# if not, how can the desired/allowed algorithm(s) be specified?

MaxStr: con 128;		# as defined in /sys/src/cmd/cpu.c

P9cpu: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

authmethods := array[] of {"p9", "netkey"};
finish: chan of int;

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	sh = load Sh Sh->PATH;
	b64 = load Encoding Encoding->BASE64PATH;
	arg := load Arg Arg->PATH;
	fdrun = load FDrun FDrun->PATH;
	fdrun->init();

	authmethod := "p9";
	keyspec := "";
	ealgs := "aes_256_cbc sha256";
	wmexport := 0;
	p9win := 0;
	infernocmd := 0;
	relaynotes := 1;
	p9winopts: list of string;
	system := "";
	cmd := "";

	arg->init(argv);
	arg->setusage("9cpu [-wrIn] [-e crypto_algs] [-a auth_method] [-k keyspec] [-c cmd] [-h system]");
	while((opt := arg->opt()) != 0){
		case opt {
		'a' =>
			authmethod = arg->earg();
		'k' =>
			keyspec = arg->earg();
		'e' =>
			ealgs = arg->earg();
		'w' =>
			wmexport = 1;
		'r' =>
			p9win = 1;
		'I' =>
			infernocmd = 1;
			wmexport = 1;
		'n' =>
			relaynotes = 0;
		'x' =>
			p9winopts = "-x"+arg->earg() :: p9winopts;
		'y' =>
			p9winopts = "-y"+arg->earg() :: p9winopts;
		'h' =>
			system = arg->earg();
		'c' =>
			cmd = arg->earg();
		* =>
			arg->usage();
		}
	}
	argv = arg->argv();
	if(argv != nil)
		arg->usage();
	for(i := 0; i < len authmethods; i++)
		if(authmethod == authmethods[i])
			break;
	if(i == len authmethods)
		fatal(sys->sprint("unknown authentication method %q", authmethod));

	sys->pctl(Sys->FORKNS, nil);
	(dfd, err) := rexcall(system, authmethod, keyspec, ealgs);
	if(dfd == nil)
		fatal(err);
	if(p9win && cmd == nil)
		cmd = "rio";
	else if(infernocmd){
		if(cmd == nil)
			cmd = "sh -i";
		cmd = "emu /dis/sh -c "+
			shquoted("{"+
				"bind '#U*' /n/local;"+
				"wmimport -d /n/local/mnt/term/dev -w /n/local/mnt/term/mnt/wm sh -c "+
					shquoted(cmd)+
				"}"
			);
	}
	finish = chan[1] of int;
	if(cmd != nil){
		# guard against limited size command buffer at other end.
		if(len array of byte cmd + 3 > MaxStr){
			writestr(dfd, "! . /mnt/term/dev/cpucmd", "command", 0);
			spawn servefileproc(sync := chan of int, "/dev", "cpucmd", array of byte (cmd+"\n"));
			<-sync;
		}else
			writestr(dfd, "! "+cmd, "command", 0);
	}
	cwd := sys->fd2path(sys->open(".", Sys->OREAD));
	if(cwd == nil)
		writestr(dfd, "NO", "dir", 0);
	else
		writestr(dfd, cwd, "dir", 0);

	(ok, data) := readstr(dfd, '\0');
	if(ok == -1)
		fatal("waiting for FS");
	if(len data < 2 || data[0:2] != "FS")
		fatal("remote cpu: "+data);
	exdir: string;
	(ok, exdir) = readstr(dfd, '\0');
	if(exdir != "/")
		fatal("cannot export portion of namespace");

	sys->write(dfd, array[] of {byte 'O', byte 'K'}, 2);

	# set up the namespace that we wish to export
	if(wmexport){
		sys->pipe(p := array[2] of ref Sys->FD);
		fdrun->run(ctxt, "wmexport"::nil, "0--", p[0:1], chan[1] of string);
		sys->mount(p[1], nil, "/mnt/wm", Sys->MREPL, nil);
	}
	if(relaynotes && !p9win){
		spawn relaynotesproc(sync := chan of int);
		<-sync;
	}

	if(p9win){
		fdrun->run(ctxt, "9win"::"-s"::p9winopts, "0--", array[] of {dfd}, status := chan of string);
		err = <-status;
		finish <-= 1;
		if(err != nil)
			raise "fail:"+err;
	}else{
		if(sys->export(dfd, "/", Sys->EXPWAIT) == -1)
			sys->print("export error: %r\n");
		finish <-= 1;
	}
}

shquoted(s: string): string
{
	return sh->quoted(ref Sh->Listnode(nil, s)::nil, 1);
}

rexcall(system, authmethod, keyspec, ealgs: string): (ref Sys->FD, string)
{
	Negerr: con "negotiating authentication method";
	na := netmkaddr(system, nil, "ncpu");
	(ok, c) := sys->dial(na, nil);
	if(ok == -1)
		return (nil, sys->sprint("cannot dial %q: %r", na));

	# plan 9 cpu protocol
	a := authmethod;
	if(ealgs != nil)
		a += " " + ealgs;
	writestr(c.dfd, a, Negerr, 0);
	err: string;
	(ok, err) = readstr(c.dfd, '\0');
	if(ok == -1)
		return (nil, Negerr);
	if(err != nil)
		return (nil, "readstr: "+err);

	case authmethod {
	"p9" =>
		return p9auth(c.dfd, ealgs, keyspec);
	"netkey" =>
		return netkeyauth(c.dfd);
	}
	return (nil, "unknown auth method");
}

netkeyauth(fd: ref Sys->FD): (ref Sys->FD, string)
{
	(ok, user) := ask("user["+getuser()+"]", getuser());
	if(ok == -1)
		return (nil, "terminated");
	writestr(fd, user, "challenge/response", 1);
	for(;;){
		chall: string;
		(ok, chall) = readstr(fd, '\0');
		if(ok == -1)
			return (nil, sys->sprint("readstr: %r"));
		if(chall == nil)
			return (fd, nil);
		resp: string;
		(ok, resp) = ask("challenge: "+chall+"; response", nil);
		if(ok == -1)
			break;
		writestr(fd, resp, "challenge/response", 1);
	}
	return (nil, "terminated");
}

ask(q: string, default: string): (int, string)
{
	sys->print("%s: ", q);
	(ok, s) := readstr(sys->fildes(0), '\n');
	if(ok == -1)
		return (-1, nil);
	if(s == nil)
		return (0, default);
	return (0, s);
}

p9auth(fd: ref Sys->FD, ealgs, keyspec: string): (ref Sys->FD, string)
{
	factotum := load Factotum Factotum->PATH;
	if(factotum == nil)
		return (nil, sys->sprint("cannot load %q: %r", Factotum->PATH));
	factotum->init();
	keyring := load Keyring Keyring->PATH;
	if(keyring == nil)
		return (nil, sys->sprint("cannot load %q: %r", Keyring->PATH));
	ai := factotum->proxy(fd, sys->open("/mnt/factotum/rpc", Sys->ORDWR),
			sys->sprint("proto=p9any role=client %s", keyspec));
	if(ai == nil)
		return (nil, sys->sprint("factotum: %r"));
	if(len ai.secret != 8)
		return (nil, "expected different length of secret");

	if(ealgs == nil)
		return (fd, nil);

	key := array[16] of byte;
	key[4:] = ai.secret;
	randombytes(key[0:4]);
	if(sys->write(fd, key, 4) != 4)
		return (nil, sys->sprint("write: %r"));
	if(readn(fd, key[12:], 4) != 4)
		return (nil, sys->sprint("read: %r"));
	digest := array[Keyring->SHA1dlen] of byte;
	keyring->sha1(key, len key, digest, nil);
	(efd, err) := pushssl(fd, ealgs, mksecret(digest), mksecret(digest[10:]));
	if(efd == nil)
		return (nil, sys->sprint("cannot push ssl: %s", err));
	return (efd, nil);
}

# plan 9 bug/strangeness: interpret hex string as base64 to use as secret.
mksecret(f: array of byte): array of byte
{
	return b64->dec(
		sys->sprint(
		"%2.2ux%2.2ux%2.2ux%2.2ux%2.2ux%2.2ux%2.2ux%2.2ux%2.2ux%2.2ux",
		int f[0], int f[1], int f[2], int f[3], int f[4],
		int f[5], int f[6], int f[7], int f[8], int f[9])
	);
}

# set up shell window button; relay events from that
relaynotesproc(sync: chan of int)
{
	shctl := sys->open("/chan/shctl", Sys->OWRITE);
	if(shctl == nil){
		sys->fprint(sys->fildes(2), "cpu: cannot relay notes: not in shell window\n");
		sync <-= -1;
		exit;
	}
	sys->fprint(shctl, "clear");
	if(sys->fprint(shctl, "action Interrupt interrupt") == -1){
		sys->fprint(sys->fildes(2), "cpu: cannot create interrupt button: %r\n");
		sync <-= -1;
		exit;
	}
	# create dummy placeholder file
	fio := file2chan("/dev", "cpunote");

	sys->bind("/chan/shctl", "/dev/cpunote", Sys->MREPL);
	sync <-= 0;
	finish <-= <-finish;
	sys->fprint(shctl, "clear");
	fio = nil;
}

file2chan(d, f: string): ref Sys->FileIO
{
	if((fio := sys->file2chan(d, f)) == nil){
		sys->bind("#s", "/dev", Sys->MBEFORE);
		fio = sys->file2chan(d, f);
	}
	return fio;
}

servefileproc(sync: chan of int, d, f: string, data: array of byte)
{
	fio := file2chan(d, f);
	sync <-= sys->pctl(0, nil);
	for(;;)alt{
	(offset, nil, nil, rc) := <-fio.read =>
		if(rc != nil){
			if(offset > len data)
				offset = len data;
			rc <-= (data[offset:], nil);
		}
	(nil, nil, nil, wc) := <-fio.write =>
		if(wc != nil)
			wc <-= (-1, "permission denied");
	<-finish =>
		finish <-= 1;
		exit;
	}
}

pushssl(fd: ref Sys->FD, ealgs: string, secretin, secretout: array of byte): (ref Sys->FD, string)
{
	ssl := load SSL SSL->PATH;
	if(ssl == nil)
		return (nil, sys->sprint("canot load %q: %r", SSL->PATH));
	(err, c) := ssl->connect(fd);
	if(err != nil)
		return (nil, "can't connect ssl: " + err);

	err = ssl->secret(c, secretin, secretout);
	if(err != nil)
		return (nil, "can't write secret: " + err);

	if(sys->fprint(c.cfd, "alg %s", ealgs) < 0)
		return (nil, sys->sprint("can't push algorithm %s: %r", ealgs));

	return (c.dfd, nil);
}

writestr(fd: ref Sys->FD, s: string, thing: string, ignore: int)
{
	x := array of byte s;
	x0 := array[len x+1] of byte;
	x0[0:] = x;
	x0[len x] = byte 0;
	n := sys->write(fd, x0, len x0);
	if(!ignore && n != len x0)
		fatal(sys->sprint("writing network: %s: %r", thing));
}

readstr(fd: ref Sys->FD, c: int): (int, string)
{
	buf := array[128] of byte;
	b := buf;
	l := 0;
	while(len b > 0){
		n := sys->read(fd, b, 1);
		if(n <= 0)
			return (-1, nil);
		if(int b[0] == c)
			return (0, string buf[0:l]);
		l++;
		b = b[1:];
	}
	return (-1, nil);
}	

netmkaddr(addr, net, svc: string): string
{
	if(net == nil)
		net = "net";
	(n, nil) := sys->tokenize(addr, "!");
	if(n <= 1){
		if(svc== nil)
			return sys->sprint("%s!%s", net, addr);
		return sys->sprint("%s!%s!%s", net, addr, svc);
	}
	if(svc == nil || n > 2)
		return addr;
	return sys->sprint("%s!%s", addr, svc);
}

randombytes(buf: array of byte): int
{
	fd := sys->open("/dev/notquiterandom", Sys->OREAD);
	if(fd == nil)
		return -1;
	if(sys->read(fd, buf, len buf) != len buf)
		return -1;
	return 0;
}

getuser(): string
{
	if ((s := readfile("/dev/user")) == nil)
		return "none";
	return s;
}

readfile(f: string): string
{
	fd := sys->open(f, sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return nil;

	return string buf[0:n];	
}

readn(fd: ref Sys->FD, buf: array of byte, nb: int): int
{
	for(nr := 0; nr < nb;){
		n := sys->read(fd, buf[nr:], nb-nr);
		if(n <= 0){
			if(nr == 0)
				return n;
			break;
		}
		nr += n;
	}
	return nr;
}

fatal(err: string)
{
	sys->fprint(sys->fildes(2), "cpu: %s\n", err);
	raise "fail:error";
}

kill(pid: int)
{
	sys->fprint(sys->open("#p/"+string pid+"/ctl", Sys->OWRITE), "kill");
}
