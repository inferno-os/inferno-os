implement Cook;

include "sys.m";
	sys: Sys;
	FD: import Sys;

include "draw.m";
	draw: Draw;

include "bufio.m";
	B: Bufio;
	Iobuf: import B;

include "string.m";
	S: String;
	splitl, splitr, splitstrl, drop, take, in, prefix, tolower : import S;

include "brutus.m";
	Size6, Size8, Size10, Size12, Size16, NSIZE,
	Roman, Italic, Bold, Type, NFONT, NFONTTAG,
	Example, Caption, List, Listelem, Label, Labelref,
	Exercise, Heading, Nofill, Author, Title,
	Index, Indextopic,
	DefFont, DefSize, TitleFont, TitleSize, HeadingFont, HeadingSize: import Brutus;

# following are needed for types in brutusext.m
include "tk.m";
	tk: Tk;
include "tkclient.m";

include "brutusext.m";
	SGML, Text, Par, Extension, Float, Special, Celem,
	FLatex, FLatexProc, FLatexBook, FLatexPart, FLatexSlides, FHtml: import Brutusext;

include "strinttab.m";
	T: StringIntTab;

Cook: module
{
	init:	fn(ctxt: ref Draw->Context, args: list of string);
};

# keep this sorted by name
tagstringtab := array[] of { T->StringInt
	("Author", Author),
	("Bold.10", Bold*NSIZE + Size10),
	("Bold.12", Bold*NSIZE + Size12),
	("Bold.16", Bold*NSIZE + Size16),
	("Bold.6", Bold*NSIZE + Size6),
	("Bold.8", Bold*NSIZE + Size8),
	("Caption", Caption),
	("Example", Example),
	("Exercise", Exercise),
	("Extension", Extension),
	("Float", Float),
	("Heading", Heading),
	("Index", Index),
	("Index-topic", Indextopic),
	("Italic.10", Italic*NSIZE + Size10),
	("Italic.12", Italic*NSIZE + Size12),
	("Italic.16", Italic*NSIZE + Size16),
	("Italic.6", Italic*NSIZE + Size6),
	("Italic.8", Italic*NSIZE + Size8),
	("Label", Label),
	("Label-ref", Labelref),
	("List", List),
	("List-elem", Listelem),
	("No-fill", Nofill),
	("Par", Par),
	("Roman.10", Roman*NSIZE + Size10),
	("Roman.12", Roman*NSIZE + Size12),
	("Roman.16", Roman*NSIZE + Size16),
	("Roman.6", Roman*NSIZE + Size6),
	("Roman.8", Roman*NSIZE + Size8),
	("SGML", SGML),
	("Title", Title),
	("Type.10", Type*NSIZE + Size10),
	("Type.12", Type*NSIZE + Size12),
	("Type.16", Type*NSIZE + Size16),
	("Type.6", Type*NSIZE + Size6),
	("Type.8", Type*NSIZE + Size8),
};

# This table must be sorted
fmtstringtab := array[] of { T->StringInt
	("html", FHtml),
	("latex", FLatex),
	("latexbook", FLatexBook),
	("latexpart", FLatexPart),
	("latexproc", FLatexProc),
	("latexslides", FLatexSlides),
};

Transtab: adt
{
	ch:		int;
	trans:	string;
};

# Order doesn't matter for these table

ltranstab := array[] of { Transtab
	('$', "\\textdollar{}"),
	('&', "\\&"),
	('%', "\\%"),
	('#', "\\#"),
	('_', "\\textunderscore{}"),
	('{', "\\{"),
	('}', "\\}"),
	('~', "\\textasciitilde{}"),
	('^', "\\textasciicircum{}"),
	('\\', "\\textbackslash{}"),
	('+', "\\textplus{}"),
	('=', "\\textequals{}"),
	('|', "\\textbar{}"),
	('<', "\\textless{}"),
	('>', "\\textgreater{}"),
	(' ', "~"),
	('-', "-"),  # needs special case ligature treatment
	('\t', " "),   # needs special case treatment
};

htranstab := array[] of { Transtab
	('α', "&alpha;"),
	('Æ', "&AElig;"),
	('Á', "&Aacute;"),
	('Â', "&Acirc;"),
	('À', "&Agrave;"),
	('Å', "&Aring;"),
	('Ã', "&Atilde;"),
	('Ä', "&Auml;"),
	('Ç', "&Ccedil;"),
	('Ð', "&ETH;"),
	('É', "&Eacute;"),
	('Ê', "&Ecirc;"),
	('È', "&Egrave;"),
	('Ë', "&Euml;"),
	('Í', "&Iacute;"),
	('Î', "&Icirc;"),
	('Ì', "&Igrave;"),
	('Ï', "&Iuml;"),
	('Ñ', "&Ntilde;"),
	('Ó', "&Oacute;"),
	('Ô', "&Ocirc;"),
	('Ò', "&Ograve;"),
	('Ø', "&Oslash;"),
	('Õ', "&Otilde;"),
	('Ö', "&Ouml;"),
	('Þ', "&THORN;"),
	('Ú', "&Uacute;"),
	('Û', "&Ucirc;"),
	('Ù', "&Ugrave;"),
	('Ü', "&Uuml;"),
	('Ý', "&Yacute;"),
	('æ', "&aElig;"),
	('á', "&aacute;"),
	('â', "&acirc;"),
	('à', "&agrave;"),
	('α', "&alpha;"),
	('&', "&amp;"),
	('å', "&aring;"),
	('ã', "&atilde;"),
	('ä', "&auml;"),
	('β', "&beta;"),
	('ç', "&ccedil;"),
	('⋯', "&cdots;"),
	('χ', "&chi;"),
	('©', "&copy;"),
	('⋱', "&ddots;"),
	('δ', "&delta;"),
	('é', "&eacute;"),
	('ê', "&ecirc;"),
	('è', "&egrave;"),
	('—', "&emdash;"),
	(' ', "&emsp;"),
	('–', "&endash;"),
	('ε', "&epsilon;"),
	('η', "&eta;"),
	('ð', "&eth;"),
	('ë', "&euml;"),
	('γ', "&gamma;"),
	('>', "&gt;"),
	('í', "&iacute;"),
	('î', "&icirc;"),
	('ì', "&igrave;"),
	('ι', "&iota;"),
	('ï', "&iuml;"),
	('κ', "&kappa;"),
	('λ', "&lambda;"),
	('…', "&ldots;"),
	('<', "&lt;"),
	('μ', "&mu;"),
	(' ', "&nbsp;"),
	('ñ', "&ntilde;"),
	('ν', "&nu;"),
	('ó', "&oacute;"),
	('ô', "&ocirc;"),
	('ò', "&ograve;"),
	('ω', "&omega;"),
	('ο', "&omicron;"),
	('ø', "&oslash;"),
	('õ', "&otilde;"),
	('ö', "&ouml;"),
	('φ', "&phi;"),
	('π', "&pi;"),
	('ψ', "&psi;"),
	(' ', "&quad;"),
	('"', "&quot;"),
	('®', "&reg;"),
	('ρ', "&rho;"),
	('­', "&shy;"),
	('σ', "&sigma;"),
	('ß', "&szlig;"),
	('τ', "&tau;"),
	('θ', "&theta;"),
	(' ', "&thinsp;"),
	('þ', "&thorn;"),
	('™', "&trade;"),
	('ú', "&uacute;"),
	('û', "&ucirc;"),
	('ù', "&ugrave;"),
	('υ', "&upsilon;"),
	('ü', "&uuml;"),
	('∈', "&varepsilon;"),
	('ϕ', "&varphi;"),
	('ϖ', "&varpi;"),
	('ϱ', "&varrho;"),
	('⋮', "&vdots;"),
	('ς', "&vsigma;"),
	('ϑ', "&vtheta;"),
	('ξ', "&xi;"),
	('ý', "&yacute;"),
	('ÿ', "&yuml;"),
	('ζ', "&zeta;"),
	('−', "-"),
};

