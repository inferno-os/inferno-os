implement Formatter;

#
# Markdown text formatter - parses Markdown and produces typeset plain text
# via the shared tlayout engine.
#
# Supports: headings, bold, italic, inline code, code blocks, bullet lists,
# numbered lists, horizontal rules, blockquotes, links, and tables.
#

include "sys.m";
	sys: Sys;

include "formatter.m";

include "tlayout.m";
	tlayout: Tlayout;
	DocNode: import tlayout;

PATH: con "/dis/xenith/render/mdfmt.dis";

init()
{
	sys = load Sys Sys->PATH;
	tlayout = load Tlayout Tlayout->PATH;
	if(tlayout != nil)
		tlayout->init();
}

info(): ref FormatterInfo
{
	return ref FormatterInfo("Markdown", ".md .markdown");
}

canformat(nil: string, nil: string): int
{
	# Rely on extension matching; no magic bytes for markdown
	return 0;
}

format(text: string, width: int): string
{
	if(tlayout == nil)
		return text;

	doc := parsemd(text);
	return tlayout->totext(doc, width);
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
			doc = ref DocNode(Tlayout->Nhrule, nil, nil, 0) :: doc;
			i++;
			continue;
		}

		# Table (| col | col |)
		if(istableline(line)){
			(tbl, ni) := parsetable(lines, i, nlines);
			if(tbl != nil){
				doc = tbl :: doc;
				i = ni;
				continue;
			}
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

		# Default: paragraph
		(para, ni) := parsepara(lines, i, nlines);
		doc = para :: doc;
		i = ni;
	}

	return reversedocs(doc);
}

# Parse a heading line
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
	return (ref DocNode(Tlayout->Nheading, nil, children, level), 0);
}

# Parse a fenced code block
parsecodeblock(lines: array of string, start: int): (ref DocNode, int)
{
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

	return (ref DocNode(Tlayout->Ncodeblock, code, nil, 0), i);
}

# Parse a blockquote
parseblockquote(lines: array of string, start, nlines: int): (ref DocNode, int)
{
	text := "";
	i := start;
	while(i < nlines){
		line := lines[i];
		if(len line == 0 || line[0] != '>')
			break;
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
	return (ref DocNode(Tlayout->Nblockquote, nil, children, 0), i);
}

# Parse a bullet list item
parsebullet(lines: array of string, start, nlines: int): (ref DocNode, int)
{
	text := lines[start][2:];
	i := start + 1;
	while(i < nlines && len lines[i] > 0 && (lines[i][0] == ' ' || lines[i][0] == '\t')){
		text += " " + stripws(lines[i]);
		i++;
	}

	children := parseinline(text);
	return (ref DocNode(Tlayout->Nbullet, nil, children, 0), i);
}

# Parse a numbered list item
parsenumber(lines: array of string, start, nlines: int): (ref DocNode, int)
{
	line := lines[start];
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
	return (ref DocNode(Tlayout->Nnumber, nil, children, num), j);
}

# Parse a paragraph
parsepara(lines: array of string, start, nlines: int): (ref DocNode, int)
{
	text := "";
	i := start;
	while(i < nlines){
		line := lines[i];
		if(isblank(line))
			break;
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
			if(istableline(line))
				break;
		}
		if(len text > 0)
			text += " ";
		text += line;
		i++;
	}

	children := parseinline(text);
	return (ref DocNode(Tlayout->Npara, nil, children, 0), i);
}

# Detect table line: starts with |
istableline(line: string): int
{
	if(len line < 3)
		return 0;
	# Skip leading whitespace
	i := 0;
	while(i < len line && (line[i] == ' ' || line[i] == '\t'))
		i++;
	if(i < len line && line[i] == '|')
		return 1;
	return 0;
}

# Check if line is a table separator (|---|---|)
istablesep(line: string): int
{
	if(!istableline(line))
		return 0;
	hasdash := 0;
	for(i := 0; i < len line; i++){
		c := line[i];
		if(c == '-' || c == ':')
			hasdash = 1;
		else if(c != '|' && c != ' ' && c != '\t')
			return 0;
	}
	return hasdash;
}

