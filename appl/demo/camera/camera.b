implement Camera;

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
	Styxserver, Eexists, Eperm, Ebadfid, Enotdir, Enotfound, Ebadarg: import styxservers;
	nametree: Nametree;
	Tree: import nametree;
include "string.m";
	str : String;
include "draw.m";
include "arg.m";

Camera : module {
	init : fn (nil : ref Draw->Context, argv : list of string);
};

cdp_get_product_info: 			con 16r01;
cdp_get_image_specifications:	con 16r02;
cdp_get_camera_status:			con 16r03;
cdp_set_product_info:			con 16r05;
cdp_get_camera_capabilities:		con 16r10;
cdp_get_camera_state:			con 16r11;
cdp_set_camera_state:			con 16r12;
cdp_get_camera_defaults:		con 16r13;
cdp_set_camera_defaults:		con 16r14;
cdp_restore_camera_states:		con 16r15;
cdp_get_scene_analysis:			con 16r18;
cdp_get_power_mode:			con 16r19;
cdp_set_power_mode:			con 16r1a;
cdp_get_s1_mode:				con 16r1d;
cdp_set_s1_mode:				con 16r1e;
cdp_start_capture:				con 16r30;
cdp_get_file_list:				con 16r40;
cdp_get_new_file_list:			con 16r41;
cdp_get_file_data:				con 16r42;
cdp_erase_file:					con 16r43;
cdp_get_storage_status:			con 16r44;
cdp_set_file_data:				con 16r47;
cdp_get_file_tag:				con 16r48;
cdp_set_user_file_tag:			con 16r49;
cdp_get_clock:					con 16r70;
cdp_set_clock:					con 16r71;
cdp_get_error:					con 16r78;
cdp_get_interface_timeout:		con 16r90;
cdp_set_interface_timeout:		con 16r91;

cdp_header_len:				con 12;

T_DIR: con 0;
T_CTL: con 1;
T_ABILITIES: con 2;
T_TIME: con 3;
T_JPGDIR: con 4;
T_JPG: con 5;
T_STORAGE: con 6;
T_POWER: con 7;
T_THUMB: con 8;
T_THUMBDIR: con 9;
T_STATE: con 10;
T_INTERFACE: con 11;

MAXFILESIZE : con 5000000;
TIMEOUT : con 4000;

nextjpgqid, nexttmbqid, dirqid, Qctl, Qabl, Qstore: int;
Qstate, Qtime, Qjpgdir, Qpwr, Qthumbdir, Qinterface : int;

error_table := array [] of {
	"No Error",
	"Unimplemented",
	"Unsupported Version",
	"Application Timeout",
	"Internal Error",
	"Parameter Error",
	"File System Null",
	"File Not Found",
	"Data Section Not Found",
	"Invalid File Type",
	"Unknown Drive",
	"Drive Not Mounted",
	"System Busy",
	"Battery Low",
};

bintro := array [] of {
	byte 16ra5,
	byte 16r5a,
	byte 16r00,
	byte 16rc8,
	byte 16r00,
	byte 16r02,
	byte 16rc9,
};

bak := array [] of {
	byte 16r5a,	# 2 byte header
	byte 16ra5,
	byte 16r55,	# I/F Type
	byte 16r00,	# Comm Flag
	byte 16r00,
	byte 16r00,
	byte 16r00,
	byte 16r00,
	byte 16r00,
	byte 16r00,
	byte 16r00,
	byte 16r00,
	byte 16r00,
};

pwl := array[] of {
	byte 0,
	byte 0,
};

pak := array [] of {
	byte 0,
	byte 0,
};

SERIAL, USB, IRDA: con (1<<iota);
BEACON, BEACONRESULT: con (1<<iota);

Camera_adt: adt {
	port_type: 	int;
	port_num:	int;
	command:	int;
	mode: 		int;
	fd:			ref Sys->FD;
	ctlfd:			ref Sys->FD;
	cdp:			array of byte;
	bufbytes:		int;
	baud:		int;
	dfs, hfs:		int;		# device and host frame sizes
	stat:			int;	# eia status file
};

statopt := array[] of {
	"status",
	"stat",
};

DL_QUANTA: con 20000;

TOUT: con -1729;

Partialtag: adt {
	offset, length, filesize: int;
};

Cfile: adt {
	driveno: int;
	pathname: array of byte;
	dosname: array of byte;
	filelength: int;
	filestatus: int;
	thumblength: int;
	thumbqid: int;
};

Fitem : adt {
	qid: Sys->Qid;
	cf: Cfile;
};

C: Camera_adt;

filelist: array of Fitem;
reslength: int;
currentstate := "";
wait : int;
usecache := 0;
connected : int;
recon := 0;
verbosity := 4;
interfacepath := "";
interfacepaths : array of string;
camname := "";
gpid : int;

init(nil : ref Draw->Context, argv : list of string)
{
	err: string;
	sys = load Sys Sys->PATH;
	gpid = sys->pctl(Sys->NEWPGRP, nil);

	str = load String String->PATH;
	daytime = load Daytime Daytime->PATH;

	styx = load Styx Styx->PATH;
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	styxservers->init(styx);
	nametree = load Nametree Nametree->PATH;
	nametree->init();
	arg := load Arg Arg->PATH;

	filelist = array[200] of Fitem;
	C.port_num = 0;			# XXXXX from argv
	C.port_type = SERIAL;		# Serial only for now
	C.baud = 115200;
	C.dfs = C.hfs = 1023;
	C.cdp = array [DL_QUANTA] of byte;
	C.mode = BEACON;

	ex.pnum = -1;
	ex.offset = -1;
	cachelist = nil;

	nextjpgqid = getqid(1, T_JPG);
	nexttmbqid = getqid(1, T_THUMB);
	dirqid = getqid(1,T_JPGDIR);
	Qctl = getqid(Qroot,T_CTL);
	Qabl = getqid(Qroot,T_ABILITIES);
	Qstore = getqid(Qroot,T_STORAGE);
	Qtime = getqid(Qroot,T_TIME);
	Qstate = getqid(Qroot,T_STATE);
	Qpwr = getqid(Qroot,T_POWER);	
	Qjpgdir = getqid(Qroot,T_JPGDIR);
	Qthumbdir = getqid(Qroot,T_THUMBDIR);
	Qinterface = getqid(Qroot,T_INTERFACE);
	
	camname = "Camera";
	extrafilelist: list of string = nil;
	arg->init(argv);
	arg->setusage("camera [-b baud] [-F framesize] [-f extrafiles] [-p port] [-n name] [-v verbosity]");
	while ((opt := arg->opt()) != 0) {
		case opt {
		'n' =>
			camname = arg->earg();
		'v' =>
			verbosity = int arg->earg();
		'F' =>
			C.dfs = C.hfs = int arg->earg();
		'b' =>
			C.baud = int arg->earg();
		'p' =>
			C.port_num = int arg->earg();
		'c' =>
			usecache = 1;
		'f' =>
			extrafilelist = arg->earg() :: extrafilelist;
		* =>
			arg->usage();
		}
	}
	arg = nil;
	interfacepaths = array[len extrafilelist] of string;
	# sys->print("INTERFACEPATHS: %d\n", len extrafilelist);
	for (i := 0; i < len interfacepaths; i++) {
		interfacepaths[i] = hd extrafilelist;
		# sys->print("INTERFACEPATH %d: %s\n", i, hd extrafilelist);
		extrafilelist = tl extrafilelist;
	}
	
	print(sys->sprint("Trying to connect to eia%d...\n",C.port_num),2);
	case C.port_type {
		SERIAL =>
			# open port and return fd
			(C.fd, C.ctlfd, err) = serialport(C.port_num);
			if (C.fd == nil) {
				print("Could not open serial port\n",1);
				exit;
			}
		USB =>
			;
		IRDA =>
			;
		* =>
			;
	}
	if (connect() != 0) {;
		print("Connection failed\n",1);
		exit;
	}
	recon = 0;
	print("Connected!\n",2);
	set_interface_timeout();
	set_camera_properties();
	get_file_list();
	connected = 1;
	ignoreabls = nil;
	get_camera_capabilities();
	sync := chan of int;
	spawn serveloop(sys->fildes(0), sync);
	<-sync;
}

set_camera_properties()
{
	for (i := 0; i < len set_camera_props; i++)
		set_camera_state(set_camera_props[i].t0,set_camera_props[i].t1);
}

set_camera_props := array[] of {
	("mcap", 0),
	("acpd", 65535),
	("actc", 65535),
	("btpd", 65535),
	("bttc", 65535),
	("flty", 1246774599),
	("ssvl", 0),
};

argval(argv: list of string, arg: string): string
{
	if (arg == "") return "";
	if (arg[0] != '-') arg = "-" + arg;
	while (argv != nil) {
		if (hd argv == arg && tl argv != nil && (hd tl argv)[0] != '-')
			return tonext(tl argv);
		argv = tl argv;
	}
	return "";
}

tonext(los: list of string): string
{
	s := "";
	while (los != nil) {
		if ((hd los)[0] != '-') s += " " + hd los;
		else break;
		los = tl los;
	}
	if (s != "") s = s[1:];
	return s;
}

int2hex(i:int): int
{
	i2 := 0;
	s := string i;
	for (k := 0; k < len s; k++)
		i2 = (i2 * 16) + int s[k:k+1];
	return i2;
}