# For speedy lookups of ascii char translation, use asciitrans.
# It should be initialized by ascii elements from one of above tables
asciitrans := array[128] of string;

stderr: ref FD;
infilename := "";
outfilename := "";
linenum := 0;
fin : ref Iobuf = nil;
fout : ref Iobuf = nil;
debug := 0;
fmt := FLatex;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	S = load String String->PATH;
	B = load Bufio Bufio->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	T = load StringIntTab StringIntTab->PATH;
	stderr = sys->fildes(2);

	for(argv = tl argv; argv != nil; ) {
		s := hd argv;
		tlargv := tl argv;
		case s {
		"-f" =>
			if(tlargv == nil)
				usage();
			fnd: int;
			(fnd, fmt) = T->lookup(fmtstringtab, hd(tlargv));
			if(!fnd) {
				sys->fprint(stderr, "unknown format: %s\n", hd(tlargv));
				exit;
			}
			argv = tlargv;
		"-o" =>
			if(tlargv == nil)
				usage();
			outfilename = hd(tlargv);
			argv = tlargv;
		"-d" =>
			debug = 1;
		"-dd" =>
			debug = 2;
		* =>
			if(tlargv == nil)
				infilename = s;
			else
				usage();
		}
		argv = tl argv;
	}
	if(infilename == "") {
		fin = B->fopen(sys->fildes(0), sys->OREAD);
		infilename = "<stdin>";
	}
	else
		fin = B->open(infilename, sys->OREAD);
	if(fin == nil) {
		sys->fprint(stderr, "cook: error opening %s: %r\n", infilename);
		exit;
	}
	if(outfilename == "") {
		fout = B->fopen(sys->fildes(1), sys->OWRITE);
		outfilename = "<stdout>";
	}
	else
		fout = B->create(outfilename, sys->OWRITE, 8r664);
	if(fout == nil) {
		sys->fprint(stderr, "cook: error creating %s: %r\n", outfilename);
		exit;
	}
	line0 := fin.gets('\n');
	if(line0 != "<SGML>\n") {
		parse_err("not an SGML file\n");
		exit;
	}
	linenum = 1;
	e := parse(SGML);
	findpars(e, 1, nil);
	e = delemptystrs(e);
	(e, nil) = canonfonts(e, DefFont*NSIZE+DefSize, DefFont*NSIZE+DefSize);
	mergeadjs(e);
	findfloats(e);
	cleanexts(e);
	cleanpars(e);
	if(debug) {
		fout.puts("After Initial transformations:\n");
		printelem(e, "", 1);
		fout.flush();
	}
	case fmt {
	FLatex or FLatexProc or FLatexBook or FLatexPart or FLatexSlides =>
		latexconv(e);
	FHtml =>
		htmlconv(e);
	}
	fin.close();
	fout.close();
}

usage()
{
	sys->fprint(stderr, "Usage: cook [-f (latex|html)] [-o outfile] [infile]\n");
	exit;
}

parse_err(msg: string)
{
	sys->fprint(stderr, "%s:%d: %s\n", infilename, linenum, msg);
}

# Parse into elements.
# Assumes tags are balanced.
# String elements are split so that there is never an internal newline.
parse(id: int) : ref Celem
{
	els : ref Celem = nil;
	elstail : ref Celem = nil;
	for(;;) {
		c := fin.getc();
		if(c == Bufio->EOF) {
			if(id == SGML)
				break;
			else {
				parse_err(sys->sprint("EOF while parsing %s", tagname(id)));
				return nil;
			}
		}
		if(c == '<') {
			tag := "";
			start := 1;
			i := 0;
			for(;;) {
				c = fin.getc();
				if(c == Bufio->EOF) {
					parse_err("EOF in middle of tag");
					return nil;
				}
				if(c == '\n') {
					linenum++;
					parse_err("newline in middle of tag");
					break;
				}
				if(c == '>')
					break;
				if(i == 0 && c == '/')
					start = 0;
				else
					tag[i++] = c;
			}
			(fnd, tid) := T->lookup(tagstringtab, tag);
			if(!fnd) {
				if(prefix("Extension ", tag)) {
					el := ref Celem(Extension, tag[10:], nil, nil, nil, nil);
					if(els == nil) {
						els = el;
						elstail = el;
					}
					else {
						el.prev = elstail;
						elstail.next = el;
						elstail = el;
					}
				}
				else
					parse_err(sys->sprint("unknown tag <%s>\n", tag));
				continue;
			}
			if(start) {
				el := parse(tid);
				if(el == nil)
					return nil;
				if(els == nil) {
					els = el;
					elstail = el;
				}
				else {
					el.prev = elstail;
					elstail.next = el;
					elstail = el;
				}
			}
			else {
				if(tid != id) {
					parse_err(sys->sprint("<%s> ended by </%s>",
						tagname(id), tag));
					continue;
				}
				break;
			}
		}
		else {
			s := "";
			i := 0;
			for(;;) {
				if(c == Bufio->EOF)
					break;
				if(c == '<') {
					fin.ungetc();
					break;
				}
				if(c == ';' && i >=3 && s[i-1] == 't' && s[i-2] == 'l' && s[i-3] == '&') {
					i -= 2;
					s[i-1] = '<';
					s = s[0:i];
				}
				else
					s[i++] = c;
				if(c == '\n') {
					linenum++;
					break;
				}
				else
					c = fin.getc();
			}
			if(s != "") {
				el := ref Celem(Text, s, nil, nil, nil, nil);
				if(els == nil) {
					els = el;
					elstail = el;
				}
				else {
					el.prev = elstail;
					elstail.next = el;
					elstail = el;
				}
			}
		}
	}
	ans := ref Celem(id, "", els, nil, nil, nil);
	if(els != nil)
		els.parent = ans;
	return ans;
}

