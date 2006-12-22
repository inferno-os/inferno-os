implement Blur;

include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "sys.m";
	sys : Sys;
include "daytime.m";
	daytime: Daytime;
include "draw.m";
	draw: Draw;
	Display, Chans, Point, Rect, Image: import draw;
include "readdir.m";
	readdir: Readdir;
include "grid/demo/exproc.m";
	exproc: Exproc;
include "grid/demo/block.m";
	block: Block;

display : ref draw->Display;
context : ref draw->Context;
path := "/tmp/blur/";

Blur : module {
	init : fn (ctxt : ref Draw->Context, nil : list of string);
	getslavedata : fn (lst: list of string);
	doblock : fn (block: int, bpath: string);
	readblock : fn (block: int, dir: string, chanout: chan of string): int;
	finish : fn (waittime: int, tkchan: chan of string);
};

init(ctxt : ref Draw->Context, argv : list of string)
{
	sys = load Sys Sys->PATH;
	if (sys == nil)
		badmod(Sys->PATH);
	draw = load Draw Draw->PATH;
	if (draw == nil)
		badmod(Draw->PATH);
	daytime = load Daytime Daytime->PATH;
	if (daytime == nil)
		badmod(Daytime->PATH);
	tk = load Tk Tk->PATH;
	if (tk == nil)
		badmod(Tk->PATH);
	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		badmod(Tkclient->PATH);
	tkclient->init();
	readdir = load Readdir Readdir->PATH;
	if (readdir == nil)
		badmod(Readdir->PATH);
	exproc = load Exproc "$self";
	if (exproc == nil)
		badmod(sys->sprint("Exproc: %r"));
	block = load Block Block->PATH;
	if (block == nil)
		badmod(Block->PATH);
	if (ctxt == nil) {
		display = Display.allocate(nil);
		if (display == nil)
			usage(sys->sprint("failed to get a display: %r"));
		context = nil;
	}
	else {
		display = ctxt.display;
		context = ctxt;
	}
	spawn blurit(argv);
}

blurit(argv: list of string)
{
	mast := 0;
	size = 12;
	blocks = Point (10,6);
	filename := "";

	argv = tl argv;
	if (len argv > 2)
		usage("too many arguments");
	
	for (; argv != nil; argv = tl argv) {
		(n,dir) := sys->stat(hd argv);
		if (n == -1)
			usage("file/directory '"+hd argv+"' does not exist");
		if (dir.mode & sys->DMDIR)
			path = hd argv;
		else {
			filename = hd argv;
			mast = 1;
		}
	}
	if (mast && context == nil)
		usage("nil context - cannot be used as master");
	if (path[len path - 1] != '/')
		path[len path] = '/';
	if (len path < 5 || path[len path - 5:] != "blur/")
		path += "blur/";
	block->init(path, exproc);
	if (mast)
		spawn master(filename);
	else {
		sys->print("starting slave\n");
		spawn block->slave();
	}
}

usage(err: string)
{
	sys->print("usage: blur [dir] [image]\n");
	if (err != nil) {
		sys->print("Error: %s\n",err);
		raise "fail:error";
	}
	else
		exit;
}

getslavedata(lst: list of string)
{
	if (lst == nil || len lst < 5)
		block->err("Cannot read data file");
	size = int hd lst;
	blocks = Point(int hd tl lst, int hd tl tl lst);
	bsize = Point(int hd tl tl tl lst, int hd tl tl tl tl lst);
	blockimg = display.newimage(((0,0),bsize), draw->RGB24,0,draw->Red);
}

blocks, bsize: Draw->Point;
size: int;
newimg: ref Draw->Image;

getxy(i, w: int): (int, int)
{
	y := i / w;
	x := i - (y * w);
	return (x,y);
}

