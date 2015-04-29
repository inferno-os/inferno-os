implement Mpeg;

include "sys.m";
sys: Sys;
FD, Connection: import Sys;
include "draw.m";
draw: Draw;
Display, Rect, Image: import draw;
include "dial.m";
dial: Dial;
include "mpeg.m";

Chroma: con 16r05;

getenv()
{
	if(sys != nil)
		return;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	dial = load Dial Dial->PATH;
}

copy(files: list of string, notify: chan of string, mpctl, mpdata: ref FD)
{
	n: int;
	c: ref Connection;
	name: list of string;	

	while(files != nil) {
		file := hd files;
		(n, name) = sys->tokenize(file, "@");
		m : ref FD;
		case n {
		1 =>
			m = sys->open(file, sys->OREAD);
			if(m == nil) {
				notify <-= "mpeg open:" + file;
				return;
			}
		2 =>
			c = dial->dial(hd tl name, nil);
			if(c == nil) {
				notify <-= "dial:" + hd tl name;
				return;
			}
			sys->fprint(c.dfd, "%s\n", hd name);
			c.cfd = nil;
			m = c.dfd;
		* =>
			notify <-= "bad file:"+hd name;
			return;
		}
		sys->stream(m, mpdata, 64*1024);
		files = tl files;
	}
	sys->fprint(mpctl, "stop");
	sys->fprint(mpctl, "window 0 0 0 0");
	notify <-= "";
}

play(display: ref Display, w: ref Image, paint: int, r: Rect, file: string, notify: chan of string): string
{
 	i, j: int;
	line: string;
	cfg: array of byte;
	buf := array[1024] of byte;
	arg, words, files: list of string;

	getenv();

	mpdata := sys->open("/dev/mpeg", sys->OWRITE);
	if(mpdata == nil)
		return sys->sprint("can't open /dev/mpeg: %r");

	obj := sys->open(file, sys->OREAD);
	if(obj == nil)
		return "open failed:"+file;

	n := sys->read(obj, buf, len buf);
	if(n < 0)
		return "mpeg object: read error";

	mpctl := sys->open("/dev/mpegctl", sys->OWRITE);
	if(mpctl == nil)
		return "open mpeg ctl file";

	# Parse into lines
	(n, arg) = sys->tokenize(string buf[0:n], "\n");
	for(i = 0; i < n; i++) {
		# Parse into words
		line = hd arg;
		(j, words) = sys->tokenize(line, " \t");

		# Pass device config lines through to the ctl file
		if(hd words == "files")
			files = tl words;
		else {
			cfg = array of byte line;
			if(sys->write(mpctl, cfg, len cfg) < 0)
				return "invalid device config:"+line;
		}
		arg = tl arg;
	}

	if(files == nil)
		return "no file to play";

	# now the driver is configured initialize the dsp's
	# and set up the trident overlay
	sys->fprint(mpctl, "init");
	sys->fprint(mpctl, "window %d %d %d %d",
			r.min.x, r.min.y, r.max.x, r.max.y);

	# paint the window with the chroma key color
	if(paint)
		w.draw(r, keycolor(display), nil, r.min);

	if(notify != nil) {
		spawn copy(files, notify, mpctl, mpdata);
		return "";
	}
	notify = chan of string;
	spawn copy(files, notify, mpctl, mpdata);
	return <-notify;
}

ctl(msg: string): int
{
	mpc: ref FD;

	getenv();

	mpc = sys->open("/dev/mpegctl", sys->OWRITE);
	if(mpc == nil)
		return -1;

	b := array of byte msg;
	n := sys->write(mpc, b, len b);
	if(n != len b)
		n = -1;

	return n; 
}

keycolor(display: ref Display): ref Image
{
	getenv();
	return display.color(Chroma);
}
