implement DebSrc;

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

include "dialog.m";
	dialog: Dialog;

include "selectfile.m";
	selectfile: Selectfile;

include "debug.m";
	debug: Debug;
	Sym, Src, Exp, Module: import debug;

include "wmdeb.m";

include	"plumbmsg.m";
	plumbmsg: Plumbmsg;
	Msg: import plumbmsg;

include "workdir.m";
	workdir: Workdir;

include "dis.m";
	dism: Dis;

mods:		list of ref Mod;
tktop:		ref Tk->Toplevel;
context:		ref Draw->Context;
opendir =	".";
srcid:		int;
xscroll, remcr:	int;

sblpath :=	array[] of
{
	("/dis/",	"/appl/"),
	("/dis/",	"/appl/cmd/"),
	# ("/dis/mux/",	"/appl/mux/"),
	# ("/dis/lib/",	"/appl/lib/"),
	# ("/dis/wm/",	"/appl/wm/"),
	("/dis/sh.",	"/appl/cmd/sh/sh."),
};

plumbed := 0;
but3: chan of string;

plumbbind := array[] of
{
	"<ButtonPress-3> {send but3 pressed}",
	"<ButtonRelease-3> {send but3 released %x %y}",
	"<Motion-Button-3> {}",
	"<Double-Button-3> {}",
	"<Double-ButtonRelease-3> {}",
};

init(acontext: ref Draw->Context,
	atktop: ref Tk->Toplevel,
	atkclient: Tkclient,
	aselectfile: Selectfile,
	adialog: Dialog,
	astr: String,
	adebug: Debug,
	xscr: int,
	rcr: int)
{
	context = acontext;
	tktop = atktop;
	sys = load Sys Sys->PATH;
	tk = load Tk Tk->PATH;
	tkclient = atkclient;
	selectfile = aselectfile;
	dialog = adialog;
	str = astr;
	debug = adebug;
	xscroll = xscr;
	remcr = rcr;

	plumbmsg = load Plumbmsg Plumbmsg->PATH;
	if(plumbmsg->init(1, nil, 0) >= 0){
		plumbed = 1;
		workdir = load Workdir Workdir->PATH;
	}
}

reinit(xscr: int, rcr: int)
{
	if(xscroll == xscr && remcr == rcr)
		return;
	xscroll = xscr;
	remcr = rcr;
	for(ml := mods; ml != nil; ml = tl ml){
		m := hd ml;
		if(xscroll)
			tkcmd(m.tk+" configure  -wrap none");
		else
			tkcmd(m.tk+" configure -wrap char");
		tkcmd("update");
		fd := sys->open(m.src, sys->OREAD);
		if(fd != nil)
			loadfile(m.tk, fd);
	}
}

#
# make a Mod with a text widget for source file src
#
loadsrc(src: string, addpath: int): ref Mod
{
	if(src == "")
		return nil;

	m : ref Mod = nil;
	for(ml := mods; ml != nil; ml = tl ml){
		m = hd ml;
		if(m.src == src || filesuffix(src, m.src))
			break;
	}

	if(ml == nil || m.tk == nil){
		if(ml == nil)
			m = ref Mod(src, nil, nil, nil, 0, 1);
		fd := sys->open(src, sys->OREAD);
		if(fd == nil)
			return nil;
		(dir, file) := str->splitr(src, "/");
		m.tk = ".t."+tk->quote(file)+string srcid++;
		if(xscroll)
			tkcmd("text "+m.tk+" -bd 0 -state disabled -wrap none");
		else
			tkcmd("text "+m.tk+" -bd 0 -state disabled");
		if (but3 == nil) {
			but3 = chan of string;
			spawn but3proc();
		}
		tk->namechan(tktop, but3, "but3");
		for (i := 0; i < len plumbbind; i++)
			tkcmd("bind "+m.tk+" "+plumbbind[i]);
		tkcmd(m.tk+" configure -insertwidth 2");
		opack := packed;
		packm(m);
		if(!loadfile(m.tk, fd)){
			fd = nil;
			packm(opack);
			tkcmd("destroy "+m.tk);
			return nil;
		}
		fd = nil;
		tkcmd(m.tk+" tag configure bpt -foreground #c00");
		tkcmd(".m.file.menu add command -label "+src+" -command {send m open "+src+"}");
		if(ml == nil)
			mods = m :: mods;

		if(addpath)
			addsearch(dir);
	}
	return m;
}