master(filename: string)
{
	block->cleanfiles(path);
	img := display.open(filename);
	if (img == nil)
		block->err("cannot read image: "+filename);
	if (img.chans.depth() != 24)
			block->err("wrong image depth! (must be 24bit)\n");
	sys->create(path, sys->OREAD, 8r777 | sys->DMDIR);

	blocks.x = img.r.dx() / 70;
	if (blocks.x < 1)
		blocks.x = 1;
	blocks.y = img.r.dy() / 70;
	if (blocks.y < 1)
		blocks.y = 1;

	bsize = Point(img.r.dx()/blocks.x, img.r.dy()/blocks.y);
		
	data := sys->sprint("%d\n%d\n%d\n%d\n%d\n",size,blocks.x,blocks.y,bsize.x,bsize.y);
	noblocks := blocks.x * blocks.y;

	n := 0;
	for (y := 0; y < blocks.y; y++) {
		for (x := 0; x < blocks.x; x++) {
			r2 := Rect(((x*bsize.x)-size, (y*bsize.y)-size), 
					(((1+x)*bsize.x)+size, ((1+y)*bsize.y)+size));
			if (r2.min.x < 0)
				r2.min.x = 0;
			if (r2.min.y < 0)
				r2.min.y = 0;
			if (r2.max.x > img.r.max.x)
				r2.max.x = img.r.max.x;
			if (r2.max.y > img.r.max.y)
				r2.max.y = img.r.max.y;

			tmpimg := display.newimage(r2,draw->RGB24,0,draw->Black);
			tmpimg.draw(r2, img, nil, r2.min);
			fdtmp := sys->create(path+"imgdata."+string n+".bit", sys->OWRITE, 8r666);			
			if (fdtmp == nil)
				sys->print("couldn't write image: '%s' %r\n",path+"imgdata."+string n+".bit");
			display.writeimage(fdtmp, tmpimg);
			n++;
		}
	}
	block->writedata(data);
	block->masterinit(noblocks);
		
	(top, titlebar) := tkclient->toplevel(context, "", "Blur", Tkclient->Hide);
	tkcmd(top, "frame .f");
	r2 := Rect((0,0),(blocks.x*bsize.x,blocks.y*bsize.y));
	newimg = display.newimage(r2,draw->RGB24,0,draw->Black);
	newimg.draw(r2,img,nil,(0,0));
	tkcmd(top, sys->sprint("panel .f.p -height %d -width %d", r2.dy(), r2.dx()));
	tk->putimage(top, ".f.p", newimg, nil);
	tkcmd(top, "label .f.l1 -text {Processed: }");
	tkcmd(top, "label .f.l2 -text {0%} -width 30");
	tkcmd(top, "grid .f.p -row 0 -column 0 -columnspan 2");
	tkcmd(top, "grid .f.l1 -row 1 -column 0 -sticky e");
	tkcmd(top, "grid .f.l2 -row 1 -column 1 -sticky w");
	tkcmd(top, "pack .f");
	tkcmd(top, "bind .Wm_t <Button-1> +{focus .}");
	tkcmd(top, "bind .Wm_t.title <Button-1> +{focus .}");
	tkcmd(top, "focus .; update");

	tkchan := chan of string;
	sync := chan of int;
	spawn block->reader(noblocks, tkchan, sync);
	readerpid := <-sync;
	spawn window(top, titlebar, newimg, tkchan, readerpid);
}

blockimg: ref Draw->Image;

doblock(block: int, bpath: string)
{
	(x,y) := getxy(block, blocks.x);
	procimg := display.open(path+"imgdata."+string block+".bit");
	if (procimg == nil)
		sys->print("Error nil image! '%s' %r\n",path+"imgdata."+string block+".bit");
	blurred := procblock(procimg, x,y,0,size,bsize);
	sketched := procblock(procimg, x,y,1,3,bsize);
	for (i := 0; i < len blurred; i++) {
		if (sketched[i] != byte 127)
			blurred[i] = sketched[i];
	}
	blockimg.writepixels(((0,0),bsize), blurred);
	fd := sys->create(path + bpath+"/img.bit",sys->OWRITE,8r666);
	display.writeimage(fd, blockimg);
	fd = nil;
	sys->create(path + bpath+"/done", sys->OWRITE, 8r666);
}

