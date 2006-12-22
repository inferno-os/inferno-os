implement PPPlink;

#
# Copyright © 2001 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "arg.m";

include "cfgfile.m";
	cfg: CfgFile;
	ConfigFile: import cfg;

include "lock.m";
include "modem.m";
include "script.m";

include "sh.m";

include "translate.m";
	translate: Translate;
	Dict: import translate;
	dict: ref Dict;

PPPlink: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

PPPInfo: adt {
	ipaddr:		string;
	ipmask:		string;
	peeraddr:		string;
	maxmtu:		string;
	username:	string;
	password:		string;
};

modeminfo: ref Modem->ModemInfo;
context: ref Draw->Context;
pppinfo: ref PPPInfo;
scriptinfo: ref Script->ScriptInfo;
isp_number: string;
lastCdir:		ref Sys->Dir;	# state of file when last read
netdir := "/net";

Packet: adt {
	src:	array of byte;
	dst:	array of byte;
	data:	array of byte;
};

DEFAULT_ISP_DB_PATH:	con "/services/ppp/isp.cfg";	# contains pppinfo & scriptinfo
DEFAULT_MODEM_DB_PATH:	con	"/services/ppp/modem.cfg";			# contains modeminfo
MODEM_DB_PATH:	con	"modem.cfg";			# contains modeminfo
ISP_DB_PATH:	con "isp.cfg";		# contains pppinfo & scriptinfo

primary := 0;
framing := 1;

Disconnected, Modeminit, Dialling, Modemup, Scriptstart, Scriptdone, Startingppp, Startedppp, Login, Linkup: con iota;
Error: con -1;

Ignorems: con 10*1000;	# time to ignore outgoing packets between dial attempts

statustext := array[] of {
Disconnected => "Disconnected",
Modeminit =>	"Initializing Modem",
Dialling =>	"Dialling Service Provider",
Modemup =>	"Logging Into Network",
Scriptstart =>	"Executing Login Script",
Scriptdone =>	"Script Execution Complete",
Startingppp =>	"Logging Into Network",
Startedppp => "Logging Into Network",
Login =>	"Verifying Password",
Linkup =>	"Connected",
};

