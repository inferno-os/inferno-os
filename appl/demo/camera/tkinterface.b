# Sort out timing with taking photo & getting jpg/thumbnail - make sure it gets the right one when 2photos have been taken & sort out 'cannot communicate with camera' error

implement tkinterface;

include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "sys.m";
	sys : Sys;
include "daytime.m";
	daytime: Daytime;
include "readdir.m";
	readdir: Readdir;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "selectfile.m";
	selectfile: Selectfile;

include "string.m";
	str : String;
include "draw.m";
	draw: Draw;
	Context, Display, Point, Rect, Image, Screen, Font: import draw;
include "grid/readjpg.m";
	readjpg: Readjpg;

display : ref draw->Display;
context : ref draw->Context;
camerapath := "";
savepath := "";
tmppath := "/tmp/";
usecache := 1;
working := 0;
processing := 0;
coords: draw->Rect;
DONE : con 1;
KILLED : con 2;
font: ref Draw->Font;
tkfont := "";
tkfontb := "";
tkfontf := "";
ssize := 3;
maxsize : Point;
nilrect := Draw->Rect((0,0),(0,0));
runwithoutcam := 0;
toplevels : list of (ref Tk->Toplevel, string, list of int, int) = nil;
procimg : ref Draw->Image;
loadimg: ref Draw->Image;

tkinterface : module {
	init : fn (ctxt : ref Draw->Context, argv : list of string);
};

init(ctxt : ref Draw->Context, argv : list of string)
{
	display = ctxt.display;
	context = ctxt;

	sys = load Sys Sys->PATH;
#	sys->pctl(Sys->NEWPGRP, nil);
#	sys->pctl(Sys->FORKNS, nil);

	str = load String String->PATH;
	readdir = load Readdir Readdir->PATH;
	daytime = load Daytime Daytime->PATH;
	bufio = load Bufio Bufio->PATH;
	
	str = load String String->PATH;
	draw = load Draw Draw->PATH;

	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	tkclient->init();
	selectfile = load Selectfile Selectfile->PATH;
	selectfile->init();
	readjpg = load Readjpg Readjpg->PATH;
	readjpg->init(display);
	font = draw->Font.open(display, "/fonts/charon/plain.small.font");
	runfrom := hd argv;
	p := isat2(runfrom,"/");
	savepath = runfrom[:p+1];
	argv = tl argv;
	while (argv != nil) {
		if (camerapath == "" && (hd argv)[0] == '/') camerapath = hd argv;
		if (hd argv == "nocache") usecache = 0;
		argv = tl argv;
	}
	if (camerapath == "")
		camerapath = "./";
	if (camerapath != "" && camerapath[len camerapath - 1] != '/')
		camerapath[len camerapath] = '/';

	r := display.image.r;
#	if (r.dx() < 800 || r.dy() < 600) ssize = 2;
	if (r.dx() < 400 || r.dy() < 300) ssize = 1;
	maxsize = (r.dx(), r.dy());

	if (ssize == 1) {
		tkfont = "/fonts/charon/plain.tiny.font";
		tkfontb = "/fonts/charon/bold.tiny.font";
		tkfontf = "/fonts/pelm/unicode.8.font";
	}
	else if (ssize == 2) {
		tkfont = "/fonts/charon/plain.small.font";
		tkfontb = "/fonts/charon/bold.small.font";
		tkfontf = "/fonts/pelm/unicode.8.font";
	}
	else {
		tkfont = "/fonts/charon/plain.normal.font";
		tkfontb = "/fonts/charon/bold.normal.font";
		tkfontf = "/fonts/pelm/unicode.8.font";
	}
	if ((sys->stat(tkfont)).t0 == -1)
		tkfont = "";
	else tkfont = " -font " + tkfont;
	if ((sys->stat(tkfontb)).t0 == -1)
		tkfontb = "";
	else tkfontb = " -font " + tkfontb;
	if ((sys->stat(tkfontf)).t0 == -1)
		tkfontf = "";
	else tkfontf = " -font " + tkfontf;

	procimg = display.open("camproc.bit");
	loadimg = display.open("camload.bit");

	spawn tkstuff();
}

# Tk stuff

thumbscr := array[] of {
	"frame .f",
	"frame .fthumb -bg white",
	"frame .f.finfo",
	"frame .f.fsnap",
	"menubutton .f.fsnap.fsettings.mb2 -text {Selected\n(0 files)} -menu .m2 @",
	"menu .m2 @",
	".m2 add command -text {Select All} -command {send butchan selectall 1}",
	".m2 add command -text {Select None} -command {send butchan selectall 0}",
	".m2 add command -text {Invert Selection} -command {send butchan invert}",
	".m2 add command -text {Refresh Files} -command {send butchan refresh}",
	"menu .m @",

	"frame .f.fsnap.fsettings -borderwidth 1 -relief raised",
	"menubutton .f.fsnap.fsettings.mb -text {Settings} -menu .m &",
	"button .f.fsnap.fsettings.b -text {Information} -command {send butchan info} &",
	"grid .f.fsnap.fsettings.b -row 0 -column 0 -sticky ew",
	"grid .f.fsnap.fsettings.mb -row 1 -column 0 -sticky ew",
	"grid .f.fsnap.fsettings.mb2 -row 2 -column 0 -sticky ew",

	"frame .f.fsnap.fstore -borderwidth 1 -relief raised",
	"label .f.fsnap.fstore.l1 -text {  Photos taken: } @",
	"label .f.fsnap.fstore.l2 -text {  Remaining: } @",
	"label .f.fsnap.fstore.l3 -text {  } @",
	"label .f.fsnap.fstore.l4 -text {  } @",
	"grid .f.fsnap.fstore.l1 -row 0 -column 0 -sticky w",
	"grid .f.fsnap.fstore.l2 -row 1 -column 0 -sticky w",
	"grid .f.fsnap.fstore.l3 -row 0 -column 1 -sticky w",
	"grid .f.fsnap.fstore.l4 -row 1 -column 1 -sticky w",

	"frame .f.fsnap.ftime -borderwidth 1 -relief raised",
	"label .f.fsnap.ftime.l1 -text {Local: } @",
	"label .f.fsnap.ftime.l2 -text {Camera: } @",
	"label .f.fsnap.ftime.l3",
	"label .f.fsnap.ftime.l4",
	"checkbutton .f.fsnap.ftime.cb -text {Set camera to local time} -variable time &",
	"button .f.fsnap.ftime.b -text {refresh} -command {send butchan gettime} &",
	"grid .f.fsnap.ftime.l1 -row 0 -column 0 -sticky w",
	"grid .f.fsnap.ftime.l2 -row 1 -column 0 -sticky w",
	"grid .f.fsnap.ftime.l3 -row 0 -column 1 -sticky w",
	"grid .f.fsnap.ftime.l4 -row 1 -column 1 -sticky w",
	"grid .f.fsnap.ftime.cb -row 2 -column 0 -columnspan 2",
	"grid .f.fsnap.ftime.b -row 3 -column 0 -columnspan 2",

	"button .f.fsnap.b -text {Take Photo} -command {send butchan snap} &",
	"grid columnconfigure .f.fsnap 2 -minsize 150",
	"frame .f.fcom",
	"frame .f.f1 -background #0d0d0d1a",
	"canvas .f.f1.c1 -yscrollcommand {.f.f1.sb1 set} -height 255 -width 542 -bg white",
	".f.f1.c1 create window 0 0 -window .fthumb -anchor nw",
	"scrollbar .f.f1.sb1 -command {.f.f1.c1 yview}",

#	"frame .f.f2",
#	"canvas .f.f2.c1 -width 556 -height 304",
#	".f.f2.c1 create window 0 0 -window .f.fsnap -anchor nw",

	"grid .f.fsnap -column 0 -row 0",
	"grid .f.f1 -column 0 -row 1",
	"grid .f.f1.c1 -column 0 -row 0",
	"grid .f.f1.sb1 -column 1 -row 0 -sticky ns",
#	"grid .f.f2 -column 0 -row 0",
#	"grid .f.f2.c1 -column 0 -row 0 -sticky ew",
	"bind .Wm_t <ButtonPress-1> +{focus .}",
	"bind .Wm_t.title <ButtonPress-1> +{focus .}",
};

lastpath := "";

Aitem: adt {
	pname,desc: string;
	dtype,factory: int;
	read, location: string;
	data: list of (string, int);
};
LIST: con 0;
MINMAX: con 1;
OTHER: con 2;

noabilities := 0;	
abilities : array of Aitem;

getdesc(l : list of string): list of string
{
	s := "";
	while(hd l != "min" && hd l != "items" && tl l != nil) {
		s += hd l + " ";
		l = tl l;
	}
	while (s[len s - 1] == ' ' || s[len s - 1] == '\n')
		s = s[:len s -1];
	l = s :: l;
	return l;
}

inflist : list of (string, string);
ablmenu : array of string;

getabilities()
{
	inflist = nil;
	abilities = array[200] of Aitem;	
	fd := bufio->open(camerapath+"abilities", bufio->OREAD);
	if (runwithoutcam)
		fd = bufio->open("/usr/danny/camera/abls", bufio->OREAD);
	i := 0;
	for (;;) {
		take := 0;
		s := fd.gets('\n');
		if (s == "") break;
		(n, lst) := sys->tokenize(s," ,:\t\n");
		abilities[i].data = nil;
		abilities[i].read = "";
		if (lst != nil && len hd lst == 4) {
			abilities[i].pname = hd lst;
			lst = getdesc(tl lst);
			abilities[i].desc = hd lst;
			if (hd tl lst == "items") {
				abilities[i].dtype = LIST;
				abilities[i].factory = int hd tl tl tl tl lst;
				noitems := int hd tl tl lst;
				for (k := 0; k < noitems; k++) {
					s = fd.gets('\n');
					(n2, lst2) := sys->tokenize(s,",:\t\n");
					name := hd lst2;
					val := int hd tl lst2;
					if (k == 0) {
						if (abilities[i].pname == "ssiz")
							abilities[i].factory = val;
						else if (abilities[i].pname == "scpn")
							abilities[i].factory = val;
					}	
					if (val == abilities[i].factory && noitems > 1) name += " *";
					abilities[i].data = (name, val) :: abilities[i].data;
				}
				if (noitems < 2) {
					inflist = (abilities[i].desc, (hd abilities[i].data).t0) :: inflist;
					take = 1;
				}
			}
			else if (hd tl lst == "min") {
				abilities[i].dtype = MINMAX;
				abilities[i].factory = int hd tl tl tl tl tl tl lst;
				min := int hd tl tl lst;
				max := int hd tl tl tl tl lst;
				mul := 1;
				while (max > 200000) {
					min /= 10;
					max /= 10;
					mul *= 10;
				}
				abilities[i].data = ("min", min) :: abilities[i].data;
				abilities[i].data = ("max", max) :: abilities[i].data;
				abilities[i].data = ("mul", mul) :: abilities[i].data;
			}
			else {
				inflist = (abilities[i].desc,list2string(tl lst)) :: inflist;
				take = 1;
			}
			if (take || 
				abilities[i].desc == "Time Format" ||
				abilities[i].desc == "Date Format" ||
				abilities[i].desc == "File Type" ||
				contains(abilities[i].desc,"Video") ||
				contains(abilities[i].desc,"Media") ||
				contains(abilities[i].desc,"Sound") ||
				contains(abilities[i].desc,"Volume") ||
				contains(abilities[i].desc,"Slide") ||
				contains(abilities[i].desc,"Timelapse") ||
				contains(abilities[i].desc,"Burst") ||
				contains(abilities[i].desc,"Power") ||
				contains(abilities[i].desc,"Sleep"))
					i--;
			i++;
		}	
	}
	noabilities = i;
}

