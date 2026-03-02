implement Formatter;

#
# HTML text formatter - tokenizes HTML and produces typeset plain text
# via the shared tlayout engine.
#
# Uses Inferno's html.m tokenizer for robust HTML parsing, then converts
# the token stream to DocNode tree and calls tlayout->totext().
#
# Supports: headings, paragraphs, bold, italic, inline code, code blocks,
# bullet/numbered lists, blockquotes, horizontal rules, links, tables.
#

include "sys.m";
	sys: Sys;

include "html.m";
	html: HTML;
	Lex, Attr: import html;

include "formatter.m";

include "tlayout.m";
	tlayout: Tlayout;
	DocNode: import tlayout;

PATH: con "/dis/xenith/render/htmlfmt.dis";

init()
{
	sys = load Sys Sys->PATH;
	html = load HTML HTML->PATH;
	tlayout = load Tlayout Tlayout->PATH;
	if(tlayout != nil)
		tlayout->init();
}

info(): ref FormatterInfo
{
	return ref FormatterInfo("HTML", ".html .htm");
}

canformat(data: string, nil: string): int
{
	if(data == nil || len data < 6)
		return 0;
	# Check for <!DOCTYPE or <html
	s := data;
	if(len s > 256)
		s = s[0:256];
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
			return 30;
		}
		break;
	}
	return 0;
}

format(text: string, width: int): string
{
	if(tlayout == nil || html == nil)
		return text;

	data := array of byte text;
	tokens := html->lex(data, HTML->UTF8, 0);
	if(tokens == nil)
		return text;

	doc := html2doc(tokens);
	return tlayout->totext(doc, width);
}

# ---- HTML -> DocNode conversion ----

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
			t := cleantext(tok.text);
			if(len t > 0)
				inlines = ref DocNode(Tlayout->Ntext, t, nil, 0) :: inlines;
			ps.pos++;
			continue;
		}

		case tok.tag {
		# Skip non-content tags entirely
		HTML->Thead or HTML->Tstyle or HTML->Tscript or HTML->Ttitle =>
			skiptag(ps, tok.tag);

		HTML->Th1 or HTML->Th2 or HTML->Th3 or
		HTML->Th4 or HTML->Th5 or HTML->Th6 =>
			if(inlines != nil){
				doc = ref DocNode(Tlayout->Npara, nil, revnodes(inlines), 0) :: doc;
				inlines = nil;
			}
			level := tok.tag - HTML->Th1 + 1;
			(heading, nil) := parseuntilclose(ps, tok.tag);
			doc = ref DocNode(Tlayout->Nheading, nil, heading, level) :: doc;

		HTML->Tp =>
			if(inlines != nil){
				doc = ref DocNode(Tlayout->Npara, nil, revnodes(inlines), 0) :: doc;
				inlines = nil;
			}
			(content, nil) := parseuntilclose(ps, HTML->Tp);
			doc = ref DocNode(Tlayout->Npara, nil, content, 0) :: doc;

		HTML->Tpre =>
			if(inlines != nil){
				doc = ref DocNode(Tlayout->Npara, nil, revnodes(inlines), 0) :: doc;
				inlines = nil;
			}
			(codetext, nil) := collecttext(ps, HTML->Tpre);
			doc = ref DocNode(Tlayout->Ncodeblock, codetext, nil, 0) :: doc;

		HTML->Tblockquote =>
			if(inlines != nil){
				doc = ref DocNode(Tlayout->Npara, nil, revnodes(inlines), 0) :: doc;
				inlines = nil;
			}
			(content, nil) := parseuntilclose(ps, HTML->Tblockquote);
			doc = ref DocNode(Tlayout->Nblockquote, nil, content, 0) :: doc;

		HTML->Tul or HTML->Tol =>
			if(inlines != nil){
				doc = ref DocNode(Tlayout->Npara, nil, revnodes(inlines), 0) :: doc;
				inlines = nil;
			}
			isol := tok.tag == HTML->Tol;
			doc = parselist(ps, isol, doc);

		HTML->Ttable =>
			if(inlines != nil){
				doc = ref DocNode(Tlayout->Npara, nil, revnodes(inlines), 0) :: doc;
				inlines = nil;
			}
			doc = parsetable(ps, doc);

		HTML->Thr =>
			if(inlines != nil){
				doc = ref DocNode(Tlayout->Npara, nil, revnodes(inlines), 0) :: doc;
				inlines = nil;
			}
			doc = ref DocNode(Tlayout->Nhrule, nil, nil, 0) :: doc;
			ps.pos++;

		HTML->Tbr =>
			inlines = ref DocNode(Tlayout->Nnewline, nil, nil, 0) :: inlines;
			ps.pos++;

		HTML->Tb or HTML->Tstrong =>
			(content, nil) := parseuntilclose(ps, tok.tag);
			inlines = ref DocNode(Tlayout->Nbold, nil, content, 0) :: inlines;

		HTML->Ti or HTML->Tem =>
			(content, nil) := parseuntilclose(ps, tok.tag);
			inlines = ref DocNode(Tlayout->Nitalic, nil, content, 0) :: inlines;

		HTML->Tcode or HTML->Ttt =>
			(codetext, nil) := collecttext(ps, tok.tag);
			inlines = ref DocNode(Tlayout->Ncode, codetext, nil, 0) :: inlines;

		HTML->Ta =>
			(content, nil) := parseuntilclose(ps, HTML->Ta);
			inlines = ref DocNode(Tlayout->Nlink, nil, content, 0) :: inlines;

		HTML->Tdiv =>
			if(inlines != nil){
				doc = ref DocNode(Tlayout->Npara, nil, revnodes(inlines), 0) :: doc;
				inlines = nil;
			}
			ps.pos++;

		* =>
			ps.pos++;
		}
	}

	if(inlines != nil)
		doc = ref DocNode(Tlayout->Npara, nil, revnodes(inlines), 0) :: doc;

	return revnodes(doc);
}