# Modify tree e so that blank lines become Par elements.
# Only do it if parize is set, and unset parize when descending into TExample's.
# Pass in most recent TString or TPar element, and return updated most-recent-TString/TPar.
# This function may set some TString strings to ""
findpars(e: ref Celem, parize: int, prevspe: ref Celem) : ref Celem
{
	while(e != nil) {
		prevnl := 0;
		prevpar := 0;
		if(prevspe != nil) {
			if(prevspe.tag == Text && len prevspe.s != 0
			   && prevspe.s[(len prevspe.s)-1] == '\n')
				prevnl = 1;
			else if(prevspe.tag == Par)
				prevpar = 1;
		}
		if(e.tag == Text) {
			if(parize && (prevnl || prevpar) && e.s[0] == '\n') {
				if(prevnl)
					prevspe.s = prevspe.s[0 : (len prevspe.s)-1];
				e.tag = Par;
				e.s = nil;
			}
			prevspe = e;
		}
		else {
			nparize := parize;
			if(e.tag == Example)
				nparize = 0;
			prevspe = findpars(e.contents, nparize, prevspe);
		}
		e = e.next;
	}
	return prevspe;
}

# Delete any empty strings from e's tree and return modified e.
# Also, delete any entity that has empty contents, except the
# Par ones
delemptystrs(e: ref Celem) : ref Celem
{
	if(e.tag == Text) {
		if(e.s == "")
			return nil;
		else
			return e;
	}
	if(e.tag == Par || e.tag == Extension || e.tag == Special)
		return e;
	h := e.contents;
	while(h != nil) {
		hnext := h.next;
		hh := delemptystrs(h);
		if(hh == nil)
			delete(h);
		h = hnext;
	}
	if(e.contents == nil)
		return nil;
	return e;
}

# Change tree under e so that any font elems contain only strings
# (by pushing the font changes down).
# Answer an be a list, so return beginning and end of list.
# Leave strings bare if font change would be to deffont,
# and adjust deffont appropriately when entering Title and
# Heading environments.
canonfonts(e: ref Celem, curfont, deffont: int) : (ref Celem, ref Celem)
{
	f := curfont;
	head : ref Celem = nil;
	tail : ref Celem = nil;
	tocombine : ref Celem = nil;
	if(e.tag == Text) {
		if(f == deffont) {
			head = e;
			tail = e;
		}
		else {
			head = ref Celem(f, nil, e, nil, nil, nil);
			e.parent = head;
			tail = head;
		}
	}
	else if(e.contents == nil) {
		head = e;
		tail = e;
	}
	else if(e.tag < NFONTTAG) {
		f = e.tag;
		allstrings := 1;
		for(g := e.contents; g != nil; g = g.next) {
			if(g.tag != Text)
				allstrings = 0;
			tail = g;
		}
		if(allstrings) {
			if(f == deffont)
				head = e.contents;
			else {
				head = e;
				tail = e;
			}
		}
	}
	if(head == nil) {
		if(e.tag == Title)
			deffont = TitleFont*NSIZE+TitleSize;
		else if(e.tag == Heading)
			deffont = HeadingFont*NSIZE+HeadingSize;
		for(h := e.contents; h != nil; ) {
			prev := h.prev;
			next := h.next;
			excise(h);
			(e1, en) := canonfonts(h, f, deffont);
			splicebetween(e1, en, prev, next);
			if(prev == nil)
				head = e1;
			tail = en;
			h = next;
		}
		tocombine = head;
		if(e.tag >= NFONTTAG) {
			e.contents = head;
			head.parent = e;
			head = e;
			tail = e;
		}
	}
	if(tocombine != nil) {
		# combine adjacent font changes to same font
		r := tocombine;
		while(r != nil) {
			if(r.tag < NFONTTAG && r.next != nil && r.next.tag == r.tag) {
				for(v := r.next; v != nil; v = v.next) {
					if(v.tag != r.tag)
						break;
					if(v == tail)
						tail = r;
				}
				# now r up to, not including v, all change to same font
				for(p := r.next; p != v; p = p.next) {
					append(r.contents, p.contents);
				}
				r.next = v;
				if(v != nil)
					v.prev = r;
				r = v;
			}
			else
				r = r.next;
		}
	}
	head.parent = nil;
	return (head, tail);
}

# Remove Pars that appear just before or just after Heading, Title, Examples, Extensions
# Really should worry about this happening at different nesting levels, but in
# practice this happens all at the same nesting level
cleanpars(e: ref Celem)
{
	for(h := e.contents; h != nil; h = h.next) {
		cleanpars(h);
		if(h.tag == Title || h.tag == Heading || h.tag == Example || h.tag == Extension) {
			hp := h.prev;
			hn := h.next;
			if(hp !=nil && hp.tag == Par)
				delete(hp);
			if(hn != nil && hn.tag == Par)
				delete(hn);
		}
	}
}

# Remove a single tab if it appears before an Extension
cleanexts(e: ref Celem)
{
	for(h := e.contents; h != nil; h = h.next) {
		cleanexts(h);
		if(h.tag == Extension) {
			hp := h.prev;
			if(hp != nil && stringof(hp) == "\t")
				delete(hp);
		}
	}
}

mergeable := array[] of { List, Exercise, Caption,Index, Indextopic };

# Merge some adjacent elements (which were probably created separate
# because of font changes)
mergeadjs(e: ref Celem)
{
	for(h := e.contents; h != nil; h = h.next) {
		hn := h.next;
		domerge := 0;
		if(hn != nil) {
			for(i := 0; i < len mergeable; i++) {
				mi := mergeable[i];
				if(h.tag == mi && hn.tag == mi)
					domerge = 1;
			}
		}
		if(domerge) {
			append(h.contents, hn.contents);
			delete(hn);
		}
		else
			mergeadjs(h);
	}
}

# Find floats: they are paragraphs with Captions at the end.
findfloats(e: ref Celem)
{
	lastpar : ref Celem = nil;
	for(h := e.contents; h != nil; h = h.next) {
		if(h.tag == Par)
			lastpar = h;
		else if(h.tag == Caption) {
			ne := ref Celem(Float, "", nil, nil, nil, nil);
			if(lastpar == nil)
				flhead := e.contents;
			else
				flhead = lastpar.next;
			insertbefore(ne, flhead);
			# now move flhead ... h into contents of ne
			ne.contents = flhead;
			flhead.parent = ne;
			flhead.prev = nil;
			ne.next = h.next;
			if(ne.next != nil)
				ne.next.prev = ne;
			h.next = nil;
			h = ne;
		}
		else
			findfloats(h);
	}
}

