implement Find;

#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#


include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Rect: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "arg.m";
include "sh.m";
include "registries.m";
	registries: Registries;
	Registry, Attributes, Service: import registries;
include "grid/announce.m";
	announce: Announce;

Find: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(sys->FORKNS | sys->NEWPGRP, nil);
	draw = load Draw Draw->PATH;
	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmod(Arg->PATH);
	if (draw == nil)
		badmod(Draw->PATH);
	tk = load Tk Tk->PATH;
	if (tk == nil)
		badmod(Tk->PATH);
	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		badmod(Tkclient->PATH);
	tkclient->init();
	registries = load Registries Registries->PATH;
	if (registries == nil)
		badmod(Registries->PATH);
	registries->init();

	command := "";
	attrs := Attributes.new(nil);
	arg->init(argv);
	arg->setusage("find [-a attributes] action1 { cmd [args...] } .. actionN { cmd [args...] }");
	title := "a resource";
	while ((opt := arg->opt()) != 0) {
		case opt {
		't' =>
			title = arg->earg();
		'a' =>
			attr := arg->earg();
			val := arg->earg();
			attrs.set(attr, val);
		* =>
			arg->usage();
		}
	}
	argv = arg->argv();
	if (argv == nil || len argv % 2)
		arg->usage();
	arg = nil;
	
	cmds := array[len argv / 2] of (string, string);
	for (i := 0; i < len cmds; i++) {
		cmds[i] = (hd argv, hd tl argv);
		argv = tl tl argv;
	}

	reg := Registry.connect(nil, nil, nil);
	if (reg == nil)
		error(ctxt, ((0,0),(0,0)), "Could not find registry");
	(matches, err) := reg.find(attrs.attrs);
	if (err != nil)
		error(ctxt, ((0,0),(0,0)), "Registry error: "+err);
	spawn tkwin(ctxt, matches, cmds, title);	
}

mainscr := array[] of {
	"frame .f",
	"frame .f.flb",
	"listbox .f.flb.lb1 -yscrollcommand {.f.flb.sb1 set} -selectmode single -bg white -selectbackground blue -font /fonts/charon/plain.normal.font",
	"bind .f.flb.lb1 <Double-Button-1> {send butchan double %y}",
	"scrollbar .f.flb.sb1 -command {.f.flb.lb1 yview}",
	"pack .f.flb.sb1 -fill y -side left",
	"pack .f.flb.lb1 -fill both -expand 1",
	"frame .f.fb",
	"pack .f.flb -fill both -expand 1 -side top",
	"pack .f.fb",
	"pack .f -fill both -expand 1",
};

errscr := array[] of {
	"frame .f",
	"frame .f.fl",
	"label .f.fl.l1 -text {} -font /fonts/charon/plain.normal.font ",
	"label .f.fl.l2 -text {Please try again later} -font /fonts/charon/plain.normal.font",
	"pack .f.fl.l1 .f.fl.l2 -side top",
	"button .f.b -text { Close } -command {send butchan exit} "+
		"-font /fonts/charon/bold.normal.font",
	"grid .f.fl -row 0 -column 0 -padx 10 -pady 5",
	"grid .f.b -row 1 -column 0 -pady 5",
	"pack .f",
};