usage()
{
	sys->fprint(sys->fildes(2), "usage: ppplink [-P] [-f] [-m mtu] [local [remote]]\n");
	raise "fail:usage";
}

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	translate = load Translate Translate->PATH;
	if(translate != nil) {
		translate->init();
		dictname := translate->mkdictname("", "pppclient");
		(dict, nil) = translate->opendict(dictname);
	}
	mtu := 1450;

	arg := load Arg Arg->PATH;
	if(arg == nil)
		error(0, sys->sprint("can't load %s: %r", Arg->PATH));
	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		'm' =>
			if((s := arg->arg()) == nil || !(s[0]>='0' && s[0]<='9'))
				usage();
			mtu = int s;
		'P' =>
			primary = 1;
		'f' =>
			framing = 0;
		* =>
			usage();
		}
	args = arg->argv();
	arg = nil;
	localip := "10.9.8.7";	# should be something locally unique
	fake := 1;
	if(args != nil){
		fake = 0;
		localip = hd args;
		args = tl args;
	}

	cerr := configinit();
	if(cerr != nil)
		error(0, sys->sprint("can't configure: %s", cerr));
	context = ctxt;

	# make default (for now)
	# if packet appears, start ppp and reset routing until it stops

	(cfd, dir, err) := getifc();
	if(err != nil)
		error(0, err);

	if(sys->fprint(cfd, "bind pkt") < 0)
		error(0, sys->sprint("can't bind pkt: %r"));
	if(sys->fprint(cfd, "add %s 255.255.255.0 10.9.8.0 %d", localip, mtu) < 0)
		error(0, sys->sprint("can't add ppp addresses: %r"));
	if(primary && addroute("0", "0", localip) < 0)
		error(0, sys->sprint("can't add default route: %r"));
	dfd := sys->open(dir+"/data", Sys->ORDWR);
	if(dfd == nil)
		error(0, sys->sprint("can't open %s: %r", dir));

	sys->pctl(Sys->NEWPGRP, nil);

	packets := chan of ref Packet;
	spawn netreader(dfd, dir, localip, fake, packets);

	logger := chan of (int, string);
	iocmd := sys->file2chan("/chan", "pppctl");
	if(iocmd == nil)
		error(0, sys->sprint("can't create /chan/pppctl: %r"));
	spawn servestatus(iocmd.read, logger);

	starteduser := 0;
	lasttime := 0;

	for(;;) alt{
	(nil, data, nil, wc) := <-iocmd.write =>	# remote io control
		if(wc == nil)
			break;
		(nil, flds) := sys->tokenize(string data, " \t");
		if(len flds > 1){
			case hd flds {
			"cancel" or "disconnect" or "hangup" =>
				;	# ignore it
			"connect" =>
				# start connection ...
				;
			* =>
				wreply(wc, (0, "illegal request"));
				continue;
			}
		}
		wreply(wc, (len data, nil));

	pkt := <-packets =>
		sys->print("ppplink: received packet %s->%s: %d bytes\n", ipa(pkt.src), ipa(pkt.dst), len pkt.data);
		if(abs(sys->millisec()-lasttime) < Ignorems){
			sys->print("ppplink: ignored, not enough time elapsed yet between dial attempts\n");
			break;
		}
		(ok, stat) := sys->stat(ISP_DB_PATH);
		if(ok < 0 || lastCdir == nil || !samefile(*lastCdir, stat)){
			cerr = configinit();
			if(cerr != nil){
				sys->print("ppplink: can't reconfigure: %s\n", cerr);
				# use existing configuration
			}
		}
		if(!starteduser){
			sync := chan of int;
			spawn userinterface(sync);
			starteduser = <-sync;
		}
		(ppperr, pppdir) := makeconnection(packets, logger, iocmd.write);
		lasttime = sys->millisec();
		if(ppperr == nil){
			sys->print("ppplink: connected on %s\n", pppdir);
			# converse ...
sys->sleep(120*1000);
		}else{
			sys->print("ppplink: ppp connect error: %s\n", ppperr);
			hangup(pppdir);
		}
	}
}

servestatus(reader: chan of (int, int, int, Sys->Rread), updates: chan of (int, string))
{
	statuspending := 0;
	statusreq: (int, int, Sys->Rread);
	step := Disconnected;
	statuslist := statusline(step, step, nil) :: nil;

	for(;;) alt{
	(off, nbytes, fid, rc) := <-reader=>
		if(rc == nil){
			statuspending = 0;
			if(step == Disconnected)
				statuslist = nil;
			break;
		}
		if(statuslist == nil){
			if(statuspending){
				alt{
				rc <-= (nil, "pppctl file already in use") => ;
				* => ;
				}
				break;
			}
			statusreq = (nbytes, fid, rc);
			statuspending = 1;
			break;
		}
		alt{
		rc <-= reads(hd statuslist, 0, nbytes) =>
			statuslist = tl statuslist;
		* => ;
		}

	(code, arg) := <-updates =>
		# convert to string
		if(code != Error)
			step = code;
		status := statusline(step, code, arg);
		if(code == Error)
			step = Disconnected;
		statuslist = appends(statuslist, status);
		sys->print("status: %d %d %s\n", step, code, status);
		if(statuspending){
			(nbytes, nil, rc) := statusreq;
			statuspending = 0;
			alt{
			rc <-= reads(hd statuslist, 0, nbytes) =>
				statuslist = tl statuslist;
			* =>
				;
			}
		}
	}
}

