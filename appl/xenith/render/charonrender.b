implement Renderer;

#
# Charon HTML renderer - wraps the Charon browser engine to render
# HTML with full table layout, CSS, and image support.
#
# Spawns Charon in render-to-file mode (-render 1 -doacme 1),
# which lays out and renders the HTML to an offscreen image,
# writes it to /tmp/.charonrender.bit, and exits.
#
# This replaces the simpler htmlrender.b which only supports
# basic inline formatting via rlayout.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	drawm: Draw;
	Display, Image, Font, Rect, Point: import drawm;

include "renderer.m";

display: ref Display;

RENDERIMG: con "/tmp/.charonrender.bit";
RENDERTXT: con "/tmp/.charonrender.txt";
RENDERHTML: con "/tmp/.charonrender.html";

CharonMod: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(d: ref Draw->Display)
{
	sys = load Sys Sys->PATH;
	drawm = load Draw Draw->PATH;
	display = d;
}

info(): ref RenderInfo
{
	return ref RenderInfo(
		"HTML (Charon)",
		".html .htm",
		1  # Has text content
	);
}

canrender(data: array of byte, hint: string): int
{
	if(data == nil || len data < 6)
		return 0;

	# Check for HTML markers
	s := string data[0:min(len data, 256)];
	for(i := 0; i < len s; i++){
		c := s[i];
		if(c == ' ' || c == '\t' || c == '\n' || c == '\r')
			continue;
		if(c == '<'){
			rest := lower(s[i:]);
			if(len rest >= 9 && rest[0:9] == "<!doctype")
				return 95;
			if(len rest >= 5 && rest[0:5] == "<html")
				return 90;
			if(len rest >= 5 && rest[0:5] == "<head")
				return 85;
			if(len rest >= 5 && rest[0:5] == "<body")
				return 85;
			# Any tag suggests HTML
			return 35;
		}
		break;
	}
	return 0;
}

render(data: array of byte, hint: string,
       width, height: int,
       progress: chan of ref RenderProgress): (ref Draw->Image, string, string)
{
	if(display == nil)
		return (nil, nil, "no display");
	if(data == nil || len data == 0)
		return (nil, nil, "no data");

	if(width <= 0)
		width = 800;

	# Write HTML to temp file
	fd := sys->create(RENDERHTML, Sys->OWRITE, 8r600);
	if(fd == nil)
		return (nil, nil, sys->sprint("cannot create %s: %r", RENDERHTML));
	sys->write(fd, data, len data);
	fd = nil;

	# Clean up old output
	sys->remove(RENDERIMG);
	sys->remove(RENDERTXT);

	# Load Charon
	ch := load CharonMod "/dis/charon.dis";
	if(ch == nil)
		return (nil, nil, sys->sprint("cannot load charon: %r"));

	# Create a Draw->Context for offscreen rendering
	ctxt := ref drawm->Context(display, nil, nil);

	# Build args: render mode, offscreen, no scripts, desired width
	args := "charon"
		:: "-render" :: "1"
		:: "-doacme" :: "1"
		:: "-defaultwidth" :: string width
		:: "-doscripts" :: "0"
		:: "-imagelvl" :: "0"
		:: "file://" + RENDERHTML
		:: nil;

	# Run Charon in render mode - it renders and exits
	done := chan of int;
	spawn charonthread(done, ch, ctxt, args);

	# Wait with timeout (30 seconds)
	timeout := chan of int;
	spawn timeoutproc(timeout, 30000);

	result := 0;
	alt {
		result = <-done => ;
		<-timeout =>
			# Clean up temp files
			sys->remove(RENDERHTML);
			progress <-= nil;
			return (nil, nil, "charon render timeout");
	}

	# Read rendered image
	img: ref Image;
	ifd := sys->open(RENDERIMG, Sys->OREAD);
	if(ifd != nil) {
		img = display.readimage(ifd);
		ifd = nil;
	}

	# Read extracted text
	text := readfile(RENDERTXT);

	# Clean up temp files
	sys->remove(RENDERHTML);
	sys->remove(RENDERIMG);
	sys->remove(RENDERTXT);

	progress <-= nil;

	if(img == nil && result != 0)
		return (nil, text, "charon render failed");

	return (img, text, nil);
}

commands(): list of ref Command
{
	return nil;
}

command(cmd: string, arg: string,
        data: array of byte, hint: string,
        width, height: int): (ref Draw->Image, string)
{
	return (nil, "unknown command: " + cmd);
}

# ---- Internal helpers ----

charonthread(done: chan of int, ch: CharonMod, ctxt: ref drawm->Context, args: list of string)
{
	pid := sys->pctl(Sys->NEWPGRP, nil);
	{
		ch->init(ctxt, args);
		done <-= 0;
	} exception {
	* =>
		done <-= 1;
	}
}

timeoutproc(ch: chan of int, ms: int)
{
	sys->sleep(ms);
	ch <-= 1;
}

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[256*1024] of byte;
	n := 0;
	for(;;) {
		r := sys->read(fd, buf[n:], len buf - n);
		if(r <= 0)
			break;
		n += r;
		if(n >= len buf)
			break;
	}
	if(n == 0)
		return nil;
	return string buf[0:n];
}

lower(s: string): string
{
	r := "";
	for(i := 0; i < len s; i++){
		c := s[i];
		if(c >= 'A' && c <= 'Z')
			c += 'a' - 'A';
		r[len r] = c;
	}
	return r;
}

min(a, b: int): int
{
	if(a < b)
		return a;
	return b;
}
