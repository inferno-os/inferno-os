implement Lex;

include "common.m";

# local copies from CU
sys: Sys;
CU: CharonUtils;
S: String;
T: StringIntTab;
C: Ctype;
J: Script;
ctype: array of byte;

EOF : con -2;
EOB : con -1;

tagnames = array[] of {
	" ",
	"!",
	"a", 
	"abbr",
	"acronym",
	"address",
	"applet", 
	"area",
	"b",
	"base",
	"basefont",
	"bdo",
	"big",
	"blink",
	"blockquote",
	"body",
	"bq",
	"br",
	"button",
	"caption",
	"center",
	"cite",
	"code",
	"col",
	"colgroup",
	"dd",
	"del",
	"dfn",
	"dir",
	"div",
	"dl",
	"dt",
	"em",
	"fieldset",
	"font",
	"form",
	"frame",
	"frameset",
	"h1",
	"h2",
	"h3",
	"h4",
	"h5",
	"h6",
	"head",
	"hr",
	"html",
	"i",
	"iframe",
	"image",
	"img",
	"input",
	"ins",
	"isindex",
	"kbd",
	"label",
	"legend",
	"li",
	"link",
	"map",
	"menu",
	"meta",
	"nobr",
	"noframes",
	"noscript",
	"object",
	"ol",
	"optgroup",
	"option",
	"p",
	"param",
	"pre",
	"q",
	"s",
	"samp",
	"script",
	"select",
	"small",
	"span",
	"strike",
	"strong",
	"style",
	"sub",
	"sup",
	"table",
	"tbody",
	"td",
	"textarea",
	"tfoot",
	"th",
	"thead",
	"title",
	"tr",
	"tt",
	"u",
	"ul",
	"var",
	"xmp"
};

tagtable : array of T->StringInt;	# initialized from tagnames

attrnames = array[] of {
	"abbr",
	"accept",
	"accept-charset",
	"accesskey",
	"action",
	"align",
	"alink",
	"alt",
	"archive",
	"axis",
	"background",
	"bgcolor",
	"border",
	"cellpadding",
	"cellspacing",
	"char",
	"charoff",
	"charset",
	"checked",
	"cite",
	"class",
	"classid",
	"clear",
	"code",
	"codebase",
	"codetype",
	"color",
	"cols",
	"colspan",
	"compact",
	"content",
	"coords",
	"data",
	"datafld",
	"dataformatas",
	"datapagesize",
	"datasrc",
	"datetime",
	"declare",
	"defer",
	"dir",
	"disabled",
	"enctype",
	"event",
	"face",
	"for",
	"frame",
	"frameborder",
	"headers",
	"height",
	"href",
	"hreflang",
	"hspace",
	"http-equiv",
	"id",
	"ismap",
	"label",
	"lang",
	"language",
	"link",
	"longdesc",
	"lowsrc",
	"marginheight",
	"marginwidth",
	"maxlength",
	"media",
	"method",
	"multiple",
	"name",
	"nohref",
	"noresize",
	"noshade",
	"nowrap",
	"object",
	"onabort",
	"onblur",
	"onchange",
	"onclick",
	"ondblclick",
	"onerror",
	"onfocus",
	"onkeydown",
	"onkeypress",
	"onkeyup",
	"onload",
	"onmousedown",
	"onmousemove",
	"onmouseout",
	"onmouseover",
	"onmouseup",
	"onreset",
	"onresize",
	"onselect",
	"onsubmit",
	"onunload",
	"profile",
	"prompt",
	"readonly",
	"rel",
	"rev",
	"rows",
	"rowspan",
	"rules",
	"scheme",
	"scope",
	"scrolling",
	"selected",
	"shape",
	"size",
	"span",
	"src",
	"standby",
	"start",
	"style",
	"summary",
	"tabindex",
	"target",
	"text",
	"title",
	"type",
	"usemap",
	"valign",
	"value",
	"valuetype",
	"version",
	"vlink",
	"vspace",
	"width"
};

attrtable : array of T->StringInt;	# initialized from attrnames