makeconnection(packets: chan of ref Packet, logger: chan of (int, string), writer: chan of (int, array of byte, int, Sys->Rwrite)): (string, string)
{
	result := chan of (string, string);
	sync := chan of int;
	spawn pppconnect(result, sync, logger);
	pid := <-sync;
	for(;;) alt{
	(err, pppdir) := <-result =>
		# pppconnect finished
		return (err, pppdir);

	pkt := <-packets =>
		# ignore packets whilst connecting
		sys->print("ppplink: ignored packet %s->%s: %d byten", ipa(pkt.src), ipa(pkt.dst), len pkt.data);

	(nil, data, nil, wc) := <-writer =>	# user control
		if(wc == nil)
			break;
		(nil, flds) := sys->tokenize(string data, " \t");
		if(len flds > 1){
			case hd flds {
			"connect" =>
				;	# ignore it
			"cancel" or "disconnect" or "hangup"=>
				kill(pid, "killgrp");
				wreply(wc, (len data, nil));
				return ("cancelled", nil);
			* =>
				wreply(wc, (0, "illegal request"));
				continue;
			}
		}
		wreply(wc, (len data, nil));
	}
}

wreply(wc: chan of (int, string), v: (int, string))
{
	alt{
	wc <-= v => ;
	* => ;
	}
}

appends(l: list of string, s: string): list of string
{
	if(l == nil)
		return s :: nil;
	return hd l :: appends(tl l, s);
}

statusline(step: int, code: int, arg: string): string
{
	s: string;
	if(code >= 0 && code < len statustext){
		n := "step";
		if(code == Linkup)
			n = "connect";
		s = sys->sprint("%d %d %s %s", step, len statustext, n, X(statustext[code]));
	}else
		s = sys->sprint("%d %d error", step, len statustext);
	if(arg != nil)
		s += sys->sprint(": %s", arg);
	return s;
}

getifc(): (ref Sys->FD, string, string)
{
	clonefile := netdir+"/ipifc/clone";
	cfd := sys->open(clonefile, Sys->ORDWR);
	if(cfd == nil)
		return (nil, nil, sys->sprint("can't open %s: %r", clonefile));
	buf := array[32] of byte;
	n := sys->read(cfd, buf, len buf);
	if(n <= 0)
		return (nil, nil, sys->sprint("can't read %s: %r", clonefile));
	return (cfd, netdir+"/ipifc/" + string buf[0:n], nil);
}

addroute(addr, mask, gate: string): int
{
	fd := sys->open(netdir+"/iproute", Sys->OWRITE);
	if(fd == nil)
		return -1;
	return sys->fprint(fd, "add %s %s %s", addr, mask, gate);
}

#	uchar	vihl;		/* Version and header length */
#	uchar	tos;		/* Type of service */
#	uchar	length[2];	/* packet length */
#	uchar	id[2];		/* ip->identification */
#	uchar	frag[2];	/* Fragment information */
#	uchar	ttl;		/* Time to live */
#	uchar	proto;		/* Protocol */
#	uchar	cksum[2];	/* Header checksum */
#	uchar	src[4];		/* IP source */
#	uchar	dst[4];		/* IP destination */
IPhdrlen: con 20;

netreader(dfd: ref Sys->FD, dir: string, localip: string, fake: int, outc: chan of ref Packet)
{
	buf := array [32*1024] of byte;
	while((n := sys->read(dfd, buf, len buf)) > 0){
		if(n < IPhdrlen){
			sys->print("ppplink: received short packet: %d bytes\n", n);
			continue;
		}
		pkt := ref Packet;
		if(n < 9*1024){
			pkt.data = array[n] of byte;
			pkt.data[0:] = buf[0:n];
		}else{
			pkt.data = buf[0:n];
			buf = array[32*1024] of byte;
		}
		pkt.src = pkt.data[12:];
		pkt.dst = pkt.data[16:];
		outc <-= pkt;
	}
	if(n < 0)
		error(1, sys->sprint("packet interface read error: %r"));
	else if(n == 0)
		error(1, "packet interface: end of file");
}

ipa(a: array of byte): string
{
	if(len a < 4)
		return "???";
	return sys->sprint("%d.%d.%d.%d", int a[0], int a[1], int a[2], int a[3]);
}

reads(str: string, off, nbytes: int): (array of byte, string)
{
	bstr := array of byte str;
	slen := len bstr;
	if(off < 0 || off >= slen)
		return (nil, nil);
	if(off + nbytes > slen)
		nbytes = slen - off;
	if(nbytes <= 0)
		return (nil, nil);
	return (bstr[off:off+nbytes], nil);
}

