implement Blurdemo;

include "sys.m";
	sys : Sys;
include "draw.m";
	draw: Draw;
	Display, Rect, Image: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "readdir.m";
	readdir: Readdir;
include "sh.m";
include "registries.m";
	registries: Registries;
	Registry, Attributes, Service: import registries;
include "grid/pathreader.m";
	reader: PathReader;
include "grid/browser.m";
	browser: Browser;
	Browse, Select, File, Parameter,
	DESELECT, SELECT, TOGGLE: import browser;
include "grid/srvbrowse.m";
	srvbrowse: Srvbrowse;
include "grid/announce.m";
	announce: Announce;
include "grid/readjpg.m";
	readjpg: Readjpg;

srvfilter: list of list of (string, string);
currstep: int;

currsrv: ref Service;
currattach: ref Registries->Attached;
ctxt: ref Draw->Context;
display: ref Draw->Display;
sysname : string;

IMAGE: con 0;
MOUNT: con 4;

imgcache: ref Image;
br: ref Browse;
sel: ref Select;

Blurdemo : module {
	init : fn (context : ref Draw->Context, argv : list of string);
	readpath: fn (dir: File): (array of ref sys->Dir, int);
};

init(context : ref Draw->Context, argv: list of string)
{
	ctxt = context;
	display = ctxt.display;
	sys = load Sys Sys->PATH;
	if (sys == nil)
		badmod(Sys->PATH);
	readdir = load Readdir Readdir->PATH;
	if (readdir == nil)
		badmod(Readdir->PATH);
	draw = load Draw Draw->PATH;
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
	browser = load Browser Browser->PATH;
	if (browser == nil)
		badmod(Browser->PATH);
	browser->init();
	srvbrowse = load Srvbrowse Srvbrowse->PATH;
	if (srvbrowse == nil)
		badmod(Srvbrowse->PATH);
	srvbrowse->init();
	announce = load Announce Announce->PATH;
	if (announce == nil)
		badmod(Announce->PATH);
	announce->init();
	reader = load PathReader "$self";
	if (reader == nil)
		badmod("PathReader");
	readjpg = load Readjpg Readjpg->PATH;
	if (readjpg == nil)
		badmod(Readjpg->PATH);
	readjpg->init(display);
	sys->pctl(sys->FORKNS | sys->NEWPGRP, nil);
	if (ctxt == nil) {
		sys->print("no draw context found!\n");
		exit;
	}
	sysname = readfile("/dev/sysname");
	if (sysname == "")
		sysname = "Localhost";
	imgcache = nil;
	setsrvfilter();
	root := "/";
	currsrv = nil;
	
	attribs := ("resource", "Cpu Pool") :: nil;
	lcpupool := srvbrowse->find(attribs :: nil);
	if (lcpupool == nil) {
		browser->dialog(ctxt, nil, "ok" :: nil, "Alert","Cannot find a Cpu Pool Resource");
		raise "fail: error cannot find a Cpu Pool resource";
	}

	(top, titlebar) := tkclient->toplevel(ctxt,"","BlurDemo", tkclient->Appl);
	butchan := chan of string;
	tk->namechan(top, butchan, "butchan");
	browsechan := chan of string;
	tk->namechan(top, browsechan, "browsechan");
	selectchan := chan of string;
	tk->namechan(top, selectchan, "selectchan");
	br = Browse.new(top, "browsechan", "services/", "Services", 1, reader);
	bropened := array[] of {
		"services/",
		"services/Data source/",
		"services/Camera/",
		"/n/remote/",
		"/" ,
	};
	for (i := 0; i < len bropened; i++)
		br.addopened(File (bropened[i], nil), 1);

	sel = Select.new(top, "selectchan");

	for (ik := 0; ik < len mainscreen; ik++)
		tkcmd(top,mainscreen[ik]);

	currstep = -1;
	
	sel.addframe("image", "Select a '.bit' image");

	changestep(top, IMAGE, nil);

	tkcmd(top, "pack .f -fill both -expand 1; pack propagate . 0");
	released := 1;
	title := "";
	resize(top, ref Rect ((0,0), (400,400)));
	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	tkpath: string;
	selected := array[2] of File;
	if (tl argv != nil)
		spawn initimg(butchan, hd tl argv);

	main: for (;;) {
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		inp := <-browsechan =>
			(nil, lst) := sys->tokenize(inp, " \n\t");
			if (len lst > 1)
				tkpath = hd tl lst;
			selected[0] = br.getselected(0);
			selected[1] = br.getselected(1);
			br.defaultaction(lst, nil);
			i = -1;
			if (!File.eq(selected[0], br.getselected(0)))
				i = 0;
			if (!File.eq(selected[1], br.getselected(1)))
				i = 1;
			if (i != -1) {
				sel.select(sel.currfname,nil,DESELECT);
				actionbutton(top, br.selected[i].file.path, br.selected[i].tkpath);
			}
			tkcmd(top, "update");
		inp := <-selectchan =>
			(nil, lst) := sys->tokenize(inp, " \n\t");
			case hd lst {
				"but3" =>
					tkpath = hd tl lst;
					x := string (int hd tl tl lst - 5);
					y := string (int hd tl tl tl lst - 5);

					path := tkcmd(top, tkpath+" cget -text");
					s := blursrvc.attrs.get("name") + " ("+blursrvc.addr+")";
					tk->cmd(top, "destroy .m2");
					tkcmd(top, "menu .m2 -font /fonts/charon/plain.normal.font");
					tkcmd(top, ".m2 add command -label {"+path+"}");
					tkcmd(top, ".m2 add separator");
					tkcmd(top, ".m2 add command -label {"+s+"}");
					tkcmd(top, ".m2 post "+x+" "+y);					
				"double1" =>
					tkpath = hd tl lst;
					path := tkcmd(top, tkpath+" cget -text");
					qid := "";
					(n, nil) := sys->tokenize(path, "/");
					if (currstep == IMAGE) {
						qid = srvbrowse->getqid(blursrvc);
						(res,name) := srvbrowse->getresname(blursrvc);
						path = "services/"+res+"/"+name+"/";
					}
					else if (currsrv.addr != blursrvc.addr)
						break;
					else if (blursrvc.addr != "Local Machine")
						path = "/n/remote" + path;
					tkpath = br.gotoselectfile(File(path,qid));
					if (tkpath != nil) {
						sel.select(sel.currfname, nil, DESELECT);
						actionbutton(top, path, tkpath);
					}
				"but1" =>
					if (currstep == IMAGE)
						br.selectfile(0, DESELECT, File (nil, nil), nil);
					else
						br.selectfile(1, DESELECT, File (nil, nil), nil);
					sel.defaultaction(lst);
					actionbutton(top, sel.getselected(sel.currfname), hd tl lst);
				* =>
					sel.defaultaction(lst);
			}
			tkcmd(top, "update");
		inp := <-butchan =>
			# sys->print("inp: %s\n",inp);
			(nil, lst) := sys->tokenize(inp, " \n\t");
			if (len lst > 1)
				tkpath = hd tl lst;
			case hd lst {
				"refresh" =>
					# ! check to see if anything is mounted first
					if (currstep == IMAGE) {
						# addlocalservice();
						srvbrowse->refreshservices(srvfilter);
					}
					br.refresh();
				"back" =>
					changestep(top, IMAGE, nil);
				"run" =>
					spawn run(ctxt, getcoords(top));
				"preview" =>
					spawn previewwin(top, butchan, hd tl lst);
				"add" =>
					additem(top, hd tl lst, int hd tl tl lst);
				"del" =>
					sel.delselection("image", hd tl lst);
					tkcmd (top, ".f.ftop.bn configure -state disabled");
					blurimage = nil;
					blurtkpath = nil;
					blursrvc = nil;
					actionbutton(top, sel.getselected(sel.currfname), hd tl lst);
				"mount" =>
					file := br.getpath(tkpath);
					(nsrv, lsrv) := sys->tokenize(file.path, "/");
					if (currstep != IMAGE)
						break;
					if (nsrv != 3)
						break;
					if (hd tl tl lsrv != "Local Filestore") {
						ok := mountsrv(file.path, file.qid, getcoords(top));
						if (!ok)
							break;
						changestep(top, MOUNT, hd tl tl lsrv);
					}
					else {
						srv : Service;
						srv.attrs = Attributes.new(("name", sysname) :: nil);
						srv.addr = "Local Machine";
						currsrv = ref srv;
						changestep(top, MOUNT, hd tl tl lsrv);
					}
			}
			tkcmd(top, "update");

		title = <-top.ctxt.ctl or
		title = <-top.wreq or
		title = <-titlebar =>
			if (title == "exit")
				break main;
			e := tkclient->wmctl(top, title);
			if (e == nil && title[0] == '!') {
				(nil, lst) := sys->tokenize(title, " \t\n");
				if (len lst >= 2 && hd lst == "!size" && hd tl lst == ".")
					resize(top, nil);
			}
		}
	}
	currattach = nil;
	killg(sys->pctl(0,nil));
}

