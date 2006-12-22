implement HTML;

include "sys.m";
include "html.m";
include "strinttab.m";

sys:	Sys;
T:	StringIntTab;

Stringtab: adt
{
	name:	string;
	val:		int;
};

chartab:= array[] of { T->StringInt
	("AElig", 'Æ'),
	("Aacute", 'Á'),
	("Acirc", 'Â'),
	("Agrave", 'À'),
	("Aring", 'Å'),
	("Atilde", 'Ã'),
	("Auml", 'Ä'),
	("Ccedil", 'Ç'),
	("ETH", 'Ð'),
	("Eacute", 'É'),
	("Ecirc", 'Ê'),
	("Egrave", 'È'),
	("Euml", 'Ë'),
	("Iacute", 'Í'),
	("Icirc", 'Î'),
	("Igrave", 'Ì'),
	("Iuml", 'Ï'),
	("Ntilde", 'Ñ'),
	("Oacute", 'Ó'),
	("Ocirc", 'Ô'),
	("Ograve", 'Ò'),
	("Oslash", 'Ø'),
	("Otilde", 'Õ'),
	("Ouml", 'Ö'),
	("THORN", 'Þ'),
	("Uacute", 'Ú'),
	("Ucirc", 'Û'),
	("Ugrave", 'Ù'),
	("Uuml", 'Ü'),
	("Yacute", 'Ý'),
	("aacute", 'á'),
	("acirc", 'â'),
	("acute", '´'),
	("aelig", 'æ'),
	("agrave", 'à'),
	("alpha", 'α'),
	("amp", '&'),
	("aring", 'å'),
	("atilde", 'ã'),
	("auml", 'ä'),
	("beta", 'β'),
	("brvbar", '¦'),
	("ccedil", 'ç'),
	("cdots", '⋯'),
	("cedil", '¸'),
	("cent", '¢'),
	("chi", 'χ'),
	("copy", '©'),
	("curren", '¤'),
	("ddots", '⋱'),
	("deg", '°'),
	("delta", 'δ'),
	("divide", '÷'),
	("eacute", 'é'),
	("ecirc", 'ê'),
	("egrave", 'è'),
	("emdash", '—'),
	("emsp", ' '),
	("endash", '–'),
	("ensp", ' '),
	("epsilon", 'ε'),
	("eta", 'η'),
	("eth", 'ð'),
	("euml", 'ë'),
	("frac12", '½'),
	("frac14", '¼'),
	("frac34", '¾'),
	("gamma", 'γ'),
	("gt", '>'),
	("iacute", 'í'),
	("icirc", 'î'),
	("iexcl", '¡'),
	("igrave", 'ì'),
	("iota", 'ι'),
	("iquest", '¿'),
	("iuml", 'ï'),
	("kappa", 'κ'),
	("lambda", 'λ'),
	("laquo", '«'),
	("ldots", '…'),
	("lt", '<'),
	("macr", '¯'),
	("micro", 'µ'),
	("middot", '·'),
	("mu", 'μ'),
	("nbsp", ' '),
	("not", '¬'),
	("ntilde", 'ñ'),
	("nu", 'ν'),
	("oacute", 'ó'),
	("ocirc", 'ô'),
	("ograve", 'ò'),
	("omega", 'ω'),
	("omicron", 'ο'),
	("ordf", 'ª'),
	("ordm", 'º'),
	("oslash", 'ø'),
	("otilde", 'õ'),
	("ouml", 'ö'),
	("para", '¶'),
	("phi", 'φ'),
	("pi", 'π'),
	("plusmn", '±'),
	("pound", '£'),
	("psi", 'ψ'),
	("quad", ' '),
	("quot", '"'),
	("raquo", '»'),
	("reg", '®'),
	("rho", 'ρ'),
	("sect", '§'),
	("shy", '­'),
	("sigma", 'σ'),
	("sp", ' '),
	("sup1", '¹'),
	("sup2", '²'),
	("sup3", '³'),
	("szlig", 'ß'),
	("tau", 'τ'),
	("theta", 'θ'),
	("thinsp", ' '),
	("thorn", 'þ'),
	("times", '×'),
	("trade", '™'),
	("uacute", 'ú'),
	("ucirc", 'û'),
	("ugrave", 'ù'),
	("uml", '¨'),
	("upsilon", 'υ'),
	("uuml", 'ü'),
	("varepsilon", '∈'),
	("varphi", 'ϕ'),
	("varpi", 'ϖ'),
	("varrho", 'ϱ'),
	("vdots", '⋮'),
	("vsigma", 'ς'),
	("vtheta", 'ϑ'), 
	("xi", 'ξ'),
	("yacute", 'ý'),
	("yen", '¥'),
	("yuml", 'ÿ'),
	("zeta", 'ζ'),
};