insertbefore(e, ebefore: ref Celem)
{
	e.prev = ebefore.prev;
	if(e.prev == nil) {
		e.parent = ebefore.parent;
		ebefore.parent = nil;
		e.parent.contents = e;
	}
	else
		e.prev.next = e;
	e.next = ebefore;
	ebefore.prev = e;
}

insertafter(e, eafter: ref Celem)
{
	e.next = eafter.next;
	if(e.next != nil)
		e.next.prev = e;
	e.prev = eafter;
	eafter.next = e;
}

# remove e from its list, leaving siblings disconnected
excise(e: ref Celem)
{
	next := e. next;
	prev := e.prev;
	e.next = nil;
	e.prev = nil;
	if(prev != nil)
		prev.next = nil;
	if(next != nil)
		next.prev = nil;
	e.parent = nil;
}

splicebetween(e1, en, prev, next: ref Celem)
{
	if(prev != nil)
		prev.next = e1;
	e1.prev = prev;
	en.next = next;
	if(next != nil)
		next.prev = en;
}

append(e1, e2: ref Celem)
{
	e1last := last(e1);
	e1last.next = e2;
	e2.prev = e1last;
	e2.parent = nil;
}

last(e: ref Celem) : ref Celem
{
	if(e != nil)
		while(e.next != nil)
			e = e.next;
	return e;
}

succ(e: ref Celem) : ref Celem
{
	if(e == nil)
		return nil;
	if(e.next != nil)
		return e.next;
	return succ(e.parent);
}

delete(e: ref Celem)
{
	ep := e.prev;
	en := e.next;
	eu := e.parent;
	if(ep == nil) {
		if(eu != nil)
			eu.contents = en;
		if(en != nil)
			en.parent = eu;
	}
	else
		ep.next = en;
	if(en != nil)
		en.prev = ep;
}

# return string represented by e, peering through font changes
stringof(e: ref Celem) : string
{
	if(e != nil) {
		if(e.tag == Text)
			return e.s;
		if(e.tag < NFONTTAG)
			return stringof(e.contents);
	}
	return "";
}

# remove any initial whitespace from e and its sucessors,
dropwhite(e: ref Celem)
{
	if(e == nil)
		return;
	del := 0;
	if(e.tag == Text) {
		e.s = drop(e.s, " \t\n");
		if(e.s == "")
			del = 1;;
	}
	else if(e.tag < NFONTTAG) {
		dropwhite(e.contents);
		if(e.contents == nil)
			del = 1;
	}
	if(del) {
		enext := e.next;
		delete(e);
		dropwhite(enext);
	}

}

firstchar(e: ref Celem) : int
{
	s := stringof(e);
	if(len s >= 1)
		return s[0];
	return -1;
}

lastchar(e: ref Celem) : int
{
	if(e == nil)
		return -1;
	while(e.next != nil)
		e = e.next;
	s := stringof(e);
	if(len s >= 1)
		return s[len s -1];
	return -1;
}

tlookup(t: array of Transtab, v: int) : string
{
	n := len t;
	for(i := 0; i < n; i++)
		if(t[i].ch == v)
			return t[i].trans;
	return "";
}

initasciitrans(t: array of Transtab)
{
	n := len t;
	for(i := 0; i < n; i++) {
		c := t[i].ch;
		if(c < 128)
			asciitrans[c] = t[i].trans;
	}
}

tagname(id: int) : string
{
	name := T->revlookup(tagstringtab, id);
	if(name == nil)
		name = "_unknown_";
	return name;
}

printelem(e: ref Celem, indent: string, recurse: int)
{
	fout.puts(indent);
	if(debug > 1) {
		fout.puts(sys->sprint("%x: ", e));
		if(e != nil && e.parent != nil)
			fout.puts(sys->sprint("(parent %x): ", e.parent));
	}
	if(e == nil)
		fout.puts("NIL\n");
	else if(e.tag == Text || e.tag == Special || e.tag == Extension) {
		if(e.tag == Special)
			fout.puts("S");
		else if(e.tag == Extension)
			fout.puts("E");
		fout.puts("«");
		fout.puts(e.s);
		fout.puts("»\n");
	}
	else {
		name := tagname(e.tag);
		fout.puts("<" + name + ">\n");
		if(recurse && e.contents != nil)
			printelems(e.contents, indent + "    ", recurse);
	}
}

printelems(els: ref Celem, indent: string, recurse: int)
{
	for(; els != nil; els = els.next)
		printelem(els, indent, recurse);
}

check(e: ref Celem, msg: string)
{
	err := checke(e);
	if(err != "") {
		fout.puts(msg + ": tree is inconsistent:\n" + err);
		printelem(e, "", 1);
		fout.flush();
		exit;
	}
}

checke(e: ref Celem) : string
{
	err := "";
	if(e.tag == SGML && e.next != nil)
		err = sys->sprint("root %x has a next field\n", e);
	ec := e.contents;
	if(ec != nil) {
		if(ec.parent != e)
			err += sys->sprint("node %x contents %x has bad parent %x\n", e, ec, e.parent);
		if(ec.prev != nil)
			err += sys->sprint("node %x contents %x has non-nil prev %x\n", e, ec, e.prev);
		p := ec;
		for(h := ec.next; h != nil; h = h.next) {
			if(h.prev != p)
				err += sys->sprint("node %x comes after %x, but prev is %x\n", h, p, h.prev);
			if(h.parent != nil)
				err += sys->sprint("node %x, not first in siblings, has parent %x\n", h, h.parent);
			p = h;
		}
		for(h = ec; h != nil; h = h.next) {
			err2 := checke(h);
			if(err2 != nil)
				err += err2;
		}
	}
	return err;
}

# Translation to Latex

# state bits
SLT, SLB, SLI, SLS6, SLS8, SLS12, SLS16, SLE, SLO, SLF : con (1<<iota);

SLFONTMASK : con SLT|SLB|SLI|SLS6|SLS8|SLS12|SLS16;
SLSIZEMASK : con SLS6|SLS8|SLS12|SLS16;