addsearch(dir: string)
{
	for(i := 0; i < len searchpath; i++)
		if(searchpath[i] == dir)
			return;
	s := array[i+1] of string;
	s[0:] = searchpath;
	s[i] = dir;
	searchpath = s;
}

#
# bring up the widget for src, if it exists
#
showstrsrc(src: string)
{
	m : ref Mod = nil;
	for(ml := mods; ml != nil; ml = tl ml){
		m = hd ml;
		if(m.src == src)
			break;
	}
	if(ml == nil)
		return;

	packm(m);
}

#
# bring up the widget for module
# at position s
#
showmodsrc(m: ref Mod, s: ref Src)
{
	if(s == nil)
		return;

	src := s.start.file;
	if(src != s.stop.file)
		s.stop = s.start;

	if(m == nil || m.tk == nil || m.src != src){
		m1 := findsrc(src);
		if(m1 == nil)
			return;
		if(m1.dis == nil)
			m1.dis = m.dis;
		if(m1.sym == nil)
			m1.sym = m.sym;
		m = m1;
	}

	tkcmd(m.tk+" mark set insert "+string s.start.line+"."+string s.start.pos);
	tkcmd(m.tk+" tag remove sel 0.0 end");
	tkcmd(m.tk+" tag add sel insert "+string s.stop.line+"."+string s.stop.pos);
	tkcmd(m.tk+" see insert");

	packm(m);
}

packm(m: ref Mod)
{
	if(packed != m && packed != nil){
		tkcmd(packed.tk+" configure -xscrollcommand {}");
		tkcmd(packed.tk+" configure -yscrollcommand {}");
		tkcmd(".body.scx configure -command {}");
		tkcmd(".body.scy configure -command {}");
		tkcmd("pack forget "+packed.tk);
	}

	if(packed != m && m != nil){
		tkcmd(m.tk+" configure -xscrollcommand {.body.scx set}");
		tkcmd(m.tk+" configure -yscrollcommand {.body.scy set}");
		tkcmd(".body.scx configure -command {"+m.tk+" xview}");
		tkcmd(".body.scy configure -command {"+m.tk+" yview}");
		tkcmd("pack "+m.tk+" -expand 1 -fill both -in .body.ft");
	}
	packed = m;
}

#
# find the dis file associated with m
# we know that m has a valid src
#
attachdis(m: ref Mod): int
{
	c := load Diss m.dis;
	if(c == nil){
		m.dis = repsuff(m.src, ".b", ".dis");
		c = load Diss m.dis;
	}
	if(c == nil && m.sym != nil){
		m.dis = repsuff(m.sym.path, ".sbl", ".dis");
		c = load Diss m.dis;
	}
	if(c != nil){
		# if m.dis in /appl, prefer one in /dis if it exists (!)
		nd := len m.dis;
		for(i := 0; i < len sblpath; i++){
			(disd, srcd) := sblpath[i];
			ns := len srcd;
			if(nd > ns && m.dis[:ns] == srcd){
				dis := disd + m.dis[ns:];
				d := load Diss dis;
				if(d != nil)
					m.dis = dis;
					break;
			}	
		}
	}
	if(c == nil){
		(dir, file) := str->splitr(repsuff(m.src, ".b", ".dis"), "/");
		pat := list of {
			file+" (Dis VM module)",
			"*.dis (Dis VM module)"
		};
		m.dis = selectfile->filename(context, tktop.image, "Locate Dis file", pat, dir);
		c = load Diss m.dis;
	}
	return c != nil;
}

#
# load the symbol file for m
# works best if m has an associated source file
#
attachsym(m: ref Mod)
{
	if(m.sym != nil)
		return;
	sbl := repsuff(m.src, ".b", ".sbl");
	err : string;
	tk->cmd(tktop, "cursor -bitmap cursor.wait");
	(m.sym, err) = debug->sym(sbl);
	tk->cmd(tktop, "cursor -default");
	if(m.sym != nil)
		return;
	if(!str->prefix("Can't open", err)){
		alert(err);
		return;
	}
	(dir, file) := str->splitr(sbl, "/");

	pat := list of {
		file+" (Symbol table file)",
		"*.sbl (Symbol table file)"
	};
	sbl = selectfile->filename(context, tktop.image, "Locate Symbol file", pat, dir);
	tk->cmd(tktop, "cursor -bitmap cursor.wait");
	(m.sym, err) = debug->sym(sbl);
	tk->cmd(tktop, "cursor -default");
	if(m.sym != nil)
		return;
	if(!str->prefix("Can't open", err)){
		alert(err);
		return;
	}
}

