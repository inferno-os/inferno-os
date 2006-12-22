implement View;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Context, Rect, Point, Display, Screen, Image: import draw;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "imagefile.m";
	imageremap: Imageremap;
	readgif: RImagefile;
	readjpg: RImagefile;
	readxbitmap: RImagefile;
	readpng: RImagefile;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include	"tkclient.m";
	tkclient: Tkclient;

include "selectfile.m";
	selectfile: Selectfile;

include	"arg.m";

include	"plumbmsg.m";
	plumbmsg: Plumbmsg;
	Msg: import plumbmsg;

stderr: ref Sys->FD;
display: ref Display;
x := 25;
y := 25;
img_patterns: list of string;
plumbed := 0;
background: ref Image;

View: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(ctxt: ref Draw->Context, argv: list of string)
{
	spawn realinit(ctxt, argv);
}

realinit(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "view: no window context\n");
		raise "fail:bad context";
	}
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	selectfile = load Selectfile Selectfile->PATH;

	sys->pctl(Sys->NEWPGRP, nil);
	tkclient->init();
	selectfile->init();

	stderr = sys->fildes(2);
	display = ctxt.display;
	background = display.color(16r222222ff);

	arg := load Arg Arg->PATH;
	if(arg == nil)
		badload(Arg->PATH);

	img_patterns = list of {
		"*.bit (Compressed image files)",
		"*.gif (GIF image files)",
		"*.jpg (JPEG image files)",
		"*.jpeg (JPEG image files)",
		"*.png (PNG image files)",
		"*.xbm (X Bitmap image files)"
		};

	imageremap = load Imageremap Imageremap->PATH;
	if(imageremap == nil)
		badload(Imageremap->PATH);

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		badload(Bufio->PATH);


	arg->init(argv);
	errdiff := 1;
	while((c := arg->opt()) != 0)
		case c {
		'f' =>
			errdiff = 0;
		'i' =>
			if(!plumbed){
				plumbmsg = load Plumbmsg Plumbmsg->PATH;
				if(plumbmsg != nil && plumbmsg->init(1, "view", 1000) >= 0)
					plumbed = 1;
			}
		}
	argv = arg->argv();
	arg = nil;
	if(argv == nil && !plumbed){
		f := selectfile->filename(ctxt, nil, "View file name", img_patterns, nil);
		if(f == "") {
			#spawn view(nil, nil, "");
			return;
		}
		argv = f :: nil;
	}


	for(;;){
		file: string;
		if(argv != nil){
			file = hd argv;
			argv = tl argv;
			if(file == "-f"){
				errdiff = 0;
				continue;
			}
		}else if(plumbed){
			file = plumbfile();
			if(file == nil)
				break;
			errdiff = 1;	# set this from attributes?
		}else
			break;

		(ims, masks, err) := readimages(file, errdiff);

		if(ims == nil)
			sys->fprint(stderr, "view: can't read %s: %s\n", file, err);
		else
			spawn view(ctxt, ims, masks, file);
	}
}

badload(s: string)
{
	sys->fprint(stderr, "view: can't load %s: %r\n", s);
	raise "fail:load";
}

readimages(file: string, errdiff: int) : (array of ref Image, array of ref Image, string)
{
	im := display.open(file);

	if(im != nil)
		return (array[1] of {im}, array[1] of ref Image, nil);

	fd := bufio->open(file, Sys->OREAD);
	if(fd == nil)
		return (nil, nil, sys->sprint("%r"));

	(mod, err1) := filetype(file, fd);
	if(mod == nil)
		return (nil, nil, err1);

	(ai, err2) := mod->readmulti(fd);
	if(ai == nil)
		return (nil, nil, err2);
	if(err2 != "")
		sys->fprint(stderr, "view: %s: %s\n", file, err2);
	ims := array[len ai] of ref Image;
	masks := array[len ai] of ref Image;
	for(i := 0; i < len ai; i++){
		masks[i] = transparency(ai[i], file);

		# if transparency is enabled, errdiff==1 is probably a mistake,
		# but there's no easy solution.
		(ims[i], err2) = imageremap->remap(ai[i], display, errdiff);
		if(ims[i] == nil)
			return(nil, nil, err2);
	}
	return (ims, masks, nil);
}

viewcfg := array[] of {
	"panel .p",
	"menu .m",
	".m add command -label Open -command {send cmd open}",
	".m add command -label Grab -command {send cmd grab} -state disabled",
	".m add command -label Save -command {send cmd save}",
	"pack .p -side bottom -fill both -expand 1",
	"bind .p <Button-3> {send cmd but3 %X %Y}",
	"bind .p <Motion-Button-3> {}",
	"bind .p <ButtonRelease-3> {}",
	"bind .p <Button-1> {send but1 %X %Y}",
};

