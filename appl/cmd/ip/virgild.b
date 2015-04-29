implement Virgild;

include "sys.m";
sys: Sys;

include "draw.m";

include "dial.m";
dial: Dial;

include "ip.m";

Virgild: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;

Udphdrsize: con IP->Udphdrlen;

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	dial = load Dial Dial->PATH;

	stderr = sys->fildes(2);

	sys->pctl(Sys->FORKNS|Sys->FORKFD, nil);
	if(sys->chdir("/lib/ndb") < 0){
		sys->fprint(stderr, "virgild: no database\n");
		return;
	}

	for(;;sys->sleep(10*1000)){
		fd := openlisten();
		if(fd == nil)
			return;

		buf := array[512] of byte;
		for(;;){
			n := sys->read(fd, buf, len buf);
			if(n <= Udphdrsize){
				break;
			}
			if(n <= Udphdrsize+1)
				continue;

			# dump any cruft after the question
			for(i := Udphdrsize; i < n; i++){
				c := int buf[i];
				if(c == ' ' || c == 0 || c == '\n')
					break;
			}

			answer := query(string buf[Udphdrsize:i]);
			if(answer == nil)
				continue;

			# reply
			r := array of byte answer;
			if(len r > len buf - Udphdrsize)
				continue;
			buf[Udphdrsize:] = r;
			sys->write(fd, buf, Udphdrsize+len r);
		}
		fd = nil;
	}
}

openlisten(): ref Sys->FD
{
	c := dial->announce("udp!*!virgil");
	if(c == nil){
		sys->fprint(stderr, "virgild: can't open port: %r\n");
		return nil;
	}

	if(sys->fprint(c.cfd, "headers") <= 0){
		sys->fprint(stderr, "virgild: can't set headers: %r\n");
		return nil;
	}

	c.dfd = sys->open(c.dir+"/data", Sys->ORDWR);
	if(c.dfd == nil) {
		sys->fprint(stderr, "virgild: can't open data file\n");
		return nil;
	}
	return c.dfd;
}

#
#  query is userid?question
#
#  for now, we're ignoring userid
#
query(request: string): string
{
	(n, l) := sys->tokenize(request, "?");
	if(n < 2){
		sys->fprint(stderr, "virgild: bad request %s %d\n", request, n);
		return nil;
	}

	#
	#  until we have something better, ask cs
	#  to translate, make the request look cs-like
	#
	fd := sys->open("/net/cs", Sys->ORDWR);
	if(fd == nil){
		sys->fprint(stderr, "virgild: can't open /net/cs - %r\n");
		return nil;
	}
	q := array of byte ("tcp!" + hd(tl l) + "!1000");
	if(sys->write(fd, q, len q) < 0){
		sys->fprint(stderr, "virgild: can't write /net/cs - %r: %s\n", string q);
		return nil;
	}
	sys->seek(fd, big 0, 0);
	buf := array[512-Udphdrsize-len request-1] of byte;
	n = sys->read(fd, buf, len buf);
	if(n <= 0){
		sys->fprint(stderr, "virgild: can't read /net/cs - %r\n");
		return nil;
	}

	(nil, l) = sys->tokenize(string buf[0:n], " \t");
	(nil, l) = sys->tokenize(hd(tl l), "!");
	return request + "=" + hd l;
}