isat(s: string, test: string): int
{
	num := -1;
	if (len test > len s) return -1;
	for (i := 0; i < (1 + (len s) - (len test)); i++) {
		if (num == -1 && test == s[i:i+len test]) num = i;
	}
	return num;
}

isat2(s: string, test: string): int
{
	num := -1;
	if (len test > len s) return -1;
	for (i := len s - len test; i >= 0; i--) {
		if (num == -1 && test == s[i:i+len test]) num = i;
	}
	return num;
}


nomatches(s: string): int
{
	n := 0;
	for (i := 0; i < noabilities; i++) {
		test := abilities[i].desc;
		if (len s <= len test && test[:len s] == s) n++;
	}
	return n;
}

matches(s1,s2: string): int
{
	if (len s1 < len s2) return 0;
	if (s1[:len s2] == s2) return 1;
	return 0;
}

biggestmatch(nm: int, s: string, l: int): string
{
	bigmatch := s;
	match := s[:l];
	for (;;) {
		if (bigmatch == match) break;
		if (nomatches(bigmatch) == nm) return bigmatch;
		p := isat2(bigmatch," ");
		if (p < len match) break;
		bigmatch = bigmatch[:p];
	}
	return match;
}

getabllist(): array of string
{
	los : list of string;
	los = nil;
	for (i := 0; i < noabilities; i++) {
		p := 0;
		p2 := 0;
		nm : int;
		for (;;) {
			nm = -1;
			tmpl := los;
			while (tmpl != nil) {
				if (matches(abilities[i].desc, hd tmpl)) nm = 0;
				tmpl = tl tmpl;
			}
			if (nm == 0) break;
			p += p2;
			tmp := abilities[i].desc[p:];
			p2 = isat(tmp, " ");
			if (p2 == -1) p2 = len tmp;
			else p2++;
			nm = nomatches(abilities[i].desc[:p+p2]);
			if (nm <= 5) break;
		}
		if (nm > 0) {
			listitem := biggestmatch(nm, abilities[i].desc,p+p2);
			los = listitem :: los;
		}
	}
	ar := array[len los] of string;
	for (i = len ar - 1; i >= 0; i--) {
		ar[i] = hd los;
		los = tl los;
	}
	return ar;
}

buildabilitiesframes(top: ref Tk->Toplevel)
{
	ablmenu = getabllist();
	tkcmd(top, ".m add command -text {Refresh Main Screen} -command {send butchan refreshstate}");
	tkcmd(top, ".m add command -text {Reset Camera} -command {send butchan reset}");
	for (k := 0; k < len ablmenu; k++) {
		if (len ablmenu[k] > 4 && (ablmenu[k][:4] == "Zoom" || ablmenu[k][:5] == "Still")) 
 			buildabilitiesframe(top,k,"butchan");
		else
			tkcmd(top, ".m add command -text {"+ablmenu[k]+
				"} -command {send butchan abls "+string k+"}");
	}
	tkcmd(top, "menu .mthumb "+tkfont);
	tkcmd(top, ".mthumb add command -label {Selection (88 files)}");
	tkcmd(top, ".mthumb add separator");
	for (k = nothumbs; k < len menu; k++)
		 tkcmd(top, ".mthumb add command -text {"+menu[k].text+"} " +
				"-command {send butchan}");

}

buildabilitiesframe(top: ref Tk->Toplevel,k: int, chanout: string)
{
	nm := string nomatches(ablmenu[k]);
	count2 := 0;
	for (i := 0; i < noabilities; i++) {
		if (matches(abilities[i].desc,ablmenu[k])) {

			frame : string;
			case abilities[i].pname {
				"scpn" or "ssiz" or "zpos" =>
					frame = ".f.fsnap.f"+abilities[i].pname;
					tkcmd(top, "frame "+frame+" -borderwidth 1 -relief raised");
				* =>
					frame = ".f";
					if (count2 == 0)  { 
						tkcmd(top, "frame "+frame);
						tkcmd(top, "label "+frame+".l -text {"+ablmenu[k]+"}"+tkfontb);
						tkcmd(top, "grid "+frame+".l -row 0 -column 0 -columnspan "+nm);
					}
					frame = frame + ".f"+string count2;
					tkcmd(top, "frame "+frame+" -borderwidth 1 -relief raised");
					tkcmd(top, "grid "+frame+" -row 1 -column "+string count2+ " -sticky nsew");
					mul := getval(abilities[i].data,"mul");
					s := abilities[i].desc[len ablmenu[k]:];
					if (mul != 1 && abilities[i].dtype == MINMAX)
						s += " (x"+string mul+")";
					tkcmd(top, "label "+frame+".l -text {"+s+"}"+tkfont);
					tkcmd(top, "grid "+frame+".l -row 0 -column 0 -sticky nw");
			}
				
			if (abilities[i].dtype == MINMAX) {
				abilities[i].location = frame+".sc";
				min := getval(abilities[i].data,"min");
				max := getval(abilities[i].data,"max");
				tkcmd(top, sys->sprint("scale %s.sc -to %d -from %d %s", frame,min,max,tkfont));
				tkcmd(top, "bind "+frame+".sc <ButtonPress-3> {send " +
					chanout + " scaleval " + string i + " %X %Y}");
				tkcmd(top, "grid "+frame+".sc -row 1 -column 0");		
			}
			else if (abilities[i].dtype == LIST) {
				tkcmd(top, "frame "+frame+".frb");
				tkcmd(top, "grid "+frame+".frb -row 1 -column 0");
				tmp := abilities[i].data;
				row := 0;
				while (tmp != nil) {
					(name, val) := hd tmp;
					s := sys->sprint("radiobutton %s.frb.rb%d -text {%s} -value %d -variable %s  -height %d %s",frame,row,name,val,abilities[i].pname,24 - (3*(3-ssize)), tkfont);
					tkcmd(top,s);
					tkcmd(top, sys->sprint("grid %s.frb.rb%d -row %d -column 0 -sticky w",
						frame,row,row));
					tmp = tl tmp;
					row++;
				}
			}
			tkcmd(top, "button "+frame+".bs -text {Set} -command "+
				"{send "+chanout+" set "+string i+"}"+butheight+tkfont);
			tkcmd(top, "grid "+frame+".bs -row 2 -column 0 -sticky ew");
			if (abilities[i].dtype == MINMAX) {
				tkcmd(top, "button "+frame+".bf -text {Default} -command "+
					"{send "+chanout+" setdef "+string i+"}"+butheight+tkfont);
				tkcmd(top, "grid "+frame+".bf -row 3 -column 0 -sticky ew");
			}
			count2++;
		}
	}
}

getvaluescr := array[] of {
	"frame .f -height 84 -width 114 -borderwidth 2 -relief raised",
	"label .f.l1 -text {Enter Value:} @",
	"entry .f.e1 -width 100 -bg white @",
	"button .f.b1 -text { ok } -command {send chanin ok} &",
	"button .f.b2 -text cancel -command {send chanin cancel} &",
	"grid .f.l1 -column 1 -row 0 -columnspan 2 -padx 0 -sticky w",
	"grid .f.e1 -column 1 -row 1 -columnspan 2 -padx 0 -pady 5",
	"grid .f.b1 -column 1 -row 2 -padx 0",
	"grid .f.b2 -column 2 -row 2 -padx 0",
	"grid columnconfigure .f 1 -minsize 20",
	"grid columnconfigure .f 2 -minsize 20",
	"grid columnconfigure .f 3 -minsize 5",
	"grid rowconfigure .f 0 -minsize 20",
	"grid rowconfigure .f 1 -minsize 20",
	"grid rowconfigure .f 2 -minsize 20",
	"grid columnconfigure .f 0 -minsize 5",
	"bind .f.e1 <Key> {send chanin key %s}",
	"focus .f.e1",
	"pack .f",
	"update",
};

getvaluescreen(x,y: string): int
{
	x = string ((int x) - 55);
	y = string ((int y) - 30);
	(top, nil) := tkclient->toplevel(context, "-x "+x+" -y "+y, nil, tkclient->Plain);
	chanin := chan of string;
	tk->namechan(top, chanin, "chanin");
	for (tk1 := 0; tk1 < len getvaluescr; tk1++)
		tkcmd(top, getvaluescr[tk1]);
	tkclient->onscreen(top, "exact");
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	for(;;) {
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		inp := <- chanin =>
			if (inp == "ok") return int tkcmd(top, ".f.e1 get");
			else if (inp == "cancel") return -1;
			else if (inp[:3] == "key") {
				s := " ";
				s[0] = int inp[4:];
				if (s[0] == '\n') return int tkcmd(top, ".f.e1 get");
				if (s[0] >= '0' && s[0] <= '9') {
					tkcmd(top, ".f.e1 delete sel.first sel.last");
					tkcmd(top, ".f.e1 insert insert {"+s+"}; update");
				}
			}
		}	
	}
}

infoscreen()
{
	(top, titlebar) := tkclient->toplevel(context, "", "Information", Tkclient->Hide);
	tmp := inflist;
	tkcmd(top, "frame .f");
	tkcmd(top, "label .f.l -text {Information}");
	tkcmd(top, "grid .f.l -row 0 -column 0 -columnspan 2");
	tkcmd(top, "frame .f.finfo -borderwidth 1 -relief raised");
	tkcmd(top, "grid .f.finfo");
	infrow := 0;
	while (tmp != nil) {
		infrow++;
		s := string infrow;
		(d1,d2) := hd tmp;
		tkcmd(top, "label .f.finfo.l"+s+"1 -text {"+d1+"}");
		tkcmd(top, "label .f.finfo.l"+s+"2 -text {"+d2+"}");
		tkcmd(top, "grid .f.finfo.l"+s+"1 -row "+s+" -column 0 -sticky w");
		tkcmd(top, "grid .f.finfo.l"+s+"2 -row "+s+" -column 1 -sticky e");
		tmp = tl tmp;
	}
	tkcmd(top, "pack .f; update");
	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	main: for(;;) {
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		title := <-top.ctxt.ctl or
		title = <-top.wreq or
		title = <- titlebar =>
			if (title == "exit") break main;
			tkclient->wmctl(top, title);
		}
	}
}