# Parse inline content until closing tag
parseuntilclose(ps: ref Pstate, opentag: int): (list of ref DocNode, int)
{
	closetag := opentag + HTML->RBRA;
	ps.pos++;

	nodes: list of ref DocNode;
	while(ps.pos < ps.ntokens){
		tok := ps.tokens[ps.pos];

		if(tok.tag == closetag){
			ps.pos++;
			return (revnodes(nodes), ps.pos);
		}

		if(tok.tag == HTML->Data){
			t := cleantext(tok.text);
			if(len t > 0)
				nodes = ref DocNode(Tlayout->Ntext, t, nil, 0) :: nodes;
			ps.pos++;
			continue;
		}

		case tok.tag {
		HTML->Tb or HTML->Tstrong =>
			(content, nil) := parseuntilclose(ps, tok.tag);
			nodes = ref DocNode(Tlayout->Nbold, nil, content, 0) :: nodes;
		HTML->Ti or HTML->Tem =>
			(content, nil) := parseuntilclose(ps, tok.tag);
			nodes = ref DocNode(Tlayout->Nitalic, nil, content, 0) :: nodes;
		HTML->Tcode or HTML->Ttt =>
			(codetext, nil) := collecttext(ps, tok.tag);
			nodes = ref DocNode(Tlayout->Ncode, codetext, nil, 0) :: nodes;
		HTML->Ta =>
			(content, nil) := parseuntilclose(ps, HTML->Ta);
			nodes = ref DocNode(Tlayout->Nlink, nil, content, 0) :: nodes;
		HTML->Tbr =>
			nodes = ref DocNode(Tlayout->Nnewline, nil, nil, 0) :: nodes;
			ps.pos++;
		* =>
			ps.pos++;
		}
	}
	return (revnodes(nodes), ps.pos);
}

# Collect raw text until closing tag
collecttext(ps: ref Pstate, opentag: int): (string, int)
{
	closetag := opentag + HTML->RBRA;
	ps.pos++;

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
	ps.pos++;

	itemnum := 1;
	while(ps.pos < ps.ntokens){
		tok := ps.tokens[ps.pos];

		if(tok.tag == closetag){
			ps.pos++;
			return doc;
		}

		# Handle nested lists
		if(tok.tag == HTML->Tul){
			doc = parselist(ps, 0, doc);
			continue;
		}
		if(tok.tag == HTML->Tol){
			doc = parselist(ps, 1, doc);
			continue;
		}

		if(tok.tag == HTML->Tli){
			(content, nil) := parseuntilclose(ps, HTML->Tli);
			if(isol){
				doc = ref DocNode(Tlayout->Nnumber, nil, content, itemnum) :: doc;
				itemnum++;
			} else
				doc = ref DocNode(Tlayout->Nbullet, nil, content, 0) :: doc;
			continue;
		}

		ps.pos++;
	}
	return doc;
}

# Parse <table>
parsetable(ps: ref Pstate, doc: list of ref DocNode): list of ref DocNode
{
	closetag := HTML->Ttable + HTML->RBRA;
	ps.pos++;

	rows: list of ref DocNode;
	while(ps.pos < ps.ntokens){
		tok := ps.tokens[ps.pos];

		if(tok.tag == closetag){
			ps.pos++;
			if(rows != nil){
				rows = revnodes(rows);
				doc = ref DocNode(Tlayout->Ntable, nil, rows, 0) :: doc;
			}
			return doc;
		}

		if(tok.tag == HTML->Ttr){
			row := parsetablerow(ps);
			if(row != nil)
				rows = row :: rows;
			continue;
		}

		# Skip thead, tbody, tfoot etc -- we just process tr children
		ps.pos++;
	}

	if(rows != nil){
		rows = revnodes(rows);
		doc = ref DocNode(Tlayout->Ntable, nil, rows, 0) :: doc;
	}
	return doc;
}

# Parse <tr>
parsetablerow(ps: ref Pstate): ref DocNode
{
	closetag := HTML->Ttr + HTML->RBRA;
	ps.pos++;

	cells: list of ref DocNode;
	while(ps.pos < ps.ntokens){
		tok := ps.tokens[ps.pos];

		if(tok.tag == closetag){
			ps.pos++;
			if(cells == nil)
				return nil;
			cells = revnodes(cells);
			return ref DocNode(Tlayout->Ntablerow, nil, cells, 0);
		}

		if(tok.tag == HTML->Ttd || tok.tag == HTML->Tth){
			(content, nil) := parseuntilclose(ps, tok.tag);
			# Flatten content to text for cell
			text := flatnodes(content);
			cells = ref DocNode(Tlayout->Ntext, text, nil, 0) :: cells;
			continue;
		}

		ps.pos++;
	}

	if(cells == nil)
		return nil;
	cells = revnodes(cells);
	return ref DocNode(Tlayout->Ntablerow, nil, cells, 0);
}

# Flatten a list of DocNodes to plain text
flatnodes(nodes: list of ref DocNode): string
{
	s := "";
	for(; nodes != nil; nodes = tl nodes){
		n := hd nodes;
		if(n.text != nil)
			s += n.text;
		if(n.children != nil)
			s += flatnodes(n.children);
	}
	return s;
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

cleantext(s: string): string
{
	if(s == nil)
		return "";
	result := "";
	lastspace := 0;
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

revnodes(l: list of ref DocNode): list of ref DocNode
{
	r: list of ref DocNode;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}
