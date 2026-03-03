implement Renderer;

#
# Markdown renderer - parses Markdown text and renders to Draw->Image.
#
# Supports: headings (#), bold (**), italic (*), inline code (`),
# code blocks (```), bullet lists (- *), numbered lists (1.),
# horizontal rules (---), blockquotes (>), links [text](url).
#
# The rendered image is a visual overlay; the original markdown text
# is returned as the extracted text content for the body buffer.
#
# Parsing is delegated to rlayout->parsemd() to avoid duplication.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	drawm: Draw;
	Display, Image, Font, Rect, Point: import drawm;

include "renderer.m";
include "rlayout.m";

rlayout: Rlayout;
display: ref Display;
DocNode: import rlayout;

# Font paths (Inferno standard)
PROPFONT: con "/fonts/vera/Vera/unicode.14.font";
MONOFONT: con "/fonts/vera/VeraMono/VeraMono.14.font";

propfont: ref Font;
monofont: ref Font;

init(d: ref Draw->Display)
{
	sys = load Sys Sys->PATH;
	drawm = load Draw Draw->PATH;
	display = d;

	rlayout = load Rlayout Rlayout->PATH;
	if(rlayout != nil)
		rlayout->init(d);

	propfont = Font.open(d, PROPFONT);
	monofont = Font.open(d, MONOFONT);
	if(propfont == nil)
		propfont = Font.open(d, "*default*");
	if(monofont == nil)
		monofont = propfont;
}

info(): ref RenderInfo
{
	return ref RenderInfo(
		"Markdown",
		".md .markdown",
		1  # Has text content (the original markdown)
	);
}

canrender(data: array of byte, hint: string): int
{
	# No magic bytes for markdown; rely on extension
	return 0;
}

render(data: array of byte, hint: string,
       width, height: int,
       progress: chan of ref RenderProgress): (ref Draw->Image, string, string)
{
	if(rlayout == nil)
		return (nil, nil, "layout module not available");
	if(propfont == nil)
		return (nil, nil, "font not available");

	# Parse markdown to text
	mdtext := string data;

	# Parse into document tree via rlayout's shared parser
	doc := rlayout->parsemd(mdtext);

	# Set up style
	if(width <= 0)
		width = 800;

	fgcolor := display.color(drawm->Black);
	bgcolor := display.color(drawm->White);
	linkcolor := display.newimage(Rect(Point(0,0), Point(1,1)), drawm->RGB24, 1, 16r2255AA);
	codebg := display.newimage(Rect(Point(0,0), Point(1,1)), drawm->RGB24, 1, 16rF0F0F0);

	style := ref Rlayout->Style(
		width,      # width
		12,         # margin
		propfont,   # font
		monofont,   # codefont
		fgcolor,    # fgcolor
		bgcolor,    # bgcolor
		linkcolor,  # linkcolor
		codebg,     # codebgcolor
		150         # h1scale
	);

	# Render
	(img, nil) := rlayout->render(doc, style);

	# Extract plain text
	text := rlayout->totext(doc);

	# Signal no progressive updates
	progress <-= nil;

	return (img, text, nil);
}

commands(): list of ref Command
{
	return nil;  # No special commands for markdown yet
}

command(cmd: string, arg: string,
        data: array of byte, hint: string,
        width, height: int): (ref Draw->Image, string)
{
	return (nil, "unknown command: " + cmd);
}