resize(top: ref Tk->Toplevel, r: ref Draw->Rect)
{
	if (r != nil) {
		sw := (*r).dx();
		sh := (*r).dy();
		ww := int tkcmd(top, ". cget -actwidth");
		wh := int tkcmd(top, ". cget -actheight");
		if (ww > sw)
			tkcmd(top, ". configure -x 0 -width "+string sw);
		if (wh > sh)
			tkcmd(top, ". configure -y 0 -height "+string sh);
	}
	w := int tkcmd(top, ".fselect cget -actwidth");
	h := int tkcmd(top, ".fselect cget -actheight");
	sel.resize(w,h);
}

nactionbuttons := 0;
actionbutton(top: ref Tk->Toplevel, path, tkpath: string)
{
	for (i := 0; i < nactionbuttons; i++) {
		tkcmd(top, "grid forget .f.ftop.baction"+string i);
		tkcmd(top, "destroy .f.ftop.baction"+string i);
	}
	if (path == nil) {
		nactionbuttons = 0;
		return;
	}
	buttons : list of (string,string) = nil;
	(n, nil) := sys->tokenize(path, "/");
	if (len tkpath > 8 && tkpath[:8] == ".fselect")
		buttons = ("Remove", "del "+tkpath) :: buttons;
	else {
		if (currstep == IMAGE) {
			if (n == 3)
				buttons = ("Mount", "mount "+tkpath) :: buttons;
		}
		else {
			if (len path > 4) {
				if (path[len path - 4:] == ".bit") {
					buttons = ("Select", "add "+path+" 0") ::
							("Preview", "preview "+path) :: buttons;
				}
				else if (path[len path - 4:] == ".jpg")
					buttons = ("Select", "add "+path+" 0") :: buttons;
			}
		}
	}
	nactionbuttons = len buttons;
	for (i = 0; i < nactionbuttons; i++) {
		name := ".f.ftop.baction"+string i+" ";
		(text,cmd) := hd buttons;
		tkcmd(top, "button "+name+"-text {"+text+"} "+
				"-font /fonts/charon/bold.normal.font "+
				"-command {send butchan "+cmd+"}");
		tkcmd(top, "grid "+name+" -row 0 -column "+string (4+i));
		buttons = tl buttons;
	}
}

