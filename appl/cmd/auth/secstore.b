implement Secstorec;

#
# interact with the Plan 9 secstore
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "secstore.m";
	secstore: Secstore;

include "arg.m";

Secstorec: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Maxfilesize: con 128*1024;

stderr: ref Sys->FD;
conn: ref Sys->Connection;
seckey: array of byte;
filekey: array of byte;
file: array of byte;
verbose := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	secstore = load Secstore Secstore->PATH;

	sys->pctl(Sys->FORKFD, nil);
	stderr = sys->fildes(2);
	secstore->init();
	secstore->privacy();

	addr := "net!$auth!secstore";
	user := readfile("/dev/user");
	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("auth/secstore [-iv] [-k key] [-p pin] [-s net!server!secstore] [-u user] [{drptx} file ...]");
	iflag := 0;
	pass, pin: string;
	while((o := arg->opt()) != 0)
		case o {
		'i' => iflag = 1;
		'k' => pass = arg->earg();
		'v' => verbose = 1;
		's' =>	addr = arg->earg();
		'u' => user = arg->earg();
		'p' => pin = arg->earg();
		* =>
			arg->usage();
		}
	args = arg->argv();
	op := -1;
	if(args != nil){
		if(len hd args != 1)
			arg->usage();
		op = (hd args)[0];
		args = tl args;
		case op {
		'd' or 'r' or 'p' or 'x' =>
			if(args == nil)
				arg->usage();
		't' =>
			;
		* =>
			arg->usage();
		}
	}
	arg = nil;

	if(iflag){
		buf := array[Secstore->Maxmsg] of byte;
		stdin := sys->fildes(0);
		for(nr := 0; nr < len buf && (n := sys->read(stdin, buf, len buf-nr)) > 0;)
			nr += n;
		s := string buf[0:nr];
		secstore->erasekey(buf[0:nr]);
		(nf, flds) := sys->tokenize(s, "\n");
		for(i := 0; i < len s; i++)
			s[i] = 0;
		if(nf < 1)
			error("no password on standard input");
		pass = hd flds;
		if(nf > 1)
			pin = hd tl flds;
	}
	conn: ref Sys->Connection;
Auth:
	for(;;){
		if(!iflag)
			pass = readpassword("secstore password");
		if(pass == nil)
			exit;
		erase();
		seckey = secstore->mkseckey(pass);
		filekey = secstore->mkfilekey(pass);
		for(i := 0; i < len pass; i++)
			pass[i] = 0;	# clear it
		conn = secstore->dial(netmkaddr(addr, "net", "secstore"));
		if(conn == nil)
			error(sys->sprint("can't connect to secstore: %r"));
		(srvname, diag) := secstore->auth(conn, user, seckey);
		if(srvname == nil){
			secstore->bye(conn);
			sys->fprint(stderr, "secstore: authentication failed: %s\n",  diag);
			if(iflag)
				raise "fail:auth";
			continue;
		}
		case diag {
		"" =>
			if(verbose)
				sys->fprint(stderr, "server: %s\n", srvname);
			secstore->erasekey(seckey);
			seckey = nil;
			break Auth;
		"need pin" =>
			if(!iflag){
				pin = readpassword("STA PIN+SecureID");
				if(len pin == 0){
					sys->fprint(stderr, "cancelled");
					exit;
				}
			}else if(pin == nil)
				raise "fail:no pin";
			if(secstore->sendpin(conn, pin) < 0){
				sys->fprint(stderr, "secstore: pin rejected: %r\n");
				if(iflag)
					raise "fail:bad pin";
				continue;
			}
		}
	}
	if(op == 't'){
		erase();	# no longer need the keys
		entries := secstore->files(conn);
		for(; entries != nil; entries = tl entries){
			(name, size, date, hash, nil) := hd entries;
			if(args != nil){
				for(l := args; l != nil; l = tl l)
					if((hd args) == name)
						break;
				if(args == nil)
					continue;
			}
			if(verbose)
				sys->print("%-14q %10d %s %s\n", name, size, date, hash);
			else
				sys->print("%q\n", name);
		}
		exit;
	}
	for(; args != nil; args = tl args){
		fname := hd args;
		case op {
		'd' =>
			checkname(fname, 1);
			if(secstore->remove(conn, fname) < 0)
				error(sys->sprint("can't remove %q: %r", fname));
			verb('d', fname);
		'p' =>
			checkname(fname, 1);
			file = getfile(conn, fname, filekey);
			lines := secstore->lines(file);
			lno := 1;
			for(; lines != nil; lines = tl lines){
				l := hd lines;
				if(sys->write(sys->fildes(1), l, len l) != len l)
					sys->fprint(sys->fildes(2), "secstore (%s:%d): %r\n", fname, lno);
				lno++;
			}
			secstore->erasekey(file);
			file = nil;
			verb('p', fname);
		'x' =>
			checkname(fname, 1);
			file = getfile(conn, fname, filekey);
			ofd := sys->create(fname, Sys->OWRITE, 8r600);
			if(ofd == nil)
				error(sys->sprint("can't create %q: %r", fname));
			if(sys->write(ofd, file, len file) != len file)
				error(sys->sprint("error writing to %q: %r", fname));
			secstore->erasekey(file);
			file = nil;
			verb('x', fname);
		'r' or * =>
			error(sys->sprint("op %c not implemented", op));
		}
	}
	erase();
}

