implement CpuPool;
#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys : Sys;
include "daytime.m";
	daytime: Daytime;
include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;
include "styxservers.m";
	styxservers: Styxservers;
	Fid, Navigator, Navop: import styxservers;
	Styxserver: import styxservers;
	nametree: Nametree;
	Tree: import nametree;
include "draw.m";
include "dial.m";
	dial: Dial;
include "sh.m";
include "arg.m";
include "registries.m";
	registries: Registries;
	Registry, Attributes, Service: import registries;
include "grid/announce.m";
	announce: Announce;
include "readdir.m";
	readdir: Readdir;

TEST: con 0;

RUN : con "#!/dis/sh\n" +
		"load std\n" +
		"if {~ $#* 0} {\n" +
		"	echo usage: run.sh cmd args\n"+
		"	raise usage\n" +
		"}\n"+
		"CMD = $*\n" +
		"{echo $CMD; dir=`{read -o 0}; cat <[0=3] > $dir/data& catpid=$apid;"+
		" cat $dir/data >[1=4]; kill $catpid >[2] /dev/null} <[3=0] >[4=1] <> clone >[1=0]\n";

EMPTYDIR: con "#//dev";
rootpath := "/tmp/cpupool/";
rstyxreg: ref Registry;
registered: ref Registries->Registered;

CpuSession: adt {
	proxyid, fid, cpuid, omode, written, finished: int;
	stdoutopen, stdinopen: int;
	stdinchan, stdoutchan: chan of array of byte;
	closestdin,closestdout, readstdout, sync: chan of int;
	rcmdfinishedstdin, rcmdfinishedstdout: chan of int;
	fio: ref sys->FileIO;
	pids: list of int;
};

NILCPUSESSION: con CpuSession (-1, -1,-1, 0, 0, 0, 0, 0, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil);

cpusession: array of CpuSession;
poolchanin : chan of string;
poolchanout : chan of int;

conids : array of int;

CpuPool: module {
	init: fn (nil : ref Draw->Context, argv: list of string);
};

init(nil : ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if (sys == nil)
		badmod(Sys->PATH);
	daytime = load Daytime Daytime->PATH;
	if (daytime == nil)
		badmod(Daytime->PATH);
	dial = load Dial Dial->PATH;
	if (dial == nil)
		badmod(Dial->PATH);
	styx = load Styx Styx->PATH;
	if (styx == nil)
		badmod(Styx->PATH);
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	if (styxservers == nil)
		badmod(Styxservers->PATH);
	styxservers->init(styx);
	nametree = load Nametree Nametree->PATH;
	if (nametree == nil)
		badmod(Nametree->PATH);
	nametree->init();
	registries = load Registries Registries->PATH;
	if (registries == nil)
		badmod(Registries->PATH);
	registries->init();
	announce = load Announce Announce->PATH;
	if (announce == nil)
		badmod(Announce->PATH);
	announce->init();
	readdir = load Readdir Readdir->PATH;
	if (readdir == nil)
		badmod(Readdir->PATH);
	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmod(Arg->PATH);
	sys->pctl(Sys->FORKNS | sys->NEWPGRP, nil);
	sys->unmount(nil, "/n/remote");
	getuid();
	sys->chdir(EMPTYDIR);
	cpusession = array[500] of { * => NILCPUSESSION };
	attrs := Attributes.new(("proto", "styx") :: ("auth", "none") :: ("resource","Cpu Pool") :: nil);

	arg->init(argv);
	arg->setusage("cpupool [-a attributes] [rootdir]");
	while ((opt := arg->opt()) != 0) {
		case opt {
		'a' =>
			attr := arg->earg();
			val := arg->earg();
			attrs.set(attr, val);
		* =>
			arg->usage();
		}
	}
	argv = arg->argv();
	arg = nil;
	
	if (argv != nil)
		rootpath = hd argv;
	if (rootpath[len rootpath - 1] != '/')
		rootpath[len rootpath] = '/';
	(n, dir) := sys->stat(rootpath);
	if (n == -1 || !(dir.mode & sys->DMDIR))
		error("Invalid tmp path: "+rootpath);

	rstyxreg = Registry.new("/mnt/rstyxreg");
	if (rstyxreg == nil)
		error("Could not find Rstyx Registry");

	reg := Registry.connect(nil, nil, nil);
	if (reg == nil)
		error("Could not find registry");
	(myaddr, c) := announce->announce();
	if (myaddr == nil)
		error(sys->sprint("cannot announce: %r"));
	persist := 0;
	err: string;
	(registered, err) = reg.register(myaddr, attrs, persist);
	if (err != nil) 
		error("could not register with registry: "+err);
	conids = array[200] of { * => -1 };
	poolchanin = chan of string;
	poolchanout = chan of int;
	userchan := chan of int;
	spawn listener(c);
	spawn cpupoolloop(poolchanin, poolchanout);
}