initimg(butchan: chan of string, imgpath: string)
{
	srv : Service;
	srv.attrs = Attributes.new(("name", sysname) :: nil);
	srv.addr = "Local Machine";
	currsrv = ref srv;
	butchan <-= "add "+imgpath+" 0";
	butchan <-= "back";
}

blurimage := "";
blurtkpath := "";
blursrvc: ref Service;

additem(top: ref Tk->Toplevel, path: string, overwrite: int)
{
	if (blurimage != nil) {
		if (overwrite || browser->dialog(ctxt, top, "ok" :: "cancel" :: nil,
			"Alert","Replace existing image '"
			+nopath(blurimage)+"' with '"+nopath(path)+"'?") == 0) {
			sel.delselection("image", blurtkpath);
		}
		else
			return;
	}
	imgpath := path;
	if (currsrv.addr != "Local Machine")
		path = path[len "/n/remote":];
	blurtkpath = sel.addselection("image", path, nil, 0);
	tkcmd(top, "update");
	blurimage = path;
	blursrvc = currsrv;
	if (overwrite)
		spawn getpreview(blurtkpath, nil, imgcache);
	else
		spawn getpreview(blurtkpath, imgpath, nil);
}

nopath(file: string): string
{
	return file[len browser->prevpath(file):];
}