connect(): int
{	
	connected = 0;
	datain := chan of array of byte;
	pchan := chan of int;
	tick := chan of int;
	reset(C.ctlfd);

	spawn timer2(tick,TIMEOUT * 2);
	tpid := <-tick;

	spawn beacon_intro(datain, pchan, C.fd);
	pid := <- pchan;
	# beacon phase
	Beacon: for (;;) {
		alt {
			buf := <- datain =>
				# got some data
				case C.mode {
					BEACON =>
						if (beacon_ok(buf)) {
							print("Got beacon\n",3);
							beacon_ack(C);
							spawn beacon_result(datain, pchan, C.fd);
							pid = <-pchan;
							C.mode = BEACONRESULT;
							break;
						}
						else {
							print("resetting\n",3);
							reset(C.ctlfd);
						}
					BEACONRESULT =>
						kill(tpid);

						print("Checking beacon result\n",3);
						if (beacon_comp(buf, C) == 0) {
							return 0;
							break Beacon;
						}
						return -1;
				}
			<- tick =>
				kill(pid);
				return -1;		# failure
		}
	}
}

CTL, ABILITIES, DATA, JPG, PIC, TIME, CONV: con iota;
NAME, FSIZE, PHOTO, THUMB: con iota;

Qdir : con iota;

contains(s: string, test: string): int
{
	num :=0;
	if (len test > len s) return 0;
	for (i := 0; i < (1 + (len s) - (len test)); i++) {
		if (test == s[i:i+len test]) num++;
	}
	return num;
}

abilitiesfilter := array[] of {
	"Time Format",
	"Date Format",
	"File Type",
	"Video",
	"Media",
	"Sound",
	"Volume",
	"Reset Camera",
	"Slide",
	"Timelapse",
	"Burst",
	"Power",
	"Sleep",
};

ignoreabls : list of string;

defattr : list of (string, int);
defaultattr, currentattr: array of (string, int);

filterabls(pname, desc: string): int
{
	for (i := 0; i < len abilitiesfilter; i++) {
		if (contains(desc, abilitiesfilter[i])) {
			ignoreabls = pname :: ignoreabls;
			return 1;
		}
	}
	return 0;
}

mountit(dfd, mountfd: ref sys->FD, sync: chan of int)
{
	sys->pctl(sys->NEWNS | sys->NEWFD, 2 :: dfd.fd :: mountfd.fd :: nil);
	sync <-= 1;
	mountfd = sys->fildes(mountfd.fd);
	dfd = sys->fildes(dfd.fd);
	if (sys->mount(mountfd, nil, "/", sys->MREPL | sys->MCREATE, nil) == -1) {
		sys->fprint(sys->fildes(2), "cannot mount\n");
		spawn exporterror(dfd, sys->sprint("%r"));
	} else {
		sync = chan of int;
		spawn exportpath(sync, dfd);
		<-sync;
	}
}

exporterror(dfd: ref Sys->FD, error: string)
{
	tmsg := Tmsg.read(dfd, 0);
	if (tmsg == nil) {
		sys->fprint(sys->fildes(2), "exporterror() EOF\n");
		exit;
	}
	pick t := tmsg {
	Readerror =>
		sys->fprint(sys->fildes(2), "exporterror() Readerror\n");
	* =>
		reply: ref Rmsg = ref Rmsg.Error(tmsg.tag, error);
		data := reply.pack();
		sys->write(dfd, data, len data);
	}
}

exportpath(sync: chan of int, dfd: ref sys->FD)
{
	sync <-= 1;
	sys->export(dfd, "/", Sys->EXPWAIT);
}

Qroot : con int iota;

ss : ref Styxserver;
uid: string;

exitfid := -1;

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

User: adt {
	attachfid: int;
	attr: array of (string, int);
};

users : array of User;

getuser(fid: int): int
{
	for (i := 0; i < len users; i++)
		if (users[i].attachfid == fid)
			return i;
	return -1;
}

getattr(pname: string): int
{
	for (i := 0; i < len defaultattr; i++)
		if (defaultattr[i].t0 == pname)
			return i;
	return -1;
}

