implement Countersigner;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;

include "keyring.m";
	kr: Keyring;

include "msgio.m";
	msgio: Msgio;

include "security.m";

Countersigner: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

stderr, stdin, stdout: ref Sys->FD;

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	msgio = load Msgio Msgio->PATH;
	msgio->init();

	stdin = sys->fildes(0);
	stdout = sys->fildes(1);
	stderr = sys->fildes(2);

	sys->pctl(Sys->FORKNS, nil);
	if(sys->chdir("/keydb") < 0){
		sys->fprint(stderr, "countersigner: no key database\n");
		raise "fail:no keydb";
	}

	# get boxid
	buf := msgio->getmsg(stdin);
	if(buf == nil){
		sys->fprint(stderr, "countersigner: client hung up\n");
		raise "fail:hungup";
	}
	boxid := string buf;

	# read file
	file := "countersigned/"+boxid;
	fd := sys->open(file, Sys->OREAD);
	if(fd == nil){
		sys->fprint(stderr, "countersigner: can't open %s: %r\n", file);
		raise "fail:bad boxid";
	}
	blind := msgio->getmsg(fd);
	if(blind == nil){
		sys->fprint(stderr, "countersigner: can't read %s\n", file);
		raise "fail:no blind";
	}

	# answer client
	msgio->sendmsg(stdout, blind, len blind);
}
