implement Renderer;

#
# Mermaid renderer - wraps the Mermaid module to conform to the
# Renderer interface.  Renders Mermaid diagram syntax to Draw->Image.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	drawm: Draw;
	Display, Image, Font, Rect, Point: import drawm;

include "renderer.m";

include "mermaid.m";
	mermaid: Mermaid;

display: ref Display;
propfont: ref Font;
monofont: ref Font;

PROPFONT: con "/fonts/combined/unicode.sans.14.font";
MONOFONT: con "/fonts/combined/unicode.14.font";

init(d: ref Display)
{
	sys = load Sys Sys->PATH;
	drawm = load Draw Draw->PATH;
	display = d;

	propfont = Font.open(d, PROPFONT);
	monofont = Font.open(d, MONOFONT);
	if(propfont == nil)
		propfont = Font.open(d, "*default*");
	if(monofont == nil)
		monofont = propfont;

	mermaid = load Mermaid Mermaid->PATH;
	if(mermaid != nil)
		mermaid->init(d, propfont, monofont);
}

info(): ref RenderInfo
{
	return ref RenderInfo(
		"Mermaid",
		".mermaid .mmd",
		0  # Diagrams have no text content
	);
}

canrender(data: array of byte, hint: string): int
{
	if(data == nil || len data < 5)
		return 0;

	# Check for common mermaid keywords at start
	s := string data[0:min(len data, 256)];
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c == ' ' || c == '\t' || c == '\n' || c == '\r')
			continue;
		# Check for mermaid diagram type keywords
		if(hasprefix(s[i:], "graph ") || hasprefix(s[i:], "flowchart ") ||
		   hasprefix(s[i:], "sequenceDiagram") ||
		   hasprefix(s[i:], "pie") || hasprefix(s[i:], "gantt") ||
		   hasprefix(s[i:], "xychart-beta") ||
		   hasprefix(s[i:], "mindmap") ||
		   hasprefix(s[i:], "classDiagram") ||
		   hasprefix(s[i:], "stateDiagram") ||
		   hasprefix(s[i:], "erDiagram") ||
		   hasprefix(s[i:], "timeline") ||
		   hasprefix(s[i:], "gitGraph") ||
		   hasprefix(s[i:], "quadrantChart") ||
		   hasprefix(s[i:], "journey") ||
		   hasprefix(s[i:], "requirementDiagram") ||
		   hasprefix(s[i:], "block-beta"))
			return 70;
		break;
	}
	return 0;
}

render(data: array of byte, hint: string,
       width, height: int,
       progress: chan of ref RenderProgress): (ref Draw->Image, string, string)
{
	if(mermaid == nil) {
		progress <-= nil;
		return (nil, nil, "mermaid module not available");
	}

	syntax := string data;
	if(width <= 0)
		width = 800;

	im: ref Image;
	err: string;
	{
		(im, err) = mermaid->render(syntax, width);
	} exception e {
	"*" =>
		progress <-= nil;
		return (nil, nil, "mermaid exception: " + e);
	}

	progress <-= nil;

	if(im == nil)
		return (nil, nil, "mermaid: " + err);

	return (im, nil, nil);
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

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

min(a, b: int): int
{
	if(a < b)
		return a;
	return b;
}