runscr := array[] of {
	"frame .f",
	"frame .f.f1",
	"label .f.f1.l -text {Select no of CPUs} -font /fonts/charon/plain.normal.font",
	"scale .f.f1.s -orient horizontal -height 16 -showvalue 0 -from 1 -to 20 -command {.f.f1.ls configure -text}",
	"label .f.f1.ls -text {1} -font /fonts/charon/plain.normal.font -width 30",
	"button .f.f1.b -text {Run} -font /fonts/charon/plain.normal.font -command {send butchan go}",
	"pack .f.f1.l .f.f1.s .f.f1.ls .f.f1.b -side left",
	"frame .f.f2",
	"text .f.f2.t -width 250 -height 150 -borderwidth 1 -bg white -font /fonts/charon/plain.normal.font -yscrollcommand { .f.f2.sy set }",
	"scrollbar .f.f2.sy -command { .f.f2.t yview }",
	"pack .f.f2.sy -side left -fill y",
	"pack .f.f2.t -fill both -expand 1",
	"bind .Wm_t <Button-1> +{focus .Wm_t}",
	"bind .Wm_t.title <Button-1> +{focus .Wm_t}",
	"focus .Wm_t",
	"pack .f.f1 -side top",
	"pack .f.f2 -fill both -expand 1",
};

run(ctxt: ref Draw->Context, coords: draw->Rect)
{
	(top, titlectl) := tkclient->toplevel(ctxt, "", nil, tkclient->Resize);
	butchan := chan of string;
	sync := chan of int;
	quit := chan of int;
	tk->namechan(top, butchan, "butchan");
	tkcmds(top, runscr);
	tkcmd(top, ". configure "+getcentre(top, coords));
	tkcmd(top, "pack .f -fill both -expand 1; pack propagate . 0; focus .; update");
	tkclient->onscreen(top, "exact");
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	done := 1;
	loop: for (;;) {
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		<-sync =>
			tkcmd(top, ".f.f1.b configure -state normal; update");
			done = 1;
		inp := <-butchan =>
			(nil, lst) := sys->tokenize(inp, " \n\t");
			case hd lst {
				"go" =>
					tkcmd(top, ".f.f1.b configure -state disabled");
					ncpus := int tkcmd(top, ".f.f1.s get");
					done = 0;
					spawn startit(ncpus, butchan, sync, quit);
				"output" =>
					tkcmd(top, ".f.f2.t insert end {"+inp[len "output ":]+"}");
				"error" =>
					tkcmd(top, ".f.f2.t insert end {Error: "+inp[len "error ":]+"\n}");
					tkcmd(top, ".f.f1.b configure -state normal");
				"fewcpu" =>
					i := browser->dialog(ctxt, top, "ok" :: "cancel" :: nil, "Alert",
							"Only found "+hd tl lst+" cpus available. Continue?");
					quit <-= i;
					if (i == 1)
						return;
			}
			tkcmd(top, "update");
		s := <-top.ctxt.ctl or
		s = <-top.wreq or
		s = <- titlectl =>
			if (s == "exit") {
				if (done)
					return;
				break loop;
			}
			else
				tkclient->wmctl(top, s);
		}
	}
	top = nil;
	for (;;) alt {
		<- butchan =>
			;
		<-sync =>
			return;
	}
}