tkwin(ctxt: ref Draw->Context, lsrv: list of ref Service, cmds: array of (string, string), title: string)
{
	(top, titlectl) := tkclient->toplevel(ctxt, "", "Find "+title, tkclient->Appl);
	butchan := chan of string;
	tk->namechan(top, butchan, "butchan");
	if (lsrv == nil) {
		tkcmds(top, errscr);
		tkcmd(top, ".f.fl.l1 configure -text {Could not find "+title+"}");
	}
	else {
		tkcmds(top, mainscr);
		for (tmp := lsrv; tmp != nil; tmp = tl tmp)
			tkcmd(top, ".f.flb.lb1 insert end {"+(hd tmp).attrs.get("name")+"}");
		for (i := 0; i < len cmds; i++) {
			si := string i;
			tkcmd(top, "button .f.fb.b"+si+" -font /fonts/charon/bold.normal.font "+
			"-text {"+cmds[i].t0+"} -command {send butchan go "+si+"}");
			tkcmd(top, "grid .f.fb.b"+si+" -row 0 -column "+si+" -padx 5 -pady 5");
		}
		tkcmd(top, ".f.flb.lb1 selection set 0");
		tkcmd(top, "pack propagate . 0");
	}
	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	for(;;) alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		inp := <- butchan =>
			(nil, lst) := sys->tokenize(inp, " \t\n");
			case hd lst {
				"exit" =>
					return;
				"go" =>
					n := int hd tl lst;
					id := tkcmd(top, ".f.flb.lb1 curselection");
					if (id != nil)
						connect(ctxt, lsrv, cmds[n].t1 :: nil, tk->rect(top, ".",0), int id);
				"double" =>
					y := hd tl lst;
					id := int tkcmd(top, ".f.flb.lb1 nearest "+y);
					connect(ctxt, lsrv, cmds[0].t1 :: nil, tk->rect(top, ".",0), id);
			}
		s := <-top.ctxt.ctl or
		s = <-top.wreq or
		s = <- titlectl =>
			if (s == "exit")
				exit;
			else
				tkclient->wmctl(top, s);
	}
}

connect(ctxt: ref Draw->Context, lsrv: list of ref Service, argv: list of string, r: Rect, id: int)
{
	for (tmp := lsrv; tmp != nil; tmp = tl tmp) {
		if (id-- == 0) {
			spawn mountit(ctxt, hd tmp, argv, r);
			break;
		}
	}
}

tkcmd(top: ref Tk->Toplevel, cmd: string): string
{
	e := tk->cmd(top, cmd);
	if (e != "" && e[0] == '!') sys->print("tk error: '%s': %s\n",cmd,e);
	return e;
}

tkcmds(top: ref Tk->Toplevel, cmds: array of string)
{
	for (i := 0; i < len cmds; i++)
		tkcmd(top, cmds[i]);
}

mountit(ctxt: ref Draw->Context, srv: ref Registries->Service, argv: list of string, r: Rect)
{
	sys->pctl(Sys->FORKNS| Sys->NEWPGRP, nil);
	attached := srv.attach(nil,nil);
	if (attached != nil) {
		if (sys->mount(attached.fd, nil, "/n/client", sys->MREPL, nil) != -1) {
			sh := load Sh Sh->PATH;
			if (sh == nil)
				badmod(Sh->PATH);
			sys->chdir("/n/client");
			err := sh->run(ctxt, argv);
			if (err != nil)
				error(ctxt, r, "failed to run: "+err);			
		}
		else
			error(ctxt, r, sys->sprint("failed to mount: %r"));			
	}
	else
		error(ctxt, r, sys->sprint("could not connect"));
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

badmod(path: string)
{
	sys->fprint(stderr(), "Find: cannot load %s: %r\n", path);
	exit;
}

errorwin := array[] of {
	"frame .f",
	"label .f.l -font /fonts/charon/plain.normal.font",
	"button .f.b -text {Ok} -font /fonts/charon/bold.normal.font "+
		"-command {send butchan ok}",
	"pack .f.l .f.b -side top -padx 5 -pady 5",
	"pack .f",
};

error(ctxt: ref Draw->Context, oldr: Draw->Rect, errstr: string)
{
	(top, titlectl) := tkclient->toplevel(ctxt, "", "Error", tkclient->Appl);
	butchan := chan of string;
	tk->namechan(top, butchan, "butchan");
	tkcmds(top, errorwin);
	tkcmd(top, ".f.l configure -text {"+errstr+"}");
	r := tk->rect(top, ".", 0);
	newx := ((oldr.dx() - r.dx())/2) + oldr.min.x;
	if (newx < 0)
		newx = 0;
	newy := ((oldr.dy() - r.dy())/2) + oldr.min.y;
	if (newy < 0)
		newy = 0;
	tkcmd(top, ". configure -x "+string newx+" -y "+string newy);
	tkclient->onscreen(top, "exact");
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	for(;;) alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		<- butchan =>
			tkclient->wmctl(top, "exit");
		s := <-top.ctxt.ctl or
		s = <-top.wreq or
		s = <- titlectl =>
			tkclient->wmctl(top, s);
	}
}	
