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

	# Parse into document tree
	doc := parsemd(mdtext);

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

# ---- Markdown Parser ----

# Parse markdown text into a list of DocNode blocks
parsemd(text: string): list of ref DocNode
{
	doc: list of ref DocNode;
	lines := splitlines(text);

	i := 0;
	nlines := len lines;
	for(;;){
		if(i >= nlines)
			break;
		line := lines[i];

		# Blank line - skip
		if(isblank(line)){
			i++;
			continue;
		}

		# Code block (```)
		if(len line >= 3 && line[0:3] == "```"){
			(block, ni) := parsecodeblock(lines, i);
			doc = block :: doc;
			i = ni;
			continue;
		}

		# Heading (#)
		if(len line > 0 && line[0] == '#'){
			(heading, ni) := parseheading(line);
			if(heading != nil){
				doc = heading :: doc;
				if(ni > i)
					i = ni;
				else
					i++;
				continue;
			}
		}

		# Horizontal rule (---, ***, ___)
		if(ishrule(line)){
			doc = ref DocNode(Rlayout->Nhrule, nil, nil, 0) :: doc;
			i++;
			continue;
		}

		# Blockquote (>)
		if(len line > 0 && line[0] == '>'){
			(bq, ni) := parseblockquote(lines, i, nlines);
			doc = bq :: doc;
			i = ni;
			continue;
		}

		# Bullet list (- or *)
		if(len line >= 2 && (line[0] == '-' || line[0] == '*') && line[1] == ' '){
			(item, ni) := parsebullet(lines, i, nlines);
			doc = item :: doc;
			i = ni;
			continue;
		}

		# Numbered list (1. 2. etc)
		if(len line >= 3 && line[0] >= '0' && line[0] <= '9'){
			(item, ni) := parsenumber(lines, i, nlines);
			if(item != nil){
				doc = item :: doc;
				i = ni;
				continue;
			}
		}

		# Default: paragraph (collect until blank line or block element)
		(para, ni) := parsepara(lines, i, nlines);
		doc = para :: doc;
		i = ni;
	}

	# Reverse to restore order
	return reversedocs(doc);
}

# Parse a heading line: # text
parseheading(line: string): (ref DocNode, int)
{
	level := 0;
	i := 0;
	while(i < len line && line[i] == '#'){
		level++;
		i++;
	}
	if(level == 0 || level > 6)
		return (nil, 0);
	while(i < len line && line[i] == ' ')
		i++;

	text := "";
	if(i < len line)
		text = line[i:];
	# Strip trailing #
	while(len text > 0 && text[len text - 1] == '#')
		text = text[:len text - 1];
	while(len text > 0 && text[len text - 1] == ' ')
		text = text[:len text - 1];

	children := parseinline(text);
	return (ref DocNode(Rlayout->Nheading, nil, children, level), 0);
}

# Parse a fenced code block
parsecodeblock(lines: array of string, start: int): (ref DocNode, int)
{
	# Skip opening ```
	i := start + 1;
	code := "";

	while(i < len lines){
		if(len lines[i] >= 3 && lines[i][0:3] == "```"){
			i++;
			break;
		}
		if(len code > 0)
			code += "\n";
		code += lines[i];
		i++;
	}

	return (ref DocNode(Rlayout->Ncodeblock, code, nil, 0), i);
}

# Parse a blockquote (> lines)
parseblockquote(lines: array of string, start, nlines: int): (ref DocNode, int)
{
	text := "";
	i := start;
	while(i < nlines){
		line := lines[i];
		if(len line == 0 || line[0] != '>')
			break;
		# Strip > and optional space
		content := "";
		j := 1;
		if(j < len line && line[j] == ' ')
			j++;
		if(j < len line)
			content = line[j:];
		if(len text > 0)
			text += " ";
		text += content;
		i++;
	}

	children := parseinline(text);
	return (ref DocNode(Rlayout->Nblockquote, nil, children, 0), i);
}

# Parse a bullet list item
parsebullet(lines: array of string, start, nlines: int): (ref DocNode, int)
{
	# Strip "- " or "* "
	text := lines[start][2:];
	i := start + 1;
	# Continuation lines (indented)
	while(i < nlines && len lines[i] > 0 && (lines[i][0] == ' ' || lines[i][0] == '\t')){
		text += " " + stripws(lines[i]);
		i++;
	}

	children := parseinline(text);
	return (ref DocNode(Rlayout->Nbullet, nil, children, 0), i);
}

# Parse a numbered list item
parsenumber(lines: array of string, start, nlines: int): (ref DocNode, int)
{
	line := lines[start];
	# Find "N. " pattern
	i := 0;
	while(i < len line && line[i] >= '0' && line[i] <= '9')
		i++;
	if(i == 0 || i >= len line || line[i] != '.')
		return (nil, start);
	num := int line[0:i];
	i++;
	if(i < len line && line[i] == ' ')
		i++;

	text := "";
	if(i < len line)
		text = line[i:];
	j := start + 1;
	while(j < nlines && len lines[j] > 0 && (lines[j][0] == ' ' || lines[j][0] == '\t')){
		text += " " + stripws(lines[j]);
		j++;
	}

	children := parseinline(text);
	return (ref DocNode(Rlayout->Nnumber, nil, children, num), j);
}