settingsscreen(k: int, ctlchan: chan of int)
{
	low := toplevels;
	for (;low != nil; low = tl low) {
		(tplvl, name, nil,nil) := hd low;
		if (name == ablmenu[k]) {
			tkcmd(tplvl, "raise .; focus .; update");
			ctlchan <-= DONE;
			return;
		}
	}
	pid := sys->pctl(0, nil);
	(top, titlebar) := tkclient->toplevel(context, "", "Config", Tkclient->Appl);
	chanin := chan of string;
	tk->namechan(top,chanin, "chanin");
	buildabilitiesframe(top,k, "chanin");
	tkcmd(top,"bind .Wm_t <ButtonPress-1> +{focus .}");
	tkcmd(top,"bind .Wm_t.title <ButtonPress-1> +{focus .}");
	tkcmd(top, "pack .f; update");
	err := 0;
	allread := 1;
	l : list of int = nil;
	for (i := 0; i < noabilities; i++) {
		if (matches(abilities[i].desc, ablmenu[k])) {
			l = i :: l;
			if (abilities[i].read != "")
				setmystate(top,i,abilities[i].read);
			else
				allread = 0;
		}
	}
	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	if (!allread) {
		spawn workingscreen2(getcoords(top),pid, ctlchan,0);
		ltmp := l;
		for (;ltmp != nil; ltmp = tl ltmp) {
			if (abilities[hd ltmp].read == "" && getstate(top, hd ltmp) == -1) {
				err = 1;
				break;
			}
		}
	}
	if (!err)
		spawn settingsloop(top,chanin,titlebar,k,l);
	ctlchan <-= DONE;
}

settingsloop(top: ref Tk->Toplevel, chanin,titlebar: chan of string, k: int, abls: list of int)
{
	tkcmd(top, "focus .Wm_t");
	pid := sys->pctl(0,nil);
	addtoplevel(top,ablmenu[k], abls, pid);
	ctlchan := chan of int;
	main: for(;;) {
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		inp := <- chanin =>
			tkcmd(top, "focus .");
			(n, lst) := sys->tokenize(inp, " \t\n");
			case hd lst {
				"scaleval" =>
					i := int hd tl lst;
					val := getvaluescreen(hd tl tl lst, hd tl tl tl lst);
					if (val != -1) tkcmd(top, abilities[i].location+" set "+string val+";update");
				"set" or "setdef" =>
					if (working)
						dialog(" Camera is busy! ", 2,-1,getcoords(top));
					else {
						spawn set(top, int hd tl lst, hd lst, ctlchan);
						<-ctlchan;
						working = 0;
					}
			}
			clearbuffer(chanin);
		title := <-top.ctxt.ctl or
		title = <-top.wreq or
		title = <- titlebar =>
			if (title == "exit") break main;
			tkclient->wmctl(top, title);
		}
	}
	deltoplevel(top);
}

clearbuffer(c: chan of string)
{
	tc := chan of int;
	spawn timer(tc);
	main: for (;;) alt {
		del := <-c => ;
		tick := <-tc =>		
			break main;
	}	
}

timer(tick: chan of int)
{
	sys->sleep(100);
	tick <- = 1;
}

getval(l: list of (string,int), s: string): int
{
	while (l != nil) {
		(name,val) := hd l;
		if (name == s) return val;
		l = tl l;
	}
	return -2;
}

list2string(l : list of string): string
{
	s := "";
	while (l != nil) {
		s += " " + hd l;
		l = tl l;
	}
	if (s != "") return s[1:];
	return s;
}

JPG: con 0;
THUMB: con 1;

Imgloaded: adt {
	name: string;
	imgtype: int;
};

nofiles := 0;
filelist := array[200] of string;
thumbimg := array[200] of ref draw->Image;
selected := array[200] of { * => 0 };
noselected := 0;
fnew : list of int;
imgloaded :  list of Imgloaded;
maxwidth, maxheight: int;
nothumbs := 0;

nocamera(): int
{
	(n,dir) := sys->stat(camerapath+"ctl");
	if (n != -1) return 0;
	return 1;
}

startuptkstuff(top: ref Tk->Toplevel, ctlchan: chan of int)
{
	pid := sys->pctl(0, nil);
	spawn workingscreen2(coords,pid, ctlchan,1);
	getabilities();
	(dirs,n) := readdir->init(camerapath+"thumb", readdir->NAME);
	if (n == -1) nothumbs = 1;
	buildabilitiesframes(top);
	refreshfilelist(top,0);
	ctlchan <-= DONE;
}

tibuild := 0;
butheight := "";

tkstuff()
{
	if (!runwithoutcam && nocamera()) {
		dialog("Cannot find camera!",0,-1,nilrect);
		exit;
	}
	(win, titlebar) := tkclient->toplevel(context, "", "Camera", Tkclient->Appl);
	tkcmd(win, "frame .test");
	if (tkcmd(win, ".test cget -bg") == "#ffffffff")
		tibuild = 1;
	tkcmd(win, "destroy .test");
	butheight = " -height "+string (16 + (5*tibuild) - (3*(3-ssize)));
	butchan := chan of string;
	tk->namechan(win, butchan, "butchan");
	for (tk1 := 0; tk1 < len thumbscr; tk1++)
		tkcmd(win, thumbscr[tk1]);
	coords = display.image.r;
	ctlchan := chan of int;
	imgloaded = nil;

	spawn startuptkstuff(win, ctlchan);
	e := <- ctlchan;
	if (e == KILLED) {
		dialog("Cancel during load!",0,-1,coords);
		exit;
	}
	working = 0;
	spawn mainscreen(win, 1, ctlchan);
	<- ctlchan;
	working = 0;

	processing = 0;	
	tkcmd(win, "pack propagate . 0");
	resizemain(win,1);
	tkcmd(win, "pack .f; update; focus .");
	coords = getcoords(win);
	loadimg = nil;
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd"::"ptr"::nil);
	main: for (;;) {
		alt {
		s := <-win.ctxt.kbd =>
			tk->keyboard(win, s);
		s := <-win.ctxt.ptr =>
			tk->pointer(win, *s);
		inp := <-butchan =>
			tkcmd(win, "focus .");
			(n, lst) := sys->tokenize(inp, "\t\n ");
			case hd lst {

				# Communicates internally

				"scaleval" =>
					i := int hd tl lst;
					val := getvaluescreen(hd tl tl lst, hd tl tl tl lst);
					if (val != -1) tkcmd(win, abilities[i].location+" set "+string val);
				"info" =>
					spawn infoscreen();
				"unload" =>
					i := int hd tl lst;
					for (k := 0; k < nofiles; k++) {
						if (i == k || (i == -1 && selected[k])) {
							delloaded(filelist[k],JPG);
							delloaded(filelist[k],THUMB);
						}
					}
				"invert" =>
					nf := 0;
					for (i := 0; i < nofiles; i++)
						selected[i] = 1 - selected[i];
					doselect(win);
				"selectall" =>
					val := int hd tl lst;
					for (i := 0; i < nofiles; i++)
						selected[i] = val;
					doselect(win);
				"select" =>
					i := int hd tl lst;
					selected[i] = 1 - selected[i];
					doselect(win);
				"selectonly" =>
					i := int hd tl lst;
					val := selected[i];
					for (k := 0; k < nofiles; k++)
						selected[k] = 0;
					if (noselected - val == 0) selected[i] = 1 - val;
					else selected[i] = 1;
					doselect(win);
				"menu" =>
					i := int hd tl lst;
					if (selected[i] && noselected > 1) i = -1;
					title := "Selection ("+string noselected+" files)";
					if (i != -1) title = filelist[i]+".jpg";
					si := string i;
						tkcmd(win, ".mthumb entryconfigure 0 -text {"+title+"}");
					for (k := nothumbs; k < len menu; k++)
						tkcmd(win, ".mthumb entryconfigure "+string (2+k-nothumbs)+
							" -command {send butchan "+	menu[k].com+" "+si+"}"); 
					tkcmd(win, ".mthumb post "+hd tl tl lst+" "+hd tl tl tl lst);
				* =>
					if (!processing) 
						spawn dealwithcamera(win, lst);
			}
			tkcmd(win, "update");
			clearbuffer(butchan);
		title := <-win.ctxt.ctl or
		title = <-win.wreq or
		title = <-titlebar =>
			if (title == "exit")
				break main;
			err := tkclient->wmctl(win, title);
			if (err == nil && title == "!size") {
				(n, lst) := sys->tokenize(title, " ");
				if (hd tl lst == ".")
					resizemain(win,0);
			}
			coords = getcoords(win);
		}	
	}
	for (; toplevels != nil; toplevels = tl toplevels) {
		(nil, nil, nil, pid) := hd toplevels;
		if (pid != -1)
			kill(pid);
	}
	while (imgloaded != nil) {
		(fname, ftype) := hd imgloaded;
		sys->remove(tmppath+fname+"."+string ftype+"~");
		imgloaded = tl imgloaded;
	}
	tkcmd(win, "destroy .");
	exit;
}

dealwithcamera(win: ref Tk->Toplevel, lst: list of string)
{
	ctlchan := chan of int;
	processing = 1;
	case hd lst {
		"gettime" =>
			spawn refreshtime(win, ctlchan);
			<- ctlchan;
		"show" =>
			spawn loadthumb(win,int hd tl lst,ctlchan);
			<- ctlchan;
		"snap" =>
			selected[nofiles+1] = 0;
			spawn takephoto(win, ctlchan);
			<- ctlchan;
			working = 0;
			if (fnew == nil)
				break;
			spawn waittilready(camerapath+"jpg/"+filelist[hd fnew]+".jpg", ctlchan);
			e := <- ctlchan;
			working = 0;
			if (e == DONE) {
				spawn loadnewthumb(win, ctlchan);
			 	<- ctlchan;
			 	working = 0;
			}
		"abls" =>
			spawn settingsscreen(int hd tl lst, ctlchan);
			<- ctlchan;
		"set" or "setdef" =>
			spawn set(win, int hd tl lst, hd lst, ctlchan);
			<- ctlchan;
		"del" =>
			spawn delete(win, int hd tl lst, ctlchan);
			<- ctlchan;
		"view" =>
			i := int hd tl lst;
			unnew(win, i);
			if (i == -1) multiview();
			else vw(i);
		"refresh" =>
			spawn refresh(win, ctlchan);
			<- ctlchan;
		"refreshstate" =>
			spawn mainscreen(win, 0, ctlchan);
			<- ctlchan;
		"dnld" =>
			i := int hd tl lst;
			unnew(win, i);
			if (i == -1) multidownload();
			else dnld(i, "");
		"reset" =>
			if (dialog("reset camera to default settings?",1,-1,coords)) {
				spawn resetcam(win,1, ctlchan);
				<- ctlchan;
			}
	}
	processing = 0;
	working = 0;
}

refresh(top: ref Tk->Toplevel, ctlchan: chan of int)
{
	pid := sys->pctl(0, nil);
	spawn workingscreen2(coords,pid, ctlchan,0);
	refreshfilelist(top,1);
	ctlchan <-= DONE;
}

delete(top: ref Tk->Toplevel, i: int, ctlchan: chan of int)
{
	pid := sys->pctl(0, nil);
	ok : int;
	s := "";
	loi : list of int;
	loi = nil;
	if (i == -1) {
		for (k := 0; k < nofiles; k++)
			if (selected[k]) s+= filelist[k]+".jpg\n";
		if (!dialog("Delete Selected files?\n\n"+s,1,-1,coords)) {
			ctlchan <-= DONE;
			return;
		}
	}
	else if (!dialog("Delete "+filelist[i]+".jpg?",1,i,coords)) {
		ctlchan <-= DONE;
		return;
	}
	spawn workingscreen2(coords,pid, ctlchan,0);
	s = "";
	for (k := 0; k < nofiles; k++) {
		if ((i == -1 && selected[k]) || k == i) {
			s += filelist[k]+".jpg ";
			ok = sys->remove(camerapath+
					"jpg/"+filelist[k]+".jpg");
			if (ok == -1) s+="failed\n";
			else {
				s+="ok\n";
				loi = k :: loi;
			}
		}
	}
	if (loi == nil && i != -1) {
		dialog("cannot remove "+filelist[i]+".jpg?",0,i,coords);
		ctlchan <-= DONE;
		return;
	}
	while (loi != nil) {
		delloaded(filelist[hd loi],JPG);
		delloaded(filelist[hd loi],THUMB);
		delselect(hd loi);
		loi = tl loi;
	}
	refreshfilelist(top,0);
	getstore(top);
	if (i == -1) dialog("Files deleted:\n\n"+s,0,-1,coords);
	ctlchan <-= DONE;
}