readppplog(log: chan of (int, string), errfile: string, pidc: chan of int) 
{
	pidc <-= sys->pctl(0, nil);
	src := sys->open(errfile, Sys->OREAD);
	if(src == nil)
		log <-= (Error, sys->sprint("can't open %s: %r", errfile));

	buf := array[1024] of byte;
	connected := 0;
	lasterror := "";

    	while((count := sys->read(src, buf, len buf)) > 0) {
	    	(nil, tokens) := sys->tokenize(string buf[:count],"\n");
	    	for(; tokens != nil; tokens = tl tokens) {
			case hd tokens {
			"no error" =>
				log <-= (Linkup, nil);
				lasterror = nil;
				connected = 1;
			"permission denied" =>
				lasterror = X("Username or Password Incorrect");
				log <-= (Error, lasterror);
			"write to hungup channel" =>
				lasterror = X("Remote Host Hung Up");
				log <-= (Error, lasterror);
			* =>
				lasterror = X(hd tokens);
				log <-= (Error, lasterror);
			}
		}
	}
	if(count == 0 && connected && lasterror == nil){	# should change ip/pppmedium.c instead?
		#hangup(nil);
		log <-= (Error, X("Lost Connection"));
	}
}

dialup(mi: ref Modem->ModemInfo, number: string, scriptinfo: ref Script->ScriptInfo, logchan: chan of (int, string)): (string, ref Sys->Connection)
{
	logchan <-= (Modeminit, nil);

	# open & init the modem

	modeminfo = mi;
	modem := load Modem Modem->PATH;
	if(modem == nil)
		return (sys->sprint("can't load %s: %r", Modem->PATH), nil);
	err := modem->init();
	if(err != nil)
		return (sys->sprint("couldn't init modem: %s", err), nil);
	Device: import modem;
	d := Device.new(modeminfo, 1);
	logchan <-= (Dialling, number);
	err = d.dial(number);
	if(err != nil){
		d.close();
		return (err, nil);
	}
	logchan <-= (Modemup, nil);

	# login script

	if(scriptinfo != nil) {
		logchan <-= (Scriptstart, nil);
		err = runscript(modem, d, scriptinfo);
		if(err != nil){
			d.close();
			return (err, nil);
		}
		logchan <-= (Scriptdone, nil);
	}

	mc := d.close();
	return (nil, mc);

}

startppp(logchan: chan of (int, string), pppinfo: ref PPPInfo): (string, string)
{
	(ifd, dir, err) := getifc();
	if(ifd == nil)
		return (err, nil);

	sync := chan of int;
	spawn readppplog(logchan, dir + "/err", sync);		# unbind gives eof on err
	<-sync;

	if(pppinfo.ipaddr == nil)
		pppinfo.ipaddr = "-";
#	if(pppinfo.ipmask == nil)
#		pppinfo.ipmask = "255.255.255.255";
	if(pppinfo.peeraddr == nil)
		pppinfo.peeraddr = "-";
	if(pppinfo.maxmtu == nil)
		pppinfo.maxmtu = "-";
#	if(pppinfo.maxmtu <= 0)
#		pppinfo.maxmtu = mtu;
#	if(pppinfo.maxmtu < 576)
#		pppinfo.maxmtu = 576;
	if(pppinfo.username == nil)
		pppinfo.username = "-";
	if(pppinfo.password == nil)
		pppinfo.password = "-";

	ifc := "bind ppp "+modeminfo.path+" "+ pppinfo.ipaddr+" "+pppinfo.peeraddr+" "+pppinfo.maxmtu
			+" "+string framing+" "+pppinfo.username+" "+pppinfo.password;

	if(sys->fprint(ifd, "%s", ifc) < 0)
		return (sys->sprint("can't bind ppp to %s: %r", dir), nil);

	sys->print("ppplink: %s\n", ifc);

	return (nil, dir);
}

runscript(modem: Modem, dev: ref Modem->Device, scriptinfo: ref Script->ScriptInfo): string
{
	script := load Script Script->PATH;
	if(script == nil)
		return sys->sprint("can't load %s: %r", Script->PATH);
	err := script->init(modem);
	if(err != nil)
		return err;
	return script->execute(dev, scriptinfo);
}