chartab:= array[] of { T->StringInt
	("AElig",	'Æ'),
	("Aacute",	'Á'),
	("Acirc",	'Â'),
	("Agrave",	'À'),
	("Alpha",	'Α'),
	("Aring",	'Å'),
	("Atilde",	'Ã'),
	("Auml",	'Ä'),
	("Beta",	'Β'),
	("Ccedil",	'Ç'),
	("Chi",	'Χ'),
	("Dagger",	'‡'),
	("Delta",	'Δ'),
	("ETH",	'Ð'),
	("Eacute",	'É'),
	("Ecirc",	'Ê'),
	("Egrave",	'È'),
	("Epsilon",	'Ε'),
	("Eta",	'Η'),
	("Euml",	'Ë'),
	("Gamma",	'Γ'),
	("Iacute",	'Í'),
	("Icirc",	'Î'),
	("Igrave",	'Ì'),
	("Iota",	'Ι'),
	("Iuml",	'Ï'),
	("Kappa",	'Κ'),
	("Lambda",	'Λ'),
	("Mu",	'Μ'),
	("Ntilde",	'Ñ'),
	("Nu",	'Ν'),
	("OElig",	'Œ'),
	("Oacute",	'Ó'),
	("Ocirc",	'Ô'),
	("Ograve",	'Ò'),
	("Omega",	'Ω'),
	("Omicron",	'Ο'),
	("Oslash",	'Ø'),
	("Otilde",	'Õ'),
	("Ouml",	'Ö'),
	("Phi",	'Φ'),
	("Pi",	'Π'),
	("Prime",	'″'),
	("Psi",	'Ψ'),
	("Rho",	'Ρ'),
	("Scaron",	'Š'),
	("Sigma",	'Σ'),
	("THORN",	'Þ'),
	("Tau",	'Τ'),
	("Theta",	'Θ'),
	("Uacute",	'Ú'),
	("Ucirc",	'Û'),
	("Ugrave",	'Ù'),
	("Upsilon",	'Υ'),
	("Uuml",	'Ü'),
	("Xi",	'Ξ'),
	("Yacute",	'Ý'),
	("Yuml",	'Ÿ'),
	("Zeta",	'Ζ'),
	("aacute",	'á'),
	("acirc",	'â'),
	("acute",	'´'),
	("aelig",	'æ'),
	("agrave",	'à'),
	("alefsym",	'ℵ'),
	("alpha",	'α'),
	("amp",	'&'),
	("and",	'∧'),
	("ang",	'∠'),
	("aring",	'å'),
	("asymp",	'≈'),
	("atilde",	'ã'),
	("auml",	'ä'),
	("bdquo",	'„'),
	("beta",	'β'),
	("brvbar",	'¦'),
	("bull",	'•'),
	("cap",	'∩'),
	("ccedil",	'ç'),
	("cdots", '⋯'),
	("cedil",	'¸'),
	("cent",	'¢'),
	("chi",	'χ'),
	("circ",	'ˆ'),
	("clubs",	'♣'),
	("cong",	'≅'),
	("copy",	'©'),
	("crarr",	'↵'),
	("cup",	'∪'),
	("curren",	'¤'),
	("dArr",	'⇓'),
	("dagger",	'†'),
	("darr",	'↓'),
	("ddots", '⋱'),
	("deg",	'°'),
	("delta",	'δ'),
	("diams",	'♦'),
	("divide",	'÷'),
	("eacute",	'é'),
	("ecirc",	'ê'),
	("egrave",	'è'),
	("emdash", '—'),
	("empty",	'∅'),
	("emsp",	' '),
	("endash", '–'),
	("ensp",	' '),
	("epsilon",	'ε'),
	("equiv",	'≡'),
	("eta",	'η'),
	("eth",	'ð'),
	("euml",	'ë'),
	("euro",	'€'),
	("exist",	'∃'),
	("fnof",	'ƒ'),
	("forall",	'∀'),
	("frac12",	'½'),
	("frac14",	'¼'),
	("frac34",	'¾'),
	("frasl",	'⁄'),
	("gamma",	'γ'),
	("ge",	'≥'),
	("gt",	'>'),
	("hArr",	'⇔'),
	("harr",	'↔'),
	("hearts",	'♥'),
	("hellip",	'…'),
	("iacute",	'í'),
	("icirc",	'î'),
	("iexcl",	'¡'),
	("igrave",	'ì'),
	("image",	'ℑ'),
	("infin",	'∞'),
	("int",	'∫'),
	("iota",	'ι'),
	("iquest",	'¿'),
	("isin",	'∈'),
	("iuml",	'ï'),
	("kappa",	'κ'),
	("lArr",	'⇐'),
	("lambda",	'λ'),
	("lang",	'〈'),
	("laquo",	'«'),
	("larr",	'←'),
	("lceil",	'⌈'),
	("ldots", '…'),
	("ldquo",	'“'),
	("le",	'≤'),
	("lfloor",	'⌊'),
	("lowast",	'∗'),
	("loz",	'◊'),
	("lrm",	'‎'),
	("lsaquo",	'‹'),
	("lsquo",	'‘'),
	("lt",	'<'),
	("macr",	'¯'),
	("mdash",	'—'),
	("micro",	'µ'),
	("middot",	'·'),
	("minus",	'−'),
	("mu",	'μ'),
	("nabla",	'∇'),
	("nbsp",	' '),
	("ndash",	'–'),
	("ne",	'≠'),
	("ni",	'∋'),
	("not",	'¬'),
	("notin",	'∉'),
	("nsub",	'⊄'),
	("ntilde",	'ñ'),
	("nu",	'ν'),
	("oacute",	'ó'),
	("ocirc",	'ô'),
	("oelig",	'œ'),
	("ograve",	'ò'),
	("oline",	'‾'),
	("omega",	'ω'),
	("omicron",	'ο'),
	("oplus",	'⊕'),
	("or",	'∨'),
	("ordf",	'ª'),
	("ordm",	'º'),
	("oslash",	'ø'),
	("otilde",	'õ'),
	("otimes",	'⊗'),
	("ouml",	'ö'),
	("para",	'¶'),
	("part",	'∂'),
	("permil",	'‰'),
	("perp",	'⊥'),
	("phi",	'φ'),
	("pi",	'π'),
	("piv",	'ϖ'),
	("plusmn",	'±'),
	("pound",	'£'),
	("prime",	'′'),
	("prod",	'∏'),
	("prop",	'∝'),
	("psi",	'ψ'),
	("quad", ' '),
	("quot",	'"'),
	("quot", '"'),
	("rArr",	'⇒'),
	("radic",	'√'),
	("rang",	'〉'),
	("raquo",	'»'),
	("rarr",	'→'),
	("rceil",	'⌉'),
	("rdquo",	'”'),
	("real",	'ℜ'),
	("reg",	'®'),
	("rfloor",	'⌋'),
	("rho",	'ρ'),
	("rlm",	'‏'),
	("rsaquo",	'›'),
	("rsquo",	'’'),
	("sbquo",	'‚'),
	("scaron",	'š'),
	("sdot",	'⋅'),
	("sect",	'§'),
	("shy",	'­'),
	("sigma",	'σ'),
	("sigmaf",	'ς'),
	("sim",	'∼'),
	("sp", ' '),
	("spades",	'♠'),
	("sub",	'⊂'),
	("sube",	'⊆'),
	("sum",	'∑'),
	("sup",	'⊃'),
	("sup1",	'¹'),
	("sup2",	'²'),
	("sup3",	'³'),
	("supe",	'⊇'),
	("szlig",	'ß'),
	("tau",	'τ'),
	("there4",	'∴'),
	("theta",	'θ'),
	("thetasym",	'ϑ'),
	("thinsp",	' '),
	("thorn",	'þ'),
	("tilde",	'˜'),
	("times",	'×'),
	("trade",	'™'),
	("uArr",	'⇑'),
	("uacute",	'ú'),
	("uarr",	'↑'),
	("ucirc",	'û'),
	("ugrave",	'ù'),
	("uml",	'¨'),
	("upsih",	'ϒ'),
	("upsilon",	'υ'),
	("uuml",	'ü'),
	("varepsilon", '∈'),
	("varphi", 'ϕ'),
	("varpi", 'ϖ'),
	("varrho", 'ϱ'),
	("vdots", '⋮'),
	("vsigma", 'ς'),
	("vtheta", 'ϑ'), 
	("weierp",	'℘'),
	("xi",	'ξ'),
	("yacute",	'ý'),
	("yen",	'¥'),
	("yuml",	'ÿ'),
	("zeta",	'ζ'),
	("zwj",	'‍'),
	("zwnj",	'‌'),
};