htmlstringtab := array[] of { T->StringInt
	("a", Ta),
	("address", Taddress),
	("applet", Tapplet),
	("area", Tarea),
	("att_footer", Tatt_footer),
	("b", Tb),
	("base", Tbase),
	("basefont", Tbasefont),
	("big", Tbig),
	("blink", Tblink),
	("blockquote", Tblockquote),
	("body", Tbody),
	("bq", Tbq),
	("br", Tbr),
	("caption", Tcaption),
	("center", Tcenter),
	("cite", Tcite),
	("code", Tcode),
	("col", Tcol),
	("colgroup", Tcolgroup),
	("dd", Tdd),
	("dfn", Tdfn),
	("dir", Tdir),
	("div", Tdiv),
	("dl", Tdl),
	("dt", Tdt),
	("em", Tem),
	("font", Tfont),
	("form", Tform),
	("frame", Tframe),
	("frameset", Tframeset),
	("h1", Th1),
	("h2", Th2),
	("h3", Th3),
	("h4", Th4),
	("h5", Th5),
	("h6", Th6),
	("head", Thead),
	("hr", Thr),
	("html", Thtml),
	("i", Ti),
	("img", Timg),
	("input", Tinput),
	("isindex", Tisindex),
	("item", Titem),
	("kbd", Tkbd),
	("li", Tli),
	("link", Tlink),
	("map", Tmap),
	("menu", Tmenu),
	("meta", Tmeta),
	("nobr", Tnobr),
	("noframes", Tnoframes),
	("ol", Tol),
	("option", Toption),
	("p", Tp),
	("param", Tparam),
	("pre", Tpre),
	("q", Tq),
	("samp", Tsamp),
	("script", Tscript),
	("select", Tselect),
	("small", Tsmall),
	("strike", Tstrike),
	("strong", Tstrong),
	("style", Tstyle),
	("sub", Tsub),
	("sup", Tsup),
	("t", Tt),
	("table", Ttable),
	("tbody", Ttbody),
	("td", Ttd),
	("textarea", Ttextarea),
	("textflow", Ttextflow),
	("tfoot", Ttfoot),
	("th", Tth),
	("thead", Tthead),
	("title", Ttitle),
	("tr", Ttr),
	("tt", Ttt),
	("u", Tu),
	("ul", Tul),
	("var", Tvar)
};

W, D, L, U, N: con byte (1<<iota);
NCTYPE: con 256;

ctype := array[NCTYPE] of {
	'0'=>D, '1'=>D, '2'=>D, '3'=>D, '4'=>D,
	'5'=>D, '6'=>D, '7'=>D, '8'=>D, '9'=>D,
	'A'=>U, 'B'=>U, 'C'=>U, 'D'=>U, 'E'=>U, 'F'=>U,
	'G'=>U, 'H'=>U, 'I'=>U, 'J'=>U, 'K'=>U, 'L'=>U,
	'M'=>U, 'N'=>U, 'O'=>U, 'P'=>U, 'Q'=>U, 'R'=>U,
	'S'=>U, 'T'=>U, 'U'=>U, 'V'=>U, 'W'=>U, 'X'=>U,
	'Y'=>U, 'Z'=>U,
	'a'=>L, 'b'=>L, 'c'=>L, 'd'=>L, 'e'=>L, 'f'=>L,
	'g'=>L, 'h'=>L, 'i'=>L, 'j'=>L, 'k'=>L, 'l'=>L,
	'm'=>L, 'n'=>L, 'o'=>L, 'p'=>L, 'q'=>L, 'r'=>L,
	's'=>L, 't'=>L, 'u'=>L, 'v'=>L, 'w'=>L, 'x'=>L,
	'y'=>L, 'z'=>L,
	'.'=>N, '-'=>N,
	' '=>W, '\n'=>W, '\t'=>W, '\r'=>W,
	* => byte 0
};