window(top: ref Tk->Toplevel, titlebar: chan of string, 
		img: ref Image, tkchan: chan of string, readerpid: int)
{
	total := blocks.x * blocks.y;
	done := 0;
	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	finished := 0;
	main: for(;;) alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		inp := <- tkchan =>
			(n, lst) := sys->tokenize(inp, " \n\t");
			case hd lst {
				"done" =>
					done++;
					tkcmd(top, ".f.l2 configure -text {"+string ((100*done)/total)+"%}");
					tkcmd(top, ".f.p dirty");
				"time" =>
					tkcmd(top, ".f.l1 configure -text {Time taken:}");
					tkcmd(top, ".f.l2 configure -text {"+hd tl lst+"} -width 80");
					finished = 1;
				* =>
					tkcmd(top, ".f.l2 configure -text {"+inp+"%}");
			}
			tkcmd(top, "update");

		title := <-top.ctxt.ctl or
		title = <-top.wreq or
		title = <- titlebar =>
			if (title == "exit") {
				if (finished) {
					kill(readerpid);
					break main;
				}
			}
			else
				tkclient->wmctl(top, title);
	}
	spawn block->cleanfiles(path);
}

readblock(block: int, dir: string, chanout: chan of string): int
{
	img := display.open(dir+"img.bit");
	if (img == nil)
		return -1;
	(ix,iy) := getxy(block, blocks.x);
	newimg.draw(img.r.addpt(Point(ix*bsize.x, iy*bsize.y)),img,nil,(0,0));
	chanout <-= "done";
	return 0;
}

finish(waittime: int, tkchan: chan of string) 
{
	hrs := waittime / 360; 
	mins := (waittime - (360 * hrs)) / 60;
	secs := waittime - (360 * hrs) - (60 * mins);
	time := addzeros(sys->sprint("%d:%d:%d",hrs,mins,secs));
	if (hrs == 0) time = time[3:];
	tkchan <-= "time "+time;
	block->cleanfiles(path);
}

procblock(procimg: ref Image, x,y, itype, size: int, bsize: Point): array of byte
{
	r := Rect((x*bsize.x, y*bsize.y), ((1+x)*bsize.x, (1+y)*bsize.y));
	r2 : Rect;
	if (itype == 0)
		r2 = procimg.r;
	else
		r2 = Rect((x*bsize.x, y*bsize.y), (((1+x)*bsize.x)+1, ((1+y)*bsize.y)+1));
	if (r2.min.x < 0)
		r2.min.x = 0;
	if (r2.min.y < 0)
		r2.min.y = 0;
	if (r2.max.x > procimg.r.max.x)
		r2.max.x = procimg.r.max.x;
	if (r2.max.y > procimg.r.max.y)
		r2.max.y = procimg.r.max.y;

	buf := array[3 * r2.dx() * r2.dy()] of byte;
	procimg.readpixels(r2,buf);
	pad := Rect((r.min.x-r2.min.x, r.min.y-r2.min.y), (r2.max.x - r.max.x, r2.max.y-r.max.y));
	if (itype == 0)
		return blurblock(size,r,pad,buf);
	if (itype == 1)
		return gradblock(10,r,pad,buf);
	return nil;
}

makepic(buf: array of int, w,nw,nh: int): array of byte
{
	newbuf := array[3*nw*nh] of byte;
	n := 0;
	for (y := 0; y < nh; y++) {
		for (x := 0; x < nw; x++) {
			val := byte buf[(y*w)+x];
			if (val < byte 0) val = -val;
			if (val > byte 255) val = byte 255;
			for (i := 0; i < 3; i++)
				newbuf[n++] = val;
		}
	}
	return newbuf;
}