startit(ncpus: int, butchan: chan of string, sync, quit: chan of int)
{
	imgattached : ref Registries->Attached;
	imgpath := blurimage;
	if (blursrvc.addr != "Local Machine") {
		imgattached = blursrvc.attach(nil, nil);
		if (imgattached == nil) {
			butchan <-= "error cannot connect to data source: "+blursrvc.attrs.get("name");
			return;
		}
		if (sys->mount(imgattached.fd, nil, "/n/local", sys->MREPL, nil) == -1) {
			butchan <-= sys->sprint("error img mount failed: %r");
			return;
		}
		imgpath = "/n/local" + imgpath;
		butchan <-= "output Found image namespace\n";
	}
	sys->pctl(sys->FORKNS, nil);
	attribs := ("resource", "Cpu Pool") :: nil;
	lsrv := srvbrowse->find(attribs :: nil);
	if (lsrv == nil) {
		butchan <-= "error cannot find Cpu Pool resource";
		return;
	}
	cpupoolsrvc := hd lsrv;
	attached := cpupoolsrvc.attach(nil, nil);
	if (attached == nil) {
		butchan <-= "error cannot connect to Cpu Pool resource";
		return;
	}
	if (sys->mount(attached.fd, nil, "/n/remote", sys->MREPL, nil) == -1) {
		butchan <-= sys->sprint("error Cpu Pool mount failed: %r");
		return;
	}
	butchan <-= "output Connected to Cpu Pool resource\n";
	if (blurimage[len blurimage - 4:] == ".jpg") {
		butchan <-= "output Converting jpg => bit image\n";
		chanin := chan of string;
		killchan := chan of int;
		spawn jpgprog(butchan, chanin, killchan);
		img := readjpg->jpg2img(imgpath, "", chan of string, chanin);
		killchan <-= 1;
		butchan <-= "output \n";
		if (img == nil) {
			butchan <-= "error Error converting jpg";
			return;
		}
		sys->remove("/n/remote/data/blurimage.bit");
		fd := sys->create("/n/remote/data/blurimage.bit", sys->OWRITE, 8r666);
		if (fd == nil || display.writeimage(fd, img) == -1) {
			butchan <-= sys->sprint("error Error saving bit: %r");
			return;
		}
		imgpath = "/n/remote/data/blurimage.bit";
	}
	afd := array[ncpus] of ref sys->FD;
	ngot := 0;
	for (i := 0; i < ncpus; i++) {
		afd[ngot] = sys->open("/n/remote/clone", sys->ORDWR);
		if (afd[ngot] == nil)
			break;
		ngot++;
	}
	if (ngot == 0) {
		butchan <-= "error no cpu resources available";
		return;
	}
	if (ngot < ncpus) {
		butchan <-= "fewcpu "+string ngot;
		q := <-quit;
		if (q)
			return;
	}
	butchan <-= "output Found "+string ngot+" Cpu resource(s)\n";
	sh := load Sh Sh->PATH;
	if (sh == nil)
		badmod(Sh->PATH);
	sys->create("/n/remote/data/blur", sys->OREAD, 8r777 | sys->DMDIR);
	done := chan of int;
	for (i = 0; i < ngot; i++)
		spawn go(afd[i], i, butchan, done);
	err := sh->run(ctxt, "/dis/grid/demo/blur.dis" :: "/n/remote/data" :: imgpath :: nil);
	if (err != nil)
		butchan <-= "error "+err;
	finished := 0;
	for (;;) {
		<-done;
		finished++;
		if (finished == ngot)
			break;
	}
	sys->unmount(nil, "/n/remote");
	butchan <-= "output Finished\n";
	sync <-= 1;
}

jpgprog(butchan, chanin: chan of string, killchan: chan of int)
{
	i := 0;
	for (;;) alt {
		<-killchan =>
			return;
		<-chanin =>
			i = (i+1) % 2;
			if (i)
				butchan <-= "output .";	
	}
}

go(fd: ref sys->FD, id: int, butchan: chan of string, done: chan of int)
{
	op := "output Cpu "+string id+": ";
	sys->fprint(fd, "/dis/grid/demo/blur.dis /data/");
	buf := array[sys->ATOMICIO] of byte;
	sys->seek(fd, big 0, sys->SEEKSTART);
	i := sys->read(fd, buf, len buf);
	if (i < 1)
		sys->print("Error reading dir name: %r\n");
	dir := string buf[:i];
	if (dir[len dir - 1] == '\n')
		dir = dir[:len dir -1];
	fdout := sys->open("/n/remote/"+dir+"/data", sys->OREAD);
	if (fdout == nil) {
		butchan <-= op+"Cannot read from stdout";
		done <-= 1;
		return;
	}
	for (;;) {
		i = sys->read(fdout, buf, len buf);
		if (i < 1)
			break;
		s := string buf[:i];
		if (s[len s - 1] != '\n')
			s[len s] = '\n';
		butchan <-= op+s;
	}
	done <-= 1;
}

kill(pid: int)
{
	if ((fd := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE)) != nil)
		sys->fprint(fd, "kill");
}

