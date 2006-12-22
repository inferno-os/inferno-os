implement PPPClient;


include "sys.m";
	sys : Sys;
include "draw.m";

include "lock.m";
include "modem.m";
include "script.m";

include "pppclient.m";

include "translate.m";
	translate : Translate;
	Dict : import translate;
	dict : ref Dict;

#
# Globals (these will have to be removed if we are going multithreaded)
#

pid := 0;
modeminfo:	ref	Modem->ModemInfo;
pppdir: string;

ppplog(log: chan of int, errfile: string, pidc: chan of int) 
{
	pidc <-= sys->pctl(0, nil);				# set reset pid to our pid 
	src := sys->open(errfile, Sys->OREAD);
	if (src == nil)
		raise sys->sprint("fail: Couldn't open %s: %r", errfile);

	LOGBUFMAX:	con 1024;
	buf := array[LOGBUFMAX] of byte;
	connected := 0;

    	while ((count := sys->read(src, buf, LOGBUFMAX)) > 0) {
	    	(n, toklist) := sys->tokenize(string buf[:count],"\n");
	    	for (;toklist != nil;toklist = tl toklist) {
			case hd toklist {
				"no error" =>
					log <-= s_SuccessPPP;
					lasterror = nil;
					connected = 1;
				"permission denied" =>
					lasterror = X("Username or Password Incorrect");
					log <-= s_Error;
				"write to hungup channel" =>
					lasterror = X("Remote Host Hung Up");
					log <-= s_Error;
				* =>
					lasterror = X(hd toklist);
					log <-= s_Error;
			}
		}
	}
	if(count == 0 && connected && lasterror == nil){	# should change ip/pppmedium.c instead?
		lasterror = X("Lost Connection");
		log <-= s_Error;
	}
}

startppp(logchan: chan of int, pppinfo: ref PPPInfo)
{
	ifd := sys->open("/net/ipifc/clone", Sys->ORDWR);
	if (ifd == nil)
		raise "fail: Couldn't open /net/ipifc/clone";

	buf := array[32] of byte;
	n := sys->read(ifd, buf, len buf);
	if(n <= 0)
		raise "fail: can't read from /net/ipifc/clone";

	pppdir = "/net/ipifc/" + string buf[0:n];
	pidc := chan of int;
	spawn ppplog(logchan, pppdir + "/err", pidc);
	pid = <-pidc;
	logchan <-= s_StartPPP;

	if (pppinfo.ipaddr == nil)
		pppinfo.ipaddr = "-";
#	if (pppinfo.ipmask == nil)
#		pppinfo.ipmask = "255.255.255.255";
	if (pppinfo.peeraddr == nil)
		pppinfo.peeraddr = "-";
	if (pppinfo.maxmtu == nil)
		pppinfo.maxmtu = "512";
	if (pppinfo.username == nil)
		pppinfo.username = "-";
	if (pppinfo.password == nil)
		pppinfo.password = "-";
	framing := "1";

	ifc := "bind ppp "+modeminfo.path+" "+ pppinfo.ipaddr+" "+pppinfo.peeraddr+" "+pppinfo.maxmtu
			+" "+framing+" "+pppinfo.username+" "+pppinfo.password;

	# send the add command
	if (sys->fprint(ifd, "%s", ifc) < 0) {
		sys->print("pppclient: couldn't write %s/ctl: %r\n", pppdir);
		raise "fail: Couldn't write /net/ipifc";
		return;
	}
}

connect(mi: ref Modem->ModemInfo, number: string,
		scriptinfo: ref Script->ScriptInfo, pppinfo: ref PPPInfo, logchan: chan of int)
{
	sys = load Sys Sys->PATH;

	translate = load Translate Translate->PATH;
	if (translate != nil) {
		translate->init();
		dictname := translate->mkdictname("", "pppclient");
		(dict, nil) = translate->opendict(dictname);
	}
	if (pid != 0)			# yikes we are already running
		reset();

	# create a new process group
	pid = sys->pctl( Sys->NEWPGRP, nil);
	
	{
		logchan <-= s_Initialized;
	
		# open & init the modem
		modeminfo = mi;
		modem := load Modem Modem->PATH;
		if (modem == nil) {
			raise "fail: Couldn't load modem module";
			return;
		}
	
		modemdev := modem->init(modeminfo);
		logchan <-= s_StartModem;
		modem->dial(modemdev, number);
		logchan <-= s_SuccessModem;

		# if script
		if (scriptinfo != nil) {
			script := load Script Script->PATH;
			if (script == nil) {
				raise "fail: Couldn't load script module";
				return;
			}
			logchan <-= s_StartScript;
			script->execute(modem, modemdev, scriptinfo);
			logchan <-= s_SuccessScript;
		}

		mc := modem->close(modemdev);	# keep connection open for ppp mode
		modemdev = nil;
		modem = nil;	# unload modem module

		# if ppp
		if (pppinfo != nil) 
			startppp(logchan, pppinfo);
		else
			logchan <-= s_Done;
	}
	exception e{
		"fail*" =>
			lasterror = e;
			sys->print("PPPclient: fatal exception: %s\n", e);
			logchan <-= s_Error;
			kill(pid, "killgrp");
			exit;
	}
}

reset()
{
	sys->print("reset...");
	if(pid != 0){
		kill(pid, "killgrp");
		pid = 0;
	}

	if(pppdir != nil){	# shut down the PPP link
		fd := sys->open(pppdir + "/ctl", Sys->OWRITE);
		if(fd == nil || sys->fprint(fd, "unbind") < 0)
			sys->print("pppclient: can't unbind: %r\n");
		fd = nil;
		pppdir = nil;
	}

	modem := load Modem Modem->PATH;
	if (modem == nil) {
		raise "fail: Couldn't load modem module";
		return;
	}
	modemdev := modem->init(modeminfo);
	if(modemdev != nil)
		modem->onhook(modemdev);
	modem = nil;

	# clear error buffer
	lasterror = nil;
}

kill(pid: int, msg: string)
{
	a := array of byte msg;
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->write(fd, a, len a) < 0)
		sys->print("pppclient: can't %s %d: %r\n", msg, pid);
}

# Translate a string 

X(s : string) : string
{
	if (dict== nil) return s;
	return dict.xlate(s);
}