# Characters Winstart..Winend are those that Windows
# uses interpolated into the Latin1 set.
# They aren't supposed to appear in HTML, but they do....
Winstart : con 16r7f;
Winend: con 16r9f;
winchars := array[] of { '•',
	'•', '•', '‚', 'ƒ', '„', '…', '†', '‡',
	'ˆ', '‰', 'Š', '‹', 'Œ', '•', '•', '•',
	'•', '‘', '’', '“', '”', '•', '–', '—',
	'˜', '™', 'š', '›', 'œ', '•', '•', 'Ÿ' 
};

NAMCHAR : con (C->L|C->U|C->D|C->N);
LETTER : con (C->L|C->U);

dbg := 0;
warn := 0;

init(cu: CharonUtils)
{
	CU = cu;
	sys = load Sys Sys->PATH;
	S = load String String->PATH;
	C = cu->C;
	J = cu->J;
	T = load StringIntTab StringIntTab->PATH;
	tagtable = CU->makestrinttab(tagnames);
	attrtable = CU->makestrinttab(attrnames);
	ctype = C->ctype;
}

TokenSource.new(b: ref CU->ByteSource, chset : Btos, mtype: int) : ref TokenSource
{
	ts := ref TSstate (
		0,				# bi
		0, 				# prevbi
		"",				# s
		0,				# si
		Convcs->Startstate,	# state
		Convcs->Startstate	# prevstate
	);
	ans := ref TokenSource(
		b,			# b
		chset,		# chset
		ts,			# state
		mtype,		# mtype
		0			# inxmp
	);
	dbg = int (CU->config).dbg['x'];
	warn = (int (CU->config).dbg['w']) || dbg;
	return ans;
}