delselect(n: int)
{
	for (i := n; i < nofiles - 1; i++)
		selected[i] = selected[i+1];
	selected[nofiles - 1] = 0;
}

doselect(top: ref Tk->Toplevel)
{
	n := 0;
	for (i := 0; i < nofiles; i++) {	
		col := "white";
		if (selected[i]) {
			col = "blue";
			n++;
		}
		tkcmd(top,".fthumb.p"+string i+" configure -bg "+col);
	}
	noselected = n;
	s := " files";
	if (n == 1) s = " file";
	tkcmd(top, ".f.fsnap.fsettings.mb2 configure -text {Selected\n("+string n+s+")}");
}

takephoto(top: ref Tk->Toplevel, ctlchan: chan of int)
{
	pid := sys->pctl(0, nil);
	spawn workingscreen2(coords,pid, ctlchan,0);
	fd := sys->open(camerapath+"ctl",sys->OWRITE);
	if (fd != nil) {
		e := sys->fprint(fd, "snap");
		if (e < 0) {
			dialog("Could not take photo",0,-1,coords);
			getstore(top);
		}
		else {
			getstore(top);
			n := nofiles;
			for (i := 0; i < 5; i++) {
				refreshfilelist(top,1);
				sys->sleep(1000);
				if (nofiles > n)
					break;
			}
		}
	}
	ctlchan <-= DONE;
}

unnew(top: ref Tk->Toplevel, i: int)
{
	if (fnew == nil)
		return;
	tmp : list of int = nil;
	for (;fnew != nil; fnew = tl fnew) {
		if (i == -1 && selected[hd fnew])
			i = hd fnew;
		if (hd fnew == i)
			tkcmd(top, ".fthumb.mb"+string hd fnew+" configure -fg black; update");
		else
			tmp = hd fnew :: tmp;
	}
	fnew = tmp;
}

refreshtime(top: ref Tk->Toplevel, ctlchan: chan of int)
{
	pid := sys->pctl(0, nil);
	spawn workingscreen2(coords,pid, ctlchan,0);
	if (!samedate(top) && tkcmd(top, "variable time") == "1") settime();
	gettime(top);
	ctlchan <-= DONE;
}

addtoplevel(top: ref Tk->Toplevel, name: string, abls: list of int, pid: int)
{
	ltmp := toplevels;
	isin := 0;
	for (;ltmp != nil; ltmp = tl ltmp) {
		(tplvl, nil, nil, nil) := hd ltmp;
		if (tplvl == top) isin = 1;
	}
	if (!isin)
		toplevels = (top, name, abls, pid) :: toplevels;
}

deltoplevel(top: ref Tk->Toplevel)
{
	ltmp : list of (ref Tk->Toplevel, string, list of int, int) = nil;;
	for (;toplevels != nil; toplevels = tl toplevels) {
		(tplvl, nm, loi, p) := hd toplevels;
		if (tplvl != top) 
			ltmp = (tplvl, nm, loi, p) :: ltmp;
	}
	toplevels = ltmp;
}

resetcam(top: ref Tk->Toplevel, show: int, ctlchan: chan of int)
{
	pid := sys->pctl(0, nil);
	spawn workingscreen2(coords,pid, ctlchan,0);
	for (i := 0; i < noabilities; i++)
		setstate(i, string abilities[i].factory);
	if (show) {
		ltmp := toplevels;
		for (;ltmp != nil; ltmp = tl ltmp) {
			(tplvl, nm, loi, p) := hd ltmp;
			for (; loi != nil; loi = tl loi)
				setmystate(tplvl, hd loi, string abilities[hd loi].factory);
		}
		if (top != nil)
			getstore(top);
	}
	ctlchan <-= DONE;
}

set(top: ref Tk->Toplevel, i: int, s: string, ctlchan: chan of int)
{
	pid := sys->pctl(0, nil);
	spawn workingscreen2(getcoords(top),pid, ctlchan,0);

	val : string;
	if (s == "setdef") {
		val = string abilities[i].factory;
		setmystate(top,i,val);
	}
	else {
		if (abilities[i].dtype == MINMAX) {
			val = tkcmd(top, abilities[i].location+" get");
			mul := getval(abilities[i].data, "mul");
			val = string (int val * mul);
		}
		else {
			val = tkcmd(top, "variable "+abilities[i].pname);	
		}
	}

	e := setstate(i,val);
	if (e == 2) getstore(top);
	else if (e == 0)
		dialog("cannot communicate with camera",0,-1,coords);
	ctlchan <-= DONE;
}

setstate(i: int, val: string): int
{
	fd := sys->open(camerapath+"ctl",sys->OWRITE);
	if (fd != nil) {
		sys->fprint(fd, "%s %s",abilities[i].pname,val);
		abilities[i].read = val;
		if (abilities[i].pname == "ssiz" || abilities[i].pname == "scpn") return 2;
		return 1;
	}
	else return 0;
}

getfirst(s: string): string
{
	(n, lst) := sys->tokenize(s," \n\t");
	if (lst == nil) return "";
	return hd lst;
}

getabl(pname: string): int
{
	for (i := 0; i < noabilities; i++)
		if (abilities[i].pname == pname) return i;
	return -1;
}

getstate(top: ref Tk->Toplevel, i: int): int
{
	fd := sys->open(camerapath+"state", sys->OWRITE);
	if (fd != nil) {
		sys->fprint(fd ,"%s", abilities[i].pname);
		sys->sleep(500);
		fdi := bufio->open(camerapath+"state",sys->OREAD);
		if (fdi != nil) {
			s := fdi.gets('\n');
			if (s != nil) {
				(n,lst) := sys->tokenize(s,":\n");
				val := hd tl lst;
				setmystate(top,i,val);
			}
			return 0;
		}
	}
	dialog("cannot communicate with camera",0,-1,coords);
	return -1;
}

setmystate(top: ref Tk->Toplevel, i: int, val: string)
{
	abilities[i].read = val;
	if (abilities[i].dtype == LIST)
		tkcmd(top, "variable "+abilities[i].pname+" "+val);
	else if (abilities[i].dtype == MINMAX) {
		mul := getval(abilities[i].data, "mul");
		tkcmd(top, abilities[i].location+" set "+string((int val)/mul));
	}
	tkcmd(top, "update");
}

max(a,b: int): int
{
	if (a > b) return a;
	return b;
}

refreshfilelist(win: ref Tk->Toplevel, refresh: int): int
{
	if (refresh) {
		fd := sys->open(camerapath+"ctl",sys->OWRITE);
		if (fd == nil) {
			dialog("cannot communicate with camera",0,-1,coords);
			return -1;
		}
		else
			sys->fprint(fd, "refresh");
	}
	oldlist := filelist[:nofiles];
	for (i := 0; i < nofiles; i++) {
		si := string i;
		tk->cmd(win, "grid forget .fthumb.mb"+si+" .fthumb.p"+si);
		tk->cmd(win, "destroy .fthumb.mb"+si+" .fthumb.p"+si+" .mthumb"+si);
	}
	(dirs,n) := readdir->init(camerapath+"jpg", readdir->NAME);
	if (n == -1)
		return -1;
	nofiles = n;
	row := 0;
	col := 0;
	nocols := -1;
	w1 := int tkcmd(win, ".f.f1.c1 cget -width");
	w := 0;
	fnew = nil;
	for (i = 0; i < nofiles; i++) {
		filelist[i] = dirs[i].name;
		if (len filelist[i] > 3 && filelist[i][len filelist[i] - 4] == '.')
			filelist[i] = filelist[i][:len filelist[i]-4];
		
		isnew := 1;
		for (k := 0; k < len oldlist; k++) {
			if (filelist[i] == oldlist[k]) {
				isnew = 0;
				break;
			}
		}
		si := string i;
		tkcmd(win, "menubutton .fthumb.mb"+si+" -bg white " +
			"-text {"+filelist[i]+".jpg} -menu .mthumb"+si+tkfontf);
		if (isnew && refresh) {
			fnew = i :: fnew;
			tkcmd(win, ".fthumb.mb"+si+" configure -fg red");
		}
		thumbimg[i] = display.newimage(Rect((0,0),(90,90)),draw->RGB24,0,int 16rffcc00ff);
		e := tkcmd(win,"panel .fthumb.p"+si+" -borderwidth 2 -bg white"+
					" -height 90 -width 90 -relief raised");
		tk->putimage(win,".fthumb.p"+si, thumbimg[i],nil);
		tkcmd(win, "bind .fthumb.p"+si+" <Double-Button-1> {send butchan view "+si+"}");
		tkcmd(win, "bind .fthumb.p"+si+" <ButtonPress-1> {send butchan selectonly "+si+"}");
		tkcmd(win, "bind .fthumb.p"+si+" <ButtonPress-2> {send butchan select "+si+"}");
		tkcmd(win, "bind .fthumb.p"+si+" <ButtonPress-3> {send butchan menu "+si+" %X %Y}");
		thisw := int tkcmd(win, ".fthumb.mb"+si+" cget -width");
		w += max(94, thisw);
		if ((nocols == -1 && w >= w1-(col*2)) || col == nocols) {
			nocols = col;
			col = 0;
			row+=2;
			w = thisw;
		}
		if (col == 0)
			tkcmd(win, "grid rowconfigure .fthumb "+string (row+1)+
						" -minsize "+string (105 - 2*(3-ssize)));

		tkcmd(win, "grid .fthumb.mb"+si+" -row "+string row+" -column "+string col);
		tkcmd(win, "grid .fthumb.p"+si+" -row "+string (row+1)+" -column "+string col+" -sticky n");

		tkcmd(win, "menu .mthumb"+si+tkfont);
		for (k = nothumbs; k < len menu; k++)
			tkcmd(win, ".mthumb"+si+" add command -text {"+menu[k].text+"} " +
				"-command {send butchan "+menu[k].com+" "+si+"}");
		
		if (isloaded(filelist[i],THUMB) && usecache)
			loadthumbnail(win,i);
		col++;
	}
	if (row == 0)
		nocols = col;
	doselect(win);
	size := tkcmd(win, "grid size .fthumb");
	csize := int size[:isat(size, " ")];
	rsize := int size[isat(size, " ")+1:];
	if (csize > nocols)
		tkcmd(win, "grid columndelete .fthumb "+string nocols+" "+string csize);
	if (rsize > row+1)
		tkcmd(win, "grid rowdelete .fthumb "+string (row+2)+" "+string rsize);
	height := string (2 + int tkcmd(win, ".fthumb cget -height"));
	width := tkcmd(win, ".f.f1.c1 cget -width");
	colsize : int;
	if (nocols > 0) colsize = int width / nocols;
	else colsize = int width;
	for (i = 0; i < nocols; i++)
			tkcmd(win, "grid columnconfigure .fthumb "+string i+" -minsize "+string colsize);

	tkcmd(win, ".f.f1.c1 configure -scrollregion { 0 0 "+width+" "+height+"}");
	tkcmd(win, "update");
	return 0;
}

