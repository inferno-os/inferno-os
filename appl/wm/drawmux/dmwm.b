implement Dmwm;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Screen, Display, Image, Rect, Point, Wmcontext, Pointer: import draw;
include "drawmux.m";
	dmux : Drawmux;
include "wmsrv.m";
	wmsrv: Wmsrv;
	Window, Client: import wmsrv;
include "tk.m";
include "wmclient.m";
	wmclient: Wmclient;
include "string.m";
	str: String;
include "dialog.m";
	dialog: Dialog;
include "arg.m";

Wm: module {
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Dmwm: module {
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Background: con int 16r777777FF;

screen: ref Screen;
display: ref Display;

badmodule(p: string)
{
	sys->fprint(sys->fildes(2), "wm: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys  = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	if(draw == nil)
		badmodule(Draw->PATH);

	str = load String String->PATH;
	if(str == nil)
		badmodule(String->PATH);

	wmsrv = load Wmsrv Wmsrv->PATH;
	if(wmsrv == nil)
		badmodule(Wmsrv->PATH);

	wmclient = load Wmclient Wmclient->PATH;
	if(wmclient == nil)
		badmodule(Wmclient->PATH);
	wmclient->init();

	dialog = load Dialog Dialog->PATH;
	if (dialog == nil) badmodule(Dialog->PATH);
	dialog->init();

	sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);
	if (ctxt == nil)
		ctxt = wmclient->makedrawcontext();
	display = ctxt.display;

	dmux = load Drawmux Drawmux->PATH;
	if (dmux != nil) {
		(err, disp) := dmux->init();
		if (err != nil) {
			dmux = nil;
			sys->fprint(stderr(), "wm: cannot start drawmux: %s\n", err);
		}
		else
			display = disp;
	}

	buts := Wmclient->Appl;
	if(ctxt.wm == nil)
		buts = Wmclient->Plain;
	# win := wmclient->window(ctxt, "Wm", buts);
	# wmclient->win.onscreen("place");
	# wmclient->win.startinput("kbd" :: "ptr" :: nil);

	# screen = makescreen(win.image);

	(clientwm, join, req) := wmsrv->init();
	clientctxt := ref Draw->Context(display, nil, nil);

	sync := chan of string;
	argv = tl argv;
	if(argv == nil)
		argv = "wm/toolbar" :: nil;
	argv = "wm/wm" :: argv;
	spawn command(clientctxt, argv, sync);
	if((e := <-sync) != nil)
		fatal("cannot run command: " + e);

	dmuxrequest := chan of (string, ref Sys->FD);
	if (dmux != nil)
		spawn dmuxlistener(dmuxrequest);

	for(;;) alt {
	(name, fd) := <- dmuxrequest =>
		spawn dmuxask(ctxt, name, fd);
	}
}

makescreen(img: ref Image): ref Screen
{
	screen = Screen.allocate(img, img.display.color(Background), 0);
	img.draw(img.r, screen.fill, nil, screen.fill.r.min);
	return screen;
}

kill(pid: int, note: string): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", note) < 0)
		return -1;
	return 0;
}

fatal(s: string)
{
	sys->fprint(sys->fildes(2), "wm: %s\n", s);
	kill(sys->pctl(0, nil), "killgrp");
	raise "fail:error";
}

command(ctxt: ref Draw->Context, args: list of string, sync: chan of string)
{
	fds := list of {0, 1, 2};
	pid := sys->pctl(sys->NEWFD, fds);

	cmd := hd args;
	file := cmd;

	if(len file<4 || file[len file-4:]!=".dis")
		file += ".dis";

	c := load Wm file;
	if(c == nil) {
		err := sys->sprint("%r");
		if(err != "permission denied" && err != "access permission denied" && file[0]!='/' && file[0:2]!="./"){
			c = load Wm "/dis/"+file;
			if(c == nil)
				err = sys->sprint("%r");
		}
		if(c == nil){
			sync <-= sys->sprint("%s: %s\n", cmd, err);
			exit;
		}
	}
	sync <-= nil;
	c->init(ctxt, args);
}

dmuxlistener(newclient : chan of (string, ref Sys->FD))
{
	(aok, c) := sys->announce("tcp!*!9998");
	if (aok < 0) {
		sys->print("cannot announce drawmux port: %r\n");
		return;
	}
	buf := array [Sys->ATOMICIO] of byte;
	for (;;) {
		(ok, nc) := sys->listen(c);
		if (ok < 0) {
			sys->fprint(stderr(), "wm: dmux listen failed: %r\n");
			return;
		}
		fd := sys->open(nc.dir+"/remote", Sys->OREAD);
		name := "unknown";
		if (fd == nil)
			sys->fprint(stderr(), "wm: dmux cannot access remote address: %r\n");
		else {
			n := sys->read(fd, buf, len buf);
			if (n > 0) {
				name = string buf[0:n];
				for (i := len name -1; i > 0; i--)
					if (name[i] == '!')
						break;
				if (i != 0)
					name = name[0:i];
			}
		}
		fd = sys->open(nc.dir+"/data", Sys->ORDWR);
		if (fd != nil)
			newclient <-= (name, fd);
	}
}

dmuxask(ctxt: ref Draw->Context, name : string, fd : ref Sys->FD)
{
	msg := sys->sprint("Screen snoop request\nAddress: %s\n\nProceed?", name);
	labs := "Ok" :: "No way!" :: nil;
	if (1 || dialog->prompt(ctxt, nil, nil, "Snoop!", msg, 1, labs) == 0)
		dmux->newviewer(fd);
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}