TokenSource.gettoks(ts: self ref TokenSource): array of ref Token
{
	ToksMax : con 500;		# max chunk of tokens returned
	a := array[ToksMax] of ref Token;
	ai := 0;
	pcdai := 0;
	lim := 0;
	# put some dbg output in here
	if(ts.mtype == CU->TextHtml) {
		pcdstate : ref TSstate;
gather:
		while(ai < ToksMax-1) {	# always allow space for a Data token
			state := getstate(ts);
			c := getchar(ts);
			if (c < ' ') {
				c = eatctls(c, ts);
				if (c < 0)
					break;
			}
			tok : ref Token;
			if(c == '<') {
				tok = gettag(ts);
				if (tok != nil && ts.inxmp && tok.tag != Txmp+RBRA) {
					rewind(ts, state);
					getchar(ts);	# consume the '<'
					tok = ref Token(Data, "<", nil);
				}
				if(tok != nil && tok.tag != Comment) {
					a[ai++] = tok;
					case (tok.tag) {
					Tselect or Ttitle or Toption=>
						# Several tags expect PCDATA after them.
						# Capture state so we can rewind if necessary
						pcdstate = state;
						pcdai = ai-1;
					Ttextarea =>
						pcdstate = state;
						pcdai = ai-1;
						# not sure if we should parse entity references
						tok = gettagdata(ts, tok.tag, 1);
						if(tok != nil) {
							pcdstate = nil;
							a[ai++] = tok;
						}
					Tscript =>
						pcdstate = state;
						pcdai = ai-1;
						# special rules for getting Data
						tok = getscriptdata(ts);
						if(tok != nil) {
							pcdstate = nil;
							a[ai++] = tok;
						}
					Txmp =>
						pcdstate = nil;
						ts.inxmp = 1;
					Txmp+RBRA =>
						pcdstate = nil;
						ts.inxmp = 0;
					Data =>
						;
					Tmeta =>
						pcdstate = nil;
						break gather;
					* =>
						pcdstate = nil;
					}
				}
			} else {
				tok = getdata(ts, c);
				if(tok != nil)
					a[ai++] = tok;
			}
			if(tok == nil && !eof(ts)) {
				# we need more input to complete the token
				lim = ts.state.bi;
				rewind(ts, state);
				break gather;
			} else
				if(dbg > 1)
					sys->print("lex: got token %s\n", tok.tostring());
		}
		# Several tags expect PCDATA after them.
		# which means that build needs to see another tag or eof
		# after any data in order to know that PCDATA is ended.
		# Rewind if we haven't got to the following tag yet.
		if (pcdstate != nil && !eof(ts)) {
			rewind(ts, pcdstate);
			ai = pcdai;
		}
	}
	else {
		# plain text (non-html) tokens
		while(ai < ToksMax) {
			tok := getplaindata(ts);
			if(tok == nil)
				break;
			else
				a[ai++] = tok;
			if(dbg > 1)
				sys->print("lex: got token %s\n", tok.tostring());
		}
	}
	if(dbg)
		sys->print("lex: returning %d tokens\n", ai);
	if (lim > ts.b.lim)
		ts.b.lim = lim;
	else
		ts.b.lim = ts.state.prevbi;
	if(ai == 0)
		return nil;
	return a[0:ai];
}