killg(pid: int)
{
	if ((fd := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE)) != nil)
		sys->fprint(fd, "killgrp");
}

mainscreen := array[] of {
	"frame .f",
	"frame .f.ftop",
	"variable opt command",
	"button .f.ftop.bp -text {Services} -command {send butchan back} -font /fonts/charon/bold.normal.font -state disabled -state disabled",
	"button .f.ftop.bn -text {Run} -command {send butchan run} -font /fonts/charon/bold.normal.font -state disabled",
	"button .f.ftop.br -text {Refresh} -command {send butchan refresh} -font /fonts/charon/bold.normal.font",
 	"grid .f.ftop.br .f.ftop.bp .f.ftop.bn -row 0",
	"grid columnconfigure .f.ftop 3 -minsize 30",
	"label .f.l -text { } -height 1 -bg red",
	"grid .f.l -row 1 -column 0 -sticky ew",
	"grid .f.ftop -row 0 -column 0 -pady 2 -sticky w",
	"grid .fbrowse -in .f -row 2 -column 0 -sticky nsew",
	"grid .fselect -in .f -row 3 -column 0 -sticky nsew",
	"grid columnconfigure .f 0 -weight 1",
	"grid rowconfigure .f 2 -weight 1",
	"grid rowconfigure .f 3 -weight 1",

	"bind .Wm_t <Button-1> +{focus .Wm_t}",
	"bind .Wm_t.title <Button-1> +{focus .Wm_t}",
	"focus .Wm_t",
};

readpath(dir: File): (array of ref sys->Dir, int)
{
	if (currstep == MOUNT) {
		(dirs, nil) := readdir->init(dir.path, readdir->NAME | readdir->COMPACT);
		dirs2 := array[len dirs] of ref sys->Dir;
		num := 0;
		for (i := 0; i < len dirs; i++)
			if (dirs[i].mode & sys->DMDIR || 
				(len dirs[i].name > 4 && (
					dirs[i].name[len dirs[i].name - 4:] == ".bit" || 
					dirs[i].name[len dirs[i].name - 4:] == ".jpg")))
				dirs2[num++] = dirs[i];
		return (dirs2[:num], 0);
	}
	else
		return srvbrowse->servicepath2Dir(dir.path, int dir.qid);
	return (nil, 0);
}

badmod(path: string)
{
	sys->print("Blurdemo: failed to load %s: %r\n",path);
	exit;
}

mountscr := array[] of {
	"frame .f -borderwidth 2 -relief raised",
	"text .f.t -width 200 -height 60 -borderwidth 1 -bg white -font /fonts/charon/plain.normal.font",
	"button .f.b -text {Cancel} -command {send butchan cancel} -width 70 -font /fonts/charon/plain.normal.font",
	"grid .f.t -row 0 -column 0 -padx 10 -pady 10",
	"grid .f.b -row 1 -column 0 -sticky n",
	"grid rowconfigure .f 1 -minsize 30",
};

mountsrv(srvpath, qid: string, coords: draw->Rect):int
{
	(top, nil) := tkclient->toplevel(ctxt, "", nil, tkclient->Plain);
	ctlchan := chan of string;
	butchan := chan of string;
	tk->namechan(top, butchan, "butchan");
	tkcmds(top, mountscr);
	tkcmd(top, ". configure "+getcentre(top, coords)+"; pack .f; update");
	spawn mountit(srvpath, qid, ctlchan);
	pid := int <-ctlchan;
	tkclient->onscreen(top, "exact");
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	for (;;) {
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		e := <- ctlchan =>
			if (e[0] == '!') {
				tkcmd(top, ".f.t insert end {"+e[1:]+"}");
				tkcmd(top, ".f.b configure -text {close}; update");
				pid = -1;
			}
			else if (e == "ok")
				return 1;
			else
				tkcmd(top, ".f.t insert end {"+e+"}; update");
		<- butchan =>
			if (pid != -1)
				kill(pid);
			return 0;
		}
	}
	return 0;
}