gradblock(threshold: int, r, pad: Rect, buffer: array of byte) : array of byte
{
	gradbufx := array[3] of array of int; 
	gradbufy := array[3] of array of int;
	width: int;
	cleaning := 3;
	for (rgb := 0; rgb < 3; rgb++) {

		greybuf := array[len buffer] of { * => 0 };
		n := 0;
		width = r.dx()+pad.max.x;
		for (y := 0; y < r.dy()+pad.max.y; y++) {
			for (x := 0; x < r.dx()+pad.max.x; x++) {
				greybuf[n++] = int buffer[(3* ((y*width) + x ))+rgb];
			}	
		}
	
		for(i := 0; i < 2; i++) {
			padx := pad.max.x;
			pady := pad.max.y;
			width = r.dx();
			height := r.dy();
			gradbuf: array of int;
			(gradbuf, width, height, padx, pady) = getgrad(greybuf, i, width,height, padx, pady);
			width = r.dx();
			if (i == 0) {
				gradbufx[rgb] = clean(hyster(gradbuf,1,width,threshold), width,5,4);
				for (k := 0; k < cleaning; k++)
					gradbufx[rgb] = clean(gradbufx[rgb], width,2,2);
			}
			else {
				gradbufy[rgb] = clean(hyster(gradbuf, 0,width,threshold), width,5,4);
				for (k := 0; k < cleaning; k++)
					gradbufy[rgb] = clean(gradbufy[rgb], width,2,2);
			}
		}
	
	}
	newbuf := array[len gradbufx[0]] of int;
	for (i := 0; i < len newbuf; i++) {
		val := 127;
		n := 0;
		for (rgb = 0; rgb < 3; rgb++) {
			if (gradbufx[rgb][i] != 127) {
				n++;
				val = gradbufx[rgb][i];
			}
			else if (gradbufy[rgb][i] != 127) {
				val = gradbufy[rgb][i];
				n++;
			}
		}
		if (n > 1)
			newbuf[i] = val;
		else
			newbuf[i] = 127;
	}
	if (sat(newbuf) > 25 && threshold > 4)
		return gradblock(threshold - 2,r,pad,buffer);
	return makepic(newbuf,width,r.dx(),r.dy());
}

X: con 0;
Y: con 1;

getgrad(buf: array of int, dir, w,h, px, py: int): (array of int, int, int, int, int)
{
	npx := px - 1;
	npy := py - 1;
	if (npx < 0) npx = 0;
	if (npy < 0) npy = 0;
	gradbuf := array[(w+npx)*(h+npy)] of int;
	n := 0;
	val1, val2: int;
	for (y := 0; y < h+npy; y++) {
		for (x := 0; x < w+npx; x++) {
			val1 = buf[(y*(w+px)) + x];
			if ((dir == X && x-w >= npx) ||
				(dir == Y && y-h >= npy))
				val2 = val1;
			else
				val2 = buf[((y+dir)*(w+px)) + x + 1 - dir];
			gradbuf[n++] = val2 - val1;
		}	
	}
	return (norm(gradbuf,0,255), w, h, px,py);
}

sat(a: array of int): int
{
	n := 0;
	for (i := 0; i < len a; i++)
		if (a[i] != 127)
			n++;
	return (100 * n)/ len a;
}

hyster(a: array of int, gox, width: int, lim: int): array of int
{
	min, max: int;
	av := 0;
	for (i := 0; i < len a; i++) {
		if (i == 0)
			min = max = a[i];
		if (a[i] < min)
			min = a[i];
		if (a[i] > max)
			max = a[i];
		av += a[i];
	}
#	sys->print("%d/%d = %d\n",av,len a,av / len a);
	av = av/len a;
	upper := av + ((max-av)/lim);
	lower := av - ((av-min)/ lim);
	low := 0;
#	sys->print("len a: %d %d %d %d\n",len a,av,min,max);
	i = 0;
	x := 0;
	y := 0;
	height := len a / width;
	newline := 1;
#	sys->print("width: %d gox: %d\n",width,gox);
	for (k := 0; k < len a; k++) {
		i = (y*width) + x;
		if (newline) {
#			if (a[i] < av) low = 1;
#			else low = 0;
			low = a[i] > av;
			newline = 0;
		}
		oldlow := low;
		if (low == 0) {
			if (a[i] > upper)
				low = 1;
		}
		else if (low == 1) {
			if (a[i] < lower)
				low = 0;
		}
#		sys->print("a[i]: %d bound: %d %d low %d => %d\n",a[i],lower,upper,oldlow,low);
		if (oldlow == low)
			a[i] =127;
		else
			a[i] = low * 255;

		if (gox) {
			i++;
			x++;
			if (x == width) {
				x = 0;
				y++;
				newline = 1;
			}
		}
		else {
			i += width;
			y++;
			if (y == height) {
#				sys->print("y: %d\n",y);
				y = 0;
				i = x;
				x++;
				newline = 1;
			}
		}
	}
	return a;
}

