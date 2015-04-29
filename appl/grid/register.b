implement Register;

#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#


include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "dial.m";
	dial: Dial;
include "registries.m";
	registries: Registries;
	Registry, Attributes, Service: import registries;
include "grid/announce.m";
	announce: Announce;
include "arg.m";

registered: ref Registries->Registered;

Register: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(sys->FORKNS | sys->NEWPGRP, nil);
	dial = load Dial Dial->PATH;
	if (dial == nil)
		badmod(Dial->PATH);
	registries = load Registries Registries->PATH;
	if (registries == nil)
		badmod(Registries->PATH);
	registries->init();
	announce = load Announce Announce->PATH;
	if (announce == nil)
		badmod(Announce->PATH);
	announce->init();
	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmod(Arg->PATH);

	attrs := Attributes.new(("proto", "styx") :: ("auth", "none") :: ("resource","Cpu Pool") :: nil);
	maxusers := -1;
	autoexit := 0;
	myaddr := "";
	arg->init(argv);
	arg->setusage("register [-u maxusers] [-e exit threshold] [-a attributes] { program }");
	while ((opt := arg->opt()) != 0) {
		case opt {
		'm' =>
			attrs.set("memory", memory());
		'u' =>
			if ((maxusers = int arg->earg()) <= 0)
				arg->usage();
		'e' =>
			if ((autoexit = int arg->earg()) < 0)
				arg->usage();
		'A' =>
			myaddr = arg->earg();
		'a' =>
			attr := arg->earg();
			val := arg->earg();
			attrs.set(attr, val);
		}
	}
	argv = arg->argv();
	if (argv == nil)
		arg->usage();
	(nil, plist) := sys->tokenize(hd argv, "{} \t\n");
	arg = nil;	
	sysname := readfile("/dev/sysname");
	reg: ref Registry;
	reg = Registry.new("/mnt/registry");
	if (reg == nil)
		reg = Registry.connect(nil, nil, nil);
	if (reg == nil)
		error(sys->sprint("Could not find registry: %r\nMake sure that ndb/cs has been started and there is a registry announcing on the machine specified in /lib/ndb/local"));

	c : ref Sys->Connection;
	if (myaddr == nil) {
		(addr, conn) := announce->announce();
		if (addr == nil)
			error(sys->sprint("cannot announce: %r"));
		myaddr = addr;
		c = conn;
	}
	else {
		n: int;
		c = dial->announce(myaddr);
		if (c == nil)
			error(sys->sprint("cannot announce: %r"));
		(n, nil) = sys->tokenize(myaddr, "*");
		if (n > 1) {
			(nil, lst) := sys->tokenize(myaddr, "!");
			if (len lst >= 3)
				myaddr = "tcp!" + sysname +"!" + hd tl tl lst;
		}
	}
	persist := 0;
	if (attrs.get("name") == nil)
		attrs.set("name", sysname);
	err: string;
	(registered, err) = reg.register(myaddr, attrs, persist);
	if (err != nil) 
		error("could not register with registry: "+err);

	mountfd := popen(ctxt, plist);
	spawn listener(c, mountfd, maxusers);
}

listener(c: ref Sys->Connection, mountfd: ref sys->FD, maxusers: int)
{
	for (;;) {
		nc := dial->listen(c);
		if (nc == nil)
			error(sys->sprint("listen failed: %r"));
		if (maxusers != -1 && nusers >= maxusers) {
			sys->fprint(stderr(), "register: maxusers (%d) exceeded!\n", nusers);
			dial->reject(nc, "server overloaded");
		}else if ((dfd := dial->accept(nc)) != nil) {
			sync := chan of int;
			addr := readfile(nc.dir + "/remote");
			if (addr == nil)
				addr = "unknown";
			if (addr[len addr - 1] == '\n')
				addr = addr[:len addr - 1];
			spawn proxy(sync, dfd, mountfd, addr);
			<-sync;
		}
	}
}

proxy(sync: chan of int, dfd, mountfd: ref sys->FD, addr: string)
{
	pid := sys->pctl(Sys->NEWFD | Sys->NEWNS, 1 :: 2 :: mountfd.fd :: dfd.fd :: nil);
	dfd = sys->fildes(dfd.fd);
	mountfd = sys->fildes(mountfd.fd);
	sync <-= 1;
	done := chan of int;
	spawn exportit(dfd, done);
	if (sys->mount(mountfd, nil, "/", sys->MREPL | sys->MCREATE, addr) == -1)
		sys->fprint(stderr(), "register: proxy mount failed: %r\n");
	nusers++;
	<-done;
	nusers--;
}

nusers := 0;
clock(tick: chan of int)
{
	for (;;) {
		sys->sleep(2000);
		tick <-= 1;
	}
}

exportit(dfd: ref sys->FD, done: chan of int)
{
	sys->export(dfd, "/", sys->EXPWAIT);
	done <-= 1;
}

popen(ctxt: ref Draw->Context, argv: list of string): ref Sys->FD
{
	sync := chan of int;
	fds := array[2] of ref Sys->FD;
	sys->pipe(fds);
	spawn runcmd(ctxt, argv, fds[0], sync);
	<-sync;
	return fds[1];
}

runcmd(ctxt: ref Draw->Context, argv: list of string, stdin: ref Sys->FD, sync: chan of int)
{
	pid := sys->pctl(Sys->FORKFD, nil);
	sys->dup(stdin.fd, 0);
	stdin = nil;
	sync <-= 0;
	sh := load Sh Sh->PATH;
	sh->run(ctxt, argv);
}

error(e: string)
{
	sys->fprint(stderr(), "register: %s\n", e);
	raise "fail:error";
}

user(): string
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

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

badmod(path: string)
{
	sys->fprint(stderr(), "Register: cannot load %s: %r\n", path);
	exit;
}

killg(pid: int)
{
	if ((fd := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE)) != nil) {
		sys->fprint(fd, "killgrp");
		fd = nil;
	}
}

memory(): string
{
	buf := array[1024] of byte;
	s := readfile("/dev/memory");
	(nil, lst) := sys->tokenize(s, " \t\n");
	if (len lst > 2) {
		mem := int hd tl lst;
		mem /= (1024*1024);
		return string mem + "mb";
	}
	return "not known";
}