# fonttag-to-state-bit table
lftagtostate := array[NFONTTAG] of {
	Roman*NSIZE+Size6 => SLS6,
	Roman*NSIZE+Size8 => SLS8,
	Roman*NSIZE+Size10 => 0,
	Roman*NSIZE+Size12 => SLS12,
	Roman*NSIZE+Size16 => SLS16,
	Italic*NSIZE+Size6 => SLI | SLS6,
	Italic*NSIZE+Size8 => SLI | SLS8,
	Italic*NSIZE+Size10 => SLI,
	Italic*NSIZE+Size12 => SLI | SLS12,
	Italic*NSIZE+Size16 => SLI | SLS16,
	Bold*NSIZE+Size6 => SLB | SLS6,
	Bold*NSIZE+Size8 => SLB | SLS8,
	Bold*NSIZE+Size10 => SLB,
	Bold*NSIZE+Size12 => SLB | SLS12,
	Bold*NSIZE+Size16 => SLB | SLS16,
	Type*NSIZE+Size6 => SLT | SLS6,
	Type*NSIZE+Size8 => SLT | SLS8,
	Type*NSIZE+Size10 => SLT,
	Type*NSIZE+Size12 => SLT | SLS12,
	Type*NSIZE+Size16 => SLT | SLS16
};

lsizecmd := array[] of { "\\footnotesize", "\\small", "\\normalsize", "\\large", "\\Large"};
llinepos : int;
lslidenum : int;
LTABSIZE : con 4;

latexconv(e: ref Celem)
{
	initasciitrans(ltranstab);

	case fmt {
	FLatex or FLatexProc =>
		if(fmt == FLatex) {
			fout.puts("\\documentclass{article}\n");
			fout.puts("\\def\\encodingdefault{T1}\n");
		}
		else {
			fout.puts("\\documentclass[10pt,twocolumn]{article}\n");
			fout.puts("\\def\\encodingdefault{T1}\n");
			fout.puts("\\usepackage{latex8}\n");
			fout.puts("\\bibliographystyle{latex8}\n");
		}
		fout.puts("\\usepackage{times}\n");
		fout.puts("\\usepackage{brutus}\n");
		fout.puts("\\usepackage{unicode}\n");
		fout.puts("\\usepackage{epsf}\n");
		title := lfindtitle(e);
		authors := lfindauthors(e);
		abstract := lfindabstract(e);
		fout.puts("\\begin{document}\n");
		if(title != nil) {
			fout.puts("\\title{");
			llinepos = 0;
			lconvl(title, 0);
			fout.puts("}\n");
			if(authors != nil) {
				fout.puts("\\author{");
				for(l := authors; l != nil; l = tl l) {
					llinepos = 0;
					lconvl(hd l, SLO|SLI);
					if(tl l != nil)
						fout.puts("\n\\and\n");
				}
				fout.puts("}\n");
			}
			fout.puts("\\maketitle\n");
		}
		fout.puts("\\pagestyle{empty}\\thispagestyle{empty}\n");
		if(abstract != nil) {
			if(fmt == FLatexProc) {
				fout.puts("\\begin{abstract}\n");
				llinepos = 0;
				lconvl(abstract, 0);
				fout.puts("\\end{abstract}\n");
			}
			else {
				fout.puts("\\section*{Abstract}\n");
				llinepos = 0;
				lconvl(abstract, 0);
			}
		}
	FLatexBook =>
		fout.puts("\\documentclass{ibook}\n");
		fout.puts("\\usepackage{brutus}\n");
		fout.puts("\\usepackage{epsf}\n");
		fout.puts("\\begin{document}\n");
	FLatexSlides =>
		fout.puts("\\documentclass[portrait]{seminar}\n");
		fout.puts("\\def\\encodingdefault{T1}\n");
		fout.puts("\\usepackage{times}\n");
		fout.puts("\\usepackage{brutus}\n");
		fout.puts("\\usepackage{unicode}\n");
		fout.puts("\\usepackage{epsf}\n");
		fout.puts("\\centerslidesfalse\n");
		fout.puts("\\slideframe{none}\n");
		fout.puts("\\slidestyle{empty}\n");
		fout.puts("\\pagestyle{empty}\n");
		fout.puts("\\begin{document}\n");
		lslidenum = 0;
	}

	llinepos = 0;
	if(e.tag == SGML)
		lconvl(e.contents, 0);

	if(fmt == FLatexSlides && lslidenum > 0)
		fout.puts("\\vfill\\end{slide*}\n");
	if(fmt != FLatexPart)
		fout.puts("\\end{document}\n");
}

