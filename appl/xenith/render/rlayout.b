implement Rlayout;

include "sys.m";
	sys: Sys;

include "draw.m";
	drawm: Draw;
	Display, Image, Font, Rect, Point: import drawm;

include "rlayout.m";

display: ref Display;

# Layout state used during rendering
Lstate: adt {
	img: ref Image;       # Target image
	style: ref Style;
	x: int;               # Current x position
	y: int;               # Current y position (top of line)
	lineheight: int;      # Height of current line
	maxwidth: int;        # Usable width (style.width - 2*margin)
	indent: int;          # Current left indent (for lists, blockquotes)
};

init(d: ref Draw->Display)
{
	sys = load Sys Sys->PATH;
	drawm = load Draw Draw->PATH;
	display = d;
}

render(doc: list of ref DocNode, style: ref Style): (ref Draw->Image, int)
{
	if(style == nil || style.font == nil)
		return (nil, 0);

	width := style.width;
	if(width <= 0)
		width = 800;

	# First pass: calculate total height needed
	height := measureheight(doc, style);
	if(height < style.font.height * 2)
		height = style.font.height * 2;

	# Add bottom margin
	height += style.margin;

	# Create target image
	r := Rect(Point(0, 0), Point(width, height));
	img := display.newimage(r, drawm->RGB24, 0, drawm->White);
	if(img == nil)
		return (nil, 0);

	# Fill background
	img.draw(r, style.bgcolor, nil, Point(0, 0));

	# Set up layout state
	ls := ref Lstate(
		img, style,
		style.margin,           # x
		style.margin,           # y
		style.font.height,      # lineheight
		width - 2 * style.margin, # maxwidth
		0                       # indent
	);

	# Second pass: render
	renderblocks(ls, doc);

	return (img, ls.y + ls.lineheight);
}

# Measure total height needed for a document
measureheight(doc: list of ref DocNode, style: ref Style): int
{
	h := style.margin;
	fh := style.font.height;
	cfh := fh;
	if(style.codefont != nil)
		cfh = style.codefont.height;
	maxw := style.width - 2 * style.margin;

	for(; doc != nil; doc = tl doc){
		node := hd doc;
		case node.kind {
		Npara =>
			# Estimate paragraph height from wrapped text
			txt := flattentext(node.children);
			lines := wrapcount(txt, style.font, maxw);
			h += lines * fh + fh/2;  # paragraph spacing
		Nheading =>
			h += fh * 2;  # heading + spacing
		Ncodeblock =>
			txt := "";
			if(node.text != nil)
				txt = node.text;
			else
				txt = flattentext(node.children);
			nlines := 1;
			for(i := 0; i < len txt; i++)
				if(txt[i] == '\n')
					nlines++;
			h += nlines * cfh + fh;  # code lines + padding + spacing
		Nbullet or Nnumber =>
			txt := flattentext(node.children);
			lines := wrapcount(txt, style.font, maxw - 24);
			h += lines * fh + 2;
		Nhrule =>
			h += fh;
		Nblockquote =>
			txt := flattentext(node.children);
			lines := wrapcount(txt, style.font, maxw - 20);
			h += lines * fh + fh/2;
		* =>
			h += fh;
		}
	}
	return h;
}

# Count lines needed to wrap text at given width
wrapcount(text: string, font: ref Font, width: int): int
{
	if(text == nil || len text == 0)
		return 1;
	if(width <= 0)
		return 1;

	lines := 1;
	linestart := 0;
	lastspace := -1;

	for(i := 0; i < len text; i++){
		c := text[i];
		if(c == '\n'){
			lines++;
			linestart = i + 1;
			lastspace = -1;
			continue;
		}
		if(c == ' ' || c == '\t')
			lastspace = i;

		seg := text[linestart:i+1];
		w := font.width(seg);
		if(w > width && linestart < i){
			lines++;
			if(lastspace > linestart){
				linestart = lastspace + 1;
				lastspace = -1;
			} else
				linestart = i;
		}
	}
	return lines;
}

