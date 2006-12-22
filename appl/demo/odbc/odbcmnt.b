implement Odbcmnt;

#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;
include "draw.m";
include "arg.m";
include "string.m";
	str: String;
include "daytime.m";
	daytime: Daytime;
include "convcs.m";
	convcs : Convcs;
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;
include "styxservers.m";
	styxservers: Styxservers;
	Styxserver, Navigator: import styxservers;
	nametree: Nametree;
	Tree: import nametree;

Column: adt {
	name: string;
	ctype: string;
	size: int;
};

Qroot: con iota;
WINCHARSET := "windows-1252";		# BUG: odbc.c should do the conversion!

Odbcmnt: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	arg := load Arg Arg->PATH;
	if(arg == nil)
		notloaded(Arg->PATH);
	daytime = load Daytime Daytime->PATH;
	if (daytime == nil)
		notloaded(Daytime->PATH);
	str = load String String->PATH;
	if(str == nil)
		notloaded(String->PATH);
	convcs = load Convcs Convcs->PATH;
	if(convcs == nil)
		notloaded(Convcs->PATH);
	cserr := convcs->init(nil);
	if (cserr != nil)
		err("convcs init failed " + cserr);
	styx = load Styx Styx->PATH;
	if(styx == nil)
		notloaded(Styx->PATH);
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	if(styxservers == nil)
		notloaded(Styxservers->PATH);
	styxservers->init(styx);
	nametree = load Nametree Nametree->PATH;
	if(nametree == nil)
		notloaded(Nametree->PATH);
	nametree->init();
	addr := "127.0.0.1";
	arg->init(argv);
	stype := "ODBC";
	while((o := arg->opt()) != 0)
		case o {
		'a' =>
			addr = arg->earg();
		*   =>
			usage();
		}

	argv = arg->argv();
	arg = nil;
	sys->pctl(Sys->FORKNS | sys->NEWPGRP, nil);
	dbdir := do_mount(netmkaddr(addr, "tcp", "6700"));
	(cfd, cdir) := do_clone(dbdir);
	sources := find_sources(cdir);
	sys->print("Found %d sources\n", len sources);
	spawn serveloop(dbdir, sources, sys->fildes(0));
}

netmkaddr(addr, net, svc: string): string
{
	if(net == nil)
		net = "net";
	(n, l) := sys->tokenize(addr, "!");
	if(n <= 1){
		if(svc== nil)
			return sys->sprint("%s!%s", net, addr);
		return sys->sprint("%s!%s!%s", net, addr, svc);
	}
	if(svc == nil || n > 2)
		return addr;
	return sys->sprint("%s!%s", addr, svc);
}

split1(s, delim: string): (string, string)
{
	(l, r) := str->splitl(s, delim);
	return (l, str->drop(r, delim)); 
}

notloaded(s: string)
{
	err(sys->sprint("failed to load %s: %r", s));
}

usage()
{
	sys->fprint(stderr, "Usage: odbcmnt [ -a address ]\n");
	raise "fail:usage";
}

do_mount(addr: string): string
{
	(ok, c) := sys->dial(addr, nil);
	remdir := "/n/remote";
	if (ok < 0)
		err(sys->sprint("failed to dial odbc server on %s: %r", addr));
	if (sys->mount(c.dfd, nil, remdir, 0, nil) < 0)
		err(sys->sprint("failed to mount odbc server on %s: %r", addr));
	dbdir := remdir + "/db";
	return dbdir;
}


do_clone(dbdir: string): (ref Sys->FD, string)
{
	newfile := dbdir + "/new";
	cfd := sys->open(newfile, Sys->OREAD);
	if (cfd == nil)
		err(sys->sprint("failed to open  %s: %r", newfile));
	cname := read_fd(cfd);
	if (cname == nil)
		err("failed to find clone directory name");
	return(cfd, dbdir + "/" + cname);
}