lconvl(el: ref Celem, state: int)
{
	for(e := el; e != nil; e = e.next) {
		tag := e.tag;
		op := "";
		cl := "";
		parlike := 1;
		nstate := state;
		if(tag < NFONTTAG) {
			parlike = 0;
			ss := lftagtostate[tag];
			if((state & SLFONTMASK) != ss) {
				t := state & SLT;
				b := state & SLB;
				i := state & SLI;
				newt := ss & SLT;
				newb := ss & SLB;
				newi := ss & SLI;
				op = "{";
				cl = "}";
				if(t && !newt)
					op += "\\rmfamily";
				else if(!t && newt)
					op += "\\ttfamily";
				if(b && !newb)
					op += "\\mdseries";
				else if(!b && newb)
					op += "\\bfseries";
				if(i && !newi)
					op += "\\upshape";
				else if(!i && newi) {
					op += "\\itshape";
					bc := lastchar(e.contents);
					ac := firstchar(e.next);
					if(bc != -1 && bc != ' ' && bc != '\n' && ac != -1 && ac != '.' && ac != ',')
						cl = "\\/}";
				}
				if((state & SLSIZEMASK) != (ss & SLSIZEMASK)) {
					nsize := 2;
					if(ss & SLS6)
						nsize = 0;
					else if(ss & SLS8)
						nsize = 1;
					else if(ss & SLS12)
						nsize = 3;
					else if(ss & SLS16)
						nsize = 4;
					# examples shrunk one size
					if((state & SLE) && nsize > 0)
							nsize--;
					op += lsizecmd[nsize];
				}
				fc := firstchar(e.contents);
				if(fc == ' ')
					op += "{}";
				else
					op += " ";
				nstate = (state & ~SLFONTMASK) | ss;
			}
		}
		else
			case tag {
			Text =>
				parlike = 0;
				if(state & SLO) {
					asciitrans[' '] = "\\ ";
					asciitrans['\n'] = "\\\\\n";
				}
				s := e.s;
				n := len s;
				for(k := 0; k < n; k++) {
					c := s[k];
					x := "";
					if(c < 128)
						x = asciitrans[c];
					else
						x = tlookup(ltranstab, c);
					if(x == "") {
						fout.putc(c);
						if(c == '\n')
							llinepos = 0;
						else
							llinepos++;
					}
					else {
						# split up ligatures
						if(c == '-' && k < n-1 && s[k+1] == '-')
								x = "-{}";
						# Avoid the 'no line to end here' latex error
						if((state&SLO) && c == '\n' && llinepos == 0)
								fout.puts("\\ ");
						else if((state&SLO) && c == '\t') {
							nspace := LTABSIZE - llinepos%LTABSIZE;
							llinepos += nspace;
							while(nspace-- > 0)
								fout.puts("\\ ");
								
						}
						else {
							fout.puts(x);
							if(x[len x - 1] == '\n')
								llinepos = 0;
							else
								llinepos++;
						}
					}
				}
				if(state & SLO) {
					asciitrans[' '] = nil;
					asciitrans['\n'] = nil;
				}
			Example =>
				if(!(state&SLE)) {
					op = "\\begin{example}";
					cl = "\\end{example}\\noindent ";
					nstate |= SLE | SLO;
				}
			List =>
				(n, bigle) := lfindbigle(e.contents);
				if(n <= 2) {
					op = "\\begin{itemize}\n";
					cl = "\\end{itemize}";
				}
				else {
					fout.puts("\\begin{itemizew}{");
					lconvl(bigle.contents, nstate);
					op = "}\n";
					cl = "\\end{itemizew}";
				}
			Listelem =>
				op = "\\item[{";
				cl = "}]";
			Heading =>
				if(fmt == FLatexProc)
					op = "\n\\Section{";
				else
					op = "\n\\section{";
				cl = "}\n";
				nstate = (state & ~SLFONTMASK) | (SLB | SLS12);
			Nofill =>
				op = "\\begin{nofill}";
				cl = "\\end{nofill}\\noindent ";
				nstate |= SLO;
			Title =>
				if(fmt == FLatexSlides) {
					op = "\\begin{slide*}\n" +
						"\\begin{center}\\Large\\bfseries ";
					if(lslidenum > 0)
						op = "\\vfill\\end{slide*}\n" + op;
					cl = "\\end{center}\n";
					lslidenum++;
				}
				else {
					if(stringof(e.contents) == "Index") {
						op = "\\printindex\n";
						e.contents = nil;
					}
					else {
						op = "\\chapter{";
						cl = "}\n";
					}
				}
				nstate = (state & ~SLFONTMASK) | (SLB | SLS16);
			Par =>
				op = "\n\\par\n";
				while(e.next != nil && e.next.tag == Par)
					e = e.next;
			Extension =>
				e.contents = convextension(e.s);
				if(e.contents != nil)
					e.contents.parent = e;
			Special =>
				fout.puts(e.s);
			Float =>
				if(!(state&SLF)) {
					isfig := lfixfloat(e);
					if(isfig) {
						op = "\\begin{figure}\\begin{center}\\leavevmode ";
						cl = "\\end{center}\\end{figure}";
					}
					else {
						op = "\\begin{table}\\begin{center}\\leavevmode ";
						cl = "\\end{center}\\end{table}";
					}
					nstate |= SLF;
				}
			Caption=>
				if(state&SLF) {
					op = "\\caption{";
					cl = "}";
					nstate = (state & ~SLFONTMASK) | SLS8;
				}
				else {
					op = "\\begin{center}";
					cl = "\\end{center}";
				}
			Label or Labelref =>
				parlike = 0;
				if(tag == Label)
					op = "\\label";
				else
					op = "\\ref";
				cl = "{" + stringof(e.contents) + "}";
				e.contents = nil;
			Exercise =>
				lfixexercise(e);
				op = "\\begin{exercise}";
				cl = "\\end{exercise}";
			Index or Indextopic =>
				parlike = 0;
				if(tag == Index)
					lconvl(e.contents, nstate);
				fout.puts("\\showidx{");
				lconvl(e.contents, nstate);
				fout.puts("}");
				lconvindex(e.contents, nstate);
				e.contents = nil;
			}
		if(op != "")
			fout.puts(op);
		if(e.contents != nil) {
			if(parlike)
				llinepos = 0;
			lconvl(e.contents, nstate);
			if(parlike)
				llinepos = 0;
		}
		if(cl != "")
			fout.puts(cl);
	}
}

lfixfloat(e: ref Celem) : int
{
	dropwhite(e.contents);
	fstart := e.contents;
	fend := last(fstart);
	hasfig := 0;
	hastab := 0;
	if(fend.tag == Caption) {
		dropwhite(fend.prev);
		if(fend.prev != nil && stringof(fstart) == "\t")
			delete(fend.prev);
		# If fend.contents is "YYY " <Label> "." rest
		# where YYY is Figure or Table,
		# then replace it with just rest, and move <Label>
		# after the caption.
		# Probably should be more robust about what to accept.
		ec := fend.contents;
		s := stringof(ec);
		if(s == "Figure ")
			hasfig = 1;
		else if(s == "Table ")
			hastab = 1;
		if(hasfig || hastab) {
			ec2 := ec.next;
			ec3 : ref Celem = nil;
			ec4 : ref Celem = nil;
			if(ec2 != nil && ec2.tag == Label) {
				ec3 = ec2.next;
				if(ec3 != nil && stringof(ec3) == ".")
					ec4 = ec3.next;
			}
			if(ec4 != nil) {
				dropwhite(ec4);
				ec4 = ec3.next;
				if(ec4 != nil) {
					excise(ec);
					excise(ec2);
					excise(ec3);
					fend.contents = ec4;
					ec4.parent = fend;
					insertafter(ec2, fend);
				}
			}
		}
	}
	return !hastab;
}

lfixexercise(e: ref Celem)
{
	dropwhite(e.contents);
	ec := e.contents;
	# Expect:
	#     "Exercise " <Label> ":" rest
	#  If so, drop the first and third.
	# Or
	#	"Exercise:" rest
	# If so, drop the first.
	s := stringof(ec);
	if(s == "Exercise ") {
		ec2 := ec.next;
		ec3 : ref Celem = nil;
		ec4 : ref Celem = nil;
			if(ec2 != nil && ec2.tag == Label) {
				ec3 = ec2.next;
				if(ec3 != nil && stringof(ec3) == ":")
					ec4 = ec3.next;
			}
			if(ec4 != nil) {
				dropwhite(ec4);
				ec4 = ec3.next;
				if(ec4 != nil) {
					excise(ec);
					excise(ec3);
					e.contents = ec2;
					ec2.parent = e;
					ec2.next = ec4;
					ec4.prev = ec2;
				}
			}
	}
	else if(s == "Exercise:") {
		dropwhite(ec.next);
		e.contents = ec.next;
		excise(ec);
		if(e.contents != nil)
			e.contents.parent = e;
	}
}

