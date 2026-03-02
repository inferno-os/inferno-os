implement Renderer;

#
# HTML renderer - parses HTML using Inferno's html.m tokenizer and
# renders to Draw->Image via the shared rlayout layout engine.
#
# Converts HTML tags to DocNode tree:
#   <h1>-<h6>  → Nheading
#   <p>         → Npara
#   <b>,<strong>→ Nbold
#   <i>,<em>    → Nitalic
#   <code>      → Ncode
#   <pre>       → Ncodeblock
#   <ul>/<li>   → Nbullet
#   <ol>/<li>   → Nnumber
#   <blockquote>→ Nblockquote
#   <hr>        → Nhrule
#   <a>         → Nlink
#   <br>        → Nnewline
#
# Text between tags is extracted and returned for the body buffer.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	drawm: Draw;
	Display, Image, Font, Rect, Point: import drawm;

include "html.m";
	html: HTML;
	Lex, Attr: import html;

include "renderer.m";
include "rlayout.m";

rlayout: Rlayout;
display: ref Display;
DocNode: import rlayout;

PROPFONT: con "/fonts/vera/Vera/unicode.14.font";
MONOFONT: con "/fonts/vera/VeraMono/VeraMono.14.font";

propfont: ref Font;
monofont: ref Font;

init(d: ref Draw->Display)
{
	sys = load Sys Sys->PATH;
	drawm = load Draw Draw->PATH;
	display = d;

	html = load HTML HTML->PATH;

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
		"HTML",
		".html .htm",
		1  # Has text content
	);
}

canrender(data: array of byte, hint: string): int
{
	if(data == nil || len data < 6)
		return 0;

	# Check for <!DOCTYPE or <html
	s := string data[0:min(len data, 256)];
	for(i := 0; i < len s; i++){
		c := s[i];
		if(c == ' ' || c == '\t' || c == '\n' || c == '\r')
			continue;
		if(c == '<'){
			rest := s[i:];
			if(len rest >= 9 && lower(rest[0:9]) == "<!doctype")
				return 90;
			if(len rest >= 5 && lower(rest[0:5]) == "<html")
				return 85;
			if(len rest >= 5 && lower(rest[0:5]) == "<head")
				return 80;
			if(len rest >= 5 && lower(rest[0:5]) == "<body")
				return 80;
			# Any tag suggests HTML
			return 30;
		}
		break;
	}
	return 0;
}

