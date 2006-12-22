#    Last change:  R    24 May 2001   11:05 am
implement PPPTest;

include "sys.m";
	sys:	Sys;
include "draw.m";

include "lock.m";
include "modem.m";
include "script.m";
include "pppclient.m";
include "pppgui.m";

PPPTest: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};
usage()
{
    sys->print("ppptest device modem_init tel user password \n");
	sys->print("Example: ppptest /dev/modem atw2 4125678 rome xxxxxxxx\n");
	exit;
	
}
init( ctxt: ref Draw->Context, argv: list of string )
{
	sys = load Sys Sys->PATH;

	mi:	Modem->ModemInfo;
	pi:	PPPClient->PPPInfo;
	tel : string;
#	si:	Script->ScriptInfo;
	argv = tl argv;
    if(argv == nil)
	    usage();
	else
		mi.path = hd argv;

	argv = tl argv;
	if(argv == nil)
	    usage();
	else
		mi.init = hd argv;
	argv = tl argv;
	if(argv == nil)
		usage();
	else
		tel = hd argv;
	argv = tl argv;
	if(argv == nil)
		usage();
	else
		pi.username = hd argv;
	argv = tl argv;
	if(argv==nil)
	    usage();
	else
	    pi.password = hd argv;


	#si.path = "rdid.script";
	#si.username = "ericvh";
	#si.password = "foobar";
	#si.timeout = 60;


	ppp := load PPPClient PPPClient->PATH;

	logger := chan of int;

	spawn ppp->connect( ref mi, tel, nil, ref pi, logger );
	
	pppgui := load PPPGUI PPPGUI->PATH;
	(respchan, err) := pppgui->init(ctxt, logger, ppp, nil);
	if(err != nil){
		sys->print("ppptest: can't %s: %s\n", PPPGUI->PATH, err);
		exit;
	}

	event := 0;
	while(1) {
		event =<- respchan;
		sys->print("GUI event received: %d\n",event);
		if(event) {
			sys->print("success");
			exit;
		} else {
			raise "fail: Couldn't connect to ISP";
		}
	}	
}