Mtype: adt {
	text, com: string;
};

menu := array[] of {
	Mtype ("Show Thumbnail", "show"),
	Mtype ("Download", "dnld"),
	Mtype ("View", "view"),
	Mtype ("Delete", "del"),
	Mtype ("Clear Cache", "unload"),
	Mtype ("Refresh Files", "refresh"),
};

tkcmd(top: ref Tk->Toplevel, cmd: string): string
{
	if (cmd[len cmd - 1] == '$')
		cmd = cmd[:len cmd - 1] + tkfontb;
	else if (cmd[len cmd - 1] == '@')
		cmd = cmd[:len cmd - 1] + tkfont;
	if (cmd[len cmd - 1] == '&')
		cmd = cmd[:len cmd - 1] + butheight+tkfont;
	
	e := tk->cmd(top, cmd);
	if (e != "" && e[0] == '!') sys->print("tk error: '%s': %s\n",cmd,e);
	return e;
}

loadnewthumb(top: ref Tk->Toplevel, ctlchan: chan of int)
{
	pid := sys->pctl(0,nil);
	spawn workingscreen2(coords,pid, ctlchan,0);
	getstore(top);
	for (tmp := fnew; tmp != nil; tmp = tl tmp)
		loadthumbnail(top,hd tmp);
	ctlchan <-= DONE;
}

loadthumb(top: ref Tk->Toplevel, i: int, ctlchan: chan of int)
{
	pid := sys->pctl(0, nil);
	spawn workingscreen2(coords,pid, ctlchan,0);
	if (i == -1) {
		for (k := 0; k < nofiles; k++)
			if (selected[k])
				if (loadthumbnail(top, k) != 0) break;
	}
	else loadthumbnail(top, i);
	ctlchan <-= DONE;
}

loadthumbnail(top: ref Tk->Toplevel, i: int): int
{
	fd : ref sys->FD;
	if (usecache && isloaded(filelist[i],THUMB))
		fd  = sys->open(tmppath+filelist[i]+"."+string THUMB+"~",sys->OREAD);
	else fd = sys->open(camerapath+"thumb/"+filelist[i]+".bit",sys->OREAD);
	if (fd == nil) {
		if (usecache && isloaded(filelist[i],THUMB)) {
			delloaded(filelist[i],THUMB);
			return loadthumbnail(top,i);
		}
		else dialog("cannot open "+filelist[i]+".bit",0,-1,coords);
		return -2;
	}
	image := display.readimage(fd);
	if (image == nil) {
		if (usecache && isloaded(filelist[i],THUMB)) {
			delloaded(filelist[i],THUMB);
			return loadthumbnail(top,i);
		}
		else dialog("Could not load thumbnail: "+filelist[i]+".jpg",0,-1,coords);
		return -1;
	}
	else {
		p := Point((90-image.r.max.x)/2,(90-image.r.max.y)/2);
		thumbimg[i].draw(image.r.addpt(p), image,nil,(0,0));
		si := string i;
		tkcmd(top,".fthumb.p"+si+" dirty");
		fd = nil;
		n := -1;
		if (usecache) {
			fd  = sys->create(tmppath+filelist[i]+"."+string THUMB+"~",sys->OWRITE,8r666);
			n = display.writeimage(fd, image);
		}
		x := int tkcmd(top, ".fthumb.mb"+string i+" cget -actx");
		y := int tkcmd(top, ".fthumb.mb"+string i+" cget -acty");
		h := int tkcmd(top, ".fthumb.mb"+string i+" cget -height");
		x1 := int tkcmd(top, ".fthumb cget -actx");
		y1 := int tkcmd(top, ".fthumb cget -acty");
		tkcmd(top, ".f.f1.c1 see "+string (x-x1)+" " +string (y-y1)+
			" "+string (x-x1+90)+" " +string (y-y1+h+102)+"; update");
		if (!usecache || n == 0) imgloaded = (filelist[i],THUMB) :: imgloaded;
	}
	return 0;
}

isloaded(name: string, ftype: int): int
{
	tmp := imgloaded;
	while (tmp != nil) {
		ic := hd tmp;
		if (ic.name == name && ic.imgtype == ftype) return 1;
		tmp = tl tmp;
	}
	return 0;
}

delloaded(name: string, ftype: int)
{
	tmp :  list of Imgloaded;
	tmp = nil;
	while (imgloaded != nil) {
		ic := hd imgloaded;
		if (ic.name != name || ic.imgtype != ftype)
			tmp = ic :: tmp;
		else sys->remove(tmppath+ic.name+"."+string ic.imgtype+"~");
		imgloaded = tl imgloaded;
	}
	imgloaded = tmp;
}

dialog(msg: string, diagtype, img: int, r: Rect): int
{
	if (diagtype == 2)
		diagtype = 0;
	else 
		working = 0;
	tmpimg : ref draw->Image;
	out := 0;
	title := "Dialog";
	if (diagtype == 0) title = "Alert!";
	(win, titlebar) := tkclient->toplevel(context, "" , title, Tkclient->Appl);
	diagchan := chan of string;
	tk->namechan(win, diagchan, "diagchan");
	tkcmd(win, "frame .f");
	tkcmd(win, "label .f.l -text {"+msg+"}"+tkfont);
	tkcmd(win, "button .f.bo -text { ok } -command {send diagchan ok} "+butheight+tkfont);
	tkcmd(win, "button .f.bc -text {cancel} -command {send diagchan cancel}"+butheight+tkfont);
	if (img >= 0 && isloaded(filelist[img], THUMB) && usecache) {
		fd := sys->open(tmppath+filelist[img]+"."+string THUMB+"~", sys->OREAD);
		if (fd != nil) {
			tmpimg = display.readimage(fd);
			tkcmd(win,"panel .f.p -height "+string tmpimg.r.max.y+
				" -width "+string tmpimg.r.max.x+" -borderwidth 2 -relief raised");
			tk->putimage(win,".f.p", tmpimg, nil);
			tkcmd(win, "grid .f.p -row 1 -column 0 -columnspan 2 -padx 5 -pady 5");
		}
	}
	tkcmd(win, "grid .f.l -row 0 -column 0 -columnspan 2 -padx 10 -pady 5");
	if (diagtype == 1) {
		tkcmd(win, "grid .f.bo -row 2 -column 0 -padx 5 -pady 5");
		tkcmd(win, "grid .f.bc -row 2 -column 1 -padx 5 -pady 5");
	}
	else 	tkcmd(win, "grid .f.bo -row 2 -column 0 -columnspan 2 -padx 5 -pady 5");
	if (!r.eq(nilrect))
		centrewin(win, r, 1);
	else
		tkcmd(win, "pack .f; focus .; update");
	tkclient->onscreen(win, "exact");
	tkclient->startinput(win, "kbd"::"ptr"::nil);
	main: for (;;) {
		alt {
		s := <-win.ctxt.kbd =>
			tk->keyboard(win, s);
		s := <-win.ctxt.ptr =>
			tk->pointer(win, *s);
		inp := <-diagchan =>
			if (inp == "ok") {
				out = 1;
				break main;
			}
			if (inp == "cancel")
				break main;

		title = <-win.ctxt.ctl or
		title = <-win.wreq or
		title = <-titlebar =>
			if (title == "exit")
				break main;
			else
				tkclient->wmctl(win, title);
		}
	}
	return out;
}	

snapscr := array[] of {
	"label .f.fsnap.ltime -text {Date and Time} $",
	"label .f.fsnap.lstore -text {Memory Status} $",
	"label .f.fsnap.lzpos -text {Zoom} $",
	"label .f.fsnap.lssiz -text {Resolution} $",
	"label .f.fsnap.lscpn -text {Compression} $",
	"grid .f.fsnap.ltime -row 0 -column 0 -sticky sw",
	"grid .f.fsnap.lstore -row 0 -column 1 -sticky sw",
	"grid .f.fsnap.lscpn -row 2 -column 0 -sticky sw",
	"grid .f.fsnap.lssiz -row 2 -column 1 -sticky sw",
	"grid .f.fsnap.lzpos -row 2 -column 2 -sticky sw",

	"grid .f.fsnap.ftime -row 1 -column 0  -sticky nsew",
	"grid .f.fsnap.fstore -row 1 -column 1  -sticky nsew",
	"grid .f.fsnap.fsettings -row 1 -column 2  -sticky nsew",
	"grid .f.fsnap.fscpn -row 3 -column 0  -sticky nsew",
	"grid .f.fsnap.fssiz -row 3 -column 1 -sticky nsew",
	"grid .f.fsnap.fzpos -row 3 -column 2  -sticky nsew",
	"grid .f.fsnap.b -row 4 -column 0 -columnspan 3",
	"grid rowconfigure .f.fsnap 0 -minsize 30",
	"grid rowconfigure .f.fsnap 2 -minsize 30",
	"grid rowconfigure .f.fsnap 4 -minsize 30",

	"update",
};

mainscreen(win: ref Tk->Toplevel, opt: int, ctlchan: chan of int)
{
	pid := sys->pctl(0, nil);
	spawn workingscreen2(coords, pid, ctlchan, opt);
	if (opt == 1) {
		for (tk1 := 0; tk1 < len snapscr; tk1++)
			tkcmd(win, snapscr[tk1]);

		gettime(win);
		if (samedate(win)) tkcmd(win, "variable time 1; update");
	}
	getstore(win);
	lst := getabl("scpn") :: getabl("ssiz") :: getabl("zpos") :: nil;
	if (getstate(win, hd tl tl lst) == 0);
		if (getstate(win, hd tl lst) == 0);
			getstate(win, hd lst);
	if (opt == 1) {
		addtoplevel(win, "", lst, -1);
		height := tkcmd(win, ".f.fsnap cget -height");
		width := tkcmd(win, ".f.fsnap cget -width");
#		tkcmd(win, ".f.f2.c1 configure -scrollregion { 0 0 "+width+" "+height+"}");
#		tkcmd(win, ".f.f2.c1 configure -height "+height+"}");
	}
	ctlchan <-= DONE;
}

kill(pid: int)
{	
	pctl := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE);
	if (pctl != nil)
		sys->write(pctl, array of byte "kill", len "kill");
}

