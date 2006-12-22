implement Write, Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	reports: Reports;
	Report, report: import reports;
include "alphabet/fs.m";
	fs: Fs;
	Value: import fs;
	Fschan, Fsdata, Entrychan, Entry,
	Gatechan, Gatequery, Option,
	Next, Down, Skip, Quit: import Fs;

Write: module {};
types(): string
{
	return "rxs-v";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: write: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	fs = load Fs Fs->PATH;
	if(fs == nil)
		badmod(Fs->PATH);
	fs->init();
	reports = load Reports Reports->PATH;
	if(reports == nil)
		badmod(Reports->PATH);
}

run(nil: ref Draw->Context, report: ref Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	sync := chan of string;
	spawn  fswriteproc(sync, (hd tl args).s().i, (hd args).x().i, report.start("fswrite"), opts!=nil);
	<-sync;
	return ref Value.Vr(sync);
}

fswriteproc(sync: chan of string, root: string, c: Fschan, errorc: chan of string, verbose: int)
{
	sys->pctl(Sys->FORKNS, nil);
	sync <-= nil;
	if(<-sync != nil){
		(<-c).t1 <-= Quit;
		quit(sync, errorc);
	}
		
	(d, reply) := <-c;
	if(root != nil){
		d.dir = ref *d.dir;
		d.dir.name = root;
	}
	fswritedir(d.dir.name, d, reply, c, errorc, verbose);
	quit(sync, errorc);
}

quit(sync: chan of string, errorc: chan of string)
{
	errorc <-= nil;
	sync <-= nil;
	exit;
}

fswritedir(path: string, d: Fsdata, dreply: chan of int, c: Fschan, errorc: chan of string, verbose: int)
{
	fd: ref Sys->FD;
	if(verbose)
		report(errorc, sys->sprint("create %q %uo", path, d.dir.mode));
	if(d.dir.mode & Sys->DMDIR){
		created := 1;
		fd = sys->create(d.dir.name, Sys->OREAD, d.dir.mode|8r777);
		if(fd == nil){
			err := sys->sprint("%r");
			if((fd = sys->open(d.dir.name, Sys->OREAD)) == nil){
				dreply <-= Next;
				report(errorc, sys->sprint("cannot create %q, mode %uo: %s", path, d.dir.mode|8r300, err));
				return;
			}else
				created = 0;
		}
		if(sys->chdir(d.dir.name) == -1){		# XXX beware of names starting with '#'
			dreply <-= Next;
			report(errorc, sys->sprint("cannot cd to %q: %r", path));
			fd = nil;
			sys->remove(d.dir.name);
			return;
		}
		dreply <-= Down;
		path[len path] = '/';
		for(;;){
			(ent, reply) := <-c;
			if(ent.dir == nil){
				reply <-= Next;
				break;
			}
			fswritedir(path + ent.dir.name, ent, reply, c, errorc, verbose);
		}
		sys->chdir("..");
		if(created && (d.dir.mode & 8r777) != 8r777){
			ws := Sys->nulldir;
			ws.mode = d.dir.mode;
			if(sys->fwstat(fd, ws) == -1)
				report(errorc, sys->sprint("cannot wstat %q: %r", path));
		}
	}else{
		fd = sys->create(d.dir.name, Sys->OWRITE, d.dir.mode);
		if(fd == nil){
			dreply <-= Next;
			report(errorc, sys->sprint("cannot create %q, mode %uo: %r", path, d.dir.mode|8r300));
			return;
		}
		dreply <-= Down;
		while((((nil, buf), reply) := <-c).t0.data != nil){
			nw := sys->write(fd, buf, len buf);
			if(nw < len buf){
				if(nw == -1)
					errorc <-= sys->sprint("error writing %q: %r", path);
				else
					errorc <-= sys->sprint("short write");
				reply <-= Skip;
				break;
			}
			reply <-= Next;
		}
		reply <-= Next;
	}
}
