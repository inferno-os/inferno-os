implement Mergewrite, Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "readdir.m";
	readdir: Readdir;
include "alphabet/reports.m";
	reports: Reports;
	Report, report, quit: import reports;
include "alphabet/fs.m";
	fs: Fs;
	Value: import fs;
	Fschan, Fsdata, Entrychan, Entry,
	Cmpchan, Option,
	Next, Down, Skip, Quit: import Fs;

Mergewrite: module {};

types(): string
{
	return "rxsm-v-n";
}

VERBOSE, NOWRITE, ASSUME: con 1<<iota;

init()
{
	sys = load Sys Sys->PATH;
	readdir = load Readdir Readdir->PATH;
	if(readdir == nil){
		sys->fprint(sys->fildes(2), "fs: mergewrite: cannot load %s: %r\n", Readdir->PATH);
		raise "fail:bad module";
	}
	readdir->init(nil, 0);

	fs = load Fs Fs->PATH;
	if(fs == nil){
		sys->fprint(sys->fildes(2), "fs: mergewrite: cannot load %s: %r\n", Fs->PATH);
		raise "fail:bad module";
	}
	reports = load Reports Reports->PATH;
	if(reports == nil){
		sys->fprint(sys->fildes(2), "fs: mergewrite: cannot load %s: %r\n", Reports->PATH);
		raise "fail:bad module";
	}
}

run(nil: ref Draw->Context, report: ref Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	sync := chan of string;
	flags := 0;
	for(; opts != nil; opts = tl opts){
		case (hd opts).opt {
		'n' =>
			flags |= NOWRITE;
		'v' =>
			flags |= VERBOSE;
		}
	}
			
	spawn  fswriteproc(sync, flags, (hd args).x().i, (hd tl args).s().i, (hd tl tl args).m().i, report.start("mergewrite"));
	sync <-= nil;
	return ref Value.Vr(sync);
}

fswriteproc(sync: chan of string, flags: int, c: Fschan, root: string, cmp: Cmpchan, errorc: chan of string)
{
	sys->pctl(Sys->FORKNS, nil);
	<-sync;
	if(<-sync != nil){
		(<-c).t1 <-= Quit;
		quit(errorc);
	}
	
	((d, nil), reply) := <-c;
	if(root != nil){
		d = ref *d;
		d.name = root;
	}
	fswritedir(d.name, cmp, d, reply, c, errorc, flags);
	errorc <-= nil;
	sync <-= nil;		# XXX should return result here...
}

fswritedir(path: string, cmp: Cmpchan, dir: ref Sys->Dir, dreply: chan of int, c: Fschan,
		errorc: chan of string, flags: int)
{
	fd: ref Sys->FD;
	if(dir.mode & Sys->DMDIR){
		made := 0;
		if(flags&VERBOSE)
			report(errorc, sys->sprint("create %q %uo", path, dir.mode));
		if(flags&NOWRITE){
			if(flags&ASSUME)
				made = 1;
			else{
				fd = sys->open(dir.name, Sys->OREAD);
				if(fd == nil){
					made = 1;
					flags |= ASSUME;
				}else if(sys->chdir(dir.name) == -1){
					dreply <-= Next;
					report(errorc, sys->sprint("cannot cd to %q: %r", path));
					return;
				}
			}
		}else{
			fd = sys->create(dir.name, Sys->OREAD, dir.mode|8r300);
			made = fd != nil;
			if(fd == nil && (fd = sys->open(dir.name, Sys->OREAD)) == nil){
				dreply <-= Next;
				report(errorc, sys->sprint("cannot create %q, mode %uo: %r", path, dir.mode|8r300));
				return;
			}
			# XXX if we haven't just made it, we should chmod the old entry u+w to enable writing.
			if(sys->chdir(dir.name) == -1){		# XXX beware of names starting with '#'
				dreply <-= Next;
				report(errorc, sys->sprint("cannot cd to %q: %r", path));
				fd = nil;
				sys->remove(dir.name);
				return;
			}
		}
		dreply <-= Down;
		entries: array of ref Sys->Dir;
		if(made == 0)
			entries = readdir->readall(fd, Readdir->NAME|Readdir->COMPACT).t0;
		i := 0;
		eod := 0;
		d0, d1: ref Sys->Dir;
		reply: chan of int;
		path[len path] = '/';
		for(;;){
			if(!eod && d0 == nil){
				((d0, nil), reply) = <-c;
				if(d0 == nil){
					reply <-= Next;
					eod = 1;
				}
			}
			if(d1 == nil && i < len entries)
				d1 = entries[i++];
			if(d0 == nil && d1 == nil)
				break;

			(wd0, wd1) := (d0, d1);
			if(d0 != nil && d1 != nil && d0.name != d1.name){
				if(d0.name < d1.name)
					wd1 = nil;
				else
					wd0 = nil;
			}
			r := compare(cmp, wd0, wd1);
			if(wd1 != nil){
				if((r & 2r10) == 0){
					if(flags&VERBOSE)
						report(errorc, "removing "+path+wd1.name);
					if((flags&NOWRITE)==0){
						if(wd1.mode & Sys->DMDIR)
							rmdir(wd1.name);
						else
							remove(wd1.name);
					}
				}
				d1 = nil;
			}
			if(wd0 != nil){
				if((r & 2r01) == 0)
					reply <-= Next;
				else
					fswritedir(path + wd0.name, cmp, d0, reply, c, errorc, flags);
				d0 = nil;
			}
		}
		if((flags&ASSUME)==0)
			sys->chdir("..");
		if((flags&NOWRITE)==0){
			if((dir.mode & 8r300) != 8r300){
				ws := Sys->nulldir;
				ws.mode = dir.mode;
				if(sys->fwstat(fd, ws) == -1)
					report(errorc, sys->sprint("cannot wstat %q: %r", path));
			}
		}
	}else{
		if(flags&VERBOSE)
			report(errorc, sys->sprint("create %q %uo", path, dir.mode));
		if(flags&NOWRITE){
			dreply <-= Next;
			return;
		}
		fd = sys->create(dir.name, Sys->OWRITE, dir.mode);
		if(fd == nil){
			dreply <-= Next;
			report(errorc, sys->sprint("cannot create %q, mode %uo: %r", path, dir.mode|8r300));
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

rmdir(name: string)
{
	(d, n) := readdir->init(name, Readdir->NONE|Readdir->COMPACT);
	for(i := 0; i < n; i++){
		path := name+"/"+d[i].name;
		if(d[i].mode & Sys->DMDIR)
			rmdir(path);
		else
			remove(path);
	}
	remove(name);
}

remove(name: string)
{
	if(sys->remove(name) < 0)
		sys->fprint(sys->fildes(2), "mergewrite: cannot remove %q: %r\n", name);
}

compare(cmp: Cmpchan, d0, d1: ref Sys->Dir): int
{
	mask := (d0 != nil) | (d1 != nil) << 1;
	if(cmp == nil)
		return mask;
	reply := chan of int;
	cmp <-= (d0, d1, reply);
	return <-reply & mask;
}