DT: con 250;

timer(dt: int, ticks, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	for(;;){
		sys->sleep(dt);
		ticks <-= 1;
	}
}

view(ctxt: ref Context, ims, masks: array of ref Image, file: string)
{
	file = lastcomponent(file);
	(t, titlechan) := tkclient->toplevel(ctxt, "", "view: "+file, Tkclient->Hide);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");
	but1 := chan of string;
	tk->namechan(t, but1, "but1");

	for (c:=0; c<len viewcfg; c++)
		tk->cmd(t, viewcfg[c]);
	tk->cmd(t, "update");

	image := display.newimage(ims[0].r, ims[0].chans, 0, Draw->White);
	if (image == nil) {
		sys->fprint(stderr, "view: can't create image: %r\n");
		return;
	}
	imconfig(t, image);
	image.draw(image.r, ims[0], masks[0], ims[0].r.min);
	tk->putimage(t, ".p", image, nil);
	tk->cmd(t, "update");

	pid := -1;
	ticks := chan of int;
	if(len ims > 1){
		pidc := chan of int;
		spawn timer(DT, ticks, pidc);
		pid = <-pidc;
	}
	imno := 0;
	grabbing := 0;
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd"::"ptr"::nil);


	for(;;) alt{
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or
	s = <-t.wreq or
	s = <-titlechan =>
		tkclient->wmctl(t, s);

	<-ticks =>
		if(masks[imno] != nil)
			paneldraw(t, image, image.r, background, nil, image.r.min);
		++imno;
		if(imno >= len ims)
			imno = 0;
		paneldraw(t, image, ims[imno].r, ims[imno], masks[imno], ims[imno].r.min);
		tk->cmd(t, "update");

	s := <-cmd =>
		(nil, l) := sys->tokenize(s, " ");
		case (hd l) {
		"open" =>
			spawn open(ctxt, t);
		"grab" =>
			tk->cmd(t, "cursor -bitmap cursor.drag; grab set .p");
			grabbing = 1;
		"save" =>
			patterns := list of {
				"*.bit (Inferno image files)",
				"*.gif (GIF image files)",
				"*.jpg (JPEG image files)",
				"* (All files)"
			};
			f := selectfile->filename(ctxt, t.image, "Save file name",
				patterns, nil);
			if(f != "") {
				fd := sys->create(f, Sys->OWRITE, 8r664);
				if(fd != nil) 
					display.writeimage(fd, ims[0]);
			}
		"but3" =>
			if(!grabbing) {
				xx := int hd tl l - 50;
				yy := int hd tl tl l - int tk->cmd(t, ".m yposition 0") - 10;
				tk->cmd(t, ".m activate 0; .m post "+string xx+" "+string yy+
					"; grab set .m; update");
			}
		}
	s := <- but1 =>
			if(grabbing) {
				(nil, l) := sys->tokenize(s, " ");
				xx := int hd l;
				yy := int hd tl l;
#				grabtop := tk->intop(ctxt.screen, xx, yy);
#				if(grabtop != nil) {
#					cim := grabtop.image;
#					imr := Rect((0,0), (cim.r.dx(), cim.r.dy()));
#					image = display.newimage(imr, cim.chans, 0, draw->White);
#					if(image == nil){
#						sys->fprint(stderr, "view: can't allocate image\n");
#						exit;
#					}
#					image.draw(imr, cim, nil, cim.r.min);
#					tk->cmd(t, ".Wm_t.title configure -text {View: grabbed}");
#					imconfig(t, image);
#					tk->putimage(t, ".p", image, nil);
#					tk->cmd(t, "update");
#					# Would be nicer if this could be spun off cleanly
#					ims = array[1] of {image};
#					masks = array[1] of ref Image;
#					imno = 0;
#					grabtop = nil;
#					cim = nil;
#				}
				tk->cmd(t, "cursor -default; grab release .p");
				grabbing = 0;
			}
	}
}

open(ctxt: ref Context, t: ref tk->Toplevel)
{
	f := selectfile->filename(ctxt, t.image, "View file name", img_patterns, nil);
	t = nil;
	if(f != "") {
		(ims, masks, err) := readimages(f, 1);
		if(ims == nil)
			sys->fprint(stderr, "view: can't read %s: %s\n", f, err);
		else
			view(ctxt, ims, masks, f);
	}
}

