implement Lobby;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect, Display, Image, Font: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "../join.m";
	join: Join;
include "dividers.m";
	dividers: Dividers;
	Divider: import dividers;
include "commandline.m";
	commandline: Commandline;
	Cmdline: import commandline;
include "sh.m";

Lobby: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

CLIENTDIR: con "/dis/spree/clients";
NAMEFONT: con "/fonts/charon/plain.small.font";
TITLEFONT: con "/fonts/charon/bold.normal.font";
HEADERFONT: con "/fonts/charon/italic.normal.font";

Object: adt {
	id:	int;
	pick {
	Session =>
		filename:		string;
		owner:		string;
		invitations: 	list of string;
		members:		list of string;
		invited:		int;
	Sessiontype =>
		start:			string;
		name:		string;
		title:			string;
		clienttype:	string;
	Invite =>
		session:		ref Object.Session;
		name:		string;
	Member =>
		parentid:		int;
		name:		string;
	Archive =>
	Other =>
	}
};

drawctxt: ref Draw->Context;
cliquefd: ref Sys->FD;
objects: array of ref Object;
myname: string;
maxid := 0;

badmodule(m: string)
{
	sys->fprint(sys->fildes(2), "lobby: cannot load %s: %r\n", m);
	raise "fail:bad module";
}

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;

	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		badmodule(Tkclient->PATH);
	tkclient->init();

	commandline = load Commandline Commandline->PATH;
	if(commandline == nil)
		badmodule(Commandline->PATH);
	commandline->init();

	dividers = load Dividers Dividers->PATH;
	if (dividers == nil)
		badmodule(Dividers->PATH);
	dividers->init();

	join = load Join Join->PATH;
	if (join == nil)
		badmodule(Join->PATH);

	drawctxt = ctxt;
	cliquefd = sys->fildes(0);
	sys->pctl(Sys->NEWPGRP, nil);
	client1();
}

columns := array[] of {("name", ""), ("members", ""), ("watch", "Watch"), ("join", "Join"), ("invite", "Invite")};

reqwidth(win: ref Tk->Toplevel, w: string): int
{
	return 2 * int cmd(win, w + " cget -bd") + int cmd(win, w + " cget -width");
}

