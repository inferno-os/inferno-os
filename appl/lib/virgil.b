implement Virgil;

include "sys.m";
	sys: Sys;
include "string.m";
include "keyring.m";
include "draw.m";
include "dial.m";
	dial: Dial;
include "security.m";
include "ip.m";
	ip: IP;
	IPaddr, Udphdr: import ip;

stderr: ref Sys->FD;
done: int;
Udphdrsize: con IP->Udphdrlen;
Virgilport: con 2202;

#
#  this module is very udp dependent.  it shouldn't be. -- presotto
#  Call with first element of argv an arbitrary string, which is
#  discarded here.  argv must also contain at least a question.
#
virgil(argv: list of string): string
{
	s,question,reply,r : string;
	timerpid, readerpid: int;

	if (argv == nil || tl argv == nil || hd (tl argv) == nil)
		return nil;
	done = 0;
	sys = load Sys Sys->PATH;
	dial = load Dial Dial->PATH;
	if(dial == nil){
		cantload(Dial->PATH);
		return nil;
	}
	str := load String String->PATH;
	if(str == nil){
		cantload(String->PATH);
		return nil;
	}
	ip = load IP IP->PATH;
	if(ip == nil){
		cantload(IP->PATH);
		return nil;
	}
	ip->init();
	stderr = sys->fildes(2);

	# We preserve the convention that the first arg is not an option.
	# Undocumented '-v address' option allows passing in address
	# of virgild, circumventing broadcast.  Used for development,
	# to avoid pestering servers on network.
	dest := ip->v4bcast;
	argv = tl argv;
	s = hd argv;
	if(s[0] == '-') {
		if(s[1] != 'v')
			return nil;
		argv = tl argv;
		if (argv == nil)
			return nil;
		s = hd argv;
		ok: int;
		(ok, dest) = IPaddr.parse(s);
		if(ok < 0){
			sys->fprint(stderr, "virgil: invalid IP address %s\n", s);
			return nil;
		}
		argv = tl argv;
	}

	# Is there a question?
	if (argv == nil)
		return nil;
	question = hd argv;

	c := dial->announce("udp!*!0");
	if(c == nil)
		return nil;
	if(sys->fprint(c.cfd, "headers") < 0)
		return nil;
	c.dfd = sys->open(c.dir+"/data", sys->ORDWR);
	if(c.dfd == nil)
		return nil;

	readerchan := chan of string;
	timerchan := chan of int;
	readerpidchan := chan of int;

	spawn timer(timerchan);
	timerpid = <-timerchan;
	spawn reader(c.dfd, readerchan, readerpidchan);
	readerpid = <-readerpidchan;

	question = getid() + "?" + question;
	qbuf := array of byte question;
	hdr := Udphdr.new();
	hdr.raddr = dest;
	hdr.rport = Virgilport;
	buf := array[Udphdrsize + len qbuf] of byte;
	buf[Udphdrsize:] = qbuf;
	hdr.pack(buf, Udphdrsize);
	for(tries := 0; tries < 5; ){
		if(sys->write(c.dfd, buf, len buf) < 0)
			break;

		alt {
		r = <-readerchan =>
			;
		<-timerchan =>
			tries++;
			continue;
		};

		if(str->prefix(question + "=", r)){
			reply = r[len question + 1:];
			break;
		}
	}

	done = 1;
	killpid(readerpid);
	killpid(timerpid);
	return reply;
}

cantload(s: string)
{
	sys->fprint(stderr, "virgil: can't load %s: %r\n", s);
}

getid(): string
{
	fd := sys->open("/dev/sysname", sys->OREAD);
	if(fd == nil)
		return "unknown";
	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 1)
		return "unknown";
	return string buf[0:n];
}

reader(fd: ref sys->FD, cstring: chan of string, cpid: chan of int)
{
	pid := sys->pctl(0, nil);
	cpid <-= pid;

	buf := array[2048] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= Udphdrsize)
		return;

	# dump cruft
	for(i := Udphdrsize; i < n; i++)
		if((int buf[i]) == 0)
				break;

	if(!done)
		cstring <-= string buf[Udphdrsize:i];
}

timer(c: chan of int)
{
	pid := sys->pctl(0, nil);
	c <-= pid;
	while(!done){
		sys->sleep(1000);
		if(done)
			break;
		c <-= 1;
	}
}

killpid(pid: int)
{
	fd := sys->open("#p/"+(string pid)+"/ctl", sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "kill");
}
