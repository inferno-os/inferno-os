#
# Copyright © 1998 Lucent Technologies Inc.  All rights reserved.
# Revisions copyright © 2000,2001 Vita Nuova Holdings Limited.  All rights reserved.
#
# Originally Written by N. W. Knauft
# Adapted by E. V. Hensbergen (ericvh@lucent.com)
# Further adapted by Vita Nuova
#

implement PPPGUI;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

include "translate.m";
	translate: Translate;
	Dict: import translate;
	dict: ref Dict;

include "lock.m";
include "modem.m";
include "script.m";
include "pppclient.m";
	ppp: PPPClient;

include "pppgui.m";

#Screen constants
BBG: con "#C0C0C0";             # Background color for button
PBG: con "#808080";             # Background color for progress bar
LTGRN: con "#00FF80";           # Color for progress bar
BARW: con 216;			# Progress bar width
BARH: con " 9";			# Progress bar height
INCR: con 30;			# Progress bar increment size
N_INCR: con 7;			# Number of increments in progress bar width
BSIZE: con 25;			# Icon button size
ISIZE: con BSIZE + 4;		# Icon window size
DIALQUANTA : con 1000;
ICONQUANTA : con 5000;

#Globals
pppquanta := DIALQUANTA;

#Font
FONT: con "/fonts/lucidasans/unicode.6.font";

#Messages
stat_msgs := array[] of {
	"Initializing Modem",
	"Dialling Service Provider",
	"Logging Into Network",
	"Executing Login Script",
	"Script Execution Complete",
	"Logging Into Network",
	"Verifying Password",
	"Connected",
	"",
};

config_icon := array[] of {
	"button .btn -text X -width "+string BSIZE+" -height "+string BSIZE+" -command {send tsk open} -bg "+BBG,
	"pack .btn",

	"pack propagate . no",
	". configure -bd 0",
	". unmap",
	"update",
};


# Create internet connect window, spawn event handler
init(ctxt: ref Draw->Context, stat: chan of int, pppmod: PPPClient, args: list of string): chan of int
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;

	if (draw == nil || tk == nil || tkclient == nil) {
		sys->fprint(sys->fildes(2), "pppgui: can't load Draw or Tk: %r\n");
		return nil;
	}

	translate = load Translate Translate->PATH;
	if(translate != nil) {
		translate->init();
		dictname := translate->mkdictname("", "pppgui");
		dicterr: string;
		(dict, dicterr) = translate->opendict(dictname);
		if(dicterr != nil)
			sys->fprint(sys->fildes(2), "pppgui: can't open %s: %s\n", dictname, dicterr);
	}else
		sys->fprint(sys->fildes(2), "pppgui: can't load %s: %r\n", Translate->PATH);
	ppp = pppmod;		# set the global

	tkargs := "";

	if (args != nil) {
		tkargs = hd args;
		args = tl args;
	} else
		tkargs="-x 340 -y 4";

	tkclient->init();
		
	(t, wmctl) := tkclient->toplevel(ctxt, tkargs, "PPP", Tkclient->Plain);

	config_win := array[] of {
		"frame .f",
		"frame .fprog",

		"canvas .cprog -bg "+PBG+" -bd 2 -width "+string BARW+" -height "+BARH+" -relief ridge",	
		"pack .cprog -in .fprog -pady 6",

		"label .stat -text {"+X("Initializing connection...")+"} -width 164 -font "+FONT,
		"pack .stat -in .f -side left -fill y -anchor w",

		"button .done -text {"+X("Cancel")+"} -width 60 -command {send cmd cancel} -bg "+BBG+" -font "+FONT,
		"pack .fprog -side bottom -expand 1 -fill x",
		"pack .done -side right -padx 1 -pady 1 -fill y -anchor e",
		"pack .f -side left -expand 1 -padx 5 -pady 3 -fill both -anchor w",

		"pack propagate . no",
		". configure -bd 2 -relief raised -width "+string WIDTH,
		"update",
	};

	for(i := 0; i < len config_win; i++)
		tk->cmd(t, config_win[i]);

	itkargs := "";
	if (args != nil) {
		itkargs = hd args;
		args = tl args;
	}
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "ptr" :: nil);

	if (itkargs == "") {
		x := int tk->cmd(t, ". cget x");
		y := int tk->cmd(t, ". cget y");
		x += WIDTH - ISIZE;
		itkargs = "-x "+string x+" -y "+string y;
	}

	(ticon, iconctl) := tkclient->toplevel(ctxt, itkargs, "PPP", Tkclient->Plain);

	for( i = 0; i < len config_icon; i++)
		tk->cmd(ticon, config_icon[i]);

	tk->cmd(ticon, "image create bitmap Network -file network.bit -maskfile network.bit");
	tk->cmd(ticon, ".btn configure -image Network");
	tkclient->startinput(ticon, "ptr"::nil);

	chn := chan of int;
	spawn handle_events(t, wmctl, ticon, iconctl, stat, chn);
	return chn;
}

ppp_timer(sync: chan of int, stat: chan of int)
{
	for(;;) {
		sys->sleep(pppquanta);
		alt {
		<-sync =>
			return;
		stat <-= -1 =>
			;
		}
	}
}