lex(b: array of byte, charset: int, keepwh: int): array of ref Lex
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(T == nil)
		T = load StringIntTab StringIntTab->PATH;
	if(T == nil) {
		sys->print("HTML->lex: couldn't %s\n", StringIntTab->PATH);
		return nil;
	}

	a: array of ref Lex;
	ai := 0;
	i := 0;
	nb := len b;
	for(;;){
   Whitespace:
		for(;;){
			# ignore nulls
			while(i<nb && (int b[i] == 0))
				i++;
			# skip white space
			if(!keepwh) {
				while(i<nb) {
					c := int b[i];
					if(!(int (ctype[c]&W)) && c != ' ')
						break;
					i++;
				}
			}
			# skip comments
			if(i<nb-4 && int b[i]=='<' && int b[i+1]=='!'
					&& int b[i+2]=='-' && int b[i+3]=='-') {
				i += 4;
				while(i<nb-3){
					if(int b[i]=='-' && int b[i+1]=='-' && int b[i+2]=='>'){
						i += 3;
						continue Whitespace;
					}
					i++;
				}
				continue Whitespace;
			}
			break;
		}
		if(i == nb)
			break;
		if(ai == len a){
			na := array[len a + 500] of ref Lex;
			if(a != nil)
				na[0:] = a;
			a = na;
		}
		if(int b[i] == '<'){
			lx : ref Lex;
			(lx, i) = gettag(b, i, charset);
			a[ai++] = lx;
		}
		else {
			s: string;
			(s, i) = getdata(b, i, keepwh, charset);
			a[ai++] = ref Lex (Data, s, nil);
		}
	}
	return a[0:ai];
}

getdata(b: array of byte, i: int, keepnls, charset: int): (string, int)
{
	s:= "";
	j:= 0;
	c: int;
	nb := len b;

loop:
	while(i < nb){
		oldi := i;
		case charset{
		Latin1 =>
			c = int b[i++];
		UTF8 =>
			j: int;
			(c, j, nil) = sys->byte2char(b, i);
			i += j;
		}
		case c {
		0 or 16r1a =>
			continue loop;
		'<' =>
			i = oldi;
			break loop;
		'&' =>
			(c, i) = ampersand(b, i);
		'\n' =>
			if(!keepnls)
				c = ' ';
		'\r' =>
			if(oldi > 0 && int b[oldi-1] == '\n')
				continue loop;
			if(keepnls)
				c = '\n';
			else
				c = ' ';
		}
		s[j++] = c;
	}
	return (s, i);
}

gettag(b: array of byte, i, charset: int): (ref Lex, int)
{
	rbra := 0;
	nb := len b;
	ans := ref Lex(Notfound, "", nil);
	al: list of Attr;
	if(++i == nb)
		return (ans, i);
	istart := i;
	c := int b[i];
	if(c == '/') {
		rbra = RBRA;
		if(++i == nb)
			return (ans, i);
		c = int b[i];
	}
	if(c>=NCTYPE || !int (ctype[c]&(L|U))) {
		while(i < nb) {
			c = int b[i++];
			if(c == '>')
				break;
		}
		ans.text = string b[istart:i];
		return (ans, i);
	}
	namstart := i;
	while(c<NCTYPE && int (ctype[c]&(L|U|D|N))) {
		if(++i == nb) {
			ans.text = string b[istart:i];
			return (ans, i);
		}
		c = int b[i];
	}
	name := lowercase(b, namstart, i);
	(fnd, tag) := T->lookup(htmlstringtab, name);
	if(fnd)
		ans.tag = tag+rbra;
	else
		ans.text = name;
attrloop:
	while(i < nb){
		# look for "ws name" or "ws name ws = ws val"  (ws=whitespace)
		# skip whitespace
		while(c<NCTYPE && int (ctype[c]&W)) {
			if(++i == nb)
				break attrloop;
			c = int b[i];
		}
		if(c == '>') {
			i++;
			break;
		}
		if(c == '<')
			break;	# error: unclosed tag
		if(c>=NCTYPE || !int (ctype[c]&(L|U))) {
			# error, not the start of a name
			# skip to end of tag
			while(i < nb) {
				c = int b[i++];
				if(c == '>')
					break;
			}
			break attrloop;
		}
		# gather name
		namstart = i;
		while(c<NCTYPE && int (ctype[c]&(L|U|D|N))) {
			if(++i == nb)
				break attrloop;
			c = int b[i];
		}
		name = lowercase(b, namstart, i);
		# skip whitespace
		while(c<NCTYPE && int (ctype[c]&W)) {
			if(++i == nb)
				break attrloop;
			c = int b[i];
		}
		if(c != '=') {
			# no value for this attr
			al = (name, "") :: al;
			continue attrloop;
		}
		# skip whitespace
		if(++i == nb)
			break attrloop;
		c = int b[i];
		while(c<NCTYPE && int (ctype[c]&W)) {
			if(++i == nb)
				break attrloop;
			c = int b[i];
		}
		# gather value
		quote := 0;
		if(c == '\'' || c == '"') {
			quote = c;
			i++;
		}
		val := "";
		nv := 0;
	valloop:
		while(i < nb) {
			case charset{
			Latin1 =>
				c = int b[i++];
			UTF8 =>
				j: int;
				(c, j, nil) = sys->byte2char(b, i);
				i += j;
			}
			if(c == '>') {
				if(quote) {
					# c might be part of string (though not good style)
					# but if line ends before close quote, assume
					# there was an unmatched quote
					for(k := i; k < nb; k++) {
						c = int b[k];
						if(c == quote) {
							val[nv++] = '>';
							continue valloop;
						}
						if(c == '\n') {
							i--;
							break valloop;
						}
					}
				}
				i--;
				break valloop;
			}
			if(quote) {
				if(c == quote)
					break valloop;
				if(c == '\n')
					continue valloop;
				if(c == '\t' || c == '\r')
					c = ' ';
			}
			else {
				if(c<NCTYPE && int (ctype[c]&W))
					break valloop;
			}
			if(c == '&')
				(c, i) = ampersand(b, i);
			val[nv++] = c;
		}
		al = (name, val) :: al;
		if(i < nb)
			c = int b[i];
	}
	ans.attr = al;
	return (ans, i);
}

