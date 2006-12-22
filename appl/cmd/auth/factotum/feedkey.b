implement Feedkey;

#
# Copyright © 2004 Vita Nuova Holdings Limited
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

include "string.m";
	str: String;

Feedkey: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

config := array[] of {
	"frame .f",
	"button .f.done -command {send cmd done} -text {Done}",
	"frame .f.key -bg white",
	"pack .f.key .f.done .f",
	"update"
};

Debug: con 0;

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	str = load String String->PATH;

	needfile := "/mnt/factotum/needkey";
	if(Debug)
		needfile = "/dev/null";

	needs := chan of list of ref Attr;
	acks := chan of int;

	sys->pctl(Sys->NEWPGRP|Sys->NEWFD, list of {0, 1, 2});

	fd := sys->open(needfile, Sys->ORDWR);
	if(fd == nil)
		err(sys->sprint("can't open %s: %r", needfile));
	spawn needy(fd, needs, acks);
	fd = nil;

	ctlfile := "/mnt/factotum/ctl";
	keyfd := sys->open(ctlfile, Sys->ORDWR);
	if(keyfd == nil)
		err(sys->sprint("can't open %s: %r", ctlfile));

	tkclient->init();

	spawn feedkey(ctxt, keyfd, needs, acks);
}

feedkey(ctxt: ref Draw->Context, keyfd: ref Sys->FD, needs: chan of list of ref Attr, acks: chan of int)
{
	(top, tkctl) := tkclient->toplevel(ctxt, nil, "Need key", Tkclient->Appl);

	cmd := chan of string;
	tk->namechan(top, cmd, "cmd");

	for(i := 0; i < len config; i++)
		tkcmd(top, config[i]);
	tkclient->startinput(top, "ptr" :: nil);
	tkclient->onscreen(top, nil);
	if(!Debug)
		tkclient->wmctl(top, "task");

	attrs: list of ref Attr;
	for(;;) alt{
	s :=<-tkctl or
	s = <-top.ctxt.ctl or
	s = <-top.wreq =>
		tkclient->wmctl(top, s);
	p := <-top.ctxt.ptr =>
		tk->pointer(top, *p);
	c := <-top.ctxt.kbd =>
		tk->keyboard(top, c);

	s := <-cmd =>
		case s {
		"done" =>
			result := extract(top, ".f.key", attrs);
			if(Debug)
				sys->print("result: %s\n", attrtext(result));
			if(sys->fprint(keyfd, "key %s", attrtext(result)) < 0)
				sys->fprint(sys->fildes(2), "feedkey: can't install key %q: %r\n", attrtext(result));
			acks <-= 0;
			tkclient->wmctl(top, "task");
			tk->cmd(top, "pack forget .f.key");
		* =>
			sys->fprint(sys->fildes(2), "feedkey: odd command: %q\n", s);
		}

	attrs = <-needs =>
		if(attrs == nil)
			exit;
		tkclient->startinput(top, "kbd" :: nil);
		tkcmd(top, "destroy .f.key");
		tkcmd(top, "frame .f.key -bg white");
		populate(top, ".f.key", attrs);
		tkcmd(top, "pack forget .f.done");
		tkcmd(top, "pack .f.key .f.done .f");
		tkcmd(top, "update");
		tkclient->wmctl(top, "unhide");
	}
}

err(s: string)
{
	sys->fprint(sys->fildes(2), "feedkey: %s\n", s);
	raise "fail:error";
}

user(): string
{
	fd := sys->open("/dev/user", Sys->OREAD);
	if(fd == nil)
		return nil;
	b := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, b, len b);
	if(n <= 0)
		return nil;
	return string b[0:n];
}

tkcmd(top: ref Tk->Toplevel, cmd: string): string
{
	if(0)
		sys->print("tk: %q\n", cmd);
	r := tk->cmd(top, cmd);
	if(r != nil && r[0] == '!')
		sys->fprint(sys->fildes(2), "feedkey: tk: %q on %q\n", r, cmd);
	return r;
}