send(cmd: chan of string, msg: string)
{
	cmd <-= msg;
}

# Process events and pass disconnect cmd to calling app
handle_events(t: ref Tk->Toplevel, wmctl: chan of string, ticon: ref Tk->Toplevel, iconctl: chan of string, stat, chn: chan of int)
{
	sys->pctl(Sys->NEWPGRP, nil);
	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	tsk := chan of string;
	tk->namechan(ticon, tsk, "tsk");

	connected := 0;
	winmapped := 1;
	timecount := 0;
	xmin := 0;
	x := 0;

	iocmd := sys->file2chan("/chan", "pppgui");
	if (iocmd == nil) {
		sys->print("fail: pppgui: file2chan: /chan/pppgui: %r\n");
		return;
	}

	pppquanta = DIALQUANTA;
	sync_chan := chan of int;
	spawn ppp_timer(sync_chan, stat);

Work:
	for(;;) alt {
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);

	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);

	s := <-t.ctxt.ctl or
	s = <-t.wreq or
	s = <-wmctl =>
		tkclient->wmctl(t, s);

	s := <-ticon.ctxt.kbd =>
		tk->keyboard(ticon, s);
	s := <-ticon.ctxt.ptr =>
		tk->pointer(ticon, *s);
	s := <-ticon.ctxt.ctl or
	s = <-ticon.wreq or
	s = <-iconctl =>
		tkclient->wmctl(ticon, s);

	(off, data, fid, wc) := <-iocmd.write =>	# remote io control
		if (wc == nil)
			break;
		spawn send(cmd, string data[0:len data]);
		wc <-= (len data, nil);

	(nil, nbytes, fid, rc) := <-iocmd.read =>
		if (rc != nil)
			rc <-= (nil, "not readable");

	press := <-cmd =>
		case press {
		"cancel" or "disconnect" =>
			tk->cmd(t, ".stat configure -text 'Disconnecting...");
			tk->cmd(t, "update");
			ppp->reset();
			if (!connected) {
				# other end may have gone away
				alt {
					chn <-= 666 => ;
					* => ;
				}
			}
			break Work;
		* => ;
		}

	prs := <-tsk =>
		case prs {
		"open" =>
			tk->cmd(ticon, ". unmap; update");
			tk->cmd(t, ". map; raise .; update");
			winmapped = 1;
			timecount = 0;
		* => ;
		}

	s := <-stat =>
		if (s == -1) {	# just an update event
			if(winmapped){
				if(!connected) {	# increment status bar
					if (x < xmin+INCR) {
						x++;
						tk->cmd(t, ".cprog create rectangle 0 0 "+string x + BARH+" -fill "+LTGRN);
					}
				}else{
					timecount++;
					if(timecount > 1){
						winmapped = 0;
						timecount = 0;
						tk->cmd(t, ". unmap; update");
						tk->cmd(ticon, ". map; raise .; update");
						continue;
					}
				}
				tk->cmd(t, "raise .; update");
			} else {
				tk->cmd(ticon, "raise .; update");
				timecount = 0;
			}
			continue;
		}
		if (s == ppp->s_Error) {
			tk->cmd(t, ".stat configure -text '"+ppp->lasterror);
			if (!winmapped) {
				tk->cmd(ticon, ". unmap; update");
				tk->cmd(t, ". map; raise .");
			}
			tk->cmd(t, "update");
			sys->sleep(3000);	
			ppp->reset();
			if (!connected)
				chn <-= 0;			# Failure	
			break Work;
		}
	
		if (s == ppp->s_Initialized)
			tk->cmd(t,".cprog create rectangle 0 0 "+string BARW + BARH+" -fill "+PBG);
		
		x = xmin = s * INCR;
		if (xmin > BARW)
			xmin = BARW;
		tk->cmd(t, ".cprog create rectangle 0 0 "+string xmin + BARH+" -fill "+LTGRN);
		tk->cmd(t, "raise .; update");
		tk->cmd(t, ".stat configure -text '"+X(stat_msgs[s]));

		if (s == ppp->s_SuccessPPP || s == ppp->s_Done) {
			if(!connected){
				chn <-= 1;
				connected = 1;
			}
			pppquanta = ICONQUANTA;

			# find and display connection speed
			speed := findrate("/dev/modemstat", "rcvrate" :: "baud" :: nil);
			if(speed != nil)
				tk->cmd(t, ".stat configure -text {"+X(stat_msgs[s])+" "+speed+" bps}");
			else
				tk->cmd(t, ".stat configure -text {"+X(stat_msgs[s])+"}");
			tk->cmd(t, ".done configure -text Disconnect -command 'send cmd disconnect");
			tk->cmd(t, "update");
			sys->sleep(2000);	
			tk->cmd(t, ". unmap; pack forget .fprog; update");
			winmapped = 0;
			tk->cmd(ticon, ". map; raise .; update");
		}

		tk->cmd(t, "update");
	}
	sync_chan <-= 1;	# stop ppp_timer
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
			if (hd flds == hd l)
				return hd tl flds;
	return nil;
}



# Translate a string 

X(s : string) : string
{
	if (dict== nil) return s;
	return dict.xlate(s);
}