hangup(pppdir: string)
{
	sys->print("ppplink: hangup...\n");
	if(pppdir != nil){	# shut down the PPP link
		fd := sys->open(pppdir + "/ctl", Sys->OWRITE);
		if(fd == nil || sys->fprint(fd, "unbind") < 0)
			sys->print("ppplink: hangup: can't unbind ppp on %s: %r\n", pppdir);
		fd = nil;
	}
	modem := load Modem Modem->PATH;
	if(modem == nil) {
		sys->print("ppplink: hangup: can't load %s: %r", Modem->PATH);
		return;
	}
	err := modem->init();
	if(err != nil){
		sys->print("ppplink: hangup: couldn't init modem: %s", err);
		return;
	}
	Device: import modem;
	d := Device.new(modeminfo, 1);
	if(d != nil){
		d.onhook();
		d.close();
	}
}

kill(pid: int, msg: string)
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", msg) < 0)
		sys->print("pppclient: can't %s %d: %r\n", msg, pid);
}

error(dokill: int, s: string)
{
	sys->fprint(sys->fildes(2), "ppplink: %s\n", s);
	if(dokill)
		kill(sys->pctl(0, nil), "killgrp");
	raise "fail:error";
}

X(s : string) : string
{
	if(dict != nil)
		return dict.xlate(s);
	return s;
}

cfile(file: string): string
{
	if(len file > 0 && file[0] == '/')
		return file;
	return "/usr/"+user()+"/config/"+file;
}

user(): string
{
	fd := sys->open("/dev/user", Sys->OREAD);
	buf := array[64] of byte;
	if(fd != nil && (n := sys->read(fd, buf, len buf)) > 0)
		return string buf[0:n];
	return "inferno";	# hmmm.
}

cfvalue(c: ref ConfigFile, key: string) :string
{
	s := "";
	for(values := c.getcfg(key); values != nil; values = tl values){
		if(s != "")
			s[len s] = ' ';
		s += hd values;
	}
	return s;
}

configinit(): string
{
	cfg = load CfgFile CfgFile->PATH;
	if(cfg == nil)
		return sys->sprint("can't load %s: %r", CfgFile->PATH);

	# Modem Configuration

	modemdb := cfile(MODEM_DB_PATH);
	cfg->verify(DEFAULT_MODEM_DB_PATH, modemdb);
	modemcfg := cfg->init(modemdb);
	if(modemcfg == nil)
		return sys->sprint("can't open %s: %r", modemdb);
	modeminfo = ref Modem->ModemInfo;
	modeminfo.path = cfvalue(modemcfg, "PATH");
	modeminfo.init = cfvalue(modemcfg, "INIT");
	modeminfo.country = cfvalue(modemcfg, "COUNTRY");
	modeminfo.other = cfvalue(modemcfg, "OTHER");
	modeminfo.errorcorrection = cfvalue(modemcfg,"CORRECT");
	modeminfo.compression = cfvalue(modemcfg,"COMPRESS");
	modeminfo.flowctl = cfvalue(modemcfg,"FLOWCTL");
	modeminfo.rateadjust = cfvalue(modemcfg,"RATEADJ");
	modeminfo.mnponly = cfvalue(modemcfg,"MNPONLY");
	modeminfo.dialtype = cfvalue(modemcfg,"DIALING");
	if(modeminfo.dialtype!="ATDP")
		modeminfo.dialtype="ATDT";

	ispdb := cfile(ISP_DB_PATH);
	cfg->verify(DEFAULT_ISP_DB_PATH, ispdb);
	sys->print("cfg->init(%s)\n", ispdb);

	# ISP Configuration
	pppcfg := cfg->init(ispdb);
	if(pppcfg == nil)
		return sys->sprint("can't read or create ISP configuration file %s: %r", ispdb);
	(ok, stat) := sys->stat(ispdb);
	if(ok >= 0)
		lastCdir = ref stat;

	pppinfo = ref PPPInfo;
	isp_number = cfvalue(pppcfg, "NUMBER");
	pppinfo.ipaddr = cfvalue(pppcfg,"IPADDR");
	pppinfo.ipmask = cfvalue(pppcfg,"IPMASK");
	pppinfo.peeraddr = cfvalue(pppcfg,"PEERADDR");
	pppinfo.maxmtu = cfvalue(pppcfg,"MAXMTU");
	pppinfo.username = cfvalue(pppcfg,"USERNAME");
	pppinfo.password = cfvalue(pppcfg,"PASSWORD");

	info := pppcfg.getcfg("SCRIPT");
	if(info != nil) {
		scriptinfo = ref Script->ScriptInfo;
		scriptinfo.path = hd info;
		scriptinfo.username = pppinfo.username;
		scriptinfo.password = pppinfo.password;
	} else
		scriptinfo = nil;

	info = pppcfg.getcfg("TIMEOUT");
	if(info != nil)
		scriptinfo.timeout = int (hd info);
	cfg = nil;	# unload it

	if(modeminfo.path == nil)
		return "no modem device configured";
	if(isp_number == nil)
		return "no telephone number configured for ISP";

	return nil;
}