serveloop(fd : ref sys->FD, sync: chan of int)
{
	tchan: chan of ref Tmsg;
	srv: ref Styxserver;
	echan := chan of string;
	users = array[20] of { * => User (-1, nil) };
	sys->pctl(Sys->FORKNS, nil);
	sync <-= 1;
	print("serveloop\n",5);
	getuid();
	(tree, treeop) := nametree->start();
	tree.create(big Qroot, dir(".",8r555 | sys->DMDIR,0,Qroot));
	tree.create(big Qroot, dir("ctl",8r222,0,Qctl));
	tree.create(big Qroot, dir("abilities",8r444,0,Qabl));
	tree.create(big Qroot, dir("storage",8r444,0,Qstore));
	tree.create(big Qroot, dir("power",8r444,0,Qpwr));
	tree.create(big Qroot, dir("date",8r666,0,Qtime));
	tree.create(big Qroot, dir("state",8r666,0,Qstate));
	tree.create(big Qroot, dir("jpg",8r777 | sys->DMDIR,0,Qjpgdir));
	tree.create(big Qroot, dir("thumb",8r777 | sys->DMDIR,0,Qthumbdir));
	for (j := 0; j < len interfacepaths; j++) {
		(n, idir) := sys->stat(interfacepaths[j]);
		if (n != -1) {
			idir.qid.path = big Qinterface;
			# intdir := dir("",8r777,0,Qinterface);
			# intdir.name = idir.name;
			# intdir.length = idir.length;
			# intdir.atime = idir.atime;
			# intdir.mtime = idir.mtime;
			tree.create(big Qroot, idir);
			Qinterface += 1<<4;
		}
	}

	tmsgqueue := Tmsgqueue.new(50);

	(tchan, srv) = Styxserver.new(fd,Navigator.new(treeop), big Qroot);
	fd = nil;

	gm, lastgm: ref Tmsg;
	gm = nil;

	oldfiles = nil;
	updatetree(tree);

	print("serveloop loop\n",5);
	alivechan := chan of int;
	spawn keepalive(alivechan);
	alivepid := <-alivechan;
	retryit := 0;
	notries := 0;
	readfid := -1;
	serveloop: for (;;) {
		wait = daytime->now();
		if (notries > 5) retryit = 0;
		if (retryit) {
			gm = lastgm;
			notries++;
		}
		else {
			notries = 0;
			loop: for (;;) {
				gm = tmsgqueue.pop(readfid);
				if (gm != nil)
					break;
				alt {
				gm = <-tchan =>
					break loop;
				c := <-alivechan =>
					for (;;) {
						s := get_clock();
						wait = daytime->now();
						# print(sys->sprint("got alivechan: %s",s),1);
						if (recon) {
							killchan := chan of int;
							spawn noresponse(tchan,srv,killchan);
							reconnect(-1);
							killchan <-= 1;
						}
						else
							break;
					}
				}
			}
		}
		lastgm = gm;
		retryit = 0;
		if (gm == nil) {
			sys->print("exiting!\n");
			break serveloop;		# nil => EOF => last mount was unmounted
		}
		print(sys->sprint("Got new GM %s tag: %d\n", gm.text(), gm.tag),4);
		# print(sys->sprint("Got new GM %s tag: %d\n", gm.text(), gm.tag),2);

		if (!connected) {
			srv.reply(ref Rmsg.Error(gm.tag, "Could not connect to camera"));
			print("Error: not connected to camera\n",1);
		}
		else pick m := gm {
		Readerror =>
			print(sys->sprint( "camera: fatal read error: %s\n", m.error),1);
			break serveloop;
		Attach =>
			nu := getuser(-1);
			if (nu == -1) {
				srv.reply(ref Rmsg.Error(m.tag, "Camera in use"));
				break;
			}
			m.uname = string nu;
			srv.default(m);
			myattr := array[len currentattr] of (string, int);
			for (i := 0; i < len myattr; i++)
				myattr[i] = currentattr[i];
			users[nu] = User (m.fid, myattr);
			print("adding user "+string nu, 2);
		Clunk =>
			nu := getuser(m.fid);
			if (nu != -1) {
				users[nu] = User (-1, nil);
				print("removing user "+string nu, 2);
			}
			if (m.fid == readfid) {
				# sys->print("readfid clunk: %d\n",readfid);
				readfid = -1;
			}
			srv.default(gm);
		Remove =>
			print("Removing file\n",3);
			f := srv.getfid(m.fid);
			if (f == nil) {
				print("Remove: Invalid fid\n",1);
				srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
				break;
			}
			ftype := gettype(int f.path);
			if (ftype != T_JPG) {
				srv.reply(ref Rmsg.Error(m.tag, "Cannot remove file"));
				break;
			}
			else {
				for (i := 0; i < reslength; i++) {
					if (f.path == filelist[i].qid.path) {
						print("removing filelist\n",5);
						if (erase_file(filelist[i].cf) != 0) {
							if (!recon) 
								srv.reply(ref Rmsg.Error(m.tag, "Cannot remove file"));
							break;
						}
					
						srv.delfid(f);
						if (get_file_list() != 0)
							srv.reply(ref Rmsg.Error(m.tag, "Cannot read files"));
						else {
							updatetree(tree);
							srv.reply(ref Rmsg.Remove(m.tag));
						}
						break;
					}
				}
			}
		Read =>
			print("got read request in serveloop\n",6);
			(f,e) := srv.canread(m);
			if(f == nil)
				break;
			if (f.qtype & Sys->QTDIR) {
				print("reading directory\n",5);
				srv.read(m);
				break;
			}
			data : array of byte;
			case gettype(int f.path) {
			T_INTERFACE =>
				(dir, intdata) := readinterface(int f.path, m.offset, m.count);
				if (dir != nil && m.offset == big 0) {
					dir.qid.path = f.path;
					tree.wstat(f.path, *dir);
				}
				srv.reply(ref Rmsg.Read(m.tag, intdata));
			T_POWER =>
				print("reading power mode...\n",3);
				data = array of byte get_power_mode();
				if (!recon) srv.reply(styxservers->readbytes(m, data));

			T_TIME =>
				print("reading clock...\n",3);
				data = array of byte get_clock();
				if (!recon)	
					srv.reply(styxservers->readbytes(m, data));

			T_ABILITIES =>
				data = array of byte get_camera_capabilities();
				if (!recon)
					srv.reply(styxservers->readbytes(m, data));

			T_JPG =>
				# sys->print("Read Jpg: user %d\n", int f.uname);
				if (readfid != -1 && readfid != m.fid) {
					tmsgqueue.push(m);
					# sys->print("in use!\n");
					# srv.reply(ref Rmsg.Error(m.tag, "Camera in use, please wait"));
					break;
				}
				readfid = m.fid;
				data = photoread2(f.path, m,tree,0);
				if (!recon)
					srv.reply(ref Rmsg.Read(m.tag, data));
	
			T_THUMB =>
				if (readfid != -1 && readfid != m.fid) {
					# srv.reply(ref Rmsg.Error(m.tag, "Camera in use, please wait"));
					tmsgqueue.push(m);
					break;
				}
				readfid = m.fid;
				# sys->print("Read Thumb: user %d\n", int f.uname);
				data = photoread2(f.path, m,tree,1);
				if (!recon)
					srv.reply(ref Rmsg.Read(m.tag, data));

			T_STATE =>
				if (currentstate == "") srv.reply(ref Rmsg.Error(m.tag, "No state requested"));
				else {
					data = array of byte get_camera_state(currentstate,int m.offset);
					if (!recon)
						srv.reply(ref Rmsg.Read(m.tag, data));
				}

			T_STORAGE =>
				data = array of byte get_storage_status();
				if (!recon) {
					if (len data == 0)
						srv.reply(ref Rmsg.Error(m.tag, "Could not read storage status"));
					else
						srv.reply(styxservers->readbytes(m, data));
				}
			* =>
				srv.reply(ref Rmsg.Error(m.tag, "Cannot read file"));
			}
			# if (readfid != -1)
			# 	sys->print("readfid set: %d\n",readfid);
		Write =>
			print("got write request in serveloop\n",6);

			(f,e) := srv.canwrite(m);
			if(f == nil) {
				print("cannot write to file\n",1);
				break;
			}
			wtype := gettype(int f.path);
			(n, s) := sys->tokenize(string m.data, " \t\n");
			if (wtype == T_TIME) {
				if (set_clock(string m.data) != 0)
					srv.reply(ref Rmsg.Error(m.tag, "Invalid date time format\n" + 
										"Usage: MM/DD/YY HH/MM/SS\n"));
				else srv.reply(ref Rmsg.Write(m.tag, len m.data));
				
			}
			else if (wtype == T_CTL) {
				err := "";
				case hd s {
				"refresh" =>
					# for (i := 0; i < reslength; i++) {
					#	tree.remove(filelist[i].qid.path);
					#	tree.remove(big filelist[i].cf.thumbqid);
					# }
					if (get_file_list() != 0)
						err = "Error: Could not read from camera";
					else 
						updatetree(tree);
						# for (i = 0; i < reslength; i++) 
						#	buildfilelist(tree, i);
				"snap" =>
					nu := int f.uname;
					print(sys->sprint("User %d taking photo\n",nu),2);
					for (i := 0; i < len currentattr; i++) {
						# sys->print("user: %s=%d current: %s=%d\n",
						# 	users[nu].attr[i].t0,users[nu].attr[i].t1,
						#	currentattr[i].t0,currentattr[i].t1);
						if (users[nu].attr[i].t1 != currentattr[i].t1) {
							set_camera_state(users[nu].attr[i].t0, users[nu].attr[i].t1);
							sys->sleep(100);
						}
					}
					e1 := capture();
					if (e1 == -1) {
						err = "Cannot communicate with camera";
						break;
					}
					if (e1 != 0) { 
						err = "Error: "+error_table[e1];
						break;
					}
					sys->sleep(4000);
					if (get_file_list() != 0) {
						err = "Error: Could not read from camera";
						break;
					}
					updatetree(tree);
				* =>
					if (n == 2) {	# assume that it is a (string, int) tuple
						na := getattr(hd s);
						if (na == -1)
							err = "Invalid command name '"+hd s+"'";
						else {
							e1 := set_camera_state(hd s, int hd tl s);
							if (e1 != nil)
								err = e;
							else
								users[int f.uname].attr[na].t1 = int hd tl s;
						}
					}
					
				}

				if (!recon) {
					if (err != "") {
						print(err+"\n",1);
						srv.reply(ref Rmsg.Error(m.tag, err));
					}
					else srv.reply(ref Rmsg.Write(m.tag, len m.data));
				}
			}
			else if (wtype == T_STATE) {
				if (s != nil)
					currentstate = hd s;
				srv.reply(ref Rmsg.Write(m.tag, len m.data));
			}
			else srv.reply(ref Rmsg.Error(m.tag, "Could not write to file"));
		Wstat =>
			print("Got Wstat command in serveloop\n",6);
			srv.reply(ref Rmsg.Error(m.tag, "Wstat failed"));
		* =>
			srv.default(gm);
		}
		if (recon) {
			retryit = 1;
			ok :=	reconnect(4);
			if (!ok) {
				srv.reply(ref Rmsg.Error(gm.tag, "Could not connect to camera"));
				killchan := chan of int;
				spawn noresponse(tchan,srv,killchan);
				reconnect(-1);
				killchan <-= 1;
				retryit = 0;
				sys->sleep(100);
			}
		}
	}
	tree.quit();
	kill(alivepid);
	killg(gpid);
}

Tmsgqueue: adt {
	start, end, length: int;
	a : array of ref Tmsg.Read;
	new: fn (n: int): ref Tmsgqueue;
	push: fn (t: self ref Tmsgqueue, t: ref Tmsg.Read): int;
	pop: fn (t: self ref Tmsgqueue, readfid: int): ref Tmsg.Read;
};

Tmsgqueue.new(n: int): ref Tmsgqueue
{
	t : Tmsgqueue;
	t.start = 0;
	t.end = 0;
	t.length = 0;
	t.a = array[n] of ref Tmsg.Read;
	return ref t;
}

Tmsgqueue.push(t: self ref Tmsgqueue,newt: ref Tmsg.Read): int
{
	if (t.length >= len t.a)
		return -1;
	t.a[t.end] = newt;
	t.end++;
	if (t.end >= len t.a)
		t.end = 0;
	t.length++;
	return 0;
}

Tmsgqueue.pop(t: self ref Tmsgqueue, readfid: int): ref Tmsg.Read
{
	if (t.length == 0)
		return nil;
	m := t.a[t.start];
	if (readfid != -1 && readfid != m.fid)
		return nil;
	t.start++;
	if (t.start >= len t.a)
		t.start = 0;
	t.length--;
	return m;
}

noresponse(tchan: chan of ref Tmsg, srv: ref Styxservers->Styxserver, killchan : chan of int)
{
	for (;;) alt {
		k := <- killchan =>
			return;
		gm := <- tchan =>
			print("noresponse: Returning Error\n",1);
			srv.reply(ref Rmsg.Error(gm.tag, "Could not connect to camera"));
			sys->sleep(100);
	}
}

