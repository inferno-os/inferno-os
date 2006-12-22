implement DBserver;

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";

include "security.m";

include "db.m";              # For now.

stderr: ref Sys->FD;

DBserver : module
{
	init:   fn(ctxt: ref Draw->Context, argv: list of string);
};

# argv is a list of Inferno supported algorithms from Security->Auth

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stdin := sys->fildes(0);
	stderr = sys->fildes(2);
	if(argv != nil)
		argv = tl argv;
	if(argv == nil)
		err("no algorithm list");

	kr := load Keyring Keyring->PATH;
	if(nil == kr)
		err(sys->sprint("can't load Keyring: %r"));

	auth := load Auth Auth->PATH;
	if(auth == nil)
		err(sys->sprint("can't load Auth: %r"));

	error := auth->init();
	if(error != nil)
		err(sys->sprint("Auth init failed: %s", error));

	ai := kr->readauthinfo("/usr/"+user()+"/keyring/default");

	(client_fd, info_or_err) := auth->server(argv, ai, stdin, 1);
	if(client_fd == nil)
		err(sys->sprint("can't authenticate client: %s", info_or_err));

	auth = nil;
	kr = nil;

	sys->pctl(Sys->FORKNS|Sys->NEWPGRP, nil);

	# run the infdb database program in the host system using /cmd

	cmdfd := sys->open("/cmd/clone", sys->ORDWR);
	if (cmdfd == nil)
		err(sys->sprint("can't open /cmd/clone: %r"));

	buf := array [20] of byte;
	n := sys->read(cmdfd, buf, len buf);
	if(n <= 0)
		err(sys->sprint("can't read /cmd/clone: %r"));
	cmddir := string buf[0:n];

	if (sys->fprint(cmdfd, "exec infdb") <= 0)
		err(sys->sprint("can't start infdb via /cmd/clone: %r"));

	datafile := "/cmd/" + cmddir + "/data";
	infdb_fd := sys->open(datafile, Sys->ORDWR);
	if (infdb_fd == nil)
		err(sys->sprint("can't open %s: %r", datafile));

	spawn dbxfer(infdb_fd, client_fd, "client");

	dbxfer(client_fd, infdb_fd, "infdb");
	sys->fprint(infdb_fd, "X1          0   0 \n");
}

dbxfer(source, sink: ref Sys->FD, tag: string)
{
	buf := array [Sys->ATOMICIO] of byte;
	while((nr := sys->read(source, buf, len buf)) > 0)
		if(sys->write(sink, buf, nr) != nr){
			sys->fprint(stderr, "dbsrv: write to %s failed: %r\n", tag);
			shutdown();
		}
	if(nr < 0){
		sys->fprint(stderr, "dbsrv: reading data for %s: %r\n", tag);
		shutdown();
	}
}

shutdown()
{
	pid := sys->pctl(0, nil);
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "killgrp") < 0)
		err(sys->sprint("can't kill group %d: %r", pid));
}

err(s: string)
{
	sys->fprint(stderr, "dbsrv: %s\n", s);
	raise "fail:error";
}

user(): string
{
	sys = load Sys Sys->PATH;

	fd := sys->open("/dev/user", sys->OREAD);
	if(fd == nil)
		return "";

	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return "";

	return string buf[0:n]; 
}
