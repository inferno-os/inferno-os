implement Gather;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect, Display, Image, Font: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "commandline.m";
	commandline: Commandline;
	Cmdline: import commandline;
include "sh.m";

Gather: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

CLIENTDIR: con "/dis/spree/clients";

drawctxt: ref Draw->Context;
cliquefd: ref Sys->FD;
stderr: ref Sys->FD;

mnt, dir: string;

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil) {
		sys->fprint(stderr, "gather: cannot load %s: %r\n", Tkclient->PATH);
		raise "fail:bad module";
	}
	tkclient->init();
	commandline = load Commandline Commandline->PATH;
	if(commandline == nil) {
		sys->fprint(stderr, "gather: cannot load %s: %r\n", Commandline->PATH);
		raise "fail:bad module";
	}
	commandline->init();
	drawctxt = ctxt;
	cliquefd = sys->fildes(0);

	if (len argv >= 3) {
		mnt = hd tl argv;
		dir = hd tl tl argv;
	} else
		sys->fprint(stderr, "gather: expected mnt, dir args\n");
	client1();
}

client1()
{
	(win, winctl) := tkclient->toplevel(drawctxt, nil, "Gathering", Tkclient->Appl);
	ech := chan of string;
	tk->namechan(win, ech, "e");
	(chat, chatevent) := Cmdline.new(win, ".chat", nil);
	updatech := chan of string;
	spawn readproc(updatech);

	cmd(win, "button .b -text Start -command {send e start}");
	cmd(win, "pack .b -side top -anchor w");
	cmd(win, "pack .chat -fill both -expand 1");
	cmd(win, "pack propagate . 0");
	cmd(win, "update");
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd"::"ptr"::nil);
	for (;;) alt {
	s := <-win.ctxt.kbd =>
		tk->keyboard(win, s);
	s := <-win.ctxt.ptr =>
		tk->pointer(win, *s);
	s := <-win.ctxt.ctl or
	s = <-win.wreq or
	s = <-winctl =>
		tkclient->wmctl(win, s);
	line := <-updatech =>
		(n, toks) := sys->tokenize(line, " ");
		if (toks == nil)
			continue;
		case hd toks {
		"clienttype" =>
			chat.addtext("starting " + hd tl toks + " session...\n");
			cmd(win, "update");
			path := CLIENTDIR + "/" + hd tl toks + ".dis";
			mod := load Command path;
			if (mod == nil) {
				chat.addtext(sys->sprint("could not load %s: %r\n", path));
				chat.addtext("bye bye\n");
				cliquefd = nil;
			} else {
				win = nil;
				chat = nil;
				startclient(mod, hd tl toks :: mnt :: dir :: tl tl toks);
				exit;
			}
		"chat" =>
			chat.addtext(hd tl toks + ": " + concat(tl tl toks) + "\n");
		"title" =>
			tkclient->settitle(win, "Gather " + concat(tl toks));
		"join" or
		"leave" or
		"watch" or
		"unwatch" =>
			chat.addtext(line + "\n");
		* =>
			chat.addtext("unknown update: " + line + "\n");
		}
		cmd(win, "update");
	c := <-chatevent =>
		lines := chat.event(c);
		for (; lines != nil; lines = tl lines)
			cliquecmd("chat " + hd lines, chat);
	c := <-ech =>
		cliquecmd(c, chat);
	}
}

cliquecmd(s: string, chat: ref Cmdline)
{
	if (sys->fprint(cliquefd, "%s", s) == -1) {
		chat.addtext(sys->sprint("command failed: %r\n"));
		cmd(chat.top, "update");
	}
}

prefixed(s: string, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

readproc(updatech: chan of string)
{
	buf := array[Sys->ATOMICIO] of byte;
	while ((n := sys->read(cliquefd, buf, Sys->ATOMICIO)) > 0) {
		(nil, lines) := sys->tokenize(string buf[0:n], "\n");
		for (; lines != nil; lines = tl lines) {
			updatech <-= hd lines;
			if (prefixed(hd lines, "clienttype"))
				exit;
		}
	}
	updatech <-= nil;
}

startclient(mod: Command, argv: list of string)
{
	{
		mod->init(drawctxt, argv);
	} exception e {
	"*" =>
		sys->print("client %s broken: %s\n", hd argv, e);
	}
}

cmd(win: ref Tk->Toplevel, s: string): string
{
	r := tk->cmd(win, s);
	if(len r > 0 && r[0] == '!')
		sys->print("error executing '%s': %s\n", s, r[1:]);
	return r;
}

concat(l: list of string): string
{
	if (l == nil)
		return nil;
	s := hd l;
	for (l = tl l; l != nil; l = tl l)
		s += " " + hd l;
	return s;
}