gettime(win: ref Tk->Toplevel)
{
	tkcmd(win,".f.fsnap.ftime.l3 configure -text {}"+tkfont);
	tkcmd(win,".f.fsnap.ftime.l4 configure -text {}"+tkfont);
	fdi := bufio->open(camerapath+"date",sys->OREAD);
	if (fdi != nil) {
		s := fdi.gets('\n');
		if (s != nil) {
			if (s[len s - 1] == '\n') s = s[:len s - 1];
			tm := daytime->local(daytime->now());
			time := sys->sprint("%d/%d/%d %d:%d:%d", tm.mon+1, tm.mday, tm.year-100,
							tm.hour,tm.min,tm.sec);
			ltime = addzeros(time);
			ctime = addzeros(s[len "date is ":]);
			tk->cmd(win,".f.fsnap.ftime.l3 configure -text {"+ltime+"}");
			tk->cmd(win,".f.fsnap.ftime.l4 configure -text {"+ctime+"}");
		}
	}
	if (len ltime < 16)
		ltime = "??/??/?? ??:??:??";
	if (len ctime < 16)
		ctime = "??/??/?? ??:??:??";
	tkcmd(win, "update");
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

samedate(win: ref Tk->Toplevel): int
{
	s1 := tkcmd(win, ".f.fsnap.ftime.l3 cget -text");
	s2 := tkcmd(win, ".f.fsnap.ftime.l4 cget -text");
	if (s1 == "" || s1 == "") return 0;
	if (s1[:len s1 - 3] == s2[:len s2 - 3]) return 1;
	return 0;
}

settime()
{
	tm := daytime->local(daytime->now());
	fd := sys->open(camerapath+"date", sys->OWRITE);
	if (fd != nil) {
		sys->fprint(fd, "%s", addzeros(sys->sprint("%d/%d/%d %d:%d:%d"
			,tm.mon+1, tm.mday, tm.year-100, tm.hour,tm.min,tm.sec)));
	}
}

getstore(win: ref Tk->Toplevel)
{
	fdi := bufio->open(camerapath+"storage",sys->OREAD);
	if (fdi != nil) {
		for(i := 0; i < 3; i++) {
			s := fdi.gets('\n');
			if (s == nil) break;
			if (i > 0) {
				(n,lst) := sys->tokenize(s,"\t\n:");
				val := string int hd tl lst;
				if (i == 2 && val == "0") 
					tkcmd(win, ".f.fsnap.b configure -state disabled");
				else tkcmd(win, ".f.fsnap.b configure -state normal");
				tkcmd(win,".f.fsnap.fstore.l"+string (2+i)+" configure -text {"+val+"  }");
			}
		}
		tkcmd(win, "update");	
	}
}

contains(s: string, test: string): int
{
	num :=0;
	if (len test > len s) return 0;
	for (i := 0; i < (1 + (len s) - (len test)); i++) {
		if (test == s[i:i+len test]) num++;
	}
	return num;
}

multidownload()
{
	getpath := selectfile->filename(context,
							display.image,
							"Multiple download to directory...", 
							nil,
							lastpath);
	if (getpath == "" || getpath[0] != '/' || getpath[len getpath - 1] != '/')
		return;
	s := "";
	for (k := 0; k < nofiles; k++) {
		if (selected[k]) {
			e := dnld(k,getpath);
			if (e != 1) 
				s += filelist[k]+".jpg ";
			if (e == 3) {
				s += "cancelled\n";
				break;
			}
			else if (e == 0)
				s += "failed\n";
			working = 0;
		}
	}
	if (s != "") s = ":\n\n"+s;
	dialog("Multiple download complete"+s,0,-1,coords);
}

downloading := "";

dnld(i: int, path: string): int
{
	ctlchan := chan of int;
	ctlchans := chan of string;
	chanout := chan of string;
	spawn downloadscreen(coords, i, ctlchans, chanout);
	spawn download(i,path,ctlchan, ctlchans, chanout);
	pid := <-ctlchan;
	alt {
		s := <-ctlchans =>
			chanout <-= "!done!";
			if (s == "kill") {
				if (downloading != "") {
					(n,lst) := sys->tokenize(downloading, " \t\n");
					for(;lst != nil; lst = tl lst)
						sys->remove(hd lst);
				}
				kill(pid);
				return 3;
			}
			else return dnld(i, "!"+s);
		e := <-ctlchan =>
			chanout <-= "!show!";
			chanout <-= "!done!";
			return e;
	}
	return 0;
}

filelenrefresh(filename: string): int
{
	fd := sys->open(camerapath+"ctl",sys->OWRITE);
	if (fd != nil) {
		sys->fprint(fd, "refresh");
		(n, dir) := sys->stat(filename);
		if (n == -1)
			return -1;
		return int dir.length;
	}
	return -1;
}

testfilesize(filename: string): int
{
	e := filelenrefresh(filename);
	if (e == 0) {
		e2 := dialog("Camera is still processing image\nwait until ready?",1,-1,coords);
		if (e2 == 0)
			return 0;
		ctlchan := chan of int;
		spawn waittilready(filename, ctlchan);
		e3 := <- ctlchan;
		working = 0;
		if (e3 == KILLED)
			return 0;
		return testfilesize(filename);
	}
	else return e;
}

waittilready(filename: string, ctlchan: chan of int)
{
	pid := sys->pctl(0, nil);
	spawn workingscreen2(coords,pid,ctlchan,0);
	for (;;) {
		if (filelenrefresh(filename) != 0)
			break;
		sys->sleep(2000);
	}
	ctlchan <-= DONE;
}

download(i: int, path: string, ctlchan: chan of int, ctlchans, chanout: chan of string)
{
	ctlchan <-= sys->pctl(0, nil);
	downloading = "";
	savename : string;
	if (path == "") {
		savename = selectfile->filename(context,
								display.image,
								"Save "+filelist[i]+".jpg to directory...", 
								"*.jpg" :: "*.jpeg" :: nil,
								lastpath);
		if (savename == "" || savename[0] != '/') {
			ctlchan <-= 0;
			return;
		}
	}
	else savename = path;

	# Used when retrying due to cache copy failing
	if (savename[0] == '!') {
		delloaded(filelist[i],JPG);
		savename = savename[1:];
		path = "";
	}
	confirm := 1;
	# Don't confirm overwrite
	if (savename[0] == '$') {
		confirm = 0;
		savename = savename[1:];
	}

	if (savename[len savename - 1] == '/')
		savename += filelist[i]+".jpg";

	if (!hasext(savename, ".jpg"))
		savename += ".jpg";

	p := isat2(savename,"/");
	lastpath = savename[:p+1];

	filename := camerapath+"jpg/"+filelist[i]+".jpg";
	filesize := testfilesize(filename);
	cached := 0;
	if (filesize > 0 && isloaded(filelist[i],JPG) && usecache) {
		cachefilename := tmppath+filelist[i]+"."+string JPG+"~";
		if (testfilesize(cachefilename) == filesize) {
			cached = 1;
			filename = cachefilename;
		}
		else delloaded(filelist[i],JPG);
	}
	fd := sys->open(filename, sys->OREAD);
	if (filesize < 1 || fd == nil) {
		ctlchan <-= -1;
		return;
	 }

	read := 0;
	cancel : int;
	buf : array of byte;
	fd2, fd3 : ref sys->FD = nil;
	cachename := tmppath+filelist[i]+"."+string JPG+"~";
	if (confirm) (fd2, cancel) = create(savename, coords);
	else fd2 = sys->create(savename,sys->OWRITE, 8r666);
	if (fd2 == nil) {
		ctlchan <-= cancel;
		return;
	}
	if (usecache && !cached)
		fd3 = sys->create(cachename,sys->OWRITE,8r666);
	chanout <-= "!show!";
	chanout <-= "l2 Downloading...";
	chanout <-= "pc 0";
	n : int;
	downloading = savename;
	if (fd3 != nil)
		downloading += " "+cachename;
	loop: for(;;) {
		rlen := 8192;
		if (read + rlen >= filesize) rlen = filesize - read;
		buf = array[rlen] of byte;
		n = sys->read(fd,buf,len buf);
		read += n;
		sout := "pc "+string ( (100*read)/filesize);
		chanout <-= sout;
		if (n < 1) break loop;
		written := 0;
		while (written < n) {
			n2 := sys->write(fd2,buf,n);
			if (n2 < 1) break loop;
			if (fd3 != nil) sys->write(fd3,buf,n);
			written += n2;
		}
	}
	chanout <-= "pc 100";
	downloading = "";
	fd = nil;
	fd2 = nil;
	if (read < filesize || n == -1) {
		if (cached) {
			ctlchans <-= savename;
			return;
		}
		sys->remove(savename);
		sys->remove(cachename);
		if (path == "")
			dialog(sys->sprint("Download Failed: %s.jpg\nread %d of %d bytes\n",
					filelist[i],read,filesize), 0, i,coords);
		ctlchan <-= 0;
		return;
	}
	
	# save it in cache 
	if (usecache)
		imgloaded = (filelist[i],JPG) :: imgloaded;
	if (path == "") dialog(filelist[i]+".jpg downloaded",0,i,coords);
	ctlchan <-= 1;
}

downloadscr := array[] of {
	"frame .f -borderwidth 2 -relief raised",
	"label .f.l1 -text { } @",
	"label .f.l2 -text {Waiting...} @",
	"button .f.b -text {Cancel} -command {send ctlchans kill} &",
	"grid .f.l1 -row 0 -column 0 -columnspan 2 -pady 5",
	"grid .f.l2 -row 2 -column 1 -sticky w -padx 10",
	"grid .f.p -row 3 -column 1 -columnspan 1 -padx 10",
	"grid .f.b -row 4 -column 0 -pady 5 -columnspan 2",
};

downloadscreen(r: Rect, i: int, ctlchans, chanin: chan of string)
{
	working = 1;
	<- chanin;
	(top, nil) := tkclient->toplevel(context,"", nil, tkclient->Plain);
	progr := Rect((0,0),(100,15));
	imgbg := display.newimage(progr,draw->CMAP8,1,draw->Black);
	black := display.newimage(progr,draw->CMAP8,1,draw->Black);
	white := display.newimage(progr,draw->CMAP8,1,draw->White);
	imgfg := display.newimage(progr,draw->CMAP8,1,draw->Blue);
	tkcmd(top, "panel .f.p -width 100 -height 15 -bg white -borderwidth 2 - relief raised");
	tk->putimage(top, ".f.p",imgbg,nil);
	tk->namechan(top, ctlchans, "ctlchans");
	for (tk1 := 0; tk1 < len downloadscr; tk1++)
		tkcmd(top, downloadscr[tk1]);
	tmpimg : ref Image = nil;
	if (i >= 0 && isloaded(filelist[i], THUMB) && usecache)
		tmpimg = display.open(tmppath+filelist[i]+"."+string THUMB+"~");
	if (tmpimg == nil)
		tmpimg = procimg;
	if (tmpimg != nil) {
		w := tmpimg.r.dx();
		h := tmpimg.r.dy();
		tkcmd(top, "panel .f.p2 -width "+string w+" -height "+string h+
					" -borderwidth 2 -relief raised");
		tk->putimage(top, ".f.p2", tmpimg, nil);
		tkcmd(top, "grid .f.p2 -row 2 -column 0 -rowspan 2 -sticky e");
		tkcmd(top, "grid columnconfigure .f 0 -minsize "+string (w + 14));
	}

	tkcmd(top, ".f.l1 configure -text {"+filelist[i]+".jpg}");
	centrewin(top,r,1);
	oldcoords := coords;
	tkclient->onscreen(top, "exact");
	tkclient->startinput(top, "kbd"::"ptr"::nil);

	main: for (;;) {
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		text := <-chanin =>
			if (!oldcoords.eq(coords)) {
				centrewin(top,coords,0);
				oldcoords = coords;
			}
			if (text == "!done!") break main;
			if (text[:2] == "pc") {
				val := int text[3:];
				imgbg.draw(((0,0),(val,15)), imgfg,nil,(0,0));
				if (val != 100)
					imgbg.draw(((val+1,0),(100,15)), black,nil,(0,0));
				imgbg.text((42,1),white,(0,0),font, text[3:]+"%");
				tkcmd(top,".f.p dirty; update");
			}
			else if (text[:2] == "l2")
				tkcmd(top, ".f.l2 configure -text {"+text[3:]+"}; update");
		}
	}
	working = 0;
}