client1()
{
	(win, winctl) := tkclient->toplevel(drawctxt, nil, "Lobby", Tkclient->Appl);
	ech := chan of string;
	tk->namechan(win, ech, "e");
	(chat, chatevent) := Cmdline.new(win, ".d2", nil);
	updatech := chan of list of string;
	spawn readproc(updatech);

	cmd(win, "frame .buts");
	cmd(win, "menubutton .buts.start -text New -menu .buts.start.m");
	cmd(win, "menu .buts.start.m");
	cmd(win, "pack .buts.start -side left");
	cmd(win, "button .buts.kick -text Kick -command {send e kick}");
	cmd(win, "pack .buts.kick -side left");
	cmd(win, "pack .buts -side top -fill x");

	cmd(win, "frame .d1");

	cmd(win, "scrollbar .d1.s -orient vertical -command {.d1.c yview}");
	cmd(win, "canvas .d1.c -yscrollcommand {.d1.s set}");
	cmd(win, "pack .d1.s -side left -fill y");
	cmd(win, "pack .d1.c -side top -fill both -expand 1");
	cmd(win, "frame .t");
	cmd(win, ".d1.c create window 0 0 -anchor nw -window .t");
	cmd(win, "frame .t.f1 -bd 2 -relief sunken");
	cmd(win, "pack .t.f1 -side top -fill both -expand 1");

	cmd(win, "label .t.f1.sessionlabel -text Sessions -font " + TITLEFONT);
	cmd(win, "pack .t.f1.sessionlabel");
	cmd(win, "frame .t.s");
	cmd(win, "pack .t.s -in .t.f1 -side top -fill both -expand 1");

	cmd(win, "frame .t.f2 -bd 2 -relief sunken");
	cmd(win, "label .t.archiveslabel -text Archives -font " + TITLEFONT);
	cmd(win, "pack .t.archiveslabel");
	cmd(win, "frame .t.a");
	cmd(win, "pack .t.a -in .t.f2 -side top -fill both -expand 1 -anchor w");
	cmd(win, "pack .t.f2 -side top -fill both -expand 1");

	cmd(win, "label .t.a.title0 -text Title -font " + HEADERFONT);
	cmd(win, "label .t.a.title1 -text Members -font " + HEADERFONT);
	cmd(win, "grid .t.a.title0 .t.a.title1 -sticky w");
	cmd(win, "grid columnconfigure .t.a 1 -weight 1");

	cmd(win, "bind .t <Configure> {.d1.c configure -scrollregion {0 0 [.t cget -width] [.t cget -height]}}");

	cmd(win, "button .tmp");
	for (i := 0; i < len columns; i++) {
		(name, mintext) := columns[i];
		cmd(win, ".tmp configure -text '" + mintext);
		cmd(win, "grid columnconfigure .t.s " + string i +
			" -name " + name +
			" -minsize " + string reqwidth(win, ".tmp"));
	}
	cmd(win, "grid columnconfigure .t.s members -weight 1");
	cmd(win, "destroy .tmp");
	cmd(win, "menu .invite");

	(divider, dividerevent) := Divider.new(win, ".d", ".d1" :: ".d2" :: nil, Dividers->NS);
	cmd(win, "pack .d -side top -fill both");
	cmd(win, "pack propagate . 0");
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd"::"ptr"::nil);
	for (;;) {
		alt {
		s := <-win.ctxt.kbd =>
			tk->keyboard(win, s);
		s := <-win.ctxt.ptr =>
			tk->pointer(win, *s);
		s := <-win.ctxt.ctl or
		s = <-win.wreq or
		s = <-winctl =>
			tkclient->wmctl(win, s);
		c := <-dividerevent =>
			divider.event(c);
		c := <-chatevent =>
			lines := chat.event(c);
			for (; lines != nil; lines = tl lines) {
				line := hd lines;
				if (len line > 0 && line[len line-1]=='\n')
					line = line[0:len line-1];
				cliquecmd("chat " + line);
			}
		lines := <-updatech =>
#sys->print("++\n");
			for (; lines != nil; lines = tl lines) {
#sys->print("+%s\n", hd lines);
				doupdate(win, chat, hd lines);
			}
			cmd(win, "update");
		c := <-ech =>
			(n, toks) := sys->tokenize(c, " ");
			case hd toks {
			"watch" =>
				joinclique(win, chat, int hd tl toks, "watch");
			"join" =>
				joinclique(win, chat, int hd tl toks, "join");
			"start" =>
				start(win, chat, int hd tl toks);
			"postinvite" =>
				postinvite(win, int hd tl toks, hd tl tl toks);
			"unarchive" =>
				e := cliquecmd("unarchive " + hd tl toks);
				if (e != nil)
					chat.addtext("failed to unarchive: " + e + "\n");
			"invite" =>
				# invite sessionid name
				(id, name) := (hd tl toks, hd tl tl toks);
				vname := "inv." + name;
				v := int cmd(win, "variable " + vname);
				s := "invite";
				if (!v)
					s = "uninvite";
				e := cliquecmd(s + " " + string id + " " + name);
				if (e != nil) {
					chat.addtext("invite failed: " + e + "\n");
					cmd(win, "variable " + vname + " " + string !v);
				}
			"kick" =>
				e := cliquecmd("kick");
				if (e != nil)
					chat.addtext("kick failed: " + e + "\n");
			* =>
				sys->print("unknown msg %s\n", c);
			}
			cmd(win, "update");
		}
	}
}

joinclique(nil: ref Tk->Toplevel, chat: ref Cmdline, id: int, how: string)
{
	pick o := objects[id] {
	Session =>
		e := join->join(drawctxt, "/n/remote", o.filename, how);
		if (e != nil)
			chat.addtext("couldn't join clique: " + e + "\n");
		else
			chat.addtext("joined clique ok\n");
	* =>
		sys->print("join bad id %d (type %d)\n", id, tagof objects[id]);
	}
}

start(nil: ref Tk->Toplevel, chat: ref Cmdline, id: int)
{
	pick o := objects[id] {
	Sessiontype =>
		e := cliquecmd("start " + o.start);
		if (e != nil)
			chat.addtext("failed to start clique: " + e + "\n");
	* =>
		sys->print("start bad id %d (type %d)\n", id, tagof objects[id]);
	}
}