isipaddr(a: string): int
{
	i, c, ac, np : int = 0;
 
	for(i = 0; i < len a; i++) {
		c = a[i];
		if(c >= '0' && c <= '9') {
			np = 10*np + c - '0';
			continue;
		}
		if(c == '.' && np) {
			ac++;
	 		if(np > 255)
				return 0;
			np = 0;
			continue;
		}
		return 0;
	}
	return np && np < 256 && ac == 3;
}

userinterface(sync: chan of int)
{
	pppgui := load Command "pppchat.dis";
	if(pppgui == nil){
		sys->fprint(sys->fildes(2), "ppplink: can't load %s: %r\n", "/dis/svc/nppp/pppchat.dis");
		# TO DO: should be optional
		sync <-= 0;
	}

	sys->pctl(Sys->NEWPGRP|Sys->NEWFD, list of {0, 1, 2});
	sync <-= sys->pctl(0, nil);
	pppgui->init(context, "pppchat" :: nil);
}

pppconnect(result: chan of (string, string), sync: chan of int, status: chan of (int, string))
{
	sys->pctl(Sys->NEWPGRP|Sys->NEWFD, list of {0, 1, 2});
	sync <-= sys->pctl(0, nil);
	pppdir: string;
	(err, mc) := dialup(modeminfo, isp_number, scriptinfo, status);	# mc keeps connection open until startppp binds it to ppp
	if(err == nil){
		if(0 && (cfd := mc.cfd) != nil){
			sys->fprint(cfd, "m1");	# cts/rts flow control/fifo's on
			sys->fprint(cfd, "q64000"); # increase queue size to 64k
			sys->fprint(cfd, "n1");	# nonblocking writes on
			sys->fprint(cfd, "r1");	# rts on
			sys->fprint(cfd, "d1");	# dtr on
		}
		status <-= (Startingppp, nil);
		(err, pppdir) = startppp(status, pppinfo);
		if(err == nil){
			status <-= (Startedppp, nil);
			result <-= (nil, pppdir);
			return;
		}
	}
	status <-= (Error, err);
	result <-= (err, nil);
}

getspeed(file: string): string
{
	return findrate("/dev/modemstat", "rcvrate" :: "baud" :: nil);
}

findrate(file: string, opt: list of string): string
{
	fd := sys->open(file, sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array [1024] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 1)
		return nil;
	(nil, flds) := sys->tokenize(string buf[0:n], " \t\r\n");
	for(; flds != nil; flds = tl flds)
		for(l := opt; l != nil; l = tl l)
			if(hd flds == hd l)
				return hd tl flds;
	return nil;
}

samefile(d1, d2: Sys->Dir): int
{
	return d1.dev==d2.dev && d1.dtype==d2.dtype &&
			d1.qid.path==d2.qid.path && d1.qid.vers==d2.qid.vers &&
			d1.mtime==d2.mtime;
}

abs(n: int): int
{
	if(n < 0)
		return -n;
	return n;
}