# Render a list of block-level nodes
renderblocks(ls: ref Lstate, doc: list of ref DocNode)
{
	for(; doc != nil; doc = tl doc){
		node := hd doc;
		case node.kind {
		Npara =>
			renderpara(ls, node);
		Nheading =>
			renderheading(ls, node);
		Ncodeblock =>
			rendercodeblock(ls, node);
		Nbullet =>
			renderbullet(ls, node);
		Nnumber =>
			rendernumber(ls, node);
		Nhrule =>
			renderhrule(ls);
		Nblockquote =>
			renderblockquote(ls, node);
		* =>
			# Treat as paragraph
			renderpara(ls, node);
		}
	}
}

# Render a paragraph
renderpara(ls: ref Lstate, node: ref DocNode)
{
	ls.x = ls.style.margin + ls.indent;
	renderinlines(ls, node.children);
	newline(ls);
	ls.y += ls.style.font.height / 3;  # Paragraph spacing
}

# Render a heading
renderheading(ls: ref Lstate, node: ref DocNode)
{
	ls.y += ls.style.font.height / 3;  # Space before heading
	ls.x = ls.style.margin + ls.indent;

	# Render heading text in bold (uppercase prefix for emphasis)
	font := ls.style.font;
	color := ls.style.fgcolor;

	# Draw text
	txt := flattentext(node.children);
	if(node.aux <= 1){
		# H1: draw with extra vertical space
		ls.img.text(Point(ls.x, ls.y + font.ascent), color, Point(0, 0), font, txt);
		ls.y += font.height;
		# Draw underline for H1
		y := ls.y + 2;
		enx := ls.style.margin + ls.maxwidth;
		ls.img.line(Point(ls.style.margin, y), Point(enx, y), drawm->Endsquare, drawm->Endsquare, 1, color, Point(0, 0));
		ls.y += 4;
	} else if(node.aux == 2){
		# H2: normal size with underline
		ls.img.text(Point(ls.x, ls.y + font.ascent), color, Point(0, 0), font, txt);
		ls.y += font.height;
		# Dashed underline for H2
		y := ls.y + 1;
		enx := ls.x + font.width(txt);
		ls.img.line(Point(ls.x, y), Point(enx, y), drawm->Endsquare, drawm->Endsquare, 0, color, Point(0, 0));
		ls.y += 3;
	} else {
		# H3+: just render with spacing
		ls.img.text(Point(ls.x, ls.y + font.ascent), color, Point(0, 0), font, txt);
		ls.y += font.height;
	}
	ls.x = ls.style.margin + ls.indent;
	ls.y += ls.style.font.height / 4;  # Space after heading
}

# Render a code block
rendercodeblock(ls: ref Lstate, node: ref DocNode)
{
	font := ls.style.codefont;
	if(font == nil)
		font = ls.style.font;

	txt := "";
	if(node.text != nil)
		txt = node.text;
	else
		txt = flattentext(node.children);

	# Measure the code block
	nlines := 1;
	for(i := 0; i < len txt; i++)
		if(txt[i] == '\n')
			nlines++;

	pad := 6;
	blockh := nlines * font.height + 2 * pad;

	# Draw background rectangle
	x0 := ls.style.margin + ls.indent;
	x1 := ls.style.margin + ls.maxwidth;
	bgr := Rect(Point(x0, ls.y), Point(x1, ls.y + blockh));
	ls.img.draw(bgr, ls.style.codebgcolor, nil, Point(0, 0));

	# Render each line
	ty := ls.y + pad;
	linestart := 0;
	for(i = 0; i <= len txt; i++){
		if(i == len txt || txt[i] == '\n'){
			line := "";
			if(i > linestart)
				line = txt[linestart:i];
			ls.img.text(Point(x0 + pad, ty + font.ascent), ls.style.fgcolor, Point(0, 0), font, line);
			ty += font.height;
			linestart = i + 1;
		}
	}

	ls.y += blockh + ls.style.font.height / 3;
	ls.x = ls.style.margin + ls.indent;
}

# Render a bullet list item
renderbullet(ls: ref Lstate, node: ref DocNode)
{
	font := ls.style.font;
	bulletindent := 20;

	# Draw bullet character
	bx := ls.style.margin + ls.indent + 6;
	by := ls.y + font.ascent;
	ls.img.text(Point(bx, by), ls.style.fgcolor, Point(0, 0), font, "•");

	# Render content with indent
	oldi := ls.indent;
	ls.indent += bulletindent;
	ls.x = ls.style.margin + ls.indent;
	renderinlines(ls, node.children);
	newline(ls);
	ls.indent = oldi;
}

