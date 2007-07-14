implement Rstyxd;

include "sys.m";
include "draw.m";
include "sh.m";
include "string.m";

sys: Sys;
str: String;
stderr: ref Sys->FD;

Rstyxd: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

#
# argv is a list of Inferno supported algorithms from Security->Auth
#
init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	if (str == nil)
		badmod(String->PATH);

	fd := sys->fildes(0);
	stderr = sys->fildes(2);
	sys->pctl(sys->FORKFD, fd.fd :: nil);

	args := readargs(fd);
	if(args == nil)
		err(sys->sprint("error reading arguments: %r"));

	cmd := hd args;
	s := "";
	for (a := args; a != nil; a = tl a)
		s += hd a + " ";
	sys->fprint(stderr, "rstyxd: cmd: %s\n", s);
	s = nil;
	file: string;
	if(cmd == "sh")
		file = "/dis/sh.dis";
	else
		file = cmd + ".dis";
	mod := load Command file;
	if(mod == nil){
		mod = load Command "/dis/"+file;
		if(mod == nil)
			badmod("/dis/"+file);
	}

	sys->pctl(Sys->FORKNS|Sys->FORKENV, nil);

	if(sys->mount(fd, nil, "/n/client", Sys->MREPL, "") < 0)
		err(sys->sprint("cannot mount connection on /n/client: %r"));

	if(sys->bind("/n/client/dev", "/dev", Sys->MBEFORE) < 0)
		err(sys->sprint("cannot bind /n/client/dev to /dev: %r"));

	fd = sys->open("/dev/cons", sys->OREAD);
	sys->dup(fd.fd, 0);
	fd = sys->open("/dev/cons", sys->OWRITE);
	sys->dup(fd.fd, 1);
	sys->dup(fd.fd, 2);
	fd = nil;

	mod->init(nil, args);
}

readargs(fd: ref Sys->FD): list of string
{
	buf := array[1024] of byte;
	c := array[1] of byte;
	for(i:=0; ; i++){
		if(i>=len buf || sys->read(fd, c, 1)!=1)
			return nil;
		buf[i] = c[0];
		if(c[0] == byte '\n')
			break;
	}
	nb := int string buf[0:i];
	if(nb <= 0)
		return nil;
	args := readn(fd, nb);
	if (args == nil)
		return nil;
	return str->unquoted(string args[0:nb]);
}

readn(fd: ref Sys->FD, nb: int): array of byte
{
	buf:= array[nb] of byte;
	if(sys->readn(fd, buf, nb) != nb)
		return nil;
	return buf;
}


err(s: string)
{
	sys->fprint(stderr, "rstyxd: %s\n", s);
	raise "fail:error";
}

badmod(s: string)
{
	sys->fprint(stderr, "rstyxd: can't load %s: %r\n", s);
	raise "fail:load";
}