centrewin(top: ref Tk->Toplevel, r: Rect, first: int)
{
	s := "";
	if (first)
		s = "pack .f;";
	w := int tkcmd(top, ".f cget -width");
	h := int tkcmd(top, ".f cget -height");
	tmp := tk->cmd(top, ".Wm_t cget -height");
	if (tmp != "" && tmp[0] != '!') {
		h += int tmp;
		s += "focus .;";
	}
	px := r.min.x + ((r.max.x - r.min.x - w) / 2);
	py := r.min.y + ((r.max.y - r.min.y - h) / 2);
	tkcmd(top, ". configure -x "+string px+" -y "+string py);
	tkcmd(top, s+"raise .; update");
}

workingscr2 := array[] of {
	"frame .f -borderwidth 2 -relief raised",
	"label .f.l3 -text { } -width 220 -height 2",
	"label .f.l -text {Please Wait} @",
	"label .f.l2 -text {|} -width 20 @",
	"button .f.b -text {Cancel} -command {send chanin kill} &",
	"grid .f.l -row 1 -column 0 -sticky e",
	"grid .f.l2 -row 1 -column 1 -sticky w",
	"grid .f.b -pady 5 -row 3 -column 0 -columnspan 2",
	"grid .f.l3 -row 4 -column 0 -columnspan 2",
	"grid rowconfigure .f 1 -minsize 80",
};

workingscreen2(r : Rect, pid: int, ctlchan: chan of int, loading: int)
{
	(top, nil) := tkclient->toplevel(context,"",nil, tkclient->Plain);
	chanin := chan of string;
	tk->namechan(top, chanin, "chanin");
	for (tk1 := 0; tk1 < len workingscr2; tk1++)
		tkcmd(top, workingscr2[tk1]);

	if (loading) {
#		loadimg := display.open("camload.bit");
		if (loadimg != nil) {
			w := loadimg.r.dx();
			h := loadimg.r.dy();
			tkcmd(top, "panel .f.p -width "+string w+" -height "+string h+
						" -borderwidth 2 -relief raised");
			tk->putimage(top, ".f.p", loadimg, nil);
			tkcmd(top, "grid .f.p -row 2 -column 0 -columnspan 2 -pady 5 -padx 20");
			tkcmd(top, "grid forget .f.l .f.l2; grid rowconfigure .f 1 -minsize 20");
		}
	}
	else {
		if (procimg != nil) {
			w := procimg.r.dx();
			h := procimg.r.dy();
			tkcmd(top, "panel .f.p -width "+string w+" -height "+string h+
						" -borderwidth 2 -relief raised");
			tk->putimage(top, ".f.p", procimg, nil);
			tkcmd(top, "grid .f.p -row 2 -column 0 -columnspan 2");
			tkcmd(top, "grid rowconfigure .f 1 -minsize 30");
			tkcmd(top, "grid rowconfigure .f 2 -minsize 50");
		}
	}

	centrewin(top,r,1);
	spawn workingupdate(top,chanin);
	tkclient->onscreen(top, "exact");
	tkclient->startinput(top, "kbd"::"ptr"::nil);

	main: for (;;) {
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		inp := <-chanin =>
			if (inp == "done") break main;
			if (inp == "kill") {
				working = 0;
				if (pid != -1) kill(pid);
				ctlchan <-= KILLED;
				<-chanin;
				break main;
			}
		}
	}
}

workingupdate(top: ref Tk->Toplevel, chanout: chan of string)
{
	show := array[] of { "/", "-", "\\\\", "|", };
	if (working) {
		chanout <-= "done";
		return;
	}
	working = 1;
	oldcoords := coords;
	hidden := 0;
	loop: for(;;) {
		for (i := 0; i < 4; i++) {
			sys->sleep(100);
			tkcmd(top, ".f.l2 configure -text {"+show[i]+"}; update");
			if (!working) break loop;
			if (!oldcoords.eq(coords)) {
				centrewin(top, coords,0);
				oldcoords = coords;
			}
		}
	}
	chanout <-= "done";
}

scrollx := 0;
scrolly := 0;

resizemain(top: ref Tk->Toplevel, init: int)
{
	h, w: int;
	if (init) {
		growheight(top, 4000);
		h = int tkcmd(top, ".f.fsnap cget -height") +
			int tkcmd(top, ".Wm_t cget -height") +
			2 * (124 - (5*(3-ssize)));
		if (h > display.image.r.dy())
			h = display.image.r.dy();
		w = display.image.r.dx();
	}
	else {
		r := tk->rect(top, ".", 0);
		h = r.dy();
		w = r.dx();	
	}

	ht := int tkcmd(top, ".Wm_t cget -height");

	hf := int tkcmd(top, ".f cget -height");
	wf := int tkcmd(top, ".f cget -width");
	wsb := int tkcmd(top, ".f.f1.sb1 cget -width");

	growwidth(top, w - 4);
	ws := int tkcmd(top, ".f.fsnap cget -width");
	if (w > ws + 4)
		w = ws + 4;
	shrinkwidth(top,w - 4);
	ws = int tkcmd(top, ".f.fsnap cget -width");
	if (w < ws || init)
		w = ws + 4;
		
	hmax := ((3*(h - ht))/5) - 4;
	growheight(top, hmax);
	shrinkheight(top, hmax);
	hs := int tkcmd(top, ".f.fsnap cget -height");

	hmb := int tkcmd(top, ".f.fsnap.fsettings.mb cget -height");
	if (h < ht+hs + 107 + hmb) h = ht+hs+107 + hmb;

#	hc2 = int tkcmd(top, ".f.fsnap cget -height");
	wc2 := int tkcmd(top, ".f.fsnap cget -width");

	hc1 := h - ht - hs - 4;
	wc1 := w-wsb-4;
#	wc1 = wc2 - wsb;
	tkcmd(top, ".f.f1.c1 configure -height "+string hc1+" -width "+string wc1);
#	tkcmd(top, ".f.f2.c1 configure -height "+string hc2+" -width "+string wc2);
	if (w < wc2 + 4)
		w = wc2 + 4;
	ws = int tkcmd(top, ".f.fsnap cget -width");
	hs = int tkcmd(top, ".f.fsnap cget -height");
		
	tkcmd(top, ". configure -height "+string h+" -width "+string w+"; update");
	refreshfilelist(top, 0);
}

growwidth(top: ref Tk->Toplevel, wc2: int)
{
	ws := int tkcmd(top, ".f.fsnap cget -width");
	if (wc2 > ws && reducew[2]) {
		tkcmd(top, ".f.fsnap.ftime.l1 configure -text {Local:}");
		tkcmd(top, ".f.fsnap.ftime.l2 configure -text {Camera:}");
		tkcmd(top, ".f.fsnap.ftime.cb configure -text {Set to local time}");
		reducew[2] = 0;
	}
	ws = int tkcmd(top, ".f.fsnap cget -width");
	if (wc2 > ws && reducew[1]) {
		tkcmd(top, ".f.fsnap.ftime.l3 configure -text {"+ltime+"}");
		tkcmd(top, ".f.fsnap.ftime.l4 configure -text {"+ctime+"}");
		tkcmd(top, ".f.fsnap.ftime.cb configure -text {Set camera to local time}");
		reducew[1] = 0;
	}
	ws = int tkcmd(top, ".f.fsnap cget -width");
	if (wc2 > ws && reducew[0]) {
		tkcmd(top, ".f.fsnap.fstore.l1 configure -text {  Photos taken:}");
		reducew[0] = 0;
	}
	ws = int tkcmd(top, ".f.fsnap cget -width");
	if (wc2 > ws) {
		wfs += wc2 - ws;
		if (wfs > 125-(20*(3-ssize))) wfs = 125-(20*(3-ssize));
		tkcmd(top, "grid columnconfigure .f.fsnap 2 -minsize "+string wfs);
	}
}

growheight(top: ref Tk->Toplevel, hc2: int)
{
	hs := int tkcmd(top, ".f.fsnap cget -height");
	if (hc2 > hs) {
		tk->cmd(top, "grid .f.fsnap.fsettings.mb2 -row 2 -column 0 -sticky ew");
		tk->cmd(top, "grid .f.fsnap.ftime.cb -row 2 -column 0 -columnspan 2");
		tk->cmd(top, "grid .f.fsnap.ftime.b -row 3 -column 0 -columnspan 2");
	}
	hs = int tkcmd(top, ".f.fsnap cget -height");
	if (hc2 > hs) {
		hsc := int tkcmd(top, ".f.fsnap.fzpos.sc cget -height");
		hsc += hc2 - hs;
		if (hsc > 88-(10*(3-ssize))) hsc = 88-(10*(3-ssize));
		tkcmd(top, ".f.fsnap.fzpos.sc configure -height "+string hsc);
	}
	hs = int tkcmd(top, ".f.fsnap cget -height");
	if (hc2 > hs) {
		hfs += hc2 - hs;
		if (hfs > 30 - (5*(3-ssize))) hfs = 30- (5*(3-ssize));
		tkcmd(top, "grid rowconfigure .f.fsnap 0 -minsize "+string hfs);
		tkcmd(top, "grid rowconfigure .f.fsnap 2 -minsize "+string hfs);
		tkcmd(top, "grid rowconfigure .f.fsnap 4 -minsize "+string hfs);
	}
}

shrinkheight(top: ref Tk->Toplevel, hc2: int)
{
	hs := int tkcmd(top, ".f.fsnap cget -height");
	if (hc2 < hs) {
		hfs -= hs - hc2;
		if (hfs < 15) hfs = 15;
		tkcmd(top, "grid rowconfigure .f.fsnap 0 -minsize "+string hfs);
		tkcmd(top, "grid rowconfigure .f.fsnap 2 -minsize "+string hfs);
		tkcmd(top, "grid rowconfigure .f.fsnap 4 -minsize "+string hfs);
	}
	hs = int tkcmd(top, ".f.fsnap cget -height");
	if (hc2 < hs) {
		hsc := int tkcmd(top, ".f.fsnap.fzpos.sc cget -height");
		hsc -= hs - hc2;
		if (hsc < 55-(5*(3-ssize))) hsc = 55-(5*(3-ssize));
		tkcmd(top, ".f.fsnap.fzpos.sc configure -height "+string hsc);
	}
	hs = int tkcmd(top, ".f.fsnap cget -height");
	if (hc2 < hs) {
		tk->cmd(top, "grid forget .f.fsnap.fsettings.mb2");
		tk->cmd(top, "grid forget .f.fsnap.ftime.cb");
		tk->cmd(top, "grid forget .f.fsnap.ftime.b");
	}
}