# convert content list headed by e to \\index{...}
lconvindex(e: ref Celem, state: int)
{
	fout.puts("\\index{");
	g := lsplitind(e);
	gp := g;
	needat := 0;
	while(g != nil) {
		gnext := g.next;
		s := stringof(g);
		if(s == "!" || s == "|") {
			if(gp != g) {
				g.next = nil;
				g.s = "";
				lprintindsort(gp);
				if(needat) {
					fout.puts("@");
					lconvl(gp, state);
				}
			}
			fout.puts(s);
			gp = gnext;
			needat = 0;
			if(s == "|") {
				if(g == nil)
					break;
				g = gnext;
				# don't lconvl the Text items, so
				# that "see{" and "}" come out untranslated.
				# (code is wrong if stuff inside see is plain
				# text but with special tex characters)
				while(g != nil) {
					gnext = g.next;
					g.next = nil;
					if(g.tag != Text)
						lconvl(g, state);
					else
						fout.puts(g.s);
					g = gnext;
				}
				gp = nil;
				break;
			}
		}
		else {
			if(g.tag != Text)
				needat = 1;
		}
		g = gnext;
	}
	if(gp != nil) {
		lprintindsort(gp);
		if(needat) {
			fout.puts("@");
			lconvl(gp, state);
		}
	}
	fout.puts("}");
}

lprintindsort(e: ref Celem)
{
	while(e != nil) {
		fout.puts(stringof(e));
		e = e.next;
	}
}

# return copy of e
lsplitind(e: ref Celem) : ref Celem
{
	dummy := ref Celem;
	for( ; e != nil; e = e.next) {
		te := e;
		if(e.tag < NFONTTAG)
			te = te.contents;
		if(te.tag != Text)
			continue;
		s := te.s;
		i := 0;
		for(j := 0; j < len s; j++) {
			if(s[j] == '!' || s[j] == '|') {
				if(j > i) {
					nte := ref Celem(Text, s[i:j], nil, nil, nil, nil);
					if(e == te)
						ne := nte;
					else
						ne = ref Celem(e.tag, nil, nte, nil, nil, nil);
					append(dummy, ne);
				}
				append(dummy, ref Celem(Text, s[j:j+1], nil, nil, nil, nil));
				i = j+1;
			}
		}
		if(j > i) {
			nte := ref Celem(Text, s[i:j], nil, nil, nil, nil);
			if(e == te)
				ne := nte;
			else
				ne = ref Celem(e.tag, nil, nte, nil, nil, nil);
			append(dummy, ne);
		}
	}
	return dummy.next;
}

# return key part of an index entry corresponding to e list
indexkey(e: ref Celem) : string
{
	s := "";
	while(e != nil) {
		s += stringof(e);
		e = e.next;
	}
	return s;
}

# find title, excise it from e, and return contents as list
lfindtitle(e: ref Celem) : ref Celem
{
	if(e.tag == Title) {
		ans := e.contents;
		delete(e);
		return ans;
	}
	else if (e.contents != nil) {
		for(h := e.contents; h != nil; h = h.next) {
			a := lfindtitle(h);
			if(a != nil)
				return a;
		}
	}
	return nil;
}

# find authors, excise them from e, and return as list of lists
lfindauthors(e: ref Celem) : list of ref Celem
{
	if(e.tag == Author) {
		a := e.contents;
		en := e.next;
		delete(e);
		rans : list of ref Celem = a :: nil;
		if(en != nil) {
			e = en;
			while(e != nil) {
				if(e.tag == Par) {
					en = e.next;
					if(en.tag == Author) {
						delete(e);
						a = en.contents;
						for(y := a; y != nil; ) {
							yn := y.next;
							if(y.tag == Par)
								delete(y);
							y = yn;
						}
						e = en.next;
						delete(en);
						rans = a :: rans;
					}
					else
						break;
				}
				else
					break;
			}
		}
		ans : list of ref Celem = nil;
		while(rans != nil) {
			ans = hd rans :: ans;
			rans = tl rans;
		}
		return ans;
	}
	else if (e.contents != nil) {
		for(h := e.contents; h != nil; h = h.next) {
			a := lfindauthors(h);
			if(a != nil)
				return a;
		}
	}
	return nil;
}

# find section called abstract, excise it from e, and return as list
lfindabstract(e: ref Celem) : ref Celem
{
	if(e.tag == Heading) {
		c := e.contents;
		if(c.tag == Text && c.s == "Abstract") {
			for(h2 := e.next; h2 != nil; h2 = h2.next) {
				if(h2.tag == Heading)
					break;
			}
			ans := e.next;
			ans.prev = nil;
			ep := e.prev;
			eu := e.parent;
			if(ep == nil) {
				if(eu != nil)
					eu.contents = h2;
				if(h2 != nil)
					h2.parent = eu;
			}
			else
				ep.next = h2;
			if(h2 != nil) {
				ansend := h2.prev;
				ansend.next = nil;
				h2.prev = ep;
			}
			return ans;
		}
	}
	else if (e.contents != nil) {
		for(h := e.contents; h != nil; h = h.next) {
			a := lfindabstract(h);
			if(a != nil)
				return a;
		}
	}
	return nil;
}

# find biggest list element with longest contents in e list
lfindbigle(e: ref Celem) : (int, ref Celem)
{
	ans : ref Celem = nil;
	maxlen := 0;
	for(h := e; h != nil; h = h.next) {
		if(h.tag == Listelem) {
			n := 0;
			for(p := h.contents; p != nil; p = p.next) {
				if(p.tag == Text)
					n += len p.s;
				else if(p.tag < NFONTTAG) {
					q := p.contents;
					if(q.tag == Text)
						n += len q.s;
				}
			}
			if(n > maxlen) {
				maxlen = n;
				ans = h;
			}
		}
	}
	return (maxlen, ans);
}

# Translation to HTML

# state bits
SHA, SHO, SHFL, SHDT: con (1<<iota);

htmlconv(e: ref Celem)
{
	initasciitrans(htranstab);

	fout.puts("<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 3.2 Final//EN\">\n");
	fout.puts("<HTML>\n");

	if(e.tag == SGML) {
		# Conforming 3.2 documents require a Title.
		# Use the Title tag both for the document title and
		# for an H1-level heading.
		# (SHDT state bit enforces: Font change markup, etc., not allowed in Title)
		fout.puts("<TITLE>\n");
		title := hfindtitle(e);
		if(title != nil)
			hconvl(title.contents, SHDT);
		else if(infilename != "")
			fout.puts(infilename);
		else
			fout.puts("An HTML document");
		fout.puts("</TITLE>\n");
		fout.puts("<BODY>\n");
		hconvl(e.contents, 0);
		fout.puts("</BODY>\n");
	}

	fout.puts("</HTML>\n");
}