# Render a numbered list item
rendernumber(ls: ref Lstate, node: ref DocNode)
{
	font := ls.style.font;
	numindent := 24;

	# Draw number
	numstr := sys->sprint("%d.", node.aux);
	nx := ls.style.margin + ls.indent + 2;
	ny := ls.y + font.ascent;
	ls.img.text(Point(nx, ny), ls.style.fgcolor, Point(0, 0), font, numstr);

	# Render content with indent
	oldi := ls.indent;
	ls.indent += numindent;
	ls.x = ls.style.margin + ls.indent;
	renderinlines(ls, node.children);
	newline(ls);
	ls.indent = oldi;
}

# Render a horizontal rule
renderhrule(ls: ref Lstate)
{
	ls.y += ls.style.font.height / 3;
	y := ls.y + ls.style.font.height / 2;
	x0 := ls.style.margin;
	x1 := ls.style.margin + ls.maxwidth;
	ls.img.line(Point(x0, y), Point(x1, y), drawm->Endsquare, drawm->Endsquare, 0, ls.style.fgcolor, Point(0, 0));
	ls.y += ls.style.font.height;
}

# Render a blockquote
renderblockquote(ls: ref Lstate, node: ref DocNode)
{
	# Draw left border line
	bx := ls.style.margin + ls.indent + 4;
	y0 := ls.y;

	# Render content indented
	oldi := ls.indent;
	ls.indent += 16;
	ls.x = ls.style.margin + ls.indent;
	renderinlines(ls, node.children);
	newline(ls);
	y1 := ls.y;
	ls.indent = oldi;

	# Draw the quote bar
	ls.img.line(Point(bx, y0), Point(bx, y1), drawm->Endsquare, drawm->Endsquare, 1, ls.style.linkcolor, Point(0, 0));

	ls.y += ls.style.font.height / 4;
}

# Render inline nodes (text, bold, italic, code, links) with word wrapping
renderinlines(ls: ref Lstate, nodes: list of ref DocNode)
{
	for(; nodes != nil; nodes = tl nodes){
		node := hd nodes;
		case node.kind {
		Ntext =>
			rendertext(ls, node.text, ls.style.font, ls.style.fgcolor, 0);
		Nbold =>
			# Bold: render twice with 1px offset for faux bold
			txt := flattentext(node.children);
			renderbold(ls, txt);
		Nitalic =>
			# Italic: render with underline (we lack italic fonts)
			txt := flattentext(node.children);
			rendertext(ls, txt, ls.style.font, ls.style.fgcolor, 1);
		Ncode =>
			# Inline code: monospace with background
			font := ls.style.codefont;
			if(font == nil)
				font = ls.style.font;
			renderinlinecode(ls, node.text, font);
		Nlink =>
			txt := flattentext(node.children);
			rendertext(ls, txt, ls.style.font, ls.style.linkcolor, 1);
		Nnewline =>
			newline(ls);
		* =>
			# Recurse for nested structures
			if(node.children != nil)
				renderinlines(ls, node.children);
			else if(node.text != nil)
				rendertext(ls, node.text, ls.style.font, ls.style.fgcolor, 0);
		}
	}
}

# Render text with word wrapping
rendertext(ls: ref Lstate, text: string, font: ref Font, color: ref Image, underline: int)
{
	if(text == nil || len text == 0)
		return;

	maxright := ls.style.margin + ls.indent + ls.maxwidth - ls.indent;

	# Process word by word
	i := 0;
	for(;;){
		# Skip to next non-space or end
		wordstart := i;
		while(i < len text && text[i] != ' ' && text[i] != '\t' && text[i] != '\n')
			i++;

		word := "";
		if(i > wordstart)
			word = text[wordstart:i];

		if(len word > 0){
			ww := font.width(word);
			# Check if word fits on current line
			if(ls.x + ww > maxright && ls.x > ls.style.margin + ls.indent){
				newline(ls);
			}
			# Draw word
			pt := Point(ls.x, ls.y + font.ascent);
			ls.img.text(pt, color, Point(0, 0), font, word);
			if(underline){
				uy := ls.y + font.ascent + 2;
				ls.img.line(Point(ls.x, uy), Point(ls.x + ww, uy),
					drawm->Endsquare, drawm->Endsquare, 0, color, Point(0, 0));
			}
			ls.x += ww;
		}

		# Handle space / newline after word
		if(i >= len text)
			break;
		if(text[i] == '\n'){
			newline(ls);
			i++;
		} else {
			# Space - add space width
			if(ls.x > ls.style.margin + ls.indent)
				ls.x += font.width(" ");
			i++;
		}
	}
}