shrinkwidth(top: ref Tk->Toplevel, wc2: int)
{
	ws := int tkcmd(top, ".f.fsnap cget -width");
	wib := int tkcmd(top, ".f.fsnap.fsettings.b cget -width");
	if (wc2 < ws) {
		diff := ws - wc2;
		wfs -= diff;
		if (wfs < wib) wfs = wib;
		tkcmd(top, "grid columnconfigure .f.fsnap 2 -minsize "+string wfs);
	}
	ws = int tkcmd(top, ".f.fsnap cget -width");
	if (wc2 < ws) {
		tkcmd(top, ".f.fsnap.fstore.l1 configure -text {  Taken:}");
		reducew[0] = 1;
	}
	ws = int tkcmd(top, ".f.fsnap cget -width");
	if (wc2 < ws) {
		tkcmd(top, ".f.fsnap.ftime.l3 configure -text {"+ltime[len ltime - 8:]+"}");
		tkcmd(top, ".f.fsnap.ftime.l4 configure -text {"+ctime[len ctime - 8:]+"}");
		tkcmd(top, ".f.fsnap.ftime.cb configure -text {Set to local time}");
		reducew[1] = 1;
	}
	ws = int tkcmd(top, ".f.fsnap cget -width");
	if (wc2 < ws) {
		tkcmd(top, ".f.fsnap.ftime.l1 configure -text {C:}");
		tkcmd(top, ".f.fsnap.ftime.l2 configure -text {}");
		tkcmd(top, ".f.fsnap.ftime.l3 configure -text {"+ctime[len ctime - 17:len ctime - 8]+"}");
		tkcmd(top, ".f.fsnap.ftime.cb configure -text {Set local}");
		reducew[2] = 1;
	}
	ws = int tkcmd(top, ".f.fsnap cget -width");
	if (wc2 > ws) {
		wfs = 125-(20*(3-ssize));
		tkcmd(top, "grid columnconfigure .f.fsnap 2 -minsize "+string wfs);
	}
}

ltime, ctime: string;
wfs := 150;
hfs := 30;
reducew := array[10] of { * => 0 };

getcoords(top: ref Tk->Toplevel): Rect
{
	h := int tkcmd(top, ". cget -height");
	w := int tkcmd(top, ". cget -width");
	x := int tkcmd(top, ". cget -actx");
	y := int tkcmd(top, ". cget -acty");
	r := Rect((x,y),(x+w,y+h));
	return r;
}

viewscr := array[] of {
	"frame .f -bg",
	"canvas .f.c -yscrollcommand {.f.sy set} -xscrollcommand {.f.sx set} -height 300 -width 500",
	"scrollbar .f.sx -command {.f.c xview} -orient horizontal",
	"scrollbar .f.sy -command {.f.c yview}",
	"grid .f.c -row 0 -column 0",
	"grid .f.sy -row 0 -column 1 -sticky ns",
	"grid .f.sx -row 1 -column 0 -sticky ew",
	"bind .Wm_t <ButtonPress-1> +{focus .}",
	"bind .Wm_t.title <ButtonPress-1> +{focus .}",
	"pack propagate . 0",
	"menu .m @",
	".m add command -text {Save As...}",
	".m add separator",
	".m add command -text {bit} -command {send butchan save bit}",
	".m add command -text {jpeg} -command {send butchan save jpg}",

};

resizeview(top: ref Tk->Toplevel, wp,hp: int)
{
	w := int tkcmd(top, ". cget -width");
	h := int tkcmd(top, ". cget -height");
	hs := int tkcmd(top, ".f.sx cget -height");
	ws := int tkcmd(top, ".f.sy cget -width");
	ht := int tkcmd(top, ".Wm_t cget -height");
	wc := w - ws - 4;
	hc := h - hs - ht - 6;
	wpc := wc - wp;
	hpc := hc - hp;
	if (wpc > 0) {
		wc -= wpc;
		w -= wpc;
	}
	if (hpc > 0) {
		hc -= hpc;
		h -= hpc;
	}
	tkcmd(top, ". configure -height "+string h+" -width "+string w);
	tkcmd(top, ".f.c configure -height "+string hc+" -width "+string wc);
	tkcmd(top, "update");
}

multiview()
{
	s := "";
	for (k := 0; k < nofiles; k++) {
		if (selected[k]) {
			e := vw(k);
			if (e != 0)
				s += filelist[k]+".jpg ";
			if (e == 3) {
				s += "cancelled\n";
				break;
			}
			else if (e == -1)
				s += "failed\n";
		}
	}
	if (s != "")
		dialog("Multiple view complete:\n\n"+s,0,-1,coords);
}

vw(i: int): int
{
	# raise window if it is already open
	low := toplevels;
	for(; low != nil; low = tl low) {
		(tplvl, name, nil, nil) := hd low;
		if (filelist[i]+".jpg" == name) {
			tkcmd(tplvl, "raise .; focus .; update");
			return 0;
		}
	}

	ctlchan := chan of int;
	ctlchans := chan of string;
	chanout := chan of string;
	chanin := chan of string;
	spawn downloadscreen(coords, i, ctlchans, chanout);
	chanout <-= "!show!";
	spawn view(i,ctlchan, chanin, chanout);
	pid := <-ctlchan;
	killed := 0;
	for (;;) alt {
		s := <-ctlchans =>
			if (s == "kill") {
				chanin <-= "kill";
				killed = 1;
			}
		e := <-ctlchan =>
			chanout <-= "!done!";
			if (killed)
				return 3;
			if (e == -1)
				dialog(sys->sprint("Cannot read file: %s.jpg\n%r",filelist[i]),0,i,coords);
			if (e == -2) return vw(i);
			else return e;
	}
	return 0;
}

view(i: int, ctlchan: chan of int, chanin, chanout: chan of string)
{
	ctlchan <-= sys->pctl(0, nil);
	titlename := filelist[i]+".jpg";

	filename := camerapath+"jpg/"+filelist[i]+".jpg";
	filesize := testfilesize(filename);
	cached := 0;
	if (filesize > 0 && isloaded(filelist[i],JPG) && usecache) {
		cachefilename := tmppath+filelist[i]+"."+string JPG+"~";
		if (testfilesize(cachefilename) == filesize) {
			cached = 1;
			filename = cachefilename;
		}
		else delloaded(filelist[i],JPG);
	}
	if (filesize < 1) {
		ctlchan <-= -1;
		return;
	 }

	img: ref Image;
	cachepath := "";
	if (!cached && usecache)
		cachepath = tmppath+filelist[i]+"."+string JPG+"~";
	img = readjpg->jpg2img(filename, cachepath, chanin, chanout);
	if(img == nil) {
		if (cachepath != nil)
			sys->remove(cachepath);
		if (!cached)
			ctlchan <-= -1;
		else {
			delloaded(filelist[i], JPG);
			ctlchan <-= -2;
		}
		return;
	}
	else {
		chanout <-= "l2 Displaying";
		if (cachepath != "")
			imgloaded = (filelist[i], JPG) :: imgloaded;
		(t, titlechan) := tkclient->toplevel(context, "", titlename, Tkclient->Appl);
		butchan := chan of string;
		tk->namechan(t, butchan, "butchan");
		tkcmd(t, "focus .Wm_t; update");
		for (tk1 := 0; tk1 < len viewscr; tk1++)
			tkcmd(t, viewscr[tk1]);
		w := img.r.dx();
		h :=  img.r.dy();
		tkcmd(t, "panel .p -width "+string w+" -height "+string h);
		tk->putimage(t, ".p",img,nil);
		tkcmd(t, "bind .p <ButtonPress-2> {send butchan move %X %Y}");
		tkcmd(t, "bind .p <ButtonRelease-2> {send butchan release}");
		tkcmd(t, "bind .p <ButtonPress-3> {send butchan menu %X %Y}");
		tkcmd(t, ".f.c create window 0 0 -window .p -anchor nw");
		tkcmd(t, ".f.c configure -scrollregion {0 0 "+string w+" "+string h+"}");
		ctlchan <-= 0;
		addtoplevel(t,titlename,nil, sys->pctl(0,nil));

		h1 := 300;
		w1 := 500;
		ht := int tkcmd(t, ".Wm_t cget -height");
		if (h1 > display.image.r.dy() - ht) h1 = display.image.r.dy() - ht;
		if (w1 > display.image.r.dx()) w1 = display.image.r.dx();
		tkcmd(t, ". configure -width "+string w1+" -height "+string h1);
		resizeview(t,w,h);
		tkcmd(t, "pack .f; update");
		scrolling := 0;
		origin := Point (0,0);
		tkclient->onscreen(t, nil);
		tkclient->startinput(t, "kbd"::"ptr"::nil);

		loop: for(;;) alt{
			s := <-t.ctxt.kbd =>
				tk->keyboard(t, s);
			s := <-t.ctxt.ptr =>
				tk->pointer(t, *s);
			inp := <- butchan =>
				(n, lst) := sys->tokenize(inp, " \t\n");
				case hd lst {
					"save" =>
						ftype := "."+hd tl lst;
						savename := selectfile->filename(context,
								display.image,
								"Save "+filelist[i]+ftype+" to directory...", 
								"*"+ftype :: nil,
								lastpath);
						if (savename != "" && savename[0] == '/') {
							lastpath = savename[:isat2(savename,"/")+1];
							if (savename[len savename - 1] == '/')
								savename += filelist[i]+ftype;

							if (!hasext(savename, ftype))
								savename += ftype;
							(fd, cancel) := create(savename, getcoords(t));
							if (fd != nil) {
								n2 := -1;
								if (ftype == ".bit")
									n2 = display.writeimage(fd,img);
								if (ftype == ".jpg")
									n2 = 1 - dnld(i, "$"+savename);
								if (n2 == 0) {
									dialog(filelist[i]+ftype+" saved",0,i,getcoords(t));
									break;
								}
								dialog("Could not save: "+filelist[i]+ftype,0,i,getcoords(t));
							}
							if (!cancel)
								dialog("Could not save: "+filelist[i]+ftype,0,i,getcoords(t));
							break;
						}
						
					"menu" =>
						tkcmd(t, ".m post "+hd tl lst+" "+hd tl tl lst);
					"release" =>
						scrolling = 0;
					"move" =>
						newpoint := Point (int hd tl lst, int hd tl tl lst);

						if (scrolling) {
							diff := (origin.sub(newpoint)).mul(2);
							tkcmd(t, ".f.c xview scroll "+string diff.x+" units");
							tkcmd(t, ".f.c yview scroll "+string diff.y+" units");
							origin = newpoint;
							# clearbuffer(butchan);
						}
						else {
							origin = newpoint;
							scrolling = 1;
						}
				}
	
			s := <-t.ctxt.ctl or
			s = <-t.wreq or
			s = <-titlechan =>
				if (s == "exit")
					break loop;
				e := tkclient->wmctl(t, s);
				if (e == nil && s[0] == '!')
					resizeview(t,w,h);
		}		
		deltoplevel(t);
	}
}

create(filename: string, co: Rect): (ref sys->FD, int)
{
	(n,dir) := sys->stat(filename);
	if (n != -1 && !dialog("overwrite "+filename+"?",1,-1,co))
		return (nil,1);
	return (sys->create(filename,sys->OWRITE,8r666), 0);
}

hasext(name,ext: string): int
{
	if (len name >= len ext && name[len name - len ext:] == ext)
		return 1;
	return 0;
}