postinvite(win: ref Tk->Toplevel, id: int, widget: string)
{
	pick o := objects[id] {
	Session =>
		cmd(win, ".invite delete 0 end");
		cmd(win, ".invite add checkbutton -text All -variable inv.all -command {send e invite " + string id + " all}");
		for (invites := o.invitations; invites != nil; invites = tl invites)
			if (hd invites == "all")
				break;
		cmd(win, "variable inv.all " + string (invites != nil));

		for (i := 0; i < len objects; i++) {
			if (objects[i] == nil)
				continue;
			pick p := objects[i] {
			Member =>
				if (tagof(objects[p.parentid]) != tagof(Object.Session) && p.name != o.owner) {
					for (invites = o.invitations; invites != nil; invites = tl invites)
						if (hd invites == p.name)
							break;
					invited := invites != nil;
					cmd(win, "variable inv." + p.name + " " + string invited);
					cmd(win, ".invite add checkbutton -variable inv." + p.name +
						" -command {send e invite " + string id + " " + p.name + "}" +
						" -text '" + p.name);
				}
			}
		}
		x := int cmd(win, widget + " cget -actx");
		y := int cmd(win, widget + " cget -acty");
		h := 2 * int cmd(win, widget + " cget -bd") + int cmd(win, widget + " cget -actheight");
		cmd(win, ".invite post " + string x + " " + string (y + h));
	* =>
		sys->print("bad invited id %d (type %d)\n", id, tagof objects[id]);
	}
}

panic(s: string)
{
	sys->print("lobby panic: %s\n", s);
	raise "panic";
}