#
# get the current selection
#
getsel(): (ref Mod, int)
{
	m := packed;
	if(m == nil || m.src == nil)
		return (nil, 0);
	attachsym(m);
	if(m.sym == nil){
		alert("No symbol file for "+m.src);
		return (nil, 0);
	}
	index := tkcmd(m.tk+" index insert");
	if(len index == 0 || index[0] == '!')
		return (nil, 0);
	(sline, spos) := str->splitl(index, ".");
	line := int sline;
	pos := int spos[1:];
	pc := m.sym.srctopc(ref Src((m.src, line, pos), (m.src, line, pos)));
	s := m.sym.pctosrc(pc);
	if(s == nil){
		alert("No pc is appropriate");
		return (nil, 0);
	}
	return (m, pc);
}

#
# return the selected string
#
snarf(): string
{
	if(packed == nil)
		return "";
	s := tk->cmd(tktop, packed.tk+" get sel.first sel.last");
	if(len s > 0 && s[0] == '!')
		s = "";
	return s;
}

plumbit(x, y: string)
{
	if (packed == nil)
		return;
	s := tk->cmd(tktop, packed.tk+" index @"+x+","+y);
	if (s == nil || s[0] == '!')
		return;
	(nil, l) := sys->tokenize(s, ".");
	msg := ref Msg(
		"WmDeb",
		"",
		workdir->init(),
		"text",
		nil,
		array of byte (packed.src+":"+hd l));
	if(msg.send() < 0)
		sys->fprint(sys->fildes(2), "deb: plumbing write error: %r\n");
}

but3proc()
{
	button3 := 0;
	for (;;) {
		s := <-but3;
		if(s == "pressed"){
			button3 = 1;
			continue;
		}
		if(plumbed == 0 || button3 == 0)
			continue;
		button3 = 0;
		(nil, l) := sys->tokenize(s, " ");
		plumbit(hd tl l, hd tl tl l);
	}
}

#
# search for another occurance of s;
# return if s was found
#
search(s: string): int
{
	if(packed == nil || s == "")
		return 0;
	pos := " sel.last";
	sel := tk->cmd(tktop, packed.tk+" get sel.last");
	if(len sel > 0 && sel[0] == '!')
		pos = " insert";
	pos = tk->cmd(tktop, packed.tk+" search -- "+tk->quote(s)+pos);
	if((len pos > 0 && pos[0] == '1') || pos == "")
		return 0;
	tkcmd(packed.tk+" mark set insert "+pos);
	tkcmd(packed.tk+" tag remove sel 0.0 end");
	tkcmd(packed.tk+" tag add sel insert "+pos+"+"+string len s+"c");
	tkcmd(packed.tk+" see insert");
	return 1;
}

#
# make a Mod for debugger module mod
#
findmod(mod: ref Module): ref Mod
{
	dis := mod.dis();
	if(dis == "")
		return nil;
	m: ref Mod;
	for(ml := mods; ml != nil; ml = tl ml){
		m = hd ml;
		if(m.dis == dis || filesuffix(dis, m.dis))
			break;
	}
	if(ml == nil){
		if(len dis > 0 && dis[0] != '$')
			m = findsrc(repsuff(dis, ".dis", ".b"));
		if(m == nil)
			mods = ref Mod("", "", dis, nil, 0, 0) :: mods;
	}
	if(m != nil){
		m.srcask = 0;
		m.dis = dis;
		if(m.symask){
			attachsym(m);
			m.symask = 0;
		}
		mod.addsym(m.sym);
	}
	return m;
}

# log(s: string)
# {
#	fd := sys->open("/usr/jrf/debug", Sys->OWRITE);
#	sys->seek(fd, 0, Sys->SEEKEND);
#	sys->fprint(fd, "%s\n", s);
#	fd = nil;
# }