ampersand(b: array of byte, i: int): (int, int)
{
	starti := i;
	c := 0;
	nb := len b;
	if(i >= nb)
		return ('?', i);
	fnd := 0;
	ans := 0;
	if(int b[i] == '#'){
		i++;
		while(i<nb){
			d := int b[i];
			if(!(int (ctype[d]&D)))
				break;
			c = c*10 + d-'0';
			i++;
		}
		if(0<c && c<256) {
			if(c==160)
				c = ' ';   # non-breaking space
			ans = c;
			fnd = 1;
		}
	}
	else {
		s := "";
		k := 0;
		c = int b[i];
		if(int (ctype[c]&(L|U))) {
			while(i<nb) {
				c = int b[i];
				if(!(int (ctype[c]&(L|U|D|N))))
					break;
				s[k++] = c;
				i++;
			}
		}
		(fnd, ans) = T->lookup(chartab, s);
	}
	if(!fnd)
		return ('&', starti);
	if(i<nb && (int b[i]==';' || int b[i]=='\n'))
		i++;
	return (ans, i);
}

lowercase(b: array of byte, istart, iend: int): string
{
	l := "";
	j := 0;
	for(i:=istart; i<iend; i++) {
		c := int b[i];
		if(c < NCTYPE && int (ctype[c]&U))
			l[j] = c-'A'+'a';
		else
			l[j] = c;
		j++;
	}
	return l;
}

uppercase(s: string): string
{
	l := "";

	for(i:=0; i<len s; i++) {
		c := s[i];
		if(c < NCTYPE && int (ctype[c]&L))
			l[i] = c+'A'-'a';
		else
			l[i] = c;
	}
	return l;
}

attrvalue(attr: list of Attr, name: string): (int, string)
{
	while(attr != nil){
		a := hd attr;
		if(a.name == name)
			return (1, a.value); 
		attr = tl attr;
	}
	return (0, "");
}

globalattr(html: array of ref Lex, tag: int, attr: string): (int, string)
{
	for(i:=0; i<len html; i++)
		if(html[i].tag == tag)
			return attrvalue(html[i].attr, attr);
	return (0, "");
}

isbreak(h: array of ref Lex, i: int): int
{
	for(; i<len h; i++){
		case h[i].tag{
		Th1 or Th2 or Th3 or Th4 or Th5 or Th6 or
		Tbr or Tp or Tbody or Taddress or Tblockquote or
		Tul or Tdl or Tdir or Tmenu or Tol or Tpre or Thr or Tform =>
			return 1;
		Data =>
			return 0;
		}
	}
	return 0;
}

# for debugging
lex2string(l: ref Lex): string
{
	ans := "";
	tag := l.tag;
	if(tag == HTML->Data)
		ans = "'" + l.text + "'";
	else {
		ans = "<";
		if(tag >= RBRA) {
			tag -= RBRA;
			ans = ans + "/";
		}
		tname := T->revlookup(htmlstringtab, tag);
		if(tname != nil)
				ans = ans + uppercase(tname);
		for(al := l.attr; al != nil; al = tl al) {
			a := hd al;
			ans = ans + " " + a.name + "='" + a.value + "'";
		}
		ans = ans + ">";
	}
	return ans;
}