doupdate(win: ref Tk->Toplevel, chat: ref Cmdline, line: string)
{
	(n, toks) := sys->tokenize(line, " ");
	if (n == 0)
		return;
	case hd toks {
	"chat" =>
		chat.addtext(sys->sprint("%s: %s\n", hd tl toks, concat(tl tl toks)));
	"create" =>
		# create id parentid vis type
		id := int hd tl toks;
		if (id >= len objects)
			objects = (array[len objects + 10] of ref Object)[0:] = objects;
		if (objects[id] != nil)
			panic(sys->sprint("object %d already exists!", id));
		parentid := int hd tl tl toks;
		objtype := tl tl tl tl toks;
		o: ref Object;
		case hd objtype {
		"sessiontype" =>
			o = ref Object.Sessiontype(id, nil, nil, nil, nil);
		"session" =>
			cmd(win, "grid rowinsert .t.s 0");
			cmd(win, "grid rowconfigure .t.s 0 -name id" + string id);
			f := ".t.s.f" + string id;
			cmd(win, "frame " + f);			# dummy, so we can destroy row easily
			cmd(win, "label "+f+".name");
			cmd(win, "grid "+f+".name -row id" + string id + " -column name -in .t.s");
			cmd(win, "button "+f+".watch -text Watch -command {send e watch " + string id + "}");
			cmd(win, "grid "+f+".watch -row id" + string id + " -column watch -in .t.s");
			cmd(win, "label "+f+".members -font " + NAMEFONT);
			cmd(win, "grid "+f+".members -row id" + string id + " -column members -in .t.s");
			o = ref Object.Session(id, nil, nil, nil, nil, 0);
		"member" =>
			o = ref Object.Member(id, parentid, nil);
		"invite" =>
			pick parent := objects[parentid] {
			Session =>
				o = ref Object.Invite(id, parent, nil);
			* =>
				panic("invite not under session");
			}
		"archive" =>
			cmd(win, "grid rowinsert .t.a 1");
			cmd(win, "grid rowconfigure .t.a 1 -name id" + string id);
			f := ".t.a.f" + string id;
			cmd(win, "frame " + f);
			cmd(win, "label "+f+".name");
			cmd(win, "grid "+f+".name -row id" + string id + " -column 0 -in .t.a -sticky w");
			cmd(win, "label "+f+".members -anchor w -font " + NAMEFONT);
			cmd(win, "grid "+f+".members -row id" + string id + " -column 1 -in .t.a -sticky ew");
			cmd(win, "button "+f+".unarchive -text Unarchive -command {send e unarchive " + string id + "}");
			cmd(win, "grid "+f+".unarchive -row id" + string id + " -column 2 -in .t.a");
			o = ref Object.Archive(id);
		* =>
			o = ref Object.Other(id);
		}
		objects[id] = o;

	"del" =>
		# del parent start end objs...
		for (objs := tl tl tl tl toks; objs != nil; objs = tl objs) {
			id := int hd objs;
			pick o := objects[id] {
			Session =>
				cmd(win, "grid rowdelete .t.s id" + string id);
				cmd(win, "destroy .t.s.f" + string id);
			Archive =>
				cmd(win, "grid rowdelete .t.a id" + string id);
				cmd(win, "destroy .t.a.f" + string id);
			Sessiontype =>
				sys->print("cannot destroy sessiontypes yet\n");
			Member =>
				pick parent := objects[o.parentid] {
				Session =>
					parent.members = removeitem(parent.members, o.name);
					cmd(win, sys->sprint(".t.s.f%d.members configure -text '%s", o.parentid, concat(parent.members)));
				* =>
					chat.addtext(o.name + " has left\n");
				}
			Invite =>
				s := o.session;
				invites := s.invitations;
				invited := 0;
				for (s.invitations = nil; invites != nil; invites = tl invites) {
					inv := hd invites;
					if (inv != o.name) {
						s.invitations = inv :: s.invitations;
						if (inv == "all" || inv == myname)
							invited = 1;
					}
				}
				if (!invited && s.invited) {
					cmd(win, "destroy .t.s.f" + hd tl toks + ".join");
					s.invited = 0;
				}
			}
			objects[id] = nil;
		}

	"name" =>
		myname = hd tl toks;
		tkclient->settitle(win, "Lobby (" + myname + ")");

	"set" =>
		# set obj attr val
		id := int hd tl toks;
		(attr, val) := (hd tl tl toks, tl tl tl toks);
		pick o := objects[id] {
		Session =>
			f := ".t.s.f" + string id;
			case attr {
			"filename" =>
				o.filename = hd val;
			"owner" =>
				if (hd val == myname) {
					cmd(win, "label "+f+".invite -text Invite -bd 2 -relief raised");
					cmd(win, "bind "+f+".invite <Button-1> {send e postinvite " + string id + " %W}");
					cmd(win, "grid "+f+".invite -row id" + string id + " -column invite -in .t.s");
				}
				o.owner = hd val;
			"title" =>
				cmd(win, f + ".name configure -text '" + concat(val));
			}
		Archive =>
			f := ".t.a.f" + string id;
			case attr {
			"name" =>
				cmd(win, f + ".name configure -text '" + concat(val));
			"members" =>
				cmd(win, f + ".members configure -text '" + concat(val));
			}
		Sessiontype =>
			case attr {
			"start" =>
				o.start = concat(val);
			"clienttype" =>
				o.clienttype = hd val;
			"title" =>
				if (o.title != nil)
					panic("can't change sessiontype name!");
				else {
					o.title = concat(val);
					cmd(win, ".buts.start.m add command" +
							" -command {send e start " + string id + "}" +
							" -text '" + o.title);
				}
			"name" =>
				o.name = hd val;
			}
		Member =>
			case attr {
			"name" =>
				if (o.name != nil)
					panic("cannot change member name!");
				o.name = hd val;
				pick parent := objects[o.parentid] {
				Session =>
					parent.members = o.name :: parent.members;
					cmd(win, sys->sprint(".t.s.f%d.members configure -text '%s", o.parentid, concat(parent.members)));
				* =>
					chat.addtext(o.name + " has arrived\n");
				}
			}
		Invite  =>
			case attr {
			"name" =>
				o.name = hd val;
				s := o.session;
				sid := string s.id;
				f := ".t.s.f" + sid;
				invited := o.name == myname || o.name == "all";
				s.invitations = o.name :: s.invitations;
				if (invited && !s.invited) {
					cmd(win, "button "+f+".join -text Join -command {send e join " + sid + "}");
					cmd(win, "grid "+f+".join -row id" + sid + " -column join -in .t.s");
					s.invited = 1;
				}
			}
		}
	}
}

removeitem(l: list of string, i: string): list of string
{
	rl: list of string;
	for (; l != nil; l = tl l)
		if (hd l != i)
			rl = hd l :: rl;
	return rl;
}

numsplit(s: string): (string, int)
{
	for (i := len s - 1; i >= 0; i--)
		if (s[i] < '0' || s[i] > '9')
			break;
	if (i == len s -1)
		return (s, 0);
	return (s[0:i+1], int s[i+1:]);
}

cliquecmd(s: string): string
{
	if (sys->fprint(cliquefd, "%s", s) == -1) {
		e := sys->sprint("%r");
		sys->print("error on '%s': %s\n", s, e);
		return e;
	}
	return nil;
}

prefixed(s: string, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

readproc(updatech: chan of list of string)
{
	buf := array[Sys->ATOMICIO] of byte;
	while ((n := sys->read(cliquefd, buf, Sys->ATOMICIO)) > 0) {
		(nil, lines) := sys->tokenize(string buf[0:n], "\n");
		if (lines != nil)
			updatech <-= lines;
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
		exit;
	}
	mod->init(drawctxt, argv);
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