mountit(srvpath, qid: string, ctlchan: chan of string)
{
	ctlchan <-= string sys->pctl(0,nil);

	n := 0;
	(nil, lst) := sys->tokenize(srvpath, "/");
	stype := hd tl lst;
	name := hd tl tl lst;
	addr := "";
	ctlchan <-= "Connecting...\n";
	lsrv := srvbrowse->servicepath2Service(srvpath, qid);
	if (len lsrv < 1) {
		ctlchan <-= "!could not find service";
		return;
	}
	srvc := hd lsrv;
	currattach = srvc.attach(nil, nil);
	if (currattach == nil) {
		ctlchan <-= "!attach failed";
		return;
	}
	ctlchan <-= "Mounting...\n";
	if (sys->mount(currattach.fd, nil, "/n/remote", sys->MREPL, nil) != -1) {
		ctlchan <-= "ok";
		currsrv = srvc;
	}
	else
		ctlchan <-= "!mount failed";
}

getcoords(top: ref Tk->Toplevel): draw->Rect
{
	h := int tkcmd(top, ". cget -height");
	w := int tkcmd(top, ". cget -width");
	x := int tkcmd(top, ". cget -actx");
	y := int tkcmd(top, ". cget -acty");
	r := draw->Rect((x,y),(x+w,y+h));
	return r;
}

getcentre(top: ref Tk->Toplevel, winr: draw->Rect): string
{
	h := int tkcmd(top, ".f cget -height");
	w := int tkcmd(top, ".f cget -width");
	midx := winr.min.x + (winr.dx() / 2);
	midy := winr.min.y + (winr.dy() / 2);
	newx := midx - (w/2);
	newy := midy - (h/2);
	return "-x "+string newx+" -y "+string newy;
}

changestep(top: ref Tk->Toplevel, step: int, label: string)
{
	root, rlabel: string;
	if (step == MOUNT) {
		tkcmd (top, ".f.ftop.bp configure -state normal");
		br.changeview(2);
			rlabel = label;
		if (currsrv.addr == "Local Machine")
			root = "/";
		else
			root = "/n/remote/";
	}
	else if (step == IMAGE) {
		br.changeview(1);
		if (currsrv != nil) {
			sys->unmount(nil, "/n/remote");
			currattach = nil;
			currsrv = nil;
		}
		srvbrowse->refreshservices(srvfilter);
		root = "services/";
		rlabel = "Image Services";
		sel.showframe("image");
		tkcmd (top, ".f.ftop.bp configure -state disabled");
		# addlocalservice();
		sel.select("image", nil, DESELECT);
	}
	currstep = step;
	br.selectfile(1, DESELECT, File (nil, nil), nil);
	br.selectfile(0, DESELECT,File (nil, nil), nil);
	actionbutton(top, nil, nil);	

	br.newroot(root, rlabel);
	if (currstep == MOUNT)
		br.selectfile(0, SELECT, File (root, nil), ".fbrowse.fl.f0.l");
	tkcmd(top, "update");
}

addlocalservice()
{
	lsrv : Service;
	attrs := ("resource", "Data source") ::
		("name", "Local Filestore") ::
		("type", "styx") :: nil;
	lsrv.attrs = Attributes.new(attrs);
	lsrv.addr = "@your local filestore";
	srvbrowse->addservice(ref lsrv);
}

tkcmd(top: ref Tk->Toplevel, cmd: string): string
{
	e := tk->cmd(top, cmd);
	if (e != "" && e[0] == '!')
		sys->print("Tk error: '%s': %s\n",cmd,e);
	return e;
}

tkcmds(top: ref Tk->Toplevel, a: array of string)
{
	for (j := 0; j < len a; j++)
		tkcmd(top, a[j]);
}

