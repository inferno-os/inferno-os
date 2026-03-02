implement Tlayout;

#
# Text layout engine - walks DocNode tree and produces typeset plain text
# using Unicode characters for visual formatting in a monospace font.
#
# Key characters:
#   U+2500 ─  horizontal rule / heading underline
#   U+2502 │  code block left bar
#   U+2022 •  bullet
#   U+258E ▎  blockquote left bar
#

include "sys.m";
	sys: Sys;

include "tlayout.m";

init()
{
	sys = load Sys Sys->PATH;
}

# Convert document tree to typeset text
totext(doc: list of ref DocNode, width: int): string
{
	if(width < 20)
		width = 80;

	out := "";
	for(; doc != nil; doc = tl doc){
		n := hd doc;
		out += blocktotext(n, width);
		# Add blank line after last item in a list/blockquote group
		if(n.kind == Nbullet || n.kind == Nnumber || n.kind == Nblockquote){
			nextkind := -1;
			if(tl doc != nil)
				nextkind = (hd tl doc).kind;
			if(nextkind != n.kind)
				out += "\n";
		}
	}
	return out;
}

# Render a single block-level node
blocktotext(n: ref DocNode, width: int): string
{
	case n.kind {
	Nheading =>
		return headingtext(n, width);
	Npara =>
		return paratext(n, width);
	Ncodeblock =>
		return codeblocktext(n, width);
	Nbullet =>
		return bullettext(n, width);
	Nnumber =>
		return numbertext(n, width);
	Nblockquote =>
		return blockquotetext(n, width);
	Nhrule =>
		return hruletext(width);
	Ntable =>
		return tabletext(n, width);
	* =>
		# Inline nodes at block level: just extract text
		t := inlinetext(n);
		if(len t > 0)
			return wordwrap(t, width) + "\n";
		return "";
	}
}

# Heading: level 1 = UPPERCASE + full-width rule
#          level 2 = text + underline matching text length
#          level 3 = text + short underline (half text length)
#          level 4+ = ── prefix
headingtext(n: ref DocNode, width: int): string
{
	t := flattext(n.children);
	level := n.aux;
	if(level < 1)
		level = 1;

	case level {
	1 =>
		up := toupper(t);
		rule := repchar(16r2500, width);  # ─
		return up + "\n" + rule + "\n\n";
	2 =>
		rlen := len t;
		if(rlen > width)
			rlen = width;
		rule := repchar(16r2500, rlen);  # ─
		return t + "\n" + rule + "\n\n";
	3 =>
		rlen := len t / 2;
		if(rlen < 4)
			rlen = 4;
		if(rlen > width)
			rlen = width;
		rule := repchar(16r2500, rlen);  # ─ (short)
		return t + "\n" + rule + "\n\n";
	* =>
		# Level 4+: decorated with ── prefix
		return "\u2500\u2500 " + t + "\n\n";
	}
}

# Paragraph: word-wrap inline content
paratext(n: ref DocNode, width: int): string
{
	t := inlinetext(n);
	return wordwrap(t, width) + "\n\n";
}

# Code block: indent 4 + │ prefix each line
codeblocktext(n: ref DocNode, nil: int): string
{
	code := n.text;
	if(code == nil)
		code = flattext(n.children);

	out := "";
	lines := splitlines(code);
	for(i := 0; i < len lines; i++)
		out += "    \u2502 " + lines[i] + "\n";  # │
	return out + "\n";
}

# Bullet: • prefix, continuation indent 4
bullettext(n: ref DocNode, width: int): string
{
	t := flattext(n.children);
	prefix := "  \u2022 ";  # •
	contprefix := "    ";
	return wrapindent(t, width, prefix, contprefix) + "\n";
}

# Numbered list: N. prefix, continuation indent 5
numbertext(n: ref DocNode, width: int): string
{
	t := flattext(n.children);
	num := string n.aux;
	prefix := "  " + num + ". ";
	# Continuation indent matches prefix width
	contprefix := "     ";
	if(n.aux >= 10)
		contprefix += " ";
	return wrapindent(t, width, prefix, contprefix) + "\n";
}

# Blockquote: ▎ prefix each wrapped line
blockquotetext(n: ref DocNode, width: int): string
{
	t := flattext(n.children);
	prefix := "  \u258E ";  # ▎
	contprefix := "  \u258E ";
	return wrapindent(t, width - 4, prefix, contprefix) + "\n";
}

# Horizontal rule: ─ × width
hruletext(width: int): string
{
	return repchar(16r2500, width) + "\n\n";  # ─
}

