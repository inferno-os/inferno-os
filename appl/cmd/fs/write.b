implement Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "fslib.m";
	fslib: Fslib;
	Report, Value, quit, report: import fslib;
	Fschan, Fsdata, Entrychan, Entry,
	Gatechan, Gatequery, Option,
	Next, Down, Skip, Quit: import Fslib;

types(): string
{
	return "vsx";
}

init()
{
	sys = load Sys Sys->PATH;
	fslib = load Fslib Fslib->PATH;
	if(fslib == nil){
		sys->fprint(sys->fildes(2), "fs: write: cannot load %s: %r\n", Fslib->PATH);
		raise "fail:bad module";
	}
}

run(nil: ref Draw->Context, report: ref Report,
			nil: list of Option, args: list of ref Value): ref Value
{
	sync := chan of int;
	spawn  fswriteproc(sync, (hd args).s().i, (hd tl args).x().i, report.start("fswrite"));
	<-sync;
	return ref Value.V(sync);
}

fswriteproc(sync: chan of int, root: string, c: Fschan, errorc: chan of string)
{
	sys->pctl(Sys->FORKNS, nil);
	sync <-= 1;
	if(<-sync == 0){
		(<-c).t1 <-= Quit;
		quit(errorc);
	}
		
	(d, reply) := <-c;
	if(root != nil){
		d.dir = ref *d.dir;
		d.dir.name = root;
	}
	fswritedir(d.dir.name, d, reply, c, errorc);
	quit(errorc);
}

fswritedir(path: string, d: Fsdata, dreply: chan of int, c: Fschan, errorc: chan of string)
{
	fd: ref Sys->FD;
	if(d.dir.mode & Sys->DMDIR){
		fd = sys->create(d.dir.name, Sys->OREAD, d.dir.mode|8r300);
		if(fd == nil && (fd = sys->open(d.dir.name, Sys->OREAD)) == nil){
			dreply <-= Next;
			report(errorc, sys->sprint("cannot create %q, mode %uo: %r", path, d.dir.mode|8r300));
			return;
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
			fswritedir(path + ent.dir.name, ent, reply, c, errorc);
		}
		sys->chdir("..");
		if((d.dir.mode & 8r300) != 8r300){
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