photoread2(qid: big, m: ref Tmsg.Read, tree: ref Nametree->Tree, isthumb: int): array of byte
{
	photonum := -1;
	data : array of byte;
	# sys->print("photoread: qid: %d resl: %d\n",int qid,reslength);
	for (i := 0; i < reslength; i++) {
		# sys->print("%d: %s %d\n",i, sconv(filelist[i].cf.dosname),int filelist[i].qid.path);
		if (!isthumb && qid == filelist[i].qid.path) {
			photonum = i;
			break;
		}
		else if (isthumb && int qid == filelist[i].cf.thumbqid) {
			photonum = i;
			break;
		}
	}
	if (photonum >= reslength || photonum < 0) {
		print(sys->sprint( "error: photonum = %d (reslength = %d)\n", photonum,reslength),1);
		return nil;
	}
	offset := int m.offset;
	dosname := filelist[photonum].cf.dosname;
	filelen := filelist[photonum].cf.filelength;
	for (k := 0; k < 5; k++) {
		if (filelen == 0) {
			get_file_size(photonum);
			print(sys->sprint("\tFilelen: %d => ",filelen),5);
			filelen = filelist[photonum].cf.filelength;
			print(sys->sprint("%d\n",filelen),5);
			tree.wstat(qid,
					dir(str->tolower(sconv(filelist[photonum].cf.dosname)),
					8r444,
					filelen,
					int qid));
			sys->sleep(1000);
		}
		else break;
	}
	if (filelen == 0 && !isthumb) return nil; # doesn't matter if filesize is wrong for thumbnail
	if (isthumb) filelen = filelist[photonum].cf.thumblength;
	if (usecache && cachesize(dosname, isthumb) == filelen) {
#		print(sys->sprint("Is cached!\n");
		n := m.count;
		filesize := cachesize(dosname,isthumb);
		if (offset >= filesize) return nil;
		if (offset+m.count >= filesize) n = filesize - offset;
		data = array[n] of byte;
		fd := sys->open(cachename(dosname,isthumb), sys->OREAD);
		if (fd == nil) cachedel(dosname,isthumb);
		else {
			sys->seek(fd,m.offset,sys->SEEKSTART);
			sys->read(fd,data,len data);
			fd = nil;
			return data;
		}
	}
#	print(sys->sprint("Is NOT cached!\n");

	if (photonum == ex.pnum && offset == ex.offset && ex.isthumb == isthumb) 
		data = ex.data;
	else if (isthumb)
		data = getthumb(photonum, offset, m.count);
	else if (!isthumb)
		data = getpicture2(photonum, offset, m.count);
	if (len data > m.count) {
		ex.pnum = photonum;
		ex.offset = offset + m.count;
		ex.data = array[len data - m.count] of byte;
		ex.data[0:] = data[m.count:len data];
		ex.isthumb = isthumb;
		data = data[:m.count];
	}
	if (usecache) {
		fd : ref sys->FD;
		cname := cachename(dosname,isthumb);
	
		if (offset == 0)
			fd = sys->create(cname,sys->OWRITE,8r666);
		else {
			fd = sys->open(cname,sys->OWRITE);
			if (fd != nil)
				sys->seek(fd,big 0,sys->SEEKEND);
		}
		if (fd != nil) {
			i = sys->write(fd,data,len data);
			fd = nil;
		}
		(n, dir) := sys->stat(cname);
		if (n == 0) {
			cacheadd(dosname,isthumb,int dir.length);
		}
	}
	return data;
}

cachelist : list of (string, int, int);

cacheprint()
{
	tmp := cachelist;
	print("cache:\n",3);
	while (tmp != nil) {
		(dn,i1,i2) := hd tmp;
		print(sys->sprint("\t%s %d %d\n",dn,i1,i2),3);
		tmp = tl tmp;
	}
}

cacheclean()
{
	tmp : list of (string, int,int);
	tmp = nil;
	while (cachelist != nil) {
		(dosnm,it,fl) := hd cachelist;
		for (i := 0; i < reslength; i++) {
			filelen := filelist[i].cf.filelength;
			if (it) filelen = filelist[i].cf.thumblength;
			if (sconv(filelist[i].cf.dosname) == dosnm && filelen == fl) {
				tmp = (dosnm,it,fl) :: tmp;
				break;
			}
		}
		cachelist = tl cachelist;
	}
	cachelist = tmp;
}	

cacheadd(dosname1: array of byte, isthumb, filelen: int)
{
	dosname := sconv(dosname1);
	tmp : list of (string, int,int);
	tmp = nil;
	updated := 0;
	while (cachelist != nil) {
		(dosnm,it,fl) := hd cachelist;
		if (dosname == dosnm && it == isthumb) {
			updated = 1;
			tmp = (dosnm,it,filelen) :: tmp;
		}
		else
			tmp = (dosnm,it,fl) :: tmp;
		cachelist = tl cachelist;
	}
	if (updated == 0)
		tmp = (dosname,isthumb,filelen) :: tmp;
	cachelist = tmp;
}


cachedel(dosname1: array of byte, isthumb: int)
{
	dosname := sconv(dosname1);
	tmp : list of (string, int,int);
	tmp = nil;
	while (cachelist != nil) {
		(dosnm,it,filelen) := hd cachelist;
		if (dosname != dosnm || it != isthumb)
			tmp = (dosnm,it,filelen) :: tmp;
		cachelist = tl cachelist;
	}
	cachelist = tmp;
}

cachesize(dosname1: array of byte, isthumb: int): int
{
	dosname := sconv(dosname1);
	tmp := cachelist;
	while (tmp != nil) {
		(dosnm,it,filelen) := hd tmp;
		if (dosname == dosnm && isthumb == it) return filelen;
		tmp = tl tmp;
	}
	return -1;
}

cachename(dosname: array of byte, isthumb: int): string
{
	name := "/tmp/" + str->tolower(sconv(dosname));
	if (isthumb) name = jpg2bit(name);
	name[len name - 1] = '~';
	return name;
}

poll_and_wait(): int
{
	print("poll and wait\n",7);
	write_n(C.fd, pwl, len pwl);
#	sys->sleep(100);
	if (read_n_to(C.fd, pak, len pak,TIMEOUT) < 0) {
 		print("poll_and_wait: unexpected read failure, exiting...\n",1);
 		return -1;
	}
	return 0;
}

send_packet(): int
{
	# computing packet size
	to_write := C.bufbytes;

	# send the first packet
	pwl[0] = byte ((1<<5)|(1<<4)|(1<<3)|(1<<2)|(to_write>>8));
	pwl[1] = byte (to_write&16rff);

	if (poll_and_wait() != 0)
		return -1;
#	pak[1] == byte 2; ?
	pak[1] = byte 2;

	wrote_here := write_n(C.fd, C.cdp, to_write);
	if (wrote_here != to_write)
		return -1;
	return 0;
}

send_message(): int
{	
	v:= 0;
	rc := chan of int;
	tc := chan of int;

	spawn timer2(tc,6000);
	tpid := <- tc;
	spawn write_message(rc);
	rpid := <- rc;

	try := 0;
	alt {
		<- tc =>
			kill(rpid);
			print("error: write timeout\n",1);
			v = -2;
			break;
		v = <- rc =>
			kill(tpid);
			break;
	}
	return v;
}

write_message(rc: chan of int)
{	
	print("writing msg...\n",6);
	rc <- = sys->pctl(0, nil);	
	if (send_packet() != 0) {
		rc <-= -1;
		return;
	}
	pwl[0] = byte 0;
	pwl[1] = byte 0;
	wrote_here := write_n(C.fd, pwl, 2);
	if (wrote_here != 2) {
		rc <-= -1;
		return;
	}
	rc <-= 0;
	print("written\n",6);
}

extra: adt {
	pnum: int;
	offset: int;
	length: int;
	data: array of byte;
	isthumb: int;
};

ex : extra;

getthumb(photonum, offset, maxlength: int): array of byte
{
	if (offset != 0) return nil;
	print("getting thumbnail\n",3);
	thumbdata: array of byte;
	err, h, w, ttype: int;
	file := filelist[photonum].cf;
	filesize := 13020;
	if (offset > 0) {
		filesize = file.thumblength;
		if (offset >= filesize) return nil;
	}
	for(;;){
		print(sys->sprint("Filesize: %d offset: %d\n",filesize, offset),5);
		if (offset + maxlength > filesize)
			maxlength = filesize - offset;
		l := maxlength;
	
		C.command = cdp_get_file_data;
		C.bufbytes = build_cdp_header(C.cdp, 68);
		off := cdp_header_len;
		off = set_int(C.cdp[off:], file.driveno, off);
		off = set_fstring(C.cdp[off:], file.pathname, off);
		off = set_dosname(C.cdp[off:], file.dosname, off);
		off = set_int(C.cdp[off:], 1, off);
	
		off = set_int(C.cdp[off:], offset, off);
		off = set_int(C.cdp[off:], l, off);
		off = set_int(C.cdp[off:], filesize, off);
	
		print(sys->sprint( "getthumbdata %d %d %d\n", offset, maxlength, filesize),5);
		send_message();
#		sys->sleep(2000);
		if ((err = receive_message()) != 0) {
			print(sys->sprint("Error %d\n", err),1);
			return nil;
		}
		off = cdp_header_len;
		print(sys->sprint( "bufbytes  = %d\n", C.bufbytes),5);
		tmpoffset: int;
		(tmpoffset, off) = get_int(C.cdp[off:], off);
		(l, off) = get_int(C.cdp[off:], off);
		(filesize, off) = get_int(C.cdp[off:], off);
		print(sys->sprint( "getthumbdata returning %d %d %d\n", offset, l, filesize),5);
	
		if (offset == 0) {
			(filesize, off) = get_int(C.cdp[off:off+4], off);
			(h, off) = get_int(C.cdp[off:off+4], off);
			(w, off) = get_int(C.cdp[off:off+4], off);
			(ttype, off) = get_int(C.cdp[off:off+4], off);
			filelist[photonum].cf.thumblength = filesize;
			thumbdata = array[filesize] of byte;
			print(sys->sprint("Thumb (%d,%d) size: %d type: %d\n",w,h,filesize,ttype),5);
		}
		if (offset + l > filesize) l = filesize - offset;
		print(sys->sprint( "Making array of size: %d\n", l),5);
		thumbdata[offset:] = C.cdp[off:off+l];
		offset += l;
		if (offset >= filesize) break;
	}
	return thumb2bit(thumbdata,w,h);
}