# must not be called from within TokenSource.gettoks()
# as it will not work with rewind() and ungetchar()
#
TokenSource.setchset(ts: self ref TokenSource, chset: Btos)
{
	st := ts.state;
	nchars := st.si;
	if (nchars > 0 && nchars < len st.s) {
		# align bi to the current input char
		bs := ts.b;
		(nil, nil, n) := ts.chset->btos(st.prevcsstate, bs.data[st.prevbi:st.bi], nchars);
		st.bi = st.prevbi + n;
		st.prevbi = st.bi;
	}
	ts.chset = chset;
	st.csstate = st.prevcsstate = Convcs->Startstate;
	st.s = nil;
	st.si = 0;
}


eof(ts : ref TokenSource) : int
{
	st := ts.state;
	bs := ts.b;
	return (st.s == nil && bs.eof && st.prevbi == bs.edata);
}

# For case where source isn't HTML.
# Just make data tokens, one per line (or partial line,
# at end of buffer), ignoring non-whitespace control
# characters and dumping \r's
getplaindata(ts: ref TokenSource): ref Token
{
	s := "";
	j := 0;

	for(c := getchar(ts); c >= 0; c = getchar(ts)) {
		if(c < ' ') {
			if(ctype[c] == C->W) {
				if(c == '\r') {
					# ignore it unless no following '\n',
					# in which case treat it like '\n'
					c = getchar(ts);
					if(c != '\n') {
						if(c >= 0)
							ungetchar(ts);
						c = '\n';
					}
				}
			}
			else
				c = 0;	# ignore
		}
		if(c != 0)
			s[j++] = c;
		if(c == '\n')
			break;
	}
	if(s == "")
		return nil;
	return ref Token(Data, s, nil);
}

eatctls(c: int, ts: ref TokenSource): int
{
	while (c >= 0) {
		if (c >= ' ')
			return c;
		if(ctype[c] == C->W) {
			if(c == '\r') {
				c = getchar(ts);
				if (c != '\n' && c >= 0) {
					ungetchar(ts);
					c = '\n';
				}
			}
			return c;
		}
		c = getchar(ts);
	}
	return -1;
}

# Gather data up to next start-of-tag or end-of-buffer.
# Translate entity references (&amp;) if not in <XMP> section.
# Ignore non-whitespace control characters and get rid of \r's.
getdata(ts: ref TokenSource, firstc : int): ref Token
{
	s := "";
	j := 0;
	c := firstc;

	while(c >= 0) {
		if (c < ' ')
			c = eatctls(c, ts);
		if (c < 0)
			break;
		if(c == '&' && !ts.inxmp) {
			ok : int;
			(c, ok) = ampersand(ts);
			if(!ok) {
				ungetchar(ts);
				break;	# incomplete entity reference (ts backed up by ampersand)
			}
		}
		else if(c == '<') {
			ungetchar(ts);
			break;
		}
		if(c != 0)
			s[j++] = c;
		c = getchar(ts);
	}
	if(s == "")
		return nil;
	return ref Token(Data, s, nil);
}

# The rules for lexing scripts are different (ugh).
# Gather up everything until see a </SCRIPT>.
getscriptdata(ts: ref TokenSource): ref Token
{
	tok := gettagdata(ts, Tscript, 0);
	if (tok != nil)
		tok.text = CU->stripscript(tok.text);
	return tok;
}

gettagdata(ts: ref TokenSource, tag, doentities: int): ref Token
{
	s := "";
	j := 0;
	c := getchar(ts);

	while(c >= 0) {
		if (c == '<') {
			tstate := getstate(ts);
			tok := gettag(ts);
			rewind(ts, tstate);
			if (tok != nil && tok.tag == tag+RBRA) {
				ungetchar(ts);
				return ref Token(Data, s, nil);
			}
			# tag was not </tag>, take as regular data
		}
		if (doentities && c == '&')
			(c, nil) = ampersand(ts);

		if(c < 0)
			break;
		if(c != 0)
			s[j++] = c;
		c = getchar(ts);
	}
	if(eof(ts))
		return ref Token(Data, s, nil);

	return nil;
}