attrval(s: string): (string, string)
{
	for (i := 0; i < len s; i++) {
		if (s[i] == '=')
			return (s[:i], s[i+1:]);
	}
	return (nil, s);
}

uid: string;
Qroot : con 0;
Qclone: con 1;

Qdata: con 2;
Qsh: con 3;
Qrun: con 4;
Qcpu: con 5;
Qsessdir: con 6;
Qsessdat: con 7;

getuid()
{
	buf := array [100] of byte;
	fd := sys->open("/dev/user", Sys->OREAD);
	uidlen := sys->read(fd, buf, len buf);
	uid = string buf[0: uidlen];
}

dir(name: string, perm: int, length: int, qid: int): Sys->Dir
{
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

defaultdirs := array[] of {
	("dis", 1),
	("dev", 1),
	("fonts", 1),
	("mnt", 0),
	("prog", 0),
};

serveloop(fd : ref sys->FD, cmdchan: chan of (int, string, chan of int), exitchan, sync: chan of int, proxyid: int)
{
	if (TEST)
		sys->fprint(sys->fildes(2), "starting serveloop");
	tchan: chan of ref Tmsg;
	srv: ref Styxserver;
	(tree, treeop) := nametree->start();
	tree.create(big Qroot, dir(".",8r555 | sys->DMDIR,0,Qroot));
	tree.create(big Qroot, dir("clone",8r666,0,Qclone));
	tree.create(big Qroot, dir("run.sh",8r555,0,Qrun));
	tree.create(big Qroot, dir("cpu",8r444,0,Qcpu));
	tree.create(big Qroot, dir("data",8r777 | sys->DMDIR,0,Qdata));
	tree.create(big Qroot, dir("runtime",8r444 | sys->DMDIR,0,Qsh));

	for (i := 0; i < len defaultdirs; i++)
		tree.create(big Qroot, dir(defaultdirs[i].t0,8r555 | sys->DMDIR ,0,8 + (i<<4)));

	(tchan, srv) = Styxserver.new(fd,Navigator.new(treeop), big Qroot);
	fd = nil;
	datafids : list of Datafid = nil;
	sync <-= 1;
	gm: ref Tmsg;
	loop: for (;;) {
		alt {
		<-exitchan =>
			break loop;
	
		gm = <-tchan =>
		
		if (gm == nil)
			break loop;
		# sys->fprint(sys->fildes(2), "Got new GM %s tag: %d\n", gm.text(), gm.tag);

		pick m := gm {
		Readerror =>
			sys->fprint(sys->fildes(2), "cpupool: fatal read error: %s\n", m.error);
			exit;
		Clunk =>
			deldf: Datafid;
			(datafids, deldf) = delfid(datafids, m.fid);
			if (deldf.sessid != -1) {
				if (deldf.omode == sys->OREAD || deldf.omode == sys->ORDWR)
					cpusession[deldf.sessid].sync <-= STDOUTCLOSE;
				else if (deldf.omode == sys->OWRITE || deldf.omode == sys->ORDWR)
					cpusession[deldf.sessid].sync <-= STDINCLOSE;
			}
			else {	
				sessid := getsession(m.fid);
				if (sessid != -1)
					cpusession[sessid].sync <-= CLONECLOSE;
			}
			srv.default(gm);
		Open =>
			(f, nil, d, err) := srv.canopen(m);
			if(f == nil) {
				srv.reply(ref Rmsg.Error(m.tag, err));
				break;
			}
			ind := int f.uname;
			mode := m.mode & 3;
			case int f.path  & 15 {
				Qclone =>
					if (mode == sys->OREAD) {
						srv.reply(ref Rmsg.Error(m.tag, "ctl cannot be open as read only"));
						break;
					}
					poolchanin <-= "request";
					cpuid := <-poolchanout;
					if (cpuid == -1)
						srv.reply(ref Rmsg.Error(m.tag, "no free resources"));
					else {
						sessid := getsession(-1);
						cpusession[sessid].fid = m.fid;
						cpusession[sessid].cpuid = cpuid;
						cpusession[sessid].omode = mode;
						cpusession[sessid].sync = chan of int;
						cpusession[sessid].proxyid = proxyid;
						spawn sessionctl(sessid, tree);
						Qdir := Qsessdir | (sessid<<4);
						tree.create(big Qroot, dir(string sessid,
							8r777 | sys->DMDIR,0, Qdir));
						tree.create(big Qdir, dir("data",	8r666,0, Qsessdat | (sessid<<4)));
						if (TEST)
							sys->fprint(sys->fildes(2), "New Session %d\n\tcpuid: %d\n"
								,sessid,cpuid);
						srv.default(gm);
					}
				Qsessdat =>
					err = "";
					sessid := (int f.path)>>4;					
					datafids = addfid(datafids, Datafid(sessid, m.fid, mode));
					if (cpusession[sessid].finished)
						err = "session already finished";
					else if (mode == sys->OREAD || mode == sys->ORDWR) {
						if (cpusession[sessid].stdoutopen == -1)
							err = "pipe closed";
						else
							cpusession[sessid].sync <-= STDOUTOPEN;
					}
					else if (mode == sys->OWRITE || mode == sys->ORDWR) {
						if (cpusession[sessid].stdinopen == -1)
							err = "pipe closed";
						else
							cpusession[sessid].sync <-= STDINOPEN;
					}
					# sys->fprint(sys->fildes(2), 
					#		"Open: Data: sessid %d, stdout %d stdin %d: err: '%s'\n",
					#		sessid,cpusession[sessid].stdoutopen,
					#		cpusession[sessid].stdinopen, err);
					if (err == nil)
						srv.default(gm);
					else
						srv.reply(ref Rmsg.Error(m.tag, err));
				* =>
					# sys->print("Open: %s tag: %d\n", gm.text(), gm.tag);
					srv.default(gm);
			}
		Write =>
			(f,e) := srv.canwrite(m);
			if(f == nil) {
				# sys->print("breaking! %r\n");
				break;
			}
			case int f.path & 15 {
				Qsessdat =>
					sessid := (int f.path)>>4;
					# sys->fprint(sys->fildes(2), "Write: Data %d len: %d\n",
					#	sessid,len m.data);
					spawn datawrite(sessid,srv,m);
				Qclone =>
					sessid := getsession(m.fid);
					# sys->fprint(sys->fildes(2), "Write: clone %d\n",sessid);
					spawn clonewrite(sessid,srv, m, cmdchan);
				* =>
					srv.default(gm);					
			}

		Read =>
			(f,e) := srv.canread(m);
			if(f == nil)
				break;
			case int f.path & 15 {
				Qclone =>
					sessid := getsession(m.fid);
					# sys->fprint(sys->fildes(2), "Read: clone %d\n",sessid);
					srv.reply(styxservers->readbytes(m, array of byte (string sessid + "\n")));
				Qsessdat =>
					sessid := (int f.path)>>4;
					# sys->fprint(sys->fildes(2), "Read: data session: %d\n",sessid);
					if (cpusession[sessid].finished)
						srv.reply(ref Rmsg.Error(m.tag, "session finished"));
					else
						spawn dataread(sessid, srv, m);
				Qrun =>
					srv.reply(styxservers->readbytes(m, array of byte RUN));
				Qcpu =>
					poolchanin <-= "refresh";
					s := (string ncpupool) + "\n";
					srv.reply(styxservers->readbytes(m, array of byte s));
				* =>
					srv.default(gm);					
			}

		* =>
			srv.default(gm);
		}
		}
	}
	if (TEST)
		sys->fprint(sys->fildes(2), "leaving serveloop...\n");
	tree.quit();
	for (i = 0; i < len cpusession; i++) {
		if (cpusession[i].proxyid == proxyid) {
			#Tear it down!
			if (TEST)
				sys->fprint(sys->fildes(2), "Killing off session %d\n",i);
			poolchanin <-= "free "+string cpusession[i].cpuid;
			for (; cpusession[i].pids != nil; cpusession[i].pids = tl cpusession[i].pids)
				kill(hd cpusession[i].pids);
			cpusession[i] = NILCPUSESSION;
		}
	}
	if (TEST)
		sys->fprint(sys->fildes(2), "serveloop exited\n");
}

dataread(sessid: int, srv: ref Styxserver, m: ref Tmsg.Read)
{
	cpusession[sessid].readstdout <-= 1;
	data := <- cpusession[sessid].stdoutchan;
	srv.reply(ref Rmsg.Read(m.tag, data));
}

datawrite(sessid: int, srv: ref Styxserver, m: ref Tmsg.Write)
{
	# sys->fprint(sys->fildes(2), "Writing to Stdin %d (%d)\n'%s'\n",
	#	len m.data, m.tag, string m.data);
	cpusession[sessid].stdinchan <-= m.data;
	# sys->fprint(sys->fildes(2), "Written to Stdin %d!\n",m.tag);
	srv.reply(ref Rmsg.Write(m.tag, len m.data));
}

clonewrite(sessid: int, srv: ref Styxserver, m: ref Tmsg.Write, cmdchan: chan of (int, string, chan of int))
{
	if (cpusession[sessid].written) {
		srv.reply(ref Rmsg.Error(m.tag, "session already started"));
		return;
	}
	rc := chan of int;
	cmdchan <-= (sessid, string m.data, rc);
	i := <-rc;
	# sys->fprint(sys->fildes(2), "Sending write\n");
	srv.reply(ref Rmsg.Write(m.tag, i));
}

badmod(path: string)
{
	sys->fprint(sys->fildes(1), "error CpuPool: failed to load: %s\n",path);
	exit;
}

listener(c: ref Sys->Connection)
{
	for (;;) {
		nc := dial->listen(c);
		if (nc == nil)
			error(sys->sprint("listen failed: %r"));
		dfd := dial->accept(nc);
		if (dfd != nil) {
			sync := chan of int;
			sys->print("got new connection!\n");
			spawn proxy(sync, dfd);
			<-sync;
		}
	}
}

proxy(sync: chan of int, dfd: ref Sys->FD)
{
	proxypid := sys->pctl(0, nil);
	sys->pctl(sys->FORKNS, nil);
	sys->chdir(EMPTYDIR);
	sync <-= 1;

	sync = chan of int;
	fds := array[2] of ref sys->FD;
	sys->pipe(fds);
	cmdchan := chan of (int, string, chan of int);
	exitchan := chan of int;
	killsrvloop := chan of int;
	spawn serveloop(fds[0], cmdchan, killsrvloop, sync, proxypid);
	<-sync;

	if (sys->mount(fds[1], nil, "/n/remote", Sys->MREPL | sys->MCREATE, nil) == -1)
		error(sys->sprint("cannot mount mountfd: %r"));

	conid := getconid(-1);
	conids[conid] = 1;
	setupworkspace(conid);
	
	spawn exportns(dfd, conid, exitchan);
	for (;;) alt {
		(sessid, cmd, reply) := <-cmdchan =>
			spawn runit(conid, sessid, cmd, reply);
		e := <-exitchan =>
			killsrvloop <-= 1;
			return;
	}
}

getconid(id: int): int
{
	for (i := 0; i < len conids; i++)
		if (conids[i] == id)
			return i;
	return -1;
}

exportns(dfd: ref Sys->FD, conid: int, exitchan: chan of int)
{
	sys->export(dfd, "/n/remote", sys->EXPWAIT);
	if (TEST)
		sys->fprint(sys->fildes(2), "Export Finished!\n");
	conids[conid] = -1;
	exitchan <-= 1;
}

error(e: string)
{
	sys->fprint(sys->fildes(2), "CpuPool: %s: %r\n", e);
	raise "fail:error";
}

setupworkspace(pathid: int)
{
	path := rootpath + string pathid;
	sys->create(path, sys->OREAD, 8r777 | sys->DMDIR);
	delpath(path, 0);
	sys->create(path + "/data", sys->OREAD, 8r777 | sys->DMDIR);
	if (sys->bind(path+"/data", "/n/remote/data",
			sys->MREPL | sys->MCREATE) == -1)
		sys->fprint(sys->fildes(2), "data bind error %r\n");
	sys->create(path + "/runtime", sys->OREAD, 8r777 | sys->DMDIR);
	if (sys->bind(path+"/runtime", "/n/remote/runtime", sys->MREPL) == -1)
		sys->fprint(sys->fildes(2), "runtime bind error %r\n");
	for (i := 0; i < len defaultdirs; i++) {
		if (defaultdirs[i].t1 == 1) {
			sys->create(path+"/"+defaultdirs[i].t0, sys->OREAD, 8r777 | sys->DMDIR);
			if (sys->bind("/"+defaultdirs[i].t0, 
					"/n/remote/"+defaultdirs[i].t0, sys->MREPL) == -1)
				sys->fprint(sys->fildes(2), "dir bind error %r\n");
		}
	}
}

delpath(path: string, incl: int)
{
	if (path[len path - 1] != '/')
		path[len path] = '/';
	(dirs, n) := readdir->init(path, readdir->NONE | readdir->COMPACT);
	for (i := 0; i < n; i++) {
		if (dirs[i].mode & sys->DMDIR)
			delpath(path + dirs[i].name, 1);
		else
			sys->remove(path + dirs[i].name);
	}
	if (incl)
		sys->remove(path);
}

runit(id, sessid: int, cmd: string, sync: chan of int)
{
	# sys->print("got runit!\n");
	cpusession[sessid].sync <-= PID;
	cpusession[sessid].sync <-=  sys->pctl(sys->FORKNS, nil);
	if (!TEST && sys->bind("/net.alt", "/net", sys->MREPL) == -1) {
			sys->fprint(sys->fildes(2), "cpupool net.alt bind failed: %r\n");
			sync <-= -1;
			return;
	}
	path := rootpath + string id;
	runfile := "/runtime/start"+string cpusession[sessid].cpuid+".sh";
	sh := load Sh Sh->PATH;
	if(sh == nil) {
		sys->fprint(sys->fildes(2), "Failed to load sh: %r\n");
		sync <-= -1;
		return;
	}

	sys->remove(path+runfile);
	fd := sys->create(path+runfile, sys->OWRITE, 8r777);
	if (fd == nil) {
		sync <-= -1;
		return;
	}
	sys->fprint(fd, "#!/dis/sh\n");
	sys->fprint(fd, "bind /prog /n/client/prog\n");
	sys->fprint(fd, "bind /n/client /\n");
	sys->fprint(fd, "cd /\n");
	sys->fprint(fd, "%s\n", cmd);

	if (sys->bind("#s", "/n/remote/runtime", Sys->MBEFORE|Sys->MCREATE) == -1) {
		sys->fprint(sys->fildes(2), "cpupool: %r\n");
		return;
	}

	cpusession[sessid].fio = sys->file2chan("/n/remote/runtime", "mycons");
	if (cpusession[sessid].fio == nil) {
		sys->fprint(sys->fildes(2), "cpupool: file2chan failed: %r\n");
		return;
	}

	if (sys->bind("/n/remote/runtime/mycons", "/n/remote/dev/cons", sys->MREPL) == -1)
		sys->fprint(sys->fildes(2), "cons bind error %r\n");
	cpusession[sessid].written = 1;

	cpusession[sessid].stdinchan = chan of array of byte;
	cpusession[sessid].closestdin = chan of int;
	cpusession[sessid].rcmdfinishedstdin = chan of int;
	spawn devconsread(sessid);

	cpusession[sessid].stdoutchan = chan of array of byte;
	cpusession[sessid].closestdout = chan of int;
	cpusession[sessid].readstdout = chan of int;
	cpusession[sessid].rcmdfinishedstdout = chan of int;
	spawn devconswrite(sessid);

	# Let it know that session channels have been created & can be listened on...
	sync <-= len cmd;

	# would prefer that it were authenticated
	if (TEST)
		sys->print("ABOUT TO RCMD\n");
	sh->run(nil, "rcmd" :: "-A" :: "-e" :: "/n/remote" :: 
				cpupool[cpusession[sessid].cpuid].srvc.addr ::
				"sh" :: "-c" :: "/n/client"+runfile :: nil);
	if (TEST)
		sys->print("DONE RCMD\n");

	sys->remove(path+runfile);
	sys->unmount(nil, "/n/remote/dev/cons");
	cpusession[sessid].rcmdfinishedstdin <-= 1;
	cpusession[sessid].rcmdfinishedstdout <-= 1;
	cpusession[sessid].sync <-= FINISHED;
}

CLONECLOSE: con 0;
FINISHED: con 1;
STDINOPEN: con 2;
STDINCLOSE: con 3;
STDOUTOPEN: con 4;
STDOUTCLOSE: con 5;
PID: con -2;

sessionctl(sessid: int, tree: ref Nametree->Tree)
{
	cpusession[sessid].pids = sys->pctl(0, nil) :: nil;
	clone := 1;
	closed := 0;
	main: for (;;) {
		i := <-cpusession[sessid].sync;
		case i {
		PID =>
			pid := <-cpusession[sessid].sync;
			if (TEST)
				sys->fprint(sys->fildes(2), "adding PID: %d\n", pid);
			cpusession[sessid].pids = pid :: cpusession[sessid].pids;
		STDINOPEN =>
			cpusession[sessid].stdinopen++;
			if (TEST)
				sys->fprint(sys->fildes(2), "%d: Open stdin: => %d\n",
					sessid, cpusession[sessid].stdinopen);
		STDOUTOPEN =>
			cpusession[sessid].stdoutopen++;
			if (TEST)
				sys->fprint(sys->fildes(2), "%d: Open stdout: => %d\n",
					sessid, cpusession[sessid].stdoutopen);
		STDINCLOSE =>
			cpusession[sessid].stdinopen--;
			if (TEST)
				sys->fprint(sys->fildes(2), "%d: Close stdin: => %d\n",
					sessid, cpusession[sessid].stdinopen);
			if (cpusession[sessid].stdinopen == 0) {
				cpusession[sessid].stdinopen = -1;
				cpusession[sessid].closestdin <-= 1;
			}
			# sys->fprint(sys->fildes(2), "Clunk: stdin (in %d: out %d\n",
			#	cpusession[sessid].stdinopen, cpusession[sessid].stdoutopen);
		STDOUTCLOSE =>
			cpusession[sessid].stdoutopen--;
			if (TEST)
				sys->fprint(sys->fildes(2), "%d: Close stdout: => %d\n",
					sessid, cpusession[sessid].stdoutopen);
			if (cpusession[sessid].stdoutopen == 0) {
				cpusession[sessid].stdoutopen = -1;
				cpusession[sessid].closestdout <-= 1;
			}
			#sys->fprint(sys->fildes(2), "Clunk: stdout (in %d: out %d\n",
			#	cpusession[sessid].stdinopen, cpusession[sessid].stdoutopen);
		CLONECLOSE =>
			if (TEST)
				sys->fprint(sys->fildes(2), "%d: Close clone\n", sessid);
			clone = 0;
			#sys->fprint(sys->fildes(2), "Clunk: clone (in %d: out %d\n",
			#	cpusession[sessid].stdinopen, cpusession[sessid].stdoutopen);
		FINISHED =>
			if (TEST)
				sys->fprint(sys->fildes(2), "%d: Rcmd finished", sessid);
			
			cpusession[sessid].finished = 1;
			poolchanin <-= "free "+string cpusession[sessid].cpuid;
			if (closed)
				break main;
		}
		if (cpusession[sessid].stdinopen <= 0 &&
			cpusession[sessid].stdoutopen <= 0 &&
			clone == 0) {
			
			closed = 1;
			tree.remove(big (Qsessdir | (sessid<<4)));
			tree.remove(big (Qsessdat | (sessid<<4)));
			if (cpusession[sessid].finished || !cpusession[sessid].written)
				break main;
		}
	}
	if (!cpusession[sessid].finished)	# ie never executed anything
		poolchanin <-= "free "+string cpusession[sessid].cpuid;
	cpusession[sessid] = NILCPUSESSION;
	if (TEST)
		sys->fprint(sys->fildes(2), "closing session %d\n",sessid);
}

devconswrite(sessid: int)
{
	cpusession[sessid].sync <-= PID;
	cpusession[sessid].sync <-= sys->pctl(0, nil);
	stdouteof := 0;
	file2chaneof := 0;
	rcmddone := 0;
	main: for (;;) alt {
	<-cpusession[sessid].rcmdfinishedstdout =>
		rcmddone = 1;
		if (file2chaneof)
			break main;
	<-cpusession[sessid].closestdout =>
		stdouteof = 1;
	(offset, d, fid, wc) := <-cpusession[sessid].fio.write =>
		if (wc != nil) {
			# sys->fprint(sys->fildes(2), "stdout: '%s'\n", string d);
			if (stdouteof) {
				# sys->fprint(sys->fildes(2), "stdout: sending EOF\n");
				wc <-= (0, nil);
				continue;
			}
			alt {
				<-cpusession[sessid].closestdout =>
					# sys->print("got closestdout\n");
					wc <-= (0, nil);
					stdouteof = 1;
				<-cpusession[sessid].readstdout =>
					cpusession[sessid].stdoutchan <-= d;
					wc <-= (len d, nil);
			}
		}
		else {
			# sys->fprint(sys->fildes(2), "got nil wc\n");
			file2chaneof = 1;
			if (rcmddone)
				break main;
		}
	}
	# No more input at this point as rcmd has finished;
	if (stdouteof || cpusession[sessid].stdoutopen == 0) {
		# sys->print("leaving devconswrite\n");
		return;
	}
	for (;;) alt {
		<-cpusession[sessid].closestdout =>
			# sys->print("got closestdout\n");
			# sys->print("leaving devconswrite\n");
			return;
		<- cpusession[sessid].readstdout =>
			cpusession[sessid].stdoutchan <-= nil;
	}
}

devconsread(sessid: int)
{
	cpusession[sessid].sync <-= PID;
	cpusession[sessid].sync <-= sys->pctl(0, nil);
	stdineof := 0;
	file2chaneof := 0;
	rcmddone := 0;
	main: for (;;) alt {
	<-cpusession[sessid].rcmdfinishedstdin =>
		rcmddone = 1;
		if (file2chaneof)
			break main;
	<-cpusession[sessid].closestdin =>
		# sys->print("got stdin close\n");
		stdineof = 1;
	(offset, count, fid, rc) := <-cpusession[sessid].fio.read =>
		if (rc != nil) {
			# sys->fprint(sys->fildes(2), "devconsread: '%d %d'\n", count, offset);
			if (stdineof) {
				rc <-= (nil, nil);
				continue;
			}
			alt {
			data := <-cpusession[sessid].stdinchan =>
				# sys->print("got data len %d\n", len data);
				rc <-= (data, nil);
			<-cpusession[sessid].closestdin =>
				# sys->print("got stdin close\n");
				stdineof = 1;
				rc <-= (nil, nil);
			}
		}
		else {
			# sys->print("got nil rc\n");
			file2chaneof = 1;
			if (rcmddone)
				break main;
		}
	}
	if (!stdineof && cpusession[sessid].stdinopen != 0)
		<-cpusession[sessid].closestdin;
	# sys->fprint(sys->fildes(2), "Leaving devconsread\n");
}

Srvcpool: adt {
	srvc: ref Service;
	inuse: int;
};

cpupool: array of Srvcpool;
ncpupool := 0;

cpupoolloop(chanin: chan of string, chanout: chan of int)
{
	cpupool = array[200] of Srvcpool;
	for (i := 0; i < len cpupool; i++)
		cpupool[i] = Srvcpool (nil, 0);
	wait := 0;
	for (;;) {
		inp := <-chanin;
		# sys->print("poolloop: '%s'\n",inp);
		(nil, lst) := sys->tokenize(inp, " \t\n");
		case hd lst {
		"refresh" =>
			if (daytime->now() - wait >= 60) {
				refreshcpupool();
				wait = daytime->now();
			}
		"request" =>
			if (daytime->now() - wait >= 60) {
				refreshcpupool();
				wait = daytime->now();
			}
			found := -1;
			# sys->print("found %d services...\n", ncpupool);
			for (i = 0; i < ncpupool; i++) {
				if (!cpupool[i].inuse) {
					found = i;
					cpupool[i].inuse = 1;
					break;
				}
			}
			# sys->print("found service %d\n", found);
			chanout <-= found;
		"free" =>
			if (TEST)
				sys->print("freed service %d\n", int hd tl lst);
			cpupool[int hd tl lst].inuse = 0;
		}
	}
}

refreshcpupool()
{
	(lsrv, err) := rstyxreg.find(("resource", "Rstyx resource") :: nil);
	# sys->print("found %d resources\n",len lsrv);
	if (err != nil)
		return;
	tmp := array[len cpupool] of Srvcpool;
	ntmp := len lsrv;
	i := 0;
	for (;lsrv != nil; lsrv = tl lsrv)
		tmp[i++] = Srvcpool(hd lsrv, 0);
	min := 0;
	for (i = 0; i < ntmp; i++) {
		for (j := min; j < ncpupool; j++) {
			if (tmp[i].srvc.addr == cpupool[j].srvc.addr) {
				if (j == min)
					min++;
				tmp[i].inuse = cpupool[j].inuse;
			}
		}
	}
	ncpupool = ntmp;	
	for (i = 0; i < ntmp; i++)
		cpupool[i] = tmp[i];
	# sys->print("ncpupool: %d\n",ncpupool);
}

getsession(fid: int): int
{
	for (i := 0; i < len cpusession; i++)
		if (cpusession[i].fid == fid)
			return i;
	return -1;
}

kill(pid: int)
{
	if ((fd := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE)) != nil)
		sys->fprint(fd, "kill");
}

killg(pid: int)
{
	if ((fd := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE)) != nil)
		sys->fprint(fd, "killgrp");
}

delfid(datafids: list of Datafid, fid: int): (list of Datafid, Datafid)
{
	rdf := Datafid (-1, -1, -1);
	tmp : list of Datafid = nil;
	for (; datafids != nil; datafids = tl datafids) {
		testdf := hd datafids;
		if (testdf.fid == fid)
			rdf = testdf;
		else
			tmp = testdf :: tmp;
	}
	return (tmp, rdf);
}

addfid(datafids: list of Datafid, df: Datafid): list of Datafid
{
	(datafids, nil) = delfid(datafids, df.fid);
	return df :: datafids;
}

Datafid: adt {
	sessid, fid, omode: int;
};