populate(top: ref Tk->Toplevel, tag: string, attrs: list of ref Attr)
{
	c := 0;
	for(al := attrs; al != nil; al = tl al){
		a := hd al;
		if(a.name == nil)
			tkcmd(top, sys->sprint("entry %s.n%d -bg yellow", tag, c));
		else
			tkcmd(top, sys->sprint("label %s.n%d -bg white -text '%s", tag, c, a.name));
		tkcmd(top, sys->sprint("label %s.e%d -bg white -text '  =  ", tag, c));
		case a.tag {
		Aquery =>
			show := "";
			if(a.name != nil && a.name[0] == '!')
				show = " -show {•}";
			tkcmd(top, sys->sprint("entry %s.v%d%s -bg yellow", tag, c, show));
			if(a.val == nil && a.name == "user")
				a.val = user();
			tkcmd(top, sys->sprint("%s.v%d insert 0 '%s", tag, c, a.val));
			tkcmd(top, sys->sprint("grid %s.n%d %s.e%d %s.v%d -in %s -sticky w -pady 1", tag, c, tag, c, tag, c, tag));
		Aval =>
			if(a.name != nil){
				val := a.val;
				if(a.name[0] == '!')
					val = "...";	# just in case
				tkcmd(top, sys->sprint("label %s.v%d -bg white -text %s", tag, c, val));
			}else
				tkcmd(top, sys->sprint("entry %s.v%d -bg yellow", tag, c));
			tkcmd(top, sys->sprint("grid %s.n%d %s.e%d %s.v%d -in %s -sticky w -pady 1", tag, c, tag, c, tag, c, tag));
		Aattr =>
			tkcmd(top, sys->sprint("grid %s.n%d x x -in %s -sticky w -pady 1", tag, c, tag));
		}
		c++;
	}
}

extract(top: ref Tk->Toplevel, tag: string, attrs: list of ref Attr): list of ref Attr
{
	c := 0;
	nl: list of ref Attr;
	for(al := attrs; al != nil; al = tl al){
		a := ref *hd al;
		if(a.tag == Aquery){
			a.val = tkcmd(top, sys->sprint("%s.v%d get", tag, c));
			if(a.name == nil)
				a.name = tk->cmd(top, sys->sprint("%s.n%d get", tag, c));	# name might start with `!'
			if(a.name != nil){
				a.tag = Aval;
				nl = a :: nl;
			}
		}else
			nl = a :: nl;
		c++;
	}
	return nl;
}

reverse[T](l: list of T): list of T
{
	rl: list of T;
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rl;
}

needy(fd: ref Sys->FD, needs: chan of list of ref Attr, acks: chan of int)
{
	if(Debug){
		for(;;){
			needs <-= parseline("proto=pass user? server=fred.com service=ftp confirm !password?");
			<-acks;
		}
	}

	buf := array[512] of byte;
	while((n := sys->read(fd, buf, len buf)) > 0){
		s := string buf[0:n];
		for(i := 0; i < len s; i++)
			if(s[i] == ' ')
				break;
		if(i >= len s)
			continue;
		attrs := parseline(s[i+1:]);
		nl: list of ref Attr;
		tag: ref Attr;
		for(; attrs != nil; attrs = tl attrs){
			a := hd attrs;
			if(a.name == "tag")
				tag = a;
			else
				nl = a :: nl;
		}
		if(nl == nil)
			continue;
		attrs = reverse(ref Attr(Aquery, nil, nil) :: ref Attr(Aquery, nil, nil) :: nl);	# add a few blank
		if(attrs != nil && tag != nil && tag.val != nil){
			needs <-= attrs;
			<-acks;
			sys->fprint(fd, "tag=%d", int tag.val);
		}
	}
	if(n < 0)
		sys->fprint(sys->fildes(2), "feedkey: error reading needkey: %r\n");
	needs <-= nil;
}

# need a library module

Aattr, Aval, Aquery: con iota;

Attr: adt {
	tag:	int;
	name:	string;
	val:	string;

	text:	fn(a: self ref Attr): string;
};

parseline(s: string): list of ref Attr
{
	fld := str->unquoted(s);
	rfld := fld;
	for(fld = nil; rfld != nil; rfld = tl rfld)
		fld = (hd rfld) :: fld;
	attrs: list of ref Attr;
	for(; fld != nil; fld = tl fld){
		n := hd fld;
		a := "";
		tag := Aattr;
		for(i:=0; i<len n; i++)
			if(n[i] == '='){
				a = n[i+1:];
				n = n[0:i];
				tag = Aval;
			}
		if(len n == 0)
			continue;
		if(tag == Aattr && len n > 1 && n[len n-1] == '?'){
			tag = Aquery;
			n = n[0:len n-1];
		}
		attrs = ref Attr(tag, n, a) :: attrs;
	}
	return attrs;
}

Attr.text(a: self ref Attr): string
{
	case a.tag {
	Aattr =>
		return a.name;
	Aval =>
		return sys->sprint("%q=%q", a.name, a.val);
	Aquery =>
		return a.name+"?";
	* =>
		return "??";
	}
}

attrtext(attrs: list of ref Attr): string
{
	s := "";
	sp := 0;
	for(; attrs != nil; attrs = tl attrs){
		if(sp)
			s[len s] = ' ';
		sp = 1;
		s += (hd attrs).text();
	}
	return s;
}