getpicture2(photonum, offset, maxlength: int): array of byte
{
	file := filelist[photonum].cf;
	filesize := int file.filelength;
	print("getting image\n",3);
	print(sys->sprint("Filesize: %d offset: %d\n",filesize, offset),5);
	if (offset >= filesize) return nil;
	if (offset + maxlength > filesize)
		maxlength = filesize - offset;
	l := maxlength;
	C.command = cdp_get_file_data;
	C.bufbytes = build_cdp_header(C.cdp, 68);
	off := cdp_header_len;
	off = set_int(C.cdp[off:], file.driveno, off);
	off = set_fstring(C.cdp[off:], file.pathname, off);
	off = set_dosname(C.cdp[off:], file.dosname, off);
	off = set_int(C.cdp[off:], 0, off);

	off = set_int(C.cdp[off:], offset, off);
	off = set_int(C.cdp[off:], l, off);
	off = set_int(C.cdp[off:], filesize, off);

	print(sys->sprint( "getfiledata %d %d %d\n", offset, maxlength, filesize),5);
	send_message();
	if ((err := receive_message()) != 0) {
		print(sys->sprint("Error %d\n", err),1);
		return nil;
	}
	off = cdp_header_len;
	print(sys->sprint( "bufbytes  = %d\n", C.bufbytes),5);
	(offset, off) = get_int(C.cdp[off:], off);
	(l, off) = get_int(C.cdp[off:], off);
	(filesize, off) = get_int(C.cdp[off:], off);
	print(sys->sprint( "getfiledata returning %d %d %d\n", offset, maxlength, filesize),5);
	filedata := array[l] of byte;
	filedata[0:] = C.cdp[off:off+l];
	return filedata;
}

erase_file(file: Cfile): int
{
	C.command = cdp_erase_file;
	C.bufbytes = build_cdp_header(C.cdp, 52);
	
	off := cdp_header_len;
	off = set_int(C.cdp[off:], file.driveno, off);
	off = set_fstring(C.cdp[off:], file.pathname, off);
	off = set_dosname(C.cdp[off:], file.dosname, off);
	send_message();
#	sys->sleep(1000);
	if (receive_message() != 0)
		return -1;
	return 0;
}


set_power_mode(): int
{
	C.command = cdp_set_power_mode;
	C.bufbytes = build_cdp_header(C.cdp, 0);
	return (send_message());
}

get_storage_status(): string
{
	s := "";

	C.command = cdp_get_storage_status;
	C.bufbytes = build_cdp_header(C.cdp, 0);
	send_message();
#	sys->sleep(2000);
	if (receive_message() != 0) return "";
	off := cdp_header_len;
	taken, available, raw : int;
	(taken, off) = get_int(C.cdp[off:], off);
	(available, off) = get_int(C.cdp[off:], off);
	(raw, off) = get_int(C.cdp[off:], off);
	s += sys->sprint("Picture Memory\n\tused:\t%d\n\tfree:\t%d",taken,available);
	if (raw == -1)
		s += "\n";
	else
		s += sys->sprint(" (compressed)\n\t\t%d (raw)\n",raw);

	return s;
}

get_power_mode(): string
{
	mode: int;

	C.command = cdp_get_power_mode;
	C.bufbytes = build_cdp_header(C.cdp, 0);
	send_message();
#	sys->sleep(2000);
	if (receive_message() != 0) return "Could not read power mode";
	off := cdp_header_len;
	(mode, off) = get_int(C.cdp[off:], off);
	return sys->sprint("Power Mode = %d\n", mode);
}

set_clock_data(s:string): int
{
	err := 0;
	if (s == "") {
		tm := daytime->local(daytime->now());
		off := cdp_header_len;
		C.cdp[cdp_header_len+0] = byte 0;
		C.cdp[cdp_header_len+1] = byte int2hex(tm.mon+1);
		C.cdp[cdp_header_len+2] = byte int2hex(tm.mday);
		C.cdp[cdp_header_len+3] = byte int2hex(tm.year);
		C.cdp[cdp_header_len+4] = byte 0;
		C.cdp[cdp_header_len+5] = byte int2hex(tm.hour);
		C.cdp[cdp_header_len+6] = byte int2hex(tm.min);
		C.cdp[cdp_header_len+7] = byte int2hex(tm.sec);
	}
	else {
		(n,datetime) := sys->tokenize(s," ");
		if (n != 2) return 1;
		off := 0;
		for (i := 0; i < 2; i++) {
			(n2,data) := sys->tokenize(hd datetime, "./:");
			if (n2 != 3) return 1;
			off++;
			for (i2 := 0; i2 < 3; i2++) {
				C.cdp[cdp_header_len+off] = byte int2hex(int hd data);
				off++;
				data = tl data;
			}
			datetime = tl datetime;
		}
	}
	return 0;
}

set_clock(s:string): int
{
	C.command = cdp_set_clock;
	C.bufbytes = build_cdp_header(C.cdp, 8);
	if (set_clock_data(s)) return 1;
	send_message();
	if (receive_message() != 0) return 1;
	return 0;
}

addzeros(s: string): string
{
	s[len s] = ' ';
	rs := "";
	start := 0;
	isnum := 0;
	for (i := 0; i < len s; i++) {
		if (s[i] < '0' || s[i] > '9') {
			if (isnum && i - start < 2) rs[len rs] = '0';
			rs += s[start:i+1];
			start = i+1;
			isnum = 0;
		}
		else isnum = 1;
	}
	i = len rs - 1;
	while (i >= 0 && rs[i] == ' ') i--;
	return rs[:i+1];
}	

get_clock(): string
{
	C.command = cdp_get_clock;
	C.bufbytes = build_cdp_header(C.cdp, 0);
	send_message();
	if (receive_message() != 0)
		return "Could not read clock\n";
	s := sys->sprint("%x/%x/%x %x:%x:%x", int C.cdp[13],int C.cdp[14],
		int C.cdp[15], int C.cdp[17], int C.cdp[18], int C.cdp[19]);
	return "date is "+addzeros(s)+"\n";
}

get_file_list(): int
{
	getoldfiledata();
	print("getting file list\n",3);
	C.command = cdp_get_file_list;
	C.bufbytes = build_cdp_header(C.cdp, 56);
	setfiledata();
	send_message();
	if (receive_message() != 0)
		return -1;
	display_filelist();
	return 0;
}

setfiledata()
{
	off := cdp_header_len;
	off = set_int(C.cdp[off:], 1, off);						# ascending order
	off = set_int(C.cdp[off:], 1, off);						# drive a: internal RAM disk
	off = set_fstring(C.cdp[off:], array of byte "", off);		# set pathname to null
	off = set_dosname(C.cdp[off:], array of byte "", off);		# set Dos filename to null 
}

get_file_size(i: int): int
{
	C.command = cdp_get_file_list;
	C.bufbytes = build_cdp_header(C.cdp, 56);
	setfiledata2(i);
	send_message();
	if (receive_message() != 0) return -1;
	display_filelist();
	return 0;
}

setfiledata2(i: int)
{
	off := cdp_header_len;
	off = set_int(C.cdp[off:], 1, off);						# ascending order
	off = set_int(C.cdp[off:], 1, off);						# drive a: internal RAM disk
	off = set_fstring(C.cdp[off:], filelist[i].cf.pathname, off);	# set pathname
	off = set_dosname(C.cdp[off:], filelist[i].cf.dosname, off);	# set Dos filename
}

set_interface_timeout()
{
	print("Setting Interface timeout\n",3);
	C.command = cdp_set_interface_timeout;
	C.bufbytes = build_cdp_header(C.cdp, 8);
	off := cdp_header_len;
	off = set_int(C.cdp[off:], 100, off);
	off = set_int(C.cdp[off:], 5, off);
	send_message();
#	sys->sleep(1000);
	receive_message();
}

display_filelist(): string
{
	off, i: int;

	off = cdp_header_len;
	(reslength, off) = get_int(C.cdp[off:], off);
	s := sys->sprint("Number of entries: %d\n", reslength);
	for (i = 0; i < reslength; i++) {
		(filelist[i].cf.driveno, off) = get_int(C.cdp[off:], off);
		(filelist[i].cf.pathname, off) = get_fstring(C.cdp[off:], off);
		(filelist[i].cf.dosname, off) = get_dosname(C.cdp[off:], off);
		(filelist[i].cf.filelength, off) = get_int(C.cdp[off:], off);
		(filelist[i].cf.filestatus, off) = get_int(C.cdp[off:], off);
		if (filelist[i].cf.filelength < 0 || filelist[i].cf.filelength > MAXFILESIZE)
			filelist[i].cf.filelength = 0;
		s += sys->sprint("\t%d, %s, %s, %d\n", filelist[i].cf.driveno,
				string filelist[i].cf.pathname,
				string filelist[i].cf.dosname,
				filelist[i].cf.filelength);
	}
	print(s,5);
	if (usecache)
		cacheclean();
	return s;
}

get_camera_capabilities(): string
{
	print("Get capabilities\n",3);
	C.command = cdp_get_camera_capabilities;
	C.bufbytes = build_cdp_header(C.cdp, 0);
	send_message();
#	sys->sleep(500);
	if (receive_message() != -1)
		return capabilities();
	print("Error recieving abilities message\n",1);
	return "";
}

Capability: adt {
	pname: string;
	d: string;
	pick {
		List =>
			t: list of (string, int);
		Range =>
			min, max, default, current: int;
		}
};

caplist: list of ref Capability;

print_camera_capabilities(): string
{
	rs := "";
#	p : ref Capability;

	pick p := hd caplist{
	List =>
		rs += sys->sprint("Pname = %s ", p.pname);
	Range =>
		rs += sys->sprint("Pname = %s  min = %d  max = %d  default = %d ", p.pname, 
				p.min, p.max, p.default);
	}
#	p := tl p;
	return rs;
}