lastcomponent(path: string) : string
{
	for(k:=len path-2; k>=0; k--)
		if(path[k] == '/'){
			path = path[k+1:];
			break;
		}
	return path;
}

imconfig(t: ref Toplevel, im: ref Draw->Image)
{
	width := im.r.dx();
	height := im.r.dy();
	tk->cmd(t, ".p configure -width " + string width
		+ " -height " + string height + "; update");
}

plumbfile(): string
{
	if(!plumbed)
		return nil;
	for(;;){
		msg := Msg.recv();
		if(msg == nil){
			sys->print("view: can't read /chan/plumb.view: %r\n");
			return nil;
		}
		if(msg.kind != "text"){
			sys->print("view: can't interpret '%s' kind of message\n", msg.kind);
			continue;
		}
		file := string msg.data;
		if(len file>0 && file[0]!='/' && len msg.dir>0){
			if(msg.dir[len msg.dir-1] == '/')
				file = msg.dir+file;
			else
				file = msg.dir+"/"+file;
		}
		return file;
	}
}

Tab: adt
{
	suf:	string;
	path:	string;
	mod:	RImagefile;
};

GIF, JPG, PIC, PNG, XBM: con iota;

tab := array[] of
{
	GIF => Tab(".gif",	RImagefile->READGIFPATH,	nil),
	JPG => Tab(".jpg",	RImagefile->READJPGPATH,	nil),
	PIC => Tab(".pic",	RImagefile->READPICPATH,	nil),
	XBM => Tab(".xbm",	RImagefile->READXBMPATH,	nil),
	PNG => Tab(".png",	RImagefile->READPNGPATH,	nil),
};

filetype(file: string, fd: ref Iobuf): (RImagefile, string)
{
	for(i:=0; i<len tab; i++){
		n := len tab[i].suf;
		if(len file>n && file[len file-n:]==tab[i].suf)
			return loadmod(i);
	}

	# sniff the header looking for a magic number
	buf := array[20] of byte;
	if(fd.read(buf, len buf) != len buf)
		return (nil, sys->sprint("%r"));
	fd.seek(big 0, 0);
	if(string buf[0:6]=="GIF87a" || string buf[0:6]=="GIF89a")
		return loadmod(GIF);
	if(string buf[0:5] == "TYPE=")
		return loadmod(PIC);
	jpmagic := array[] of {byte 16rFF, byte 16rD8, byte 16rFF, byte 16rE0,
		byte 0, byte 0, byte 'J', byte 'F', byte 'I', byte 'F', byte 0};
	if(eqbytes(buf, jpmagic))
		return loadmod(JPG);
	pngmagic := array[] of {byte 137, byte 80, byte 78, byte 71, byte 13, byte 10, byte 26, byte 10};
	if(eqbytes(buf, pngmagic))
		return loadmod(PNG);
	if(string buf[0:7] == "#define")
		return loadmod(XBM);
	return (nil, "can't recognize file type");
}

eqbytes(buf, magic: array of byte): int
{
	for(i:=0; i<len magic; i++)
		if(magic[i]>byte 0 && buf[i]!=magic[i])
			return 0;
	return i == len magic;
}

loadmod(i: int): (RImagefile, string)
{
	if(tab[i].mod == nil){
		tab[i].mod = load RImagefile tab[i].path;
		if(tab[i].mod == nil)
			sys->fprint(stderr, "view: can't find %s reader: %r\n", tab[i].suf);
		else
			tab[i].mod->init(bufio);
	}
	return (tab[i].mod, nil);
}

transparency(r: ref RImagefile->Rawimage, file: string): ref Image
{
	if(r.transp == 0)
		return nil;
	if(r.nchans != 1){
		sys->fprint(stderr, "view: can't do transparency for multi-channel image %s\n", file);
		return nil;
	}
	i := display.newimage(r.r, display.image.chans, 0, 0);
	if(i == nil){
		sys->fprint(stderr, "view: can't allocate mask for %s: %r\n", file);
		exit;
	}
	pic := r.chans[0];
	npic := len pic;
	mpic := array[npic] of byte;
	index := r.trindex;
	for(j:=0; j<npic; j++)
		if(pic[j] == index)
			mpic[j] = byte 0;
		else
			mpic[j] = byte 16rFF;
	i.writepixels(i.r, mpic);
	return i;
}

paneldraw(t: ref Tk->Toplevel, dst: ref Image, r: Rect, src, mask: ref Image, p: Point)
{
	dst.draw(r, src, mask, p);
	s := sys->sprint(".p dirty %d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
	tk->cmd(t, s);
}
