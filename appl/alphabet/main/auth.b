implement Authenticate, Mainmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "keyring.m";
	keyring: Keyring;
include "security.m";
	auth: Auth;
include "alphabet/reports.m";
	reports: Reports;
		Report, report: import reports;
include "alphabet.m";
	alphabet: Alphabet;
		Value: import alphabet;

Authenticate: module {};

typesig(): string
{
	return "ww-ks-Cs-v";
}

init()
{
	sys = load Sys Sys->PATH;
	alphabet = load Alphabet Alphabet->PATH;
	reports = load Reports Reports->PATH;
	keyring = load Keyring Keyring->PATH;
	auth = load Auth Auth->PATH;
	auth->init();
}

quit()
{
}

After, Before, Create: con 1<<iota;

run(nil: ref Draw->Context, r: ref Reports->Report, errorc: chan of string,
		opts: list of (int, list of ref Alphabet->Value),
		args: list of ref Alphabet->Value): ref Alphabet->Value
{
	keyfile: string;
	alg: string;
	verbose: int;
	for(; opts != nil; opts = tl opts){
		case (hd opts).t0 {
		'k' =>
			keyfile = (hd (hd opts).t1).s().i;
			if (keyfile != nil && ! (keyfile[0] == '/' || (len keyfile > 2 &&  keyfile[0:2] == "./")))
				keyfile = "/usr/" + user() + "/keyring/" + keyfile;
		'C' =>
			alg = (hd (hd opts).t1).s().i;
		'v' =>
			verbose = 1;
		}
	}
	if(keyfile == nil)
		keyfile = "/usr/" + user() + "/keyring/default";
	cert := keyring->readauthinfo(keyfile);
	if (cert == nil) {
		report(errorc, sys->sprint("auth: cannot read %q: %r", keyfile));
		return nil;
	}
	w := chan of ref Sys->FD;
	spawn authproc((hd args).w().i, w, cert, verbose, alg, r.start("auth"));
	return ref Value.Vw(w);
}

authproc(f0, f1: chan of ref Sys->FD, cert: ref Keyring->Authinfo,
		verbose: int, alg: string, errorc: chan of string)
{
	fd0 := <-f0;
	if(fd0 == nil){
		sys->pipe(p := array[2] of ref Sys->FD);
		f0 <-= p[1];
		fd0 = p[0];
	}else
		f0 <-= nil;

	eu: string;
	(fd0, eu) = auth->client(alg, cert, fd0);
	if(fd0 == nil){
		report(errorc, "authentication failed: "+eu);
		f1 <-= nil;
		<-f1;
		reports->quit(errorc);
	}
	if(verbose)
		report(errorc, sys->sprint("remote user %q", eu));
	f1 <-= fd0;
	fd1 := <-f1;
	if(fd1 == nil)
		reports->quit(errorc);
	wstream(fd0, fd1, errorc);
	reports->quit(errorc);
}

wstream(fd0, fd1: ref Sys->FD, errorc: chan of string)
{
	sync := chan[2] of int;
	qc := chan of int;
	spawn stream(fd0, fd1, sync, qc, errorc);
	spawn stream(fd1, fd0, sync, qc, errorc);
	<-qc;
	kill(<-sync);
	kill(<-sync);
}

stream(fd0, fd1: ref Sys->FD, sync, qc: chan of int, errorc: chan of string)
{
	sync <-= sys->pctl(0, nil);
	buf := array[Sys->ATOMICIO] of byte;
	while((n := sys->read(fd0, buf, len buf)) > 0){
		if(sys->write(fd1, buf, n) == -1){
			report(errorc, sys->sprint("write error: %r"));
			break;
		}
	}
	qc <-= 1;
	exit;
}

kill(pid: int)
{
	sys->fprint(sys->open("#p/"+string pid+"/ctl", Sys->OWRITE), "kill");
}


exists(f: string): int
{
	(ok, nil) := sys->stat(f);
	return ok != -1;
}

user(): string
{
	u := readfile("/dev/user");
	if (u == nil)
		return "nobody";
	return u;
}

readfile(f: string): string
{
	fd := sys->open(f, sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return nil;

	return string buf[0:n];	
}