capabilities(): string
{
	off, i, ncaps, t: int;
	l, m, n: int;
	pname, desc: array of byte;
	s: array of byte;
	rs := "";
	off = cdp_header_len;
	(ncaps, off) = get_int(C.cdp[off:], off);
	if (ncaps > 200)
		return "error reading capabilities\n";
	rs += sys->sprint("i = %d\n", i);
	firsttime := 0;
	if (ignoreabls == nil)
		firsttime = 1;
	for (j := 0; j < ncaps; j++) {
		line := "";
		(pname, off) = get_pname(C.cdp[off:], off);
		line += sys->sprint("%s,  ", string pname);
		(t, off) = get_int(C.cdp[off:], off);
		(desc, off) = get_fstring(C.cdp[off:], off);
		line += sys->sprint("%s:  ", string desc);
		fact := "";
		case t {
			1 =>
				t: list of (string, int);

				(l, off) = get_int(C.cdp[off:], off);
				(m, off) = get_int(C.cdp[off:], off);
				line += sys->sprint("items: %d  factory: %d\n", l, m);

				for (k := 0; k < l; k++) {
					(s, off) = get_fstring(C.cdp[off:], off);
					(n, off) = get_int(C.cdp[off:], off);
					line += sys->sprint("		%s: %d\n", string s, n);
					if (m == n)
						fact = sconv(s);
					t = (sconv(s), n) :: t;
				}
				cl := ref Capability.List (sconv(pname), sconv(desc), t);
			2 =>
				(l, off) = get_int(C.cdp[off:], off);
				(m, off) = get_int(C.cdp[off:], off);
				(n, off) = get_int(C.cdp[off:], off);
				line += sys->sprint("min: %d   max: %d   factory:%d\n", l, m, n);
				fact = string n;
			3 =>
				(l, off) = get_int(C.cdp[off:], off);
				case l {
					7 =>
						(s, off) = get_dosname(C.cdp[off:], off);
					8 =>
						(s, off) = get_fstring(C.cdp[off:], off);
					* =>
						line += sys->sprint("Invalid type %d\n", l);
						break;
				}
				fact = string s;
				line += sys->sprint("%s\n", string s);
			4 to 8 =>
				break;
			9 =>
				break;
			* =>
				line += sys->sprint("Invalid type %d\n", t);
				break;
		}
		if (firsttime) {
			if (!filterabls(sconv(pname), string desc))
				defattr = (sconv(pname), int fact) :: defattr;
		}
		if (!isin(ignoreabls, string pname))
			rs += line;
	}
	if (firsttime) {
		defaultattr = array[len defattr] of (string, int);
		currentattr = array[len defattr] of (string, int);
		i = 0;
		for (;defattr != nil; defattr = tl defattr) {
			defaultattr[i] = hd defattr;
			currentattr[i++] = hd defattr;
		}
	}
	return rs;
}

isin(los: list of string, s: string): int
{
	for (;los !=nil; los = tl los)
		if (hd los == s)
			return 1;
	return 0;
}

set_capture_data(): int
{
	C.cdp[cdp_header_len+0] = byte 0;
	C.cdp[cdp_header_len+1] = byte 0;
	C.cdp[cdp_header_len+2] = byte 0;
	C.cdp[cdp_header_len+3] = byte 0;
	return 4;
}

get_camera_state(pname: string,offset: int): string
{
	if (offset != 0) return "";
	print(sys->sprint( "get_camera_state(%s)\n", pname),3);
	C.command = cdp_get_camera_state;
	off := cdp_header_len;
	if (pname == "")
		C.bufbytes = build_cdp_header(C.cdp, 0);
	else {
		if (len pname != 4)
			return "Invalid command name: "+pname+"\n";
		C.cdp[off+0] = byte pname[0];
		C.cdp[off+1] = byte pname[1];
		C.cdp[off+2] = byte pname[2];
		C.cdp[off+3] = byte pname[3];
		C.bufbytes = build_cdp_header(C.cdp, 4);
	}
	send_message();
	if (receive_message() != 0) return "Could not read state: "+pname+"\n";
	off = cdp_header_len;
	rlen: int;
	(rlen, off) = get_int(C.cdp[off:],off);
	s := "";
	rlen = 1;
	if (pname == "") {
		for (q := off; q < len C.cdp; q++) {
			s[0] = int C.cdp[q];
			if (s[0] > 0) print(sys->sprint("%s",s),5);
		}
		print("\n",5);
	}
	for (i := 0; i < rlen; i++) {
		name, data: array of byte;
		type1, tmp: int;
		(name,off) = get_pname(C.cdp[off:],off);
		(type1,off) = get_int(C.cdp[off:],off);
		print(sys->sprint( "%d: %s - %d\n", i,pname,type1),5);
		case type1 {
			1 to 5 =>
				(tmp,off) = get_int(C.cdp[off:],off);
				data = array of byte string tmp;
			6 =>
				(data,off) = get_pname(C.cdp[off:],off);
			7 =>
				(data,off) = get_dosname(C.cdp[off:],off);
			8 =>
				(data,off) = get_fstring(C.cdp[off:],off);
			* =>
				data = array of byte "!ERROR!";
		}
		# if (string data == "!ERROR!") return "";
#		if (rlen == 1)
#			s = string data;
#		else s += sys->sprint("%s: %s\n",string name, string data);
		s += sys->sprint("%s: %s\n",string name, string data);
	}
	return s;
}


set_camera_state(pname: string, val: int): string
{
	print(sys->sprint( "set_camera_state(%s, %d)\n", pname, val),3);
	if (len pname != 4)
		return "Command name must be 4 characters";
	off := cdp_header_len;
	C.cdp[off+0] = byte pname[0];
	C.cdp[off+1] = byte pname[1];
	C.cdp[off+2] = byte pname[2];
	C.cdp[off+3] = byte pname[3];
	off += 4;
	off = set_int(C.cdp[off:], val, off);

	C.command = cdp_set_camera_state;
	C.bufbytes = build_cdp_header(C.cdp, 8);
	send_message();
#	sys->sleep(1000);
	if ((e := receive_message()) == 0) {
		na := getattr(pname);
		if (na != -1)
			currentattr[na].t1 =  val;
		return nil;
	}
	else
		return error_table[e];
}

capture(): int
{
	C.command = cdp_get_camera_status;
	C.bufbytes = build_cdp_header(C.cdp, 0);
	send_message();
#	sys->sleep(1000);
	if (receive_message() != 0)
		return -1;

	d := set_capture_data();
	C.command = cdp_start_capture;
	C.bufbytes = build_cdp_header(C.cdp, d);
	send_message();
#	sys->sleep(3000);
	return receive_message();
}

dump_message()
{
	print(sys->sprint("	Message length = %d\n", C.bufbytes),5);
	print(sys->sprint("	CDP Length = %d\n", (int C.cdp[2]<<8)+(int C.cdp[3])),5);
	print(sys->sprint("	CDP Version = %d\n", int C.cdp[4]),5);
	print(sys->sprint("	CDP Command = %x\n", int ((C.cdp[8]<<8)|(C.cdp[9]))),5);
	print(sys->sprint("	CDP Result Code = %d\n", int ((C.cdp[10]<<8)|(C.cdp[11]))),5);
}

build_cdp_header(cdp: array of byte, x: int): int
{
	cdp[4] = byte 0;
	cdp[5] = byte 0;
	cdp[6] = byte 0;
	cdp[7] = byte 0;
	cdp[8] = byte ((C.command>>8)&16rff);
	cdp[9] = byte (C.command&16rff);
	cdp[10] = byte 0;
	cdp[11] = byte 0;

	l := 8 + x;
	cdp[0] = byte ((l>>24)&16rff);
	cdp[1] = byte ((l>>16)&16rff);
	cdp[2] = byte ((l>>8)&16rff);
	cdp[3] = byte (l&16rff);

	return 12+x;
}

poll_and_reply(nak: int): int
{
	print("poll and reply\n",7);
	if ((read_n_to(C.fd, pwl, len pwl,TIMEOUT) < 0) && nak) {
		pak[0] = byte 0;	
		pak[1] = byte 2;		# reject
		write_n(C.fd, pak, len pak);
		return 0;
	}
	pak[0] = byte 0;
	pak[1] = byte 1;
	write_n(C.fd, pak, len pak);

	return 1;
}

receive_packet(buf: array of byte): int
{
	print("receive_packet\n",6);
	if (!poll_and_reply(!0)) {
		print("Poll and reply failed\n",1);
		return -1;
	}

	l := int (((int pwl[0]&3)<<8)|(int pwl[1]));
	C.bufbytes += l;
	r := read_n_to(C.fd, buf, l,TIMEOUT);
	if (r != l) {
		print(sys->sprint( "could not read packet (read %d, expected %d)\n", r, l),1);
		return -1;
	}
	return 0;
}

receive_message(): int
{
	print("read_message\n",6);
	C.bufbytes = 0;
	if (receive_packet(C.cdp[0:]) != 0) {
		recon = 1;
		print("receive packet failed\n",1);
		return 3;
		# raise "error: receive packet failed";
	}
	dump_message();	
	rc := int C.cdp[9];
	if ((~rc&16rff) != (C.command&16rff)) {
		print("command & return are different\n",1);
		consume(C.fd);
		return 3;
		# raise "error: command and return command are not the same\n";
	}
	message_len := (int C.cdp[2]<<8)+(int C.cdp[3]);

	while (C.bufbytes < message_len) {
		if (receive_packet(C.cdp[C.bufbytes:]) != 0) {
			print("Packet is too short\n",1);
			recon = 1;
			return 3;
			# raise "error: receive packet2 failed";
		}
	}
#	sys->sleep(500);
	read_n_to(C.fd, pak, len pak, TIMEOUT);
	return  (int ((C.cdp[10]<<8)|(C.cdp[11])));  # result code
}