# Parse a paragraph (until blank line or block element)
parsepara(lines: array of string, start, nlines: int): (ref DocNode, int)
{
	text := "";
	i := start;
	while(i < nlines){
		line := lines[i];
		if(isblank(line))
			break;
		# Check if next line starts a block element
		if(i > start){
			if(len line > 0 && line[0] == '#')
				break;
			if(len line >= 3 && line[0:3] == "```")
				break;
			if(ishrule(line))
				break;
			if(len line > 0 && line[0] == '>')
				break;
			if(len line >= 2 && (line[0] == '-' || line[0] == '*') && line[1] == ' ')
				break;
			if(len line >= 3 && line[0] >= '0' && line[0] <= '9' && hasdotspace(line))
				break;
		}
		if(len text > 0)
			text += " ";
		text += line;
		i++;
	}

	children := parseinline(text);
	return (ref DocNode(Rlayout->Npara, nil, children, 0), i);
}

# Parse inline formatting: **bold**, *italic*, `code`, [link](url)
parseinline(text: string): list of ref DocNode
{
	nodes: list of ref DocNode;
	i := 0;
	plain := "";

	while(i < len text){
		c := text[i];

		# Bold: **text**
		if(c == '*' && i+1 < len text && text[i+1] == '*'){
			if(len plain > 0){
				nodes = ref DocNode(Rlayout->Ntext, plain, nil, 0) :: nodes;
				plain = "";
			}
			end := findclose(text, i+2, "**");
			if(end > 0){
				inner := text[i+2:end];
				nodes = ref DocNode(Rlayout->Nbold, nil, ref DocNode(Rlayout->Ntext, inner, nil, 0) :: nil, 0) :: nodes;
				i = end + 2;
				continue;
			}
		}

		# Italic: *text*  (but not **)
		if(c == '*' && !(i+1 < len text && text[i+1] == '*')){
			if(len plain > 0){
				nodes = ref DocNode(Rlayout->Ntext, plain, nil, 0) :: nodes;
				plain = "";
			}
			end := findclose(text, i+1, "*");
			if(end > 0){
				inner := text[i+1:end];
				nodes = ref DocNode(Rlayout->Nitalic, nil, ref DocNode(Rlayout->Ntext, inner, nil, 0) :: nil, 0) :: nodes;
				i = end + 1;
				continue;
			}
		}

		# Inline code: `text`
		if(c == '`'){
			if(len plain > 0){
				nodes = ref DocNode(Rlayout->Ntext, plain, nil, 0) :: nodes;
				plain = "";
			}
			end := findclose(text, i+1, "`");
			if(end > 0){
				inner := text[i+1:end];
				nodes = ref DocNode(Rlayout->Ncode, inner, nil, 0) :: nodes;
				i = end + 1;
				continue;
			}
		}

		# Link: [text](url)
		if(c == '['){
			if(len plain > 0){
				nodes = ref DocNode(Rlayout->Ntext, plain, nil, 0) :: nodes;
				plain = "";
			}
			(linknode, ni) := parselink(text, i);
			if(linknode != nil){
				nodes = linknode :: nodes;
				i = ni;
				continue;
			}
		}

		plain[len plain] = c;
		i++;
	}

	if(len plain > 0)
		nodes = ref DocNode(Rlayout->Ntext, plain, nil, 0) :: nodes;

	return reversenodes(nodes);
}

# Find closing delimiter in text starting from pos
findclose(text: string, start: int, delim: string): int
{
	dlen := len delim;
	for(i := start; i <= len text - dlen; i++){
		if(text[i:i+dlen] == delim)
			return i;
	}
	return -1;
}

# Parse a [text](url) link
parselink(text: string, start: int): (ref DocNode, int)
{
	# Find ]
	i := start + 1;
	while(i < len text && text[i] != ']')
		i++;
	if(i >= len text)
		return (nil, start + 1);

	linktext := text[start+1:i];
	i++;  # skip ]

	# Expect (
	if(i >= len text || text[i] != '(')
		return (nil, start + 1);
	i++;

	# Find )
	j := i;
	while(j < len text && text[j] != ')')
		j++;
	if(j >= len text)
		return (nil, start + 1);

	# url := text[i:j];  # URL available but not used in display yet
	j++;  # skip )

	children := ref DocNode(Rlayout->Ntext, linktext, nil, 0) :: nil;
	return (ref DocNode(Rlayout->Nlink, nil, children, 0), j);
}

# ---- Helpers ----

splitlines(text: string): array of string
{
	# Count lines
	nlines := 1;
	for(i := 0; i < len text; i++)
		if(text[i] == '\n')
			nlines++;

	lines := array[nlines] of string;
	li := 0;
	start := 0;
	for(i = 0; i < len text; i++){
		if(text[i] == '\n'){
			lines[li++] = text[start:i];
			start = i + 1;
		}
	}
	if(start <= len text)
		lines[li] = text[start:];
	return lines;
}

isblank(line: string): int
{
	for(i := 0; i < len line; i++)
		if(line[i] != ' ' && line[i] != '\t' && line[i] != '\r')
			return 0;
	return 1;
}

ishrule(line: string): int
{
	if(len line < 3)
		return 0;
	c := line[0];
	if(c != '-' && c != '*' && c != '_')
		return 0;
	count := 0;
	for(i := 0; i < len line; i++){
		if(line[i] == c)
			count++;
		else if(line[i] != ' ')
			return 0;
	}
	return count >= 3;
}

hasdotspace(line: string): int
{
	for(i := 0; i < len line; i++){
		if(line[i] == '.' && i+1 < len line && line[i+1] == ' ')
			return 1;
		if(line[i] < '0' || line[i] > '9')
			return 0;
	}
	return 0;
}

stripws(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;
	if(i >= len s)
		return "";
	return s[i:];
}

reversedocs(l: list of ref DocNode): list of ref DocNode
{
	r: list of ref DocNode;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}

reversenodes(l: list of ref DocNode): list of ref DocNode
{
	return reversedocs(l);
}