# We've just seen a '<'.  Gather up stuff to closing '>' (if buffer
# ends before then, return nil).
# If it's a tag, look up the name, gather the attributes, and return
# the appropriate token.
# Else it's either just plain data or some kind of ignorable stuff:
# return a Data or Comment token as appropriate.
gettag(ts: ref TokenSource): ref Token
{
	rbra := 0;
	ans : ref Token = nil;
	al: list of Attr;
	start := getstate(ts);
	c := getchar(ts);

	# dummy loop: break out of this when hit end of buffer
 eob:
	for(;;) {
		if(c == '/') {
			rbra = RBRA;
			c = getchar(ts);
		}
		if(c < 0)
			break eob;
		if(c>=C->NCTYPE || !int (ctype[c]&LETTER)) {
			# not a tag
			if(c == '!') {
				ans = comment(ts);
				if(ans != nil)
					return ans;
				break eob;
			}
			else {
				rewind(ts, start);
				return ref Token(Data, "<", nil);
			}
		}
		# c starts a tagname
		ans = ref Token(Notfound, nil, nil);
		name := "";
		name[0] = lowerc(c);
		i := 1;
		for(;;) {
			c = getchar(ts);
			if(c < 0)
				break eob;
			if(c>=C->NCTYPE || !int (ctype[c]&NAMCHAR))
				break;
			name[i++] = lowerc(c);
		}
		(fnd, tag) := T->lookup(tagtable, name);
		if(fnd)
			ans.tag = tag+rbra;
		else
			ans.text = name;	# for warning print, in build
attrloop:
		for(;;) {
			# look for "ws name" or "ws name ws = ws val"  (ws=whitespace)
			# skip whitespace
			while(c < C->NCTYPE && ctype[c] == C->W) {
				c = getchar(ts);
				if(c < 0)
					break eob;
			}
			if(c == '>')
				break attrloop;
			if(c == '<') {
				if(warn)
					sys->print("warning: unclosed tag; last name=%s\n", name);
				ungetchar(ts);
				break attrloop;
			}
			if(c >= C->NCTYPE || !int (ctype[c]&LETTER)) {
				if(warn)
					sys->print("warning: expected attribute name; last name=%s\n", name);
				# skip to next attribute name
				for(;;) {
					c = getchar(ts);
					if(c < 0)
						break eob;
					if(c < C->NCTYPE && int (ctype[c]&LETTER))
						continue attrloop;
					if(c == '<') {
						if(warn)
							sys->print("warning: unclosed tag; last name=%s\n", name);
						ungetchar(ts);
						break attrloop;
					}
					if(c == '>')
						break attrloop;
				}
			}
			# gather attribute name
			name = "";
			name[0] = lowerc(c);
			i = 1;
			for(;;) {
				c = getchar(ts);
				if(c < 0)
					break eob;
				if(c >= C->NCTYPE || !int (ctype[c]&NAMCHAR))
					break;
				name[i++] = lowerc(c);
			}
			(afnd, attid) := T->lookup(attrtable, name);
			if(warn && !afnd)
				sys->print("warning: unknown attribute name %s\n", name);
			# skip whitespace
			while(c < C->NCTYPE && ctype[c] == C->W) {
				c = getchar(ts);
				if(c < 0)
					break eob;
			}
			if(c != '=') {
				# no value for this attr
				if(afnd)
					al = (attid, "") :: al;
				continue attrloop;
			}
			# c is '=' here;  skip whitespace
			for(;;) {
				c = getchar(ts);
				if(c < 0)
					break eob;
				if(c >= C->NCTYPE || ctype[c] != C->W)
					break;
			}
			# gather value
			quote := 0;
			if(c == '\'' || c == '"') {
				quote = c;
				c = getchar(ts);
				if(c < 0)
					break eob;
			}
			val := "";
			nv := 0;
		valloop:
			for(;;) {
				if(c < 0)
					break eob;
# other browsers allow value strings to be broken across lines
# especially the case for Javascript event handlers / URLs
				if (c == '>' && !quote)
					break valloop;
# old code otherwise ok - keep for now for reference
#				if(c == '>') {
#					if(quote) {
#						# c might be part of string (though not good style)
#						# but if line ends before close quote, assume
#						# there was an unmatched quote
#						ti := ts.i;
#						for(;;) {
#							c = getchar(ts);
#							if(c < 0)
#								break eob;
#							if(c == quote) {
#								backup(ts, ti);
#								val[nv++] = '>';
#								c = getchar(ts);
#								continue valloop;
#							}
#							if(c == '\n') {
#								if(warn)
#									sys->print("warning: apparent unmatched quote\n");
#								backup(ts, ti);
#								quote = 0;
#								c = '>';
#								break valloop;
#							}
#						}
#					}
#					else
#						break valloop;
#				}
				if(quote) {
					if(c == quote) {
						c = getchar(ts);
						if(c < 0)
							break eob;
						break valloop;
					}
					if(c == '\r') {
						c = getchar(ts);
						continue valloop;
					}
					if(c == '\t' || c == '\n')
						c = ' ';
				}
				else {
					if(c < C->NCTYPE && ctype[c]==C->W)
						break valloop;
				}
				if(c == '&') {
					ok : int;
					(c, ok) = ampersand(ts);
					if(!ok)
						break eob;
				}
				val[nv++] = c;
				c = getchar(ts);
			}
			if(afnd)
				al = (attid, val) :: al;
		}
		ans.attr = al;
		return ans;
	}
	if(eof(ts)) {
		if(warn)
			sys->print("warning: incomplete tag at end of page\n");
		rewind(ts, start);
		return ref Token(Data, "<", nil);
	}
	return nil;
}