checkname(s: string, noslash: int): string
{
	tail := s;
	for(i := 0; i < len s; i++){
		if(s[i] == '/'){
			if(noslash)
				break;
			tail = s[i+1:];
		}
		if(s[i] == '\n' || s[i] <= ' ')
			break;
	}
	if(s == nil || tail == nil || i < len s || s == "..")
		error(sys->sprint("can't use %q as a secstore file name", s));	# server checks as well, of course
	return tail;
}

verb(op: int, n: string)
{
	if(verbose)
		sys->fprint(stderr, "%c %q\n", op, n);
}

getfile(conn: ref Sys->Connection, fname: string, key: array of byte): array of byte
{
	f := secstore->getfile(conn, fname, 0);
	if(f == nil)
		error(sys->sprint("can't fetch %q: %r", fname));
	if(fname != "."){
		f = secstore->decrypt(f, key);
		if(f == nil)
			error(sys->sprint("can't decrypt %q: %r", fname));
	}
	return f;
}

erase()
{
	if(secstore != nil){
		secstore->erasekey(seckey);
		secstore->erasekey(filekey);
		secstore->erasekey(file);
	}
}

error(s: string)
{
	erase();
	sys->fprint(stderr, "secstore: %s\n", s);
	raise "fail:error";
}

readpassword(prompt: string): string
{
	cons := sys->open("/dev/cons", Sys->ORDWR);
	if(cons == nil)
		return nil;
	stdin := bufio->fopen(cons, Sys->OREAD);
	if(stdin == nil)
		return nil;
	cfd := sys->open("/dev/consctl", Sys->OWRITE);
	if (cfd == nil || sys->fprint(cfd, "rawon") <= 0)
		sys->fprint(stderr, "secstore: warning: cannot hide typed password\n");
L:
	for(;;){
		sys->fprint(cons, "%s: ", prompt);
		s := "";
		while ((c := stdin.getc()) >= 0){
			case c {
			'\n' or ('d'&8r037) =>
				sys->fprint(cons, "\n");
				return s;
			'\b' or 8r177 =>
				if(len s > 0)
					s = s[0:len s - 1];
			'u' & 8r037 =>
				sys->fprint(cons, "\n");
				continue L;
			* =>
				s[len s] = c;
			}
		}
		break;
	}
	return nil;
}

readfile(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return "";
	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return "";
	return string buf[0:n]; 
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