# Render bold text (faux bold: draw twice with 1px x offset)
renderbold(ls: ref Lstate, text: string)
{
	if(text == nil || len text == 0)
		return;

	font := ls.style.font;
	color := ls.style.fgcolor;
	maxright := ls.style.margin + ls.indent + ls.maxwidth - ls.indent;

	i := 0;
	for(;;){
		wordstart := i;
		while(i < len text && text[i] != ' ' && text[i] != '\t' && text[i] != '\n')
			i++;

		word := "";
		if(i > wordstart)
			word = text[wordstart:i];

		if(len word > 0){
			ww := font.width(word);
			if(ls.x + ww > maxright && ls.x > ls.style.margin + ls.indent)
				newline(ls);

			pt := Point(ls.x, ls.y + font.ascent);
			# Draw twice for faux bold
			ls.img.text(pt, color, Point(0, 0), font, word);
			ls.img.text(Point(pt.x + 1, pt.y), color, Point(0, 0), font, word);
			ls.x += ww + 1;
		}

		if(i >= len text)
			break;
		if(text[i] == '\n'){
			newline(ls);
			i++;
		} else {
			if(ls.x > ls.style.margin + ls.indent)
				ls.x += font.width(" ");
			i++;
		}
	}
}

# Render inline code with background
renderinlinecode(ls: ref Lstate, text: string, font: ref Font)
{
	if(text == nil)
		return;

	pad := 3;
	tw := font.width(text);
	maxright := ls.style.margin + ls.indent + ls.maxwidth - ls.indent;

	if(ls.x + tw + 2*pad > maxright && ls.x > ls.style.margin + ls.indent)
		newline(ls);

	# Draw background
	bgr := Rect(Point(ls.x, ls.y), Point(ls.x + tw + 2*pad, ls.y + font.height));
	ls.img.draw(bgr, ls.style.codebgcolor, nil, Point(0, 0));

	# Draw text
	pt := Point(ls.x + pad, ls.y + font.ascent);
	ls.img.text(pt, ls.style.fgcolor, Point(0, 0), font, text);
	ls.x += tw + 2*pad + 2;
}

# Move to next line
newline(ls: ref Lstate)
{
	ls.y += ls.style.font.height;
	ls.x = ls.style.margin + ls.indent;
}

# Flatten all inline children to plain text
flattentext(nodes: list of ref DocNode): string
{
	s := "";
	for(; nodes != nil; nodes = tl nodes){
		node := hd nodes;
		if(node.text != nil)
			s += node.text;
		if(node.children != nil)
			s += flattentext(node.children);
	}
	return s;
}

# Extract plain text from an entire document tree
totext(doc: list of ref DocNode): string
{
	s := "";
	for(; doc != nil; doc = tl doc){
		node := hd doc;
		case node.kind {
		Npara or Nblockquote =>
			s += flattentext(node.children) + "\n\n";
		Nheading =>
			s += flattentext(node.children) + "\n\n";
		Ncodeblock =>
			if(node.text != nil)
				s += node.text + "\n\n";
			else
				s += flattentext(node.children) + "\n\n";
		Nbullet =>
			s += "• " + flattentext(node.children) + "\n";
		Nnumber =>
			s += sys->sprint("%d. ", node.aux) + flattentext(node.children) + "\n";
		Nhrule =>
			s += "---\n\n";
		* =>
			if(node.text != nil)
				s += node.text;
			if(node.children != nil)
				s += flattentext(node.children);
			s += "\n";
		}
	}
	return s;
}