# We've just read a '<!',
# so this may be a comment or other ignored section, or it may
# be just a literal string if there is no close before end of file
# (other browsers do that).
# The accepted practice seems to be (note: contrary to SGML spec!):
# If see <!--, look for --> to close, or if none, > to close.
# If see <!(not --), look for > to close.
# If no close before end of file, leave original characters in as literal data.
#
# If we see ignorable stuff, return Comment token.
# Else return nil (caller should back up and try again when more data arrives,
# unless at end of file, in which case caller should just make '<' a data token).
comment(ts: ref TokenSource) : ref Token
{
	havecomment := 0;
	commentstart := 0;
	c := getchar(ts);
	if(c == '-') {
		state := getstate(ts);
		c = getchar(ts);
		if(c == '-') {
			commentstart = 1;
			if(findstr(ts, "-->"))
				havecomment = 1;
			else
				rewind(ts, state);
		}
	}
	if(!havecomment) {
		if(c == '>')
			havecomment = 1;
		else if(c >= 0) {
			if(findstr(ts, ">"))
				havecomment = 1;
		}
	}
	if(havecomment)
		return ref Token(Comment, nil, nil);
	return nil;
}

# Look for string s in token source.
# If found, return 1, with buffer at next char after s,
# else return 0 (caller should back up).
findstr(ts: ref TokenSource, s: string) : int
{
	n := len s;
	eix := n-1;
	buf := "";
	c : int;

	if (n == 1) {
		while ((c = getchar(ts)) >= 0)
			if (c == s[0])
				return 1;
		return 0;
	}

	for (i := 0; i < n; i++) {
		c = getchar(ts);
		if (c < 0)
			return 0;
		buf[i] = c;
	}

	for (;;) {
		# this could be much more efficient by tracking
		# the start char through buf
		if (buf == s)
			return 1;
		c = getchar(ts);
		if (c < 0)
			return 0;
		buf = buf[1:];
		buf[eix] = c;
	}
	return 0;	# keep the compiler quiet
}