readfile(f: string): string
{
	fd := sys->open(f, sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return nil;

	return string buf[:n];	
}

setsrvfilter()
{
	imagefilter := ("proto", "styx") :: ("auth", "none") :: ("Image resource", "1") :: nil;
	srvfilter = imagefilter :: nil;	
}

getpreview(tkpath, imgpath: string, img: ref Image)
{
	if (imgpath != nil && imgpath[len imgpath - 4:] == ".jpg") {
		tkcmd (sel.top, ".f.ftop.bn configure -state normal");
		return;
	}
	if (img == nil) {
		img = display.open(imgpath);
		if (img == nil) {
			browser->dialog(ctxt, sel.top, "ok" :: nil, "Alert",
				sys->sprint("Invalid '.bit' image: %r"));
			sel.delselection("image", blurtkpath);
			blurimage = nil;
			blursrvc = nil;
			return;
		}
	}
	previmg := preview(img, 100);
	tk->cmd(sel.top, "destroy .preview");
	tkcmd(sel.top, "image create bitmap .preview");
	tk->putimage(sel.top, ".preview", previmg, nil);
	tkcmd(sel.top, sys->sprint("%s configure -image .preview -width %d -height %d",
		tkpath, previmg.r.dx(), previmg.r.dy()));
	tkcmd(sel.top, "grid forget "+tkpath+"; grid "+tkpath+" -row 1 "+
			"-column 0 -columnspan 3 -pady 5 -sticky ew;");
	sel.setscrollr(sel.currfname);
	tkcmd (sel.top, ".f.ftop.bn configure -state normal");
	tkcmd(sel.top, "update;");
}

preview(img: ref Image, maxsize: int): ref Image
{
	mx := max(img.r.dx(), img.r.dy());
	if (mx <= maxsize) {
		imgcache = img;
		return img;
	}
	prevr := Rect ((0,0), (img.r.dx()*maxsize/mx, img.r.dy()*maxsize/mx));
	tmpimg := display.newimage(img.r, Draw->RGB24, 0, Draw->White);
	previmg := display.newimage(prevr, Draw->RGB24, 0, Draw->White);
	tmpimg.draw(img.r, img, nil, (0,0));

	getr := Rect ((0,0), (img.r.dx() / prevr.dx(), img.r.dy() / prevr.dy()));

	nopixels := getr.dx() * getr.dy();
	getrgb := array[nopixels * 3] of byte;
	newrgb := array[3] of byte;
	for (y := 0; y < prevr.dy(); y++) {
		for (x := 0; x < prevr.dx(); x++) {
			tmpimg.readpixels(getr.addpt((x*getr.dx(), y*getr.dy())), getrgb);
			tmprgb := array[] of { 0, 0, 0 };
			for (i := 0; i < len getrgb; i++)
				tmprgb[i%3] += int getrgb[i];
			for (i = 0; i < 3; i++)
				newrgb[i] = byte (tmprgb[i] / nopixels);
			previmg.writepixels(((x,y),(x+1,y+1)), newrgb);
		}
	}
	imgcache = previmg;
	return previmg;
}

max(a,b: int): int
{
	if (a > b)
		return a;
	return b;
}

previewscr := array[] of {
	"frame .f",
	"panel .f.p -borderwidth 2 -relief raised",
	"button .f.bs -text Select -font /fonts/charon/plain.normal.font -command {send prevchan select} -state disabled",
	"button .f.bc -text Close -font /fonts/charon/plain.normal.font -command {send prevchan close} -state disabled",
	"pack .f",
	"grid .f.p -row 0 -column 0 -columnspan 2 -padx 5 -pady 5",
	"grid .f.bs .f.bc -row 1 -padx 5 -pady 5",
	"update",
};

previewwin(oldtop: ref Tk->Toplevel, chanout: chan of string, path: string)
{
	(top, titlectl) := tkclient->toplevel(ctxt, "", "Loading...", 0);
	prevchan := chan of string;
	tk->namechan(top, prevchan, "prevchan");
	tkclient->onscreen(top, "exact");

	img := display.open(path);
	if (img == nil) {
		browser->dialog(ctxt, oldtop, "ok" :: nil, "Alert", "Invalid '.bit' image");
		return;
	}
	
	previmg := preview(img, 100);
	tkcmds(top, previewscr);
	tk->putimage(top, ".f.p", previmg, nil);
	tkcmd(top, ".Wm_t.title configure -text Preview");
	tkcmd(top, ".f.p dirty; update");
	browser->setcentre(oldtop, top);
	tkcmd(top, ".f.bs configure -state normal; .f.bc configure -state normal");
	tkclient->startinput(top, "kbd"::"ptr"::nil);

	main: for(;;) alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		s := <- prevchan =>
			if (s == "select")
				chanout <-= "add "+path+" 1";
			break main;
		s := <-top.ctxt.ctl or
		s = <-top.wreq or
		s = <- titlectl =>
			if (s == "exit")
				break main;
			else
				tkclient->wmctl(top, s);
	}
}