hconvl(el: ref Celem, state: int)
{
	for(e := el; e != nil; e = e.next) {
		tag := e.tag;
		op := "";
		cl := "";
		nstate := state;
		if(tag == Text) {
			s := e.s;
			n := len s;
			for(k := 0; k < n; k++) {
				c := s[k];
				x := "";
				if(c < 128) {
					if(c == '\n' && (state&SHO))
						x = "\n\t";
					else
						x = asciitrans[c];
				}
				else
					x = tlookup(htranstab, c);
				if(x == "")
					fout.putc(c);
				else
					fout.puts(x);
			}
		}
		else if(!(state&SHDT))
			case tag {
			Roman*NSIZE+Size6 =>
				op = "<FONT SIZE=1>";
				cl = "</FONT>";
				nstate |= SHA;
			Roman*NSIZE+Size8 =>
				op = "<FONT SIZE=2>";
				cl = "</FONT>";
				nstate |= SHA;
			Roman*NSIZE+Size10 =>
				if(state & SHA) {
					op = "<FONT SIZE=3>";
					cl = "</FONT>";
					nstate &= ~SHA;
				}
			Roman*NSIZE+Size12 =>
				op = "<FONT SIZE=4>";
				cl = "</FONT>";
				nstate |= SHA;
			Roman*NSIZE+Size16 =>
				op = "<FONT SIZE=5>";
				cl = "</FONT>";
				nstate |= SHA;
			Italic*NSIZE+Size6 =>
				op = "<I><FONT SIZE=1>";
				cl = "</FONT></I>";
				nstate |= SHA;
			Italic*NSIZE+Size8 =>
				op = "<I><FONT SIZE=2>";
				cl = "</FONT></I>";
				nstate |= SHA;
			Italic*NSIZE+Size10 =>
				if(state & SHA) {
					op =  "<I><FONT SIZE=3>";
					cl = "</FONT></I>";
					nstate &= ~SHA;
				}
				else {
					op = "<I>";
					cl = "</I>";
				}
			Italic*NSIZE+Size12 =>
				op = "<I><FONT SIZE=4>";
				cl = "</FONT></I>";
				nstate |= SHA;
			Italic*NSIZE+Size16 =>
				op = "<I><FONT SIZE=5>";
				cl = "</FONT></I>";
				nstate |= SHA;
			Bold*NSIZE+Size6 =>
				op = "<B><FONT SIZE=1>";
				cl = "</FONT></B>";
				nstate |= SHA;
			Bold*NSIZE+Size8 =>
				op = "<B><FONT SIZE=2>";
				cl = "</FONT></B>";
				nstate |= SHA;
			Bold*NSIZE+Size10 =>
				if(state & SHA) {
					op =  "<B><FONT SIZE=3>";
					cl = "</FONT></B>";
					nstate &= ~SHA;
				}
				else {
					op = "<B>";
					cl = "</B>";
				}
			Bold*NSIZE+Size12 =>
				op = "<B><FONT SIZE=4>";
				cl = "</FONT></B>";
				nstate |= SHA;
			Bold*NSIZE+Size16 =>
				op = "<B><FONT SIZE=5>";
				cl = "</FONT></B>";
				nstate |= SHA;
			Type*NSIZE+Size6 =>
				op = "<TT><FONT SIZE=1>";
				cl = "</FONT></TT>";
				nstate |= SHA;
			Type*NSIZE+Size8 =>
				op = "<TT><FONT SIZE=2>";
				cl = "</FONT></TT>";
				nstate |= SHA;
			Type*NSIZE+Size10 =>
				if(state & SHA) {
					op =  "<TT><FONT SIZE=3>";
					cl = "</FONT></TT>";
					nstate &= ~SHA;
				}
				else {
					op = "<TT>";
					cl = "</TT>";
				}
			Type*NSIZE+Size12 =>
				op = "<TT><FONT SIZE=4>";
				cl = "</FONT></TT>";
				nstate |= SHA;
			Type*NSIZE+Size16 =>
				op = "<TT><FONT SIZE=5>";
				cl = "</FONT></TT>";
				nstate |= SHA;
			Example =>
				op = "<P><PRE>\t";
				cl = "</PRE><P>\n";
				nstate |= SHO;
			List =>
				op = "<DL>";
				cl = "</DD></DL>";
				nstate |= SHFL;
			Listelem =>
				if(state & SHFL)
					op = "<DT>";
				else
					op = "</DD><DT>";
				cl = "</DT><DD>";
				# change first-list-elem state for this level
				state &= ~SHFL;
			Heading =>
				op = "<H2>";
				cl = "</H2>\n";
			Nofill =>
				op = "<P><PRE>";
				cl = "</PRE>";
			Title =>
				op = "<H1>";
				cl = "</H1>\n";
			Par =>
				op = "<P>\n";
			Extension =>
				e.contents = convextension(e.s);
			Special =>
				fout.puts(e.s);
			}
		if(op != "")
			fout.puts(op);
		hconvl(e.contents, nstate);
		if(cl != "")
			fout.puts(cl);
	}
}

# find title, if there is one, and return it (but leave it in contents too)
hfindtitle(e: ref Celem) : ref Celem
{
	if(e.tag == Title)
		return e;
	else if (e.contents != nil) {
		for(h := e.contents; h != nil; h = h.next) {
			a := hfindtitle(h);
			if(a != nil)
				return a;
		}
	}
	return nil;
}

Exten: adt
{
	name: string;
	mod: Brutusext;
};

extens: list of Exten = nil;

convextension(s: string) : ref Celem
{
	for(i:=0; i<len s; i++)
		if(s[i] == ' ')
			break;
	if(i == len s) {
		sys->fprint(stderr, "badly formed extension %s\n", s);
		return nil;
	}
	modname := s[0:i];
	s = s[i+1:];
	mod: Brutusext = nil;
	for(le := extens; le != nil; le = tl le) {
		el := hd le;
		if(el.name == modname)
			mod = el.mod;
	}
	if(mod == nil) {
		file := modname;
		if(i < 4 || file[i-4:i] != ".dis")
			file += ".dis";
		if(file[0] != '/')
			file = "/dis/wm/brutus/" + file;
		mod = load Brutusext file;
		if(mod == nil) {
			sys->fprint(stderr, "can't load extension module %s: %r\n", file);
			return nil;
		}
		mod->init(sys, draw, B, tk, nil);
		extens = Exten(modname, mod) :: extens;
	}
	f := infilename;
	if(f == "<stdin>")
		f = "";
	(ans, err) := mod->cook(f, fmt, s);
	if(err != "") {
		sys->fprint(stderr, "extension module %s cook error: %s\n", modname, err);
		return nil;
	}
	return ans;
}