# We've just read an '&'; look for an entity reference
# name, and if found, return (translated char, 1).
# Otherwise the input stream is rewound to just after
# the '&'
# if there is a complete entity name but it isn't known,
# ('&', 1) is returned, if an incomplete name is encountered
# (0, 0) is returned
ampersand(ts: ref TokenSource): (int, int)
{
	state := getstate(ts);
	c := getchar(ts);
	fnd := 0;
	ans := 0;
	if(c == '#') {
		v := 0;
		c = getchar(ts);
		if (c == 'x' || c == 'X') {
			for (c = getchar(ts); c >= 0; c = getchar(ts)) {
				if (int (ctype[c] & C->D)) {
					v = v*16 + c-'0';
					continue;
				}
				c = lowerc(c);
				if (c >= 'a' && c <= 'f') {
					v = v*16 + 10 + c-'a';
					continue;
				}
				break;
			}
		} else {
			while(c >= 0) {
				if(ctype[c] != C->D)
					break;
				v = v*10 + c-'0';
				c = getchar(ts);
			}
		}
		if(c >= 0) {
			if(!(c == ';' || c == '\n' || c == '\r' || c == '<'))
				ungetchar(ts);
			c = v;
			if(c==160)
				c = ' ';   # non-breaking space
			if(c >= Winstart && c <= Winend)
				c = winchars[c-Winstart];
			ans = c;
			fnd = (v != 0);
		}
	}
	# only US-ASCII chars can make up &charnames;
	else if(c >= 0 && c < 16r80 && int (ctype[c] & LETTER)) {
		s := "";
		s[0] = c;
		k := 1;
		for(;;) {
			c = getchar(ts);
			if(c < 0)
				break;
			if(c < 16r80 && int (ctype[c]&NAMCHAR))
				s[k++] = c;
			else {
				if(!(c == ';' || c == '\n' || c == '\r'))
					ungetchar(ts);
				break;
			}
		}
		if (c < 0 || c == ' ' || c == ';' || c == '\n' || c == '\r' || c == '<')
			(fnd, ans) = T->lookup(chartab, s);
	}
	if(!fnd) {
		if(c < 0 && !eof(ts)) {
			# was incomplete
			rewind(ts, state);
			return (0, 0);
		}
		else {
			rewind(ts, state);
			return ('&', 1);
		}
	}
	# elide soft hyphens (&shy; / &xAD;)
# not suficient - need to do it for all input in getdata() which is too heavy handed
#	if (ans == '­')
#		ans = 0;
	return (ans, 1);
}

# If c is an uppercase letter, return its lowercase version,
# otherwise return c.
# Assume c is a NAMCHAR, so don't need range check on ctype[]
lowerc(c: int) : int
{
	if(ctype[c] == C->U) {
		# this works for accented characters in Latin1, too
		return c + 16r20;
	}
	return c;
}

Token.aval(t: self ref Token, attid: int): (int, string)
{
	attr := t.attr;
	while(attr != nil) {
		a := hd attr;
		if(a.attid == attid)
			return (1, a.value); 
		attr = tl attr;
	}
	return (0, "");
}


# for debugging
Token.tostring(t: self ref Token) : string
{
	ans := "";
	tag := t.tag;
	if(tag == Data)
		ans = ans + "'" + t.text + "'";
	else {
		ans = ans + "<";
		if(tag >= RBRA) {
			tag -= RBRA;
			ans = ans + "/";
		}
		tname := tagnames[tag];
		if(tag == Notfound)
			tname = "?";
		ans = ans + S->toupper(tname);
		for(al := t.attr; al != nil; al = tl al) {
			a := hd al;
			aname := attrnames[a.attid];
			ans = ans + " " + aname;
			if(a.value != "")
				ans = ans + "='" + a.value + "'";
		}
		ans = ans + ">";
	}
	return ans;
}


CONVBLK : con 1024;		# number of characters to convert at a time

# Returns -1 if no complete character left before current end of data.
getchar(ts: ref TokenSource): int
{
	st := ts.state;
	if (st.s == nil || st.si >= len st.s) {
		bs := ts.b;
		st.si = 0;
		st.s = "";
		st.prevcsstate = st.csstate;
		st.prevbi = st.bi;
		edata := bs.edata;
		if (st.bi >= edata)
			return -1;
		(state, s, n ) := ts.chset->btos(st.csstate, bs.data[st.bi:edata], CONVBLK);
		if (s == nil) {
			if (bs.eof && edata == bs.edata) {
				# must have been an encoding error at eof
				st.prevbi = st.bi = edata;
			}
			return -1;
		}
		st.csstate = state;
		st.s = s;
		st.bi += n;
	}
	return st.s[st.si++];
}

# back up by one input character
# NOTE: can only call this function post a successful getchar() call
ungetchar(ts : ref TokenSource)
{
	st := ts.state;
	# assert(len st.s >= 1 && st.si > 0)
	if (st.si <= 0)
		raise "EXInternal:too many backups";
	st.si--;
}

rewind(ts : ref TokenSource, state : ref TSstate)
{
	ts.state = state;
}

# return a copy of the TokenSource state
getstate(ts : ref TokenSource) : ref TSstate
{
	return ref *ts.state;
}

