implement WmTask;

include "sys.m";
	sys: Sys;
	Dir: import sys;

include "draw.m";
	draw: Draw;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include "tkclient.m";
	tkclient: Tkclient;

include "dialog.m";
	dialog: Dialog;

Prog: adt
{
	pid:	int;
	pgrp: int;
	size:	int;
	state:	string;
	mod:	string;
};

WmTask: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Wm: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

task_cfg := array[] of {
	"frame .fl",
	"scrollbar .fl.scroll -command {.fl.l yview}",
	"listbox .fl.l -width 40w -yscrollcommand {.fl.scroll set}",
	"frame .b",
	"button .b.ref -text Refresh -command {send cmd r}",
	"button .b.deb -text Debug -command {send cmd d}",
	"button .b.files -text Files -command {send cmd f}",
	"button .b.kill -text Kill -command {send cmd k}",
	"button .b.killg -text {Kill Group} -command {send cmd kg}",
	"pack .b.ref .b.deb .b.files .b.kill .b.killg -side left -padx 2 -pady 2",
	"pack .b -fill x",
	"pack .fl.scroll -side left -fill y",
	"pack .fl.l -fill both -expand 1",
	"pack .fl -fill both -expand 1",
	"pack propagate . 0",
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys  = load Sys  Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "task: no window context\n");
		raise "fail:bad context";
	}
	draw = load Draw Draw->PATH;
	tk   = load Tk   Tk->PATH;
	tkclient= load Tkclient Tkclient->PATH;
	dialog = load Dialog Dialog->PATH;

	tkclient->init();
	dialog->init();

	sysnam := sysname();

	(t, wmctl) := tkclient->toplevel(ctxt, "", sysnam, Tkclient->Appl);
	if(t == nil)
		return;

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	for (c:=0; c<len task_cfg; c++)
		tk->cmd(t, task_cfg[c]);

	readprog(t);

	tk->cmd(t, ".fl.l see end;update");
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd"::"ptr"::nil);

	for(;;) alt {
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or
	s = <-t.wreq =>
		tkclient->wmctl(t, s);
	menu := <-wmctl =>
		case menu {
		"exit" =>
			return;
		"task" =>
			tkclient->wmctl(t, menu);
			tk->cmd(t, ".fl.l delete 0 end");
			readprog(t);
			tk->cmd(t, ".fl.l see end;update");
		* =>
			tkclient->wmctl(t, menu);
		}
	bcmd := <-cmd =>
		case bcmd {
		"d" =>
			sel := tk->cmd(t, ".fl.l curselection");
			if(sel == "")
				break;
			pid := int tk->cmd(t, ".fl.l get "+sel);
			stk := load Wm "/dis/wm/deb.dis";
			if(stk == nil)
				break;
			spawn stk->init(ctxt, "wm/deb" :: "-p "+string pid :: nil);
			stk = nil;
		"k" or "kg" =>
			sel := tk->cmd(t, ".fl.l curselection");
			if(sel == "")
				break;
			pid := int tk->cmd(t, ".fl.l get "+sel);
			what := "opening ctl file";
			cfile := "/prog/"+string pid+"/ctl";
			cfd := sys->open(cfile, sys->OWRITE);
			if(cfd != nil) {
				if(bcmd == "kg"){
					if(sys->fprint(cfd, "killgrp") > 0){
						cfd = nil;
						refresh(t);
						break;
					}
				}else if(sys->fprint(cfd, "kill") > 0){
					tk->cmd(t, ".fl.l delete "+sel);
					cfd = nil;
					break;
				}
				cfd = nil;
				what = "sending kill request";
			}
			if(bcmd == "k" && sys->sprint("%r") == "file does not exist") {
				refresh(t);
				break;
			}
			dialog->prompt(ctxt, t.image, "error -fg red", "Kill",
					"Error "+what+"\n"+
					 "System: "+sys->sprint("%r"),
					0, "OK" :: nil);
		"r" =>
			refresh(t);
		"f" =>
			sel := tk->cmd(t, ".fl.l curselection");
			if(sel == "")
				break;
			pid := int tk->cmd(t, ".fl.l get "+sel);
			fi := load Wm "/dis/wm/edit.dis";
			if(fi == nil)
				break;
			spawn fi->init(ctxt,
				"edit" ::
				"/prog/"+string pid+"/fd" :: nil);
			fi = nil;
		}
	}
}

refresh(t: ref Tk->Toplevel)
{
	tk->cmd(t, ".fl.l delete 0 end");
	readprog(t);
	tk->cmd(t, ".fl.l see end;update");
}

mkprog(file: string): ref Prog
{
	fd := sys->open("/prog/"+file+"/status", sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;

	(v, l) := sys->tokenize(string buf[0:n], " ");
	if(v < 6)
		return nil;

	prg := ref Prog;
	prg.pid = int hd l;
	l = tl l;
	prg.pgrp = int hd l;
	l = tl l;
	l = tl l;
	# eat blanks in user name
	while(len l > 3)
		l = tl l;
	prg.state = hd l;
	l = tl l;
	prg.size = int hd l;
	l = tl l;
	prg.mod = hd l;

	return prg;
}

readprog(t: ref Toplevel)
{
	fd := sys->open("/prog", sys->OREAD);
	if(fd == nil)
		return;
	for(;;) {
		(n, d) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			p := mkprog(d[i].name);
			if(p != nil){
				l := sys->sprint("%4d %4d %3dK %-7s  %s", p.pid, p.pgrp, p.size, p.state, p.mod);
				tk->cmd(t, ".fl.l insert end '"+l);
			}
		}
	}
}

sysname(): string
{
	fd := sys->open("#c/sysname", sys->OREAD);
	if(fd == nil)
		return "Anon";
	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0) 
		return "Anon";
	return string buf[0:n];
}