reset(fd: ref Sys->FD)
{
	sys->fprint(fd, "d1");
	sys->sleep(20);
	sys->fprint(fd, "d0");
	sys->fprint(fd, "b9600");
}

kill(pid: int)
{	
	pctl := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE);
	if (pctl != nil)
		sys->write(pctl, array of byte "kill", len "kill");
}

killg(pid: int)
{
	if ((fd := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE)) != nil)
		sys->fprint(fd, "killgrp");
}

#dump_buf(buf: array of byte, i: int)
#{
#	for (j := 0; j < i; j++)
#		sys->fprint(sys->fildes(2), "%x ", int buf[j]);
#	sys->fprint(sys->fildes(2), "\n");
#}

serialport(port : int) : (ref Sys->FD, ref Sys->FD, string)
{
	C.fd = nil;
	C.ctlfd = nil;
	C.mode = BEACON;

	serport := "/dev/eia" + string port;
	serctl := serport + "ctl";

	for (i := 0; i < len statopt; i++) {
		statfd := sys->open("/dev/eia"+string port+statopt[i],sys->OREAD);
		if (statfd != nil)
			C.stat = i;
		statfd = nil;
	}
	readstat();	

	fd := sys->open(serport, Sys->ORDWR);
	if (fd == nil)
		return (nil, nil, sys->sprint("cannot read %s: %r", serport));
	ctlfd := sys->open(serctl, Sys->OWRITE);
	if (ctlfd == nil)
		return (nil, nil, sys->sprint("cannot open %s: %r", serctl));

	config := array [] of {
		"b9600",
		"l8",
		"p0",
		"m0",
		"s1",
		"r1",
		"i1",
		"f",
	};

	for (i = 0; i < len config; i++) {
		if (sys->fprint(ctlfd,"%s", config[i]) < 0)
			print(sys->sprint("serial config (%s): %r\n", config[i]),3);
	}
	sys->sleep(100);
	consume(fd);
	sys->fprint(ctlfd, "d1");
	sys->sleep(40);
	sys->fprint(ctlfd, "d0");
	return (fd, ctlfd, nil);
}

consume(fd: ref sys->FD)
{
	if (fd != nil) {
		print("Consuming...\n",6);
		read_n_to(fd, array[1000] of byte, 1000, 1000);
	}
}

beacon_intro(data: chan of array of byte, pchan: chan of int, fd: ref Sys->FD)
{
	buf := array[64] of byte;
	cbuf: array of byte;
	pid := sys->pctl(0, nil);
#	print(sys->sprint("b_intro: starting %d\n",pid);
	pchan <-= pid;
	failed := array[len bintro] of { * => byte 0 };
	# discard characters until lead in character reached
	print(sys->sprint("\tWaiting for: %d...\n",int bintro[0]),3);
	do {
		n := read_n_to(fd, buf, 1, TIMEOUT);
		if (n == -1) {
			data <- = failed;
			return;
		}
		print(sys->sprint("\tGot: %d\n",int buf[0]),5);
	} while (buf[0] != bintro[0]);
	print("Getting beacon\n",3);
	# read the next 6 bytes of beacon
	i := read_n_to(fd, buf[1:], 6,TIMEOUT);
	for (k := 0; k < i; k++) 
		print(sys->sprint("\tRead %d: %d (wanted %d)\n",k+1, int buf[1+k], int bintro[1+k]),5);
	if (i != 6) {
		print("Error reading beacon\n",3);
		exit;
	}
	else {
		print("sending beacon\n",3);
		cbuf = buf[0:7];
		data <- = cbuf;	
	}

}

beacon_result(data: chan of array of byte, pchan: chan of int, fd: ref Sys->FD)
{
	buf := array[64] of byte;
	cbuf: array of byte;
	pid := sys->pctl(0, nil);
	pchan <-= pid;

	# read the next 10 bytes of beacon
	p := 0;
	intro := 1;
	for (;;) {
		i := read_n_to(fd, buf[p:], 1, TIMEOUT);
		if (intro) {
			if (buf[p] != bintro[p]) {
				intro = 0;
				buf[0] = buf[p];
				p = 1;
			}
			else {
				p++;
				if (p >= len bintro) p = 0;
			}
		}
		else p++;
		if (p == 10) break;
	}
			
	for (k := 0; k < p; k++) print(sys->sprint("\tRead %d: %d\n",k, int buf[k]),5);
	if (p != 10) {
		print("Error reading beacon result\n",3);
		exit;
	}
	else {
		print("reading beacon result\n",3);
		cbuf = buf[0:10];
		data <- = cbuf;	
	}
}

beacon_comp(buf: array of byte, C: Camera_adt): int
{
	speed: string;

	case int buf[0] {
		0 =>
			C.baud = (int buf[2]<<24)|(int buf[3]<<16)|(int buf[4]<<8)|(int buf[5]);
			C.dfs = (int buf[6]<<8)|(int buf[7]);
			C.hfs = (int buf[8]<<8)|(int buf[9]);
			# do baud rate change here
			sys->sleep(1000);

			case C.baud {
				115200 =>
					speed = "b115200";
				57600 =>
					speed = "b57600";
				38400 =>
					speed = "b38400";
				19200 =>
					speed = "b19200";
				* =>
					speed = "b9600";
			}
			print(sys->sprint("Connection Details:\n  Baud rate:\t%dbps\n",C.baud),3);
			print(sys->sprint("  Host frame size:\t%dbytes\n",C.hfs),3);
			print(sys->sprint("  Device frame size:\t%dbytes\n",C.dfs),3);
			if (sys->fprint(C.ctlfd,"%s", speed) < 0) {
				print(sys->sprint("Error setting baud rate %s\n", speed),3);
				return -1;
			}
		-1 =>
			print("Incompatible Data Rate\n",1);
			return -1;
		-2 =>
			print("Device does not support these modes\n",1);
			return -2;
		* =>
			print(sys->sprint("I'm here!? buf[0] = %d\n",int buf[0]),1);
			return -1;
	}
	return 0;
}

read_n(fd: ref Sys->FD, buf: array of byte, n: int, res: chan of int)
{
	pid := sys->pctl(0, nil);
#	print(sys->sprint("read_n: starting %d\n",pid);
	res <-= pid;
	print(sys->sprint( "read_n %d\n", n),7);
	nread := 0;
	while (nread < n) {
		i := sys->read(fd, buf[nread:], n-nread);
		sys->sleep(1);
		if (i <= 0) 
			break;
		nread += i;
	}
	res <-= nread;
#	print(sys->sprint("read_n: ending %d\n",pid);
}

read_n2(fd: ref Sys->FD, buf: array of byte, n: int): int
{
	print(sys->sprint( "read_n2 %d\n", n),7);
	nread := 0;
	while (nread < n) {
		i := sys->read(fd, buf[nread:], n-nread);
		sys->sleep(1);
		if (i <= 0) 
			break;
		nread += i;
	}
	return nread;
}

read_n_to(fd: ref Sys->FD, buf: array of byte, n,t : int): int
{	
	v:= 0;
	rc := chan of int;
	tc := chan of int;

	spawn timer2(tc,t);
	tpid := <- tc;
	spawn read_n(fd, buf, n, rc);
	rpid := <- rc;

	try := 0;
	alt {
		<- tc =>
			kill(rpid);
			print(sys->sprint( "error: read_n timeout\n"),1);
			recon = 1;
			return -1;
		v = <- rc =>
			kill(tpid);
			break;
	}
	return v;
}

write_n(fd: ref Sys->FD, buf: array of byte, n: int): int
{
	print(sys->sprint("write_n %d\n", n),7);
	nwrite := 0;
	while (nwrite < n) {
		i := sys->write(fd, buf[nwrite:], n-nwrite);
		sys->sleep(1);
		if (i <= 0) {
			print(sys->sprint("Error returned by write: %r\n"),1);
			readstat();
#			recon = 1;
			return nwrite;
		}
		nwrite += i;
	}
	print(sys->sprint("write_n returning %d\n", nwrite),7);
	return nwrite;	
}

readstat()
{
	consume(C.fd);
	print("Serial status: ",5);
	statfd := sys->open("/dev/eia"+string C.port_num+statopt[C.stat], sys->OREAD);
	buf := array[100] of byte;
	if (statfd != nil) {
		for (;;) {
			k := sys->read(statfd,buf,len buf);
			if (k > 0) print(string buf[:k],2);
			else break;
		}
		print("\n",2);
	}
	else print("cannot read serial status\n",1);
}

beacon_ack(C: Camera_adt)
{
	# set speed
	i := C.baud;
	bak[4] = byte ((i>>24)&16rff);
	bak[5] = byte ((i>>16)&16rff);
	bak[6] = byte ((i>>8)&16rff);
	bak[7] = byte (i&16rff);

	# set frame size to device
	i = C.dfs;
	bak[8] = byte ((i>>8)&16rff);
	bak[9] = byte (i&16rff);

	# set frame size to host
	i = C.hfs;
	bak[10] = byte ((i>>8)&16rff);
	bak[11] = byte (i&16rff);
	bak[12] = check_sum(bak, 12);

	if (write_n(C.fd, bak, len bak) != len bak) {
		print("Error writing beacon acknowledgement\n",3);
		exit;
	}
	print("beacon acknowledgement written\n",3);
}