# Parse a table
parsetable(lines: array of string, start, nlines: int): (ref DocNode, int)
{
	rows: list of ref DocNode;
	i := start;

	while(i < nlines && istableline(lines[i])){
		# Skip separator lines
		if(istablesep(lines[i])){
			i++;
			continue;
		}
		row := parsetablerow(lines[i]);
		if(row != nil)
			rows = row :: rows;
		i++;
	}

	if(rows == nil)
		return (nil, start);

	# Reverse to restore order
	rows = revnodes(rows);
	return (ref DocNode(Tlayout->Ntable, nil, rows, 0), i);
}

# Parse a single table row: | cell | cell | cell |
parsetablerow(line: string): ref DocNode
{
	cells: list of ref DocNode;
	i := 0;

	# Skip leading whitespace
	while(i < len line && (line[i] == ' ' || line[i] == '\t'))
		i++;
	# Skip leading |
	if(i < len line && line[i] == '|')
		i++;

	while(i < len line){
		# Collect cell text until next |
		start := i;
		while(i < len line && line[i] != '|')
			i++;
		cell := "";
		if(i > start)
			cell = trim(line[start:i]);
		# Only add non-trailing-empty cells
		if(i < len line || len cell > 0){
			cellchildren := parseinline(cell);
			cells = ref DocNode(Tlayout->Npara, nil, cellchildren, 0) :: cells;
		}
		if(i < len line)
			i++;  # skip |
	}

	if(cells == nil)
		return nil;

	# Reverse
	cells = revnodes(cells);
	return ref DocNode(Tlayout->Ntablerow, nil, cells, 0);
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
				nodes = ref DocNode(Tlayout->Ntext, plain, nil, 0) :: nodes;
				plain = "";
			}
			end := findclose(text, i+2, "**");
			if(end > 0){
				inner := text[i+2:end];
				nodes = ref DocNode(Tlayout->Nbold, nil, ref DocNode(Tlayout->Ntext, inner, nil, 0) :: nil, 0) :: nodes;
				i = end + 2;
				continue;
			}
		}

		# Italic: *text*
		if(c == '*' && !(i+1 < len text && text[i+1] == '*')){
			if(len plain > 0){
				nodes = ref DocNode(Tlayout->Ntext, plain, nil, 0) :: nodes;
				plain = "";
			}
			end := findclose(text, i+1, "*");
			if(end > 0){
				inner := text[i+1:end];
				nodes = ref DocNode(Tlayout->Nitalic, nil, ref DocNode(Tlayout->Ntext, inner, nil, 0) :: nil, 0) :: nodes;
				i = end + 1;
				continue;
			}
		}

		# Inline code: `text`
		if(c == '`'){
			if(len plain > 0){
				nodes = ref DocNode(Tlayout->Ntext, plain, nil, 0) :: nodes;
				plain = "";
			}
			end := findclose(text, i+1, "`");
			if(end > 0){
				inner := text[i+1:end];
				nodes = ref DocNode(Tlayout->Ncode, inner, nil, 0) :: nodes;
				i = end + 1;
				continue;
			}
		}

		# Link: [text](url)
		if(c == '['){
			if(len plain > 0){
				nodes = ref DocNode(Tlayout->Ntext, plain, nil, 0) :: nodes;
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
		nodes = ref DocNode(Tlayout->Ntext, plain, nil, 0) :: nodes;

	return reversenodes(nodes);
}

# Find closing delimiter
findclose(text: string, start: int, delim: string): int
{
	dlen := len delim;
	for(i := start; i <= len text - dlen; i++)
		if(text[i:i+dlen] == delim)
			return i;
	return -1;
}

# Parse a [text](url) link
parselink(text: string, start: int): (ref DocNode, int)
{
	i := start + 1;
	while(i < len text && text[i] != ']')
		i++;
	if(i >= len text)
		return (nil, start + 1);

	linktext := text[start+1:i];
	i++;

	if(i >= len text || text[i] != '(')
		return (nil, start + 1);
	i++;

	j := i;
	while(j < len text && text[j] != ')')
		j++;
	if(j >= len text)
		return (nil, start + 1);
	j++;

	children := ref DocNode(Tlayout->Ntext, linktext, nil, 0) :: nil;
	return (ref DocNode(Tlayout->Nlink, nil, children, 0), j);
}

# ---- Helpers ----

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

trim(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t'))
		j--;
	if(j <= i)
		return "";
	return s[i:j];
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

revnodes(l: list of ref DocNode): list of ref DocNode
{
	return reversedocs(l);
}