# Table: measure column widths, pad with spaces, ─ separator
tabletext(n: ref DocNode, nil: int): string
{
	# Collect rows
	rows: list of ref DocNode;
	for(ch := n.children; ch != nil; ch = tl ch)
		if((hd ch).kind == Ntablerow)
			rows = hd ch :: rows;
	rows = revnodes(rows);

	if(rows == nil)
		return "";

	# Count max columns and measure widths
	ncols := 0;
	for(r := rows; r != nil; r = tl r){
		nc := listlen((hd r).children);
		if(nc > ncols)
			ncols = nc;
	}
	if(ncols == 0)
		return "";

	colwidths := array[ncols] of { * => 0 };

	# First pass: measure
	for(r = rows; r != nil; r = tl r){
		col := 0;
		for(ch = (hd r).children; ch != nil && col < ncols; ch = tl ch){
			ct := flattext((hd ch).children);
			if(ct == nil)
				ct = (hd ch).text;
			if(ct == nil)
				ct = "";
			if(len ct > colwidths[col])
				colwidths[col] = len ct;
			col++;
		}
	}

	# Add padding
	gap := 2;

	out := "";
	firstrow := 1;
	for(r = rows; r != nil; r = tl r){
		line := "  ";
		col := 0;
		for(ch = (hd r).children; ch != nil && col < ncols; ch = tl ch){
			ct := flattext((hd ch).children);
			if(ct == nil)
				ct = (hd ch).text;
			if(ct == nil)
				ct = "";
			line += padright(ct, colwidths[col] + gap);
			col++;
		}
		# Pad remaining columns
		while(col < ncols){
			line += padright("", colwidths[col] + gap);
			col++;
		}
		out += line + "\n";

		# Separator after first row (header)
		if(firstrow){
			totalw := 0;
			for(col = 0; col < ncols; col++)
				totalw += colwidths[col] + gap;
			out += "  " + repchar(16r2500, totalw) + "\n";  # ─ continuous
			firstrow = 0;
		}
	}
	return out + "\n";
}

# Extract inline text from a node, handling formatting markers
inlinetext(n: ref DocNode): string
{
	case n.kind {
	Ntext =>
		return n.text;
	Nbold or Nitalic or Nlink =>
		return flattext(n.children);
	Ncode =>
		return "`" + n.text + "`";
	Nnewline =>
		return "\n";
	Npara =>
		return flattext(n.children);
	* =>
		if(n.text != nil)
			return n.text;
		return flattext(n.children);
	}
}

# Flatten children to plain text
flattext(children: list of ref DocNode): string
{
	s := "";
	for(; children != nil; children = tl children)
		s += inlinetext(hd children);
	return s;
}

# Word-wrap text to width columns
wordwrap(text: string, width: int): string
{
	if(width < 10)
		width = 10;

	out := "";
	col := 0;
	words := splitwords(text);
	for(; words != nil; words = tl words){
		w := hd words;
		if(w == "\n"){
			out += "\n";
			col = 0;
			continue;
		}
		wlen := len w;
		if(col > 0 && col + 1 + wlen > width){
			out += "\n";
			col = 0;
		}
		if(col > 0){
			out += " ";
			col++;
		}
		out += w;
		col += wlen;
	}
	return out;
}

# Word-wrap with prefix for first line and continuation lines
wrapindent(text: string, width: int, prefix: string, contprefix: string): string
{
	plen := printlen(prefix);
	avail := width - plen;
	if(avail < 10)
		avail = 10;

	out := prefix;
	col := 0;
	first := 1;
	words := splitwords(text);
	for(; words != nil; words = tl words){
		w := hd words;
		if(w == "\n"){
			out += "\n" + contprefix;
			col = 0;
			first = 0;
			continue;
		}
		wlen := len w;
		if(col > 0 && col + 1 + wlen > avail){
			out += "\n" + contprefix;
			col = 0;
			first = 0;
		}
		if(col > 0){
			out += " ";
			col++;
		}
		out += w;
		col += wlen;
	}
	return out;
}

# ---- Helpers ----

# Repeat a Unicode codepoint n times
repchar(c: int, n: int): string
{
	s := "";
	for(i := 0; i < n; i++)
		s[len s] = c;
	return s;
}

# Convert to uppercase (ASCII only)
toupper(s: string): string
{
	r := "";
	for(i := 0; i < len s; i++){
		c := s[i];
		if(c >= 'a' && c <= 'z')
			c -= 'a' - 'A';
		r[len r] = c;
	}
	return r;
}

# Pad string to width with spaces on the right
padright(s: string, width: int): string
{
	while(len s < width)
		s += " ";
	return s;
}

# Split text into words (preserving newlines as separate tokens)
splitwords(text: string): list of string
{
	words: list of string;
	i := 0;
	while(i < len text){
		# Skip whitespace (except newlines)
		while(i < len text && (text[i] == ' ' || text[i] == '\t'))
			i++;
		if(i >= len text)
			break;
		if(text[i] == '\n'){
			words = "\n" :: words;
			i++;
			continue;
		}
		# Collect word
		start := i;
		while(i < len text && text[i] != ' ' && text[i] != '\t' && text[i] != '\n')
			i++;
		if(i > start)
			words = text[start:i] :: words;
	}
	# Reverse
	rev: list of string;
	for(; words != nil; words = tl words)
		rev = hd words :: rev;
	return rev;
}

# Split string into lines
splitlines(text: string): array of string
{
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

# Printable length of a string (accounts for multi-byte Unicode being 1 column in monospace)
# This is a simplification: treats each rune as 1 column
printlen(s: string): int
{
	return len s;
}

# List length
listlen(l: list of ref DocNode): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

# Reverse node list
revnodes(l: list of ref DocNode): list of ref DocNode
{
	r: list of ref DocNode;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}