# timer thread send tick <- = 0 to kill

timer2(tick: chan of int, delay: int)
{
	pid := sys->pctl(0, nil);
	tick <-= pid;
	sys->sleep(delay);
	tick <- = TOUT;
}

beacon_ok(buf: array of byte): int
{

	for (i := 0; i < len bintro; i++) {
		if (buf[i] != bintro[i]) {
			print(sys->sprint("Beacon failed on byte %d: %d (wanted %d)\n",i,int buf[i],int bintro[i]),3);
			return 0;
		}
	}
	print("Beacon passed\n",3);
	return 1;
}

check_sum(buf: array of byte, l: int): byte
{
	sum := 0;
 	for (i := 0; i < l; i++) 
		sum += int buf[i];
  	return byte (sum&16rff);
}


set_int(b: array of byte, i, off: int): int
{
	b[0] = byte (i>>24&16rff);
	b[1] = byte (i>>16&16rff);
	b[2] = byte (i>>8&16rff);
	b[3] = byte (i&16rff);

	return (off+4);
}

set_fstring(b: array of byte, s: array of byte, off: int): int
{
	for (i := 0; i < 32; i++)
		b[i] = byte 0;
	for (i = 0; i < len s; i++)
		b[i] = s[i];
	return (off+32);
}

set_dosname(b: array of byte, s: array of byte, off: int): int
{
	for (i := 0; i < 16; i++)
		b[i] = byte 0;
	for (i = 0; i < len s; i++)
		b[i] = s[i];
	return (off+16);
}

get_tag(b: array of byte, off: int): (int, Partialtag)
{
	tag: Partialtag;
	(off, tag.offset) = get_int(b, off);
	(off, tag.length) = get_int(b, off);
	(off, tag.filesize) = get_int(b, off);
	return (off, tag);
}

get_int(b: array of byte, off: int): (int, int)
{
	return (get_int2(b), off+4);
}

get_int2(b: array of byte): int
{
	i := (int b[0]<<24)|(int b[1]<<16)|(int b[2]<<8)|(int b[3]);
	return i;
}


get_pname(b: array of byte, off: int): (array of byte, int)
{
	return get_string(b, off, 4);
}

get_dosname(b: array of byte, off: int): (array of byte, int)
{
	return get_string(b, off, 16);
}

get_string(b: array of byte, off: int, l: int): (array of byte, int)
{
	s := array[l] of byte;
	s[0:] = b[0:l];
	return (s, off+l);
}

get_fstring(b: array of byte, off: int): (array of byte, int)
{
	return get_string(b, off, 32);
}

sconv(b: array of byte): string
{
	s := string b;
	i := len s-1;
	while (i >= 0 && s[i] == 0)
		i--;
	return s[0:i+1];
}

name2dos(s: string): array of byte
{
	return array of byte str->toupper(s);
}

getqid(i, ftype: int): int
{
	qid := (i<<4) + ftype;
	return qid;
}

gettype(qid: int): int
{
	ftype := qid & 15;
	return ftype;
}

cutdir(ab:array of byte): string
{
	s := sconv(ab);
	for (i := 0; i < len s-1; i++)
		if (s[i] == '/')
			return s[i+1:len s - 1];
	return "";
}

convert_thumb(w,h: int, data: array of byte): array of byte
{
	rgb := array[w * h * 3] of byte;
	index := 0;
	rgbi := 0;
	for (i := 0; i < (w * h) / 2; i++) {

		cb := real data[index];
		y := real data[index+1];
		cr := real data[index+2];

		rb := conv(y + (1.77200 * (cb - 128.0)));
		gb := conv(y - (0.34414 * (cb - 128.0)) - (0.71414 * (cr - 128.0)));
		bb := conv(y + (1.4020 * (cr - 128.0)));

		for (loop := 0; loop < 2; loop++) {
			rgb[rgbi++] = rb;
			rgb[rgbi++] = gb;
			rgb[rgbi++] = bb;
		}
		index += 4;
	}
	return rgb;
}

conv(a: real): byte
{
	r := int a;
	if (r < 0) r = -r;
	if (r > 255) r = 255;
	return byte r;
}

thumb2bit(buf: array of byte, w,h: int):  array of byte
{
	convbuf := convert_thumb(w,h,buf);
	# assume thumbs are small so we wont gain much by compressing them
	bitarray := array [60+len convbuf] of byte;
	# assume chans = RGB24
	bitarray[:] = array of byte sys->sprint("%11s %11d %11d %11d %11d ", "r8g8b8", 0, 0, w, h);
	bitarray[60:] = convbuf;
	return bitarray;
}

jpg2bit(s: string): string
{
	if (len s < 4) return s;
	if (s[len s - 4:] != ".jpg") return s;
	return s[:len s - 4]+".bit";
}

oldfiles : list of (string, int, int);

getoldfiledata()
{
	oldfiles = nil;
	for(i := 0; i < reslength; i++)
		oldfiles = (str->tolower(sconv(filelist[i].cf.dosname)),
				int filelist[i].qid.path,
				filelist[i].cf.thumbqid) :: oldfiles;
}

updatetree(tree: ref Nametree->Tree)
{
	for (i := 0; i < reslength; i++) {
		name := str->tolower(sconv(filelist[i].cf.dosname));
		found := 0;
		tmp : list of (string, int, int) = nil;
		for (; oldfiles != nil; oldfiles = tl oldfiles) {
			(oldname, oldqid, oldthumbqid) := hd oldfiles;
			# sys->print("'%s' == '%s'?\n",name,oldname);
			if (name == oldname) {
				found = 1;	
				filelist[i].qid = (big oldqid, 0, sys->QTFILE);
				filelist[i].cf.thumbqid = oldthumbqid;
			}
			else
				tmp = hd oldfiles :: tmp;
		}
		oldfiles = tmp;
		# sys->print("len oldfiles: %d\n",len oldfiles);
		if (found)
			updateintree(tree, name, i);
		else
			addtotree(tree, name, i);
		
	}
	for (; oldfiles != nil; oldfiles = tl oldfiles) {
		(oldname, oldqid, oldthumbqid) := hd oldfiles;
		# sys->print("remove from tree: %s\n",oldname);
		tree.remove(big oldqid);
		tree.remove(big oldthumbqid);
	}
}

updateintree(tree: ref Nametree->Tree, name: string, i: int)
{
	# sys->print("update tree: %s\n",name);
	tree.wstat(filelist[i].qid.path, 
			dir(name, 
				8r444,
				filelist[i].cf.filelength,
				int filelist[i].qid.path));
	tree.wstat(big filelist[i].cf.thumbqid,
			dir(jpg2bit(name),
				8r444,
				13020,
				filelist[i].cf.thumbqid));
}

addtotree(tree: ref Nametree->Tree, name: string, i: int)
{
	# sys->print("addtotree: %s\n",name);
	nextjpgqid += 1<<4;
	filelist[i].qid = (big nextjpgqid, 0, sys->QTFILE);
	parentqid := Qjpgdir;
	tree.create(big parentqid,
				dir(name,
				8r444,
				filelist[i].cf.filelength,
				nextjpgqid));

	nexttmbqid += 1<<4;
	filelist[i].cf.thumbqid = nexttmbqid;
	tree.create(big Qthumbdir,
			dir(jpg2bit(name),
			8r444,
			13020,
			nexttmbqid));
}

keepalive(alivechan: chan of int)
{	
	alivechan <-= sys->pctl(0,nil);
	for (;;) {
		sys->sleep(300000);
		now := daytime->now();
		print(sys->sprint("Alive: %d idle seconds\n",now-wait),6);
		if (now < wait)
			wait = now - 300;
		if (now - wait >= 300)
			alivechan <-= 1;
	}
}

reconnect(n: int): int
{
	attempt := 0;
	connected = 0;
	delay := 100;
	to5 := 0;
	for (;;) {
		print(sys->sprint( "Attempting to reconnect (attempt %d)\n",++attempt),2);
		sys->sleep(100);
		(C.fd, C.ctlfd, nil) = serialport(C.port_num);
		if (C.fd == nil || C.ctlfd == nil)
			print(sys->sprint("Could not open serial port\n"),3);
		else if (connect() == 0) {
			set_interface_timeout();
			connected = 1;
			print("Reconnected!\n",2);
			break;
		}
		if (n != -1 && attempt >= n)
			break;
		if (++to5 >= 5) {
			delay  *= 2;
			to5 = 0;
			if (delay > 600000)
				delay = 600000;
		}
		sys->sleep(delay);
	}
	recon = 0;
	return connected;
}

# 1: errors
# 2: connection
# 3: main procs

print(s: string, v: int)
{
	if (s != nil && s[len s - 1] == '\n')
		s = s[:len s - 1];
	if (v <= verbosity)
		sys->fprint(sys->fildes(2), "%s (%s)\n",s,camname);
}

readinterface(qid : int, offset: big, size: int): (ref sys->Dir, array of byte)
{
	i := qid >> 4;
	buf := array[size] of byte;
	fd := sys->open(interfacepaths[i], sys->OREAD);
	if (fd == nil)
		return (nil,nil);
	(n, dir) := sys->fstat(fd);
	if (offset >= dir.length)
		return (nil,nil);
	sys->seek(fd, offset, sys->SEEKSTART);
	i = sys->read(fd,buf,size);
	return (ref dir, buf[:i]);
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