clean(a: array of int, width, r, d: int): array of int
{
	height := len a / width;
	csize := (2*r) ** 2;
	for (y := 0; y < height; y++) {
		for (x := 0; x < width; x++) {
			i := (width*y)+x;
			if (a[i] != 127) {
				sx := x - r;
				if (sx < 0) sx = 0;
				ex := x + r;
				if (ex > width) ex = width;
				sy := y - r;
				if (sy < 0) sy = 0;
				ey := y + r;
				n := 0;
				if (ey > height) ey = height;
				for (iy := sy; iy < ey; iy++) {
					for (ix := sx; ix < ex; ix++) {
						if (a[(width*iy)+ix] == a[i])
							n++;
					}
				}
				#sys->print("%f\n",real ((ex-sx)*(ey-sy))/ real csize);
#				if (n < int (real d * (real ((ex-sx)*(ey-sy))/ real csize)))
				if (n < d)
					a[i] = 127;
			}
		}
	}
	return a;
}


norm(a: array of int, lower, upper: int): array of int
{
	min, max: int;
	for (i := 0; i < len a; i++) {
		if (i == 0)
			min = max = a[i];
		if (a[i] < min)
			min = a[i];
		if (a[i] > max)
			max = a[i];
	}
	multi : real = (real (upper - lower)) / (real (max - min));
	add := real (lower - min);
	for (i = 0; i < len a; i++) {
		a[i] = int ((add + real a[i]) * multi);
		if (a[i] < lower)
			a[i] = lower;
		if (a[i] > upper)
			a[i] = upper;
	}
	return a;
}

opt := 2;

blurblock(size: int, r, pad: Rect, buffer: array of byte) : array of byte
{
	newbuf := array[3 * r.dx() * r.dy()] of byte;
	n := 0;
	width := r.dx()+pad.min.x+pad.max.x;
	for (y := 0; y < r.dy(); y++) {
		for (x := 0; x < r.dx(); x++) {
			r2 := Rect((x-size,y-size),(x+size+1,y+size+1));
			if (r2.min.x < -pad.min.x)
				r2.min.x = -pad.min.x;
			if (r2.min.y < -pad.min.y)
				r2.min.y = -pad.min.y;
			if (r2.max.x > r.dx()+pad.max.x)
				r2.max.x = r.dx()+pad.max.x;
			if (r2.max.y > r.dy()+pad.max.y)
				r2.max.y = r.dy()+pad.max.y;
			nosamples := r2.dx()*r2.dy();

			r2.min.x += pad.min.x;
			r2.min.y += pad.min.y;
			r2.max.x += pad.min.x;
			r2.max.y += pad.min.y;
			pixel := array[3] of { * => 0};
			for (sy := r2.min.y; sy < r2.max.y; sy++) {
				for (sx := r2.min.x; sx < r2.max.x; sx++) {
					for (i := 0; i < 3; i++)
						pixel[i] += int buffer[(3* ( ((sy)*width) + (sx) ) )+ i];
				}
			}
			for (i := 0; i < 3; i++) {
				if (opt == 0)
					newbuf[n++] = byte (pixel[i] / nosamples);
				if (opt == 1)
					newbuf[n++] = byte (255 - (pixel[i] / nosamples));
				if (opt == 2)
					newbuf[n++] = byte (63 + (pixel[i] / (2*nosamples)));

			}

		}
	}
	return newbuf;
}

tkcmd(top: ref Tk->Toplevel, cmd: string): string
{
	e := tk->cmd(top, cmd);
	if (e != "" && e[0] == '!') sys->print("tk error: '%s': %s\n",cmd,e);
	return e;
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

kill(pid: int)
{	
	pctl := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE);
	if (pctl != nil)
		sys->write(pctl, array of byte "kill", len "kill");
}

badmod(path: string)
{
	sys->print("Blur: failed to load: %s\n",path);
	exit;
}