findbm(dis: string): ref Mod
{
	if(dism == nil){
		dism = load Dis Dis->PATH;
		if(dism != nil)
			dism->init();
	}
	if(dism != nil && (b := dism->src(dis)) != nil)
		return loadsrc(b, 1);
	return nil;	
}

findsrc(src: string): ref Mod
{
	m := loadsrc(src, 1);
	if(m != nil)
		return m;
	m = findbm(repsuff(src, ".b", ".dis"));
	if(m != nil)
		return m;
	(dir, file) := str->splitr(src, "/");
	for(i := 0; i < len searchpath; i++){
		if(dir != "" && dir[0] != '/')
			m = loadsrc(searchpath[i] + src, 0);
		if(m != nil)
			return m;
		m = loadsrc(searchpath[i] + file, 0);
		if(m != nil)
			return m;
	}

	ns := len src;
	for(i = 0; i < len sblpath; i++){
		(disd, srcd) := sblpath[i];
		nd := len disd;
		if(ns > nd && src[:nd] == disd){
			m = loadsrc(srcd + src[nd:], 0);
			if(m != nil)
				return m;
		}
	}

	(dir, file) = str->splitr(src, "/");
	opdir := dir;
	if(opdir == "" || opdir[0] != '/')
		opdir = opendir;

	pat := list of {
		file+" (Limbo source)",
		"*.b (Limbo source)"
	};

	src = selectfile->filename(context, tktop.image, "Locate Limbo Source", pat, opdir);
	if(src == nil)
		return nil;
	(opendir, nil) = str->splitr(src, "/");
	if(opendir == "")
		opendir = ".";
	m = loadsrc(src, 1);
	if(m != nil
	&& dir != "" && dir[0] != '/'
	&& suffix(dir, opendir))
		addsearch(opendir[:len opendir - len dir]);
	else if(m != nil)	# remember anyway
		addsearch(opendir);
	return m;
}

suffix(suff, s: string): int
{
	if(len suff > len s)
		return 0;
	return suff == s[len s - len suff:];
}

#
# load the contents of fd into tkt
#
loadfile(tkt: string, fd: ref Sys->FD): int
{
	buf := array[512] of byte;
	i := 0;

	(ok, d) := sys->fstat(fd);
	if(ok < 0)
		return 0;
	tk->cmd(tktop, "cursor -bitmap cursor.wait");
	length := int d.length;
	whole := array[length] of byte;
	cr := 0;
	for(;;){
		if(cr){
			buf[0] = byte '\r';
			n := sys->read(fd, buf[1:], len buf - 1);
			n++;
		}
		else
			n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		if(remcr){
			for(k := 0; k < n-1; ){
				if(buf[k] == byte '\r' && buf[k+1] == byte '\n')
					buf[k:] = buf[k+1:n--];
				else
					k++;
			}
			if(buf[n-1] == byte '\r'){
				n--;
				cr = 1;
			}
		}
		j := i+n;
		if(j > length)
			break;
		whole[i:] = buf[:n];
		i += n;
	}
	tk->cmd(tktop, tkt+" delete 1.0 end;"+tkt+" insert end '"+string whole[:i]);
	tk->cmd(tktop, "update; cursor -default");
	return 1;
}

delmod(mods: list of ref Mod, m: ref Mod): list of ref Mod
{
	if(mods == nil)
		return nil;
	mh := hd mods;
	if(mh == m)
		return tl mods;
	return mh :: delmod(tl mods, m);
}

#
# replace an occurance in name of suffix old with new
#
repsuff(name, old, new: string): string
{
	no := len old;
	nn := len name;
	if(nn >= no && name[nn-no:] == old)
		return name[:nn-no] + new;
	return name;
}

filesuffix(suf, s: string): int
{
	nsuf := len suf;
	ns := len s;
	return ns > nsuf
		&& suf[0] != '/'
		&& s[ns-nsuf-1] == '/'
		&& s[ns-nsuf:] == suf;
}

alert(m: string)
{
	dialog->prompt(context, tktop.image, "warning -fg yellow",
		"Debugger Alert", m, 0, "Dismiss"::nil);
}

tkcmd(s: string): string
{
	return tk->cmd(tktop, s);
}