dir(name: string, perm: int, length: int, qid: int): Sys->Dir
{
	uid := read_file("/dev/user");
	d := sys->zerodir;
	d.name = name;
	d.uid = uid;
	d.gid = uid;
	d.qid.path = big qid;
	if (perm & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	else {
		d.qid.qtype = Sys->QTFILE;
		d.length = big length;
	}
	d.mode = perm;
	d.atime = d.mtime = daytime->now();
	return d;
}

newconv(dbdir, source: string): (ref Sys->FD, ref Sys->FD, ref Sys->FD, ref Sys->FD, string)
{
	err := "";
	(clonefd, cdir) := do_clone(dbdir);
	ctlf := cdir + "/ctl";
	ctlfd := sys->open(ctlf, Sys->ORDWR);
	if (ctlfd == nil)
		err = sys->sprint("Failed to open %s: %r", ctlf);
	cmdf := cdir + "/cmd";
	cmdfd := sys->open(cmdf, Sys->ORDWR);
	if (cmdfd == nil)
		err = sys->sprint("Failed to open %s: %r", cmdf);
	dataf := cdir + "/data";
	datafd := sys->open(dataf, Sys->ORDWR);
	if (datafd == nil)
		err = sys->sprint("Failed to open %s: %r", dataf);
	if (write_fd(ctlfd, "connect " + source) < 0)
		err = sys->sprint("failed to connect to %s: %r", source);
	return (clonefd, ctlfd, cmdfd, datafd, err);
}

SRCDIR: con 1;
SQL: con 2;
TABLE: con 3;
TABLEDIR: con 4;
COLUMN: con 5;

gettype(fid: big): int
{
	return int fid & 7;
}

SrcFD: adt {
	clonefd, ctlfd, cmdfd, datafd: ref sys->FD;
};

serveloop(dbdir: string, sources: list of string, confd: ref sys->FD)
{
	srcqid := 0;
	sqlqid := 0;
	tableqid := 0;
	colqid := 0;
	tabledirqid := 0;
	(bs, cserr) := convcs->getbtos(WINCHARSET);
	if (bs == nil)
		err("getbtos error: " + cserr);
	(tree, treeop) := nametree->start();
	tree.create(big Qroot, dir(".",8r555 | sys->DMDIR,0,Qroot));
	contents: list of string;
	srcfds := array[len sources] of SrcFD;
	i := 0;
	for (sl := sources; sl!=nil; sl=tl sl) {
		(srcname, srcdriver) := split1(hd sl, ":");
		# Don't do anything with 'srvdriver' - could make a driver 
		#    file to read - but does anyone care about it?
		(clonefd, ctlfd, cmdfd, datafd, e) := newconv(dbdir, srcname);
		if (e != nil)
			sys->fprint(sys->fildes(2), "Odbcmnt: %s\n",e);
		else {
			srcfds[i] = (clonefd, ctlfd, cmdfd, datafd);
			sys->print("%s\n",srcname);
			Qsrc := SRCDIR + (srcqid++<<3);
			tree.create(big Qroot, dir(srcname,8r555 | sys->DMDIR,0,Qsrc));
			Qtabledir := TABLEDIR + (tabledirqid++<<3);
			tree.create(big Qsrc, dir("tables",8r555 | sys->DMDIR,0,Qtabledir));
			Qsql := SQL + (sqlqid++<<3);
			tree.create(big Qsrc, dir("sql",8r666,0, Qsql));
			
			tables := find_tables(srcfds[i].cmdfd, srcfds[i].datafd);
			if (tables == nil)
				err(sys->sprint("failed to find tables: %r"));
			if (write_fd(srcfds[i].ctlfd, "headings") < 0)
				err(sys->sprint("failed to write to ctl file: %r"));
			sys->print("\tBuilding tree...");
			for (tlist:=tables; tlist!=nil; tlist=tl tlist) {
				table := hd tlist;
				Qtable := TABLE + (tableqid++<<3);
				tree.create(big Qtabledir, dir(table,8r555 | sys->DMDIR,0,Qtable));
				columns := find_columns(srcfds[i].cmdfd, srcfds[i].datafd, table);
				for (clist:=columns; clist!=nil; clist=tl clist) {
					column := hd clist;
					Qcol := COLUMN + (colqid<<3);
					tree.create(big Qtable, dir(column.name,8r555,0,Qcol));
					data := sys->sprint("%s %d\n", column.ctype, column.size);
					contents = data :: contents;
					colqid++;
				}
			}
			sys->print("done\n");
		}
		i++;
	}
	colcontent := array[colqid] of string;
	for (i = colqid - 1; i >= 0; i--) {
		colcontent[i] = hd contents;
		contents = tl contents;
	}
	(tchan, srv) := Styxserver.new(confd, Navigator.new(treeop), big Qroot);
	sys->pctl(Sys->FORKNS|Sys->FORKFD, nil);
	gm: ref Tmsg;
	buf := array[Sys->ATOMICIO] of byte;
	serverloop: for (;;) {
		gm = <-tchan;
		if (gm == nil)
			break serverloop;
		pick m := gm {
		Readerror =>
			sys->fprint(sys->fildes(2), "odbcmnt: fatal read error: %s\n", m.error);
			break serverloop;
		Read =>
			c := srv.getfid(m.fid);
			if(c.qtype & Sys->QTDIR){
				srv.read(m);	# does readdir
				break;
			}
			case gettype(c.path) {
				SQL =>
					srcno := int c.path >> 3;
					sys->seek(srcfds[srcno].datafd, m.offset, Sys->SEEKSTART);
					n := sys->read(srcfds[srcno].datafd, buf, len buf);
					if (n >= 0) {
						(state, s, err) := bs->btos(nil, buf[:n], -1);
						r := ref Rmsg.Read(gm.tag, array of byte s);
						srv.reply(r);
					} else
						srv.reply(ref Rmsg.Error(gm.tag, sys->sprint("%r")));
					break;
			COLUMN =>
				srv.reply(styxservers->readstr(m, colcontent[int c.path>>3]));
				* =>
					srv.default(gm);
			}
		Write =>
			c := srv.getfid(m.fid);
			case gettype(c.path) {
				SQL =>
					srcno := int c.path >> 3;
					n := sys->write(srcfds[srcno].cmdfd, m.data, len m.data);
					if (n == len m.data)
						srv.reply(ref Rmsg.Write(m.tag, n));
					else
						srv.reply(ref Rmsg.Error(gm.tag, sys->sprint("%r")));
					break;
				* =>
					srv.default(gm);
			}

		* =>
			srv.default(gm);
		}
	}
	tree.quit();
}

find_tables(cmdfd, datafd: ref Sys->FD): list of string
{
	tlist: list of string;
	if (write_fd(cmdfd, "tables") < 0)
		err(sys->sprint("failed to write to cmd file: %r"));
	while((rec := read_fd(datafd)) != nil) {
		fields := atokenize(rec, "|");
		if (len fields < 4)
			err("bad table name");
		tname := fields[2];
		tlist = tname :: tlist;
	}
	return tlist;
}


find_columns(cmdfd, datafd: ref Sys->FD, table: string): list of Column
{
	clist: list of Column;
	if (write_fd(cmdfd, "columns " + table) < 0)
		err(sys->sprint("failed to write to cmd file: %r"));
	while((rec := read_fd(datafd)) != nil) {
		fields := atokenize(rec, "|");
		if (len fields < 3)
			err("bad column name");
		cname :=fields[3];
		ctype := "";
		if (len fields > 5)
			ctype = fields[5];
		csize := 0;
		if (len fields > 6)
			csize = int fields[6];
		clist = (fields[3], ctype, csize) :: clist;
	}
	return clist;
}

atokenize(s: string, delim: string): array of string
{
	if (s == nil)
		return nil;
	dl := len delim;
	r: list of string;
	l: string;
	for (;;) {
		(l, s) = str->splitstrl(s, delim);
		r = l :: r;
		if (s == nil || s == delim)
			break;
		s = s[dl:];
	}
	a := array[len r] of string;
	for (i:=len r-1; i>=0; i--) {
		a[i] = hd r;
		r = tl r;
	}
	return a;
}

find_sources(cdir: string): list of string
{
	sfile := cdir+"/sources";
	fd := sys->open(sfile, Sys->OREAD);
	if (fd == nil)
		err(sys->sprint("failed to open  %s: %r", sfile));
	s := read_fd(fd);
	(n, lines) := sys->tokenize(s, "\n");
	return lines;
}

err(s: string)
{
	sys->fprint(stderr, "odbcgw: %s\n", s);
	raise "fail:error";
}

read_fd(fd: ref Sys->FD): string
{
	MAX : con Sys->ATOMICIO;
	buf := array[MAX] of byte;
#	sys->seek(fd, big 0, Sys->SEEKSTART);
	size := sys->read(fd, buf, MAX);
	if (size <= 0) {
#		if (size < 0)
#			sys->fprint(stderr, "read_fd error: %r\n");
		return nil;
	}
	return string buf[0:size];
}

read_file(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if (fd == nil)
		return nil;
	return read_fd(fd);
}

write_fd(fd: ref Sys->FD, s: string): int
{
	a := array of byte s;
	if (sys->write(fd, a, len a) != len a)
		return -1;
	return 0;
}