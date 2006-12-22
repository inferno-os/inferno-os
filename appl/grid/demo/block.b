implement Block;

include "sys.m";
	sys : Sys;
include "daytime.m";
	daytime: Daytime;
include "draw.m";
	draw: Draw;
	Chans, Context, Display, Point, Rect, Image, Screen, Font: import draw;
include "readdir.m";
	readdir: Readdir;
include "grid/demo/exproc.m";
	exproc: Exproc;
include "grid/demo/block.m";

timeout := 50;
WAITING: con -1;
DONE: con -2;
path := "";

init(pathname: string, ep: Exproc)
{
	sys = load Sys Sys->PATH;
	if (sys == nil)
		badmod(Sys->PATH);
	draw = load Draw Draw->PATH;
	if (draw == nil)
		badmod(Draw->PATH);
	daytime = load Daytime Daytime->PATH;
	if (daytime == nil)
		badmod(Daytime->PATH);
	readdir = load Readdir Readdir->PATH;
	if (readdir == nil)
		badmod(Readdir->PATH);
	if (pathname == "")
		err("no path given");
	if (pathname[len pathname - 1] != '/')
		pathname[len pathname] = '/';
	path = pathname;
	exproc = ep;
	if (exproc == nil)
		badmod("Exproc");
	sys->create(path, sys->OREAD, 8r777 | sys->DMDIR);
	(n, nil) := sys->stat(path);
	if (n == -1)
		sys->print("Cannot find path: %s\n",path);
}

slave()
{
	buf := array[8192] of byte;
	for(;;) {
		(n, nil) := sys->stat(path+"working");
		if (n == -1)
			sys->sleep(1000);
		else {
			fd := sys->open(path + "data.dat", sys->OREAD);
			if (fd != nil) {
				s := "";
				for (;;) {
					i := sys->read(fd, buf, len buf);
					if (i < 1)
						break;
					s += string buf[:i];
				}
				(nil, lst) := sys->tokenize(s, "\n");
				exproc->getslavedata(lst);
				break;
			}
		}
	}
	doneblocks := 0;
	loop: for (;;) {
		(dirs, nil) := readdir->init(path+"todo", readdir->NAME);
		if (len dirs == 0) {
			(n, nil) := sys->stat(path + "working");
			if (n == -1)
				break loop;
			sys->sleep(2000);
		}
		for (i := 0; i < len dirs; i++) {
			fd := sys->create(path+dirs[i].name, sys->OREAD, 8r777 | sys->DMDIR);
			if (fd != nil) {
				(nil, lst) := sys->tokenize(dirs[i].name, ".");
				exproc->doblock(int hd tl lst, dirs[i].name);
				doneblocks++;
			}
			(n, nil) := sys->stat(path + "working");
			if (n == -1)
				break loop;
		}
	}
	sys->print("Finished: %d blocks\n",doneblocks);
}

writedata(s: string)
{
	fd := sys->create(path+"data.dat", sys->OWRITE, 8r666);
	if (fd != nil)
		sys->fprint(fd, "%s", s);
	else
		err("could not create data.dat");
	fd = nil;
}

masterinit(noblocks: int)
{
	sys->create(path+"todo", sys->OREAD, 8r777 | sys->DMDIR);
	sys->create(path+"working", sys->OWRITE, 8r666);
	for (i := 0; i < noblocks; i++)
		makefile(i, "");
}

reader(noblocks: int, chanout: chan of string, sync: chan of int)
{
	sync <-= sys->pctl(0,nil);
	starttime := daytime->now();
	times := array[noblocks] of { * => WAITING };
	let := array[noblocks] of { * => "a" };
	buf := array[50] of byte;
	result := 0;
	for (;;) {
		nodone := 0;
		for (i := 0; i < noblocks; i++) {
			if (times[i] != DONE) {
				(n,nil) := sys->stat(path+"block."+string i+"."+let[i]+"/done");
				if (n == -1) {
					(n2, nil) := sys->stat(path+"block."+string i+"."+let[i]);
					if (n2 != -1) {
						now := daytime->now();
						if (times[i] == WAITING)
							times[i] = now;
						else if (now - times[i] > timeout) {
							let[i] = makefile(i, let[i]);
							times[i] = WAITING;
						}
					}
				}
				else {
					sys->remove(path +"todo/block."+string i+"."+let[i]);
					if (exproc->readblock(i, path+"block."+string i+"."+let[i]+"/", chanout) == -1) {
						let[i] = makefile(i, let[i]);
						times[i] = WAITING;
					}
					else {
						times[i] = DONE;
						nodone++;
					}
				}
			}
			else
				nodone++;
		}
		if (nodone == noblocks)
			break;
		chanout <-= string ((nodone*100)/noblocks);
		sys->sleep(1000);
	}
	endtime := daytime->now();
	chanout <-= "100";
	spawn exproc->finish(endtime - starttime, chanout);
}

makefile(block: int, let: string): string
{
	if (let == "")
		let = "a";
	else {
		sys->remove(path +"todo/block."+string block+"."+let);
		let[0]++;
	}
	name := path+"todo/block."+string block+"."+let;
	fd :=	sys->create(name, sys->OREAD, 8r666);
	if (fd == nil)
		sys->print("Error creating: '%s'\n",name);
	return let;
}

err(s: string)
{
	sys->print("Error: '%s'\n",s);
	exit;
}

cleanfiles(delpath: string)
{	
	buf := array[8192] of byte;
	if (delpath == "")
		return;
	if (delpath[len delpath - 1] != '/')
		delpath[len delpath] = '/';
	(dirs, n) := readdir->init(delpath, readdir->NAME);
	for (i := 0; i < len dirs; i++) {
		if (dirs[i].mode & sys->DMDIR)
			cleanfiles(delpath+dirs[i].name+"/");
		sys->remove(delpath+dirs[i].name);
	}
}

isin(l: list of string, s: string): int
{
	for(tmpl := l; tmpl != nil; tmpl = tl tmpl)
		if (hd tmpl == s)
			return 1;
	return 0;
}

badmod(path: string)
{
	sys->print("Block: failed to load: %s\n",path);
	exit;
}