render(data: array of byte, hint: string,
       width, height: int,
       progress: chan of ref RenderProgress): (ref Draw->Image, string, string)
{
	if(rlayout == nil)
		return (nil, nil, "layout module not available");
	if(html == nil)
		return (nil, nil, "html module not available");
	if(propfont == nil)
		return (nil, nil, "font not available");

	# Tokenize HTML
	tokens := html->lex(data, HTML->UTF8, 0);
	if(tokens == nil)
		return (nil, nil, "html lex failed");

	# Convert tokens to document tree
	doc := html2doc(tokens);

	# Set up style
	if(width <= 0)
		width = 800;

	fgcolor := display.color(drawm->Black);
	bgcolor := display.color(drawm->White);
	linkcolor := display.newimage(Rect(Point(0,0), Point(1,1)), drawm->RGB24, 1, 16r2255AA);
	codebg := display.newimage(Rect(Point(0,0), Point(1,1)), drawm->RGB24, 1, 16rF0F0F0);

	style := ref Rlayout->Style(
		width, 12,
		propfont, monofont,
		fgcolor, bgcolor, linkcolor, codebg,
		150
	);

	# Render
	(img, nil) := rlayout->render(doc, style);

	# Extract text
	text := rlayout->totext(doc);

	progress <-= nil;

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

# ---- HTML → DocNode conversion ----

# Parser state
Pstate: adt {
	tokens: array of ref Lex;
	pos: int;
	ntokens: int;
};

html2doc(tokens: array of ref Lex): list of ref DocNode
{
	ps := ref Pstate(tokens, 0, len tokens);
	doc: list of ref DocNode;
	inlines: list of ref DocNode;

	while(ps.pos < ps.ntokens){
		tok := ps.tokens[ps.pos];

		if(tok.tag == HTML->Data){
			# Text data
			t := cleantext(tok.text);
			if(len t > 0)
				inlines = ref DocNode(Rlayout->Ntext, t, nil, 0) :: inlines;
			ps.pos++;
			continue;
		}

		# Opening tags
		case tok.tag {
		# Skip non-content tags entirely
		HTML->Thead or HTML->Tstyle or HTML->Tscript or HTML->Ttitle =>
			skiptag(ps, tok.tag);

		HTML->Th1 or HTML->Th2 or HTML->Th3 or
		HTML->Th4 or HTML->Th5 or HTML->Th6 =>
			# Flush pending inlines
			if(inlines != nil){
				doc = ref DocNode(Rlayout->Npara, nil, revnodes(inlines), 0) :: doc;
				inlines = nil;
			}
			level := tok.tag - HTML->Th1 + 1;
			(heading, ni) := parseuntilclose(ps, tok.tag);
			doc = ref DocNode(Rlayout->Nheading, nil, heading, level) :: doc;

		HTML->Tp =>
			if(inlines != nil){
				doc = ref DocNode(Rlayout->Npara, nil, revnodes(inlines), 0) :: doc;
				inlines = nil;
			}
			(content, ni) := parseuntilclose(ps, HTML->Tp);
			doc = ref DocNode(Rlayout->Npara, nil, content, 0) :: doc;

		HTML->Tpre =>
			if(inlines != nil){
				doc = ref DocNode(Rlayout->Npara, nil, revnodes(inlines), 0) :: doc;
				inlines = nil;
			}
			(codetext, ni) := collecttext(ps, HTML->Tpre);
			doc = ref DocNode(Rlayout->Ncodeblock, codetext, nil, 0) :: doc;

		HTML->Tblockquote =>
			if(inlines != nil){
				doc = ref DocNode(Rlayout->Npara, nil, revnodes(inlines), 0) :: doc;
				inlines = nil;
			}
			(content, ni) := parseuntilclose(ps, HTML->Tblockquote);
			doc = ref DocNode(Rlayout->Nblockquote, nil, content, 0) :: doc;

		HTML->Tul or HTML->Tol =>
			if(inlines != nil){
				doc = ref DocNode(Rlayout->Npara, nil, revnodes(inlines), 0) :: doc;
				inlines = nil;
			}
			isol := tok.tag == HTML->Tol;
			doc = parselist(ps, isol, doc);

		HTML->Thr =>
			if(inlines != nil){
				doc = ref DocNode(Rlayout->Npara, nil, revnodes(inlines), 0) :: doc;
				inlines = nil;
			}
			doc = ref DocNode(Rlayout->Nhrule, nil, nil, 0) :: doc;
			ps.pos++;

		HTML->Tbr =>
			inlines = ref DocNode(Rlayout->Nnewline, nil, nil, 0) :: inlines;
			ps.pos++;

		HTML->Tb or HTML->Tstrong =>
			(content, ni) := parseuntilclose(ps, tok.tag);
			inlines = ref DocNode(Rlayout->Nbold, nil, content, 0) :: inlines;

		HTML->Ti or HTML->Tem =>
			(content, ni) := parseuntilclose(ps, tok.tag);
			inlines = ref DocNode(Rlayout->Nitalic, nil, content, 0) :: inlines;

		HTML->Tcode or HTML->Ttt =>
			(codetext, ni) := collecttext(ps, tok.tag);
			inlines = ref DocNode(Rlayout->Ncode, codetext, nil, 0) :: inlines;

		HTML->Ta =>
			(content, ni) := parseuntilclose(ps, HTML->Ta);
			inlines = ref DocNode(Rlayout->Nlink, nil, content, 0) :: inlines;

		HTML->Tdiv =>
			# Treat div as paragraph boundary
			if(inlines != nil){
				doc = ref DocNode(Rlayout->Npara, nil, revnodes(inlines), 0) :: doc;
				inlines = nil;
			}
			ps.pos++;

		* =>
			# Skip closing tags and unknown tags
			ps.pos++;
		}
	}

	# Flush remaining inlines
	if(inlines != nil)
		doc = ref DocNode(Rlayout->Npara, nil, revnodes(inlines), 0) :: doc;

	return revnodes(doc);
}

# Parse inline content until closing tag
parseuntilclose(ps: ref Pstate, opentag: int): (list of ref DocNode, int)
{
	closetag := opentag + HTML->RBRA;
	ps.pos++;  # skip opening tag

	nodes: list of ref DocNode;
	while(ps.pos < ps.ntokens){
		tok := ps.tokens[ps.pos];

		# Closing tag found
		if(tok.tag == closetag){
			ps.pos++;
			return (revnodes(nodes), ps.pos);
		}

		if(tok.tag == HTML->Data){
			t := cleantext(tok.text);
			if(len t > 0)
				nodes = ref DocNode(Rlayout->Ntext, t, nil, 0) :: nodes;
			ps.pos++;
			continue;
		}

		# Handle nested inline tags
		case tok.tag {
		HTML->Tb or HTML->Tstrong =>
			(content, nil) := parseuntilclose(ps, tok.tag);
			nodes = ref DocNode(Rlayout->Nbold, nil, content, 0) :: nodes;
		HTML->Ti or HTML->Tem =>
			(content, nil) := parseuntilclose(ps, tok.tag);
			nodes = ref DocNode(Rlayout->Nitalic, nil, content, 0) :: nodes;
		HTML->Tcode or HTML->Ttt =>
			(codetext, nil) := collecttext(ps, tok.tag);
			nodes = ref DocNode(Rlayout->Ncode, codetext, nil, 0) :: nodes;
		HTML->Ta =>
			(content, nil) := parseuntilclose(ps, HTML->Ta);
			nodes = ref DocNode(Rlayout->Nlink, nil, content, 0) :: nodes;
		HTML->Tbr =>
			nodes = ref DocNode(Rlayout->Nnewline, nil, nil, 0) :: nodes;
			ps.pos++;
		* =>
			# Skip unknown/closing tags
			ps.pos++;
		}
	}
	return (revnodes(nodes), ps.pos);
}

# Collect raw text until closing tag (for <pre>, <code>)
collecttext(ps: ref Pstate, opentag: int): (string, int)
{
	closetag := opentag + HTML->RBRA;
	ps.pos++;  # skip opening tag

	text := "";
	while(ps.pos < ps.ntokens){
		tok := ps.tokens[ps.pos];
		if(tok.tag == closetag){
			ps.pos++;
			return (text, ps.pos);
		}
		if(tok.tag == HTML->Data)
			text += tok.text;
		ps.pos++;
	}
	return (text, ps.pos);
}

# Parse <ul> or <ol> list
parselist(ps: ref Pstate, isol: int, doc: list of ref DocNode): list of ref DocNode
{
	closetag := HTML->Tul + HTML->RBRA;
	if(isol)
		closetag = HTML->Tol + HTML->RBRA;
	ps.pos++;  # skip <ul>/<ol>

	itemnum := 1;
	while(ps.pos < ps.ntokens){
		tok := ps.tokens[ps.pos];

		if(tok.tag == closetag){
			ps.pos++;
			return doc;
		}

		if(tok.tag == HTML->Tli){
			(content, nil) := parseuntilclose(ps, HTML->Tli);
			if(isol){
				doc = ref DocNode(Rlayout->Nnumber, nil, content, itemnum) :: doc;
				itemnum++;
			} else
				doc = ref DocNode(Rlayout->Nbullet, nil, content, 0) :: doc;
			continue;
		}

		# Skip non-li content
		ps.pos++;
	}
	return doc;
}

# ---- Helpers ----

# Skip everything until the matching close tag
skiptag(ps: ref Pstate, opentag: int)
{
	closetag := opentag + HTML->RBRA;
	ps.pos++;
	depth := 1;
	while(ps.pos < ps.ntokens && depth > 0){
		tok := ps.tokens[ps.pos];
		if(tok.tag == opentag)
			depth++;
		else if(tok.tag == closetag)
			depth--;
		ps.pos++;
	}
}

# Clean text: collapse whitespace, trim
cleantext(s: string): string
{
	if(s == nil)
		return "";

	result := "";
	lastspace := 1;  # start as if preceded by space (trim leading)
	for(i := 0; i < len s; i++){
		c := s[i];
		if(c == '\n' || c == '\r' || c == '\t')
			c = ' ';
		if(c == ' '){
			if(!lastspace){
				result[len result] = ' ';
				lastspace = 1;
			}
		} else {
			result[len result] = c;
			lastspace = 0;
		}
	}
	# Trim trailing space
	if(len result > 0 && result[len result - 1] == ' ')
		result = result[:len result - 1];
	return result;
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

revnodes(l: list of ref DocNode): list of ref DocNode
{
	r: list of ref DocNode;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}
