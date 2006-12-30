implement Man2html;

include "sys.m";
	stderr: ref Sys->FD;
	sys: Sys;
	print, fprint, sprint: import sys;


include "bufio.m";

include "draw.m";

include "daytime.m";
	dt: Daytime;

include "string.m";
	str: String;

Man2html: module
{
	init:	fn(ctxt: ref Draw->Context, args: list of string);
};

Runeself: con 16r80;
false, true: con iota;

Troffspec: adt {
	name: string;
	value: string;
};

tspec := array [] of { Troffspec
	("ff", "ff"),
	("fi", "fi"),
	("fl", "fl"),
	("Fi", "ffi"),
	("ru", "_"),
	("em", "&#173;"),
	("14", "&#188;"),
	("12", "&#189;"),
	("co", "&#169;"),
	("de", "&#176;"),
	("dg", "&#161;"),
	("fm", "&#180;"),
	("rg", "&#174;"),
#	("bu", "*"),
	("bu", "•"),
	("sq", "&#164;"),
	("hy", "-"),
	("pl", "+"),
	("mi", "-"),
	("mu", "&#215;"),
	("di", "&#247;"),
	("eq", "="),
	("==", "=="),
	(">=", ">="),
	("<=", "<="),
	("!=", "!="),
	("+-", "&#177;"),
	("no", "&#172;"),
	("sl", "/"),
	("ap", "&"),
	("~=", "~="),
	("pt", "oc"),
	("gr", "GRAD"),
	("->", "->"),
	("<-", "<-"),
	("ua", "^"),
	("da", "v"),
	("is", "Integral"),
	("pd", "DIV"),
	("if", "oo"),
	("sr", "-/"),
	("sb", "(~"),
	("sp", "~)"),
	("cu", "U"),
	("ca", "(^)"),
	("ib", "(="),
	("ip", "=)"),
	("mo", "C"),
	("es", "&Oslash;"),
	("aa", "&#180;"),
	("ga", "`"),
	("ci", "O"),
	("L1", "Lucent"),
	("sc", "&#167;"),
	("dd", "++"),
	("lh", "<="),
	("rh", "=>"),
	("lt", "("),
	("rt", ")"),
	("lc", "|"),
	("rc", "|"),
	("lb", "("),
	("rb", ")"),
	("lf", "|"),
	("rf", "|"),
	("lk", "|"),
	("rk", "|"),
	("bv", "|"),
	("ts", "s"),
	("br", "|"),
	("or", "|"),
	("ul", "_"),
	("rn", " "),
	("*p", "PI"),
	("**", "*"),
};

	Entity: adt {
		 name: string;
		 value: int;
	};
	Entities: array of Entity;

Entities = array[] of {
		Entity( "&#161;",	'¡' ),
		Entity( "&#162;",	'¢' ),
		Entity( "&#163;",	'£' ),
		Entity( "&#164;",	'¤' ),
		Entity( "&#165;",	'¥' ),
		Entity( "&#166;",	'¦' ),
		Entity( "&#167;",	'§' ),
		Entity( "&#168;",	'¨' ),
		Entity( "&#169;",	'©' ),
		Entity( "&#170;",	'ª' ),
		Entity( "&#171;",	'«' ),
		Entity( "&#172;",	'¬' ),
		Entity( "&#173;",	'­' ),
		Entity( "&#174;",	'®' ),
		Entity( "&#175;",	'¯' ),
		Entity( "&#176;",	'°' ),
		Entity( "&#177;",	'±' ),
		Entity( "&#178;",	'²' ),
		Entity( "&#179;",	'³' ),
		Entity( "&#180;",	'´' ),
		Entity( "&#181;",	'µ' ),
		Entity( "&#182;",	'¶' ),
		Entity( "&#183;",	'·' ),
		Entity( "&#184;",	'¸' ),
		Entity( "&#185;",	'¹' ),
		Entity( "&#186;",	'º' ),
		Entity( "&#187;",	'»' ),
		Entity( "&#188;",	'¼' ),
		Entity( "&#189;",	'½' ),
		Entity( "&#190;",	'¾' ),
		Entity( "&#191;",	'¿' ),
		Entity( "&Agrave;",	'À' ),
		Entity( "&Aacute;",	'Á' ),
		Entity( "&Acirc;",	'Â' ),
		Entity( "&Atilde;",	'Ã' ),
		Entity( "&Auml;",	'Ä' ),
		Entity( "&Aring;",	'Å' ),
		Entity( "&AElig;",	'Æ' ),
		Entity( "&Ccedil;",	'Ç' ),
		Entity( "&Egrave;",	'È' ),
		Entity( "&Eacute;",	'É' ),
		Entity( "&Ecirc;",	'Ê' ),
		Entity( "&Euml;",	'Ë' ),
		Entity( "&Igrave;",	'Ì' ),
		Entity( "&Iacute;",	'Í' ),
		Entity( "&Icirc;",	'Î' ),
		Entity( "&Iuml;",	'Ï' ),
		Entity( "&ETH;",	'Ð' ),
		Entity( "&Ntilde;",	'Ñ' ),
		Entity( "&Ograve;",	'Ò' ),
		Entity( "&Oacute;",	'Ó' ),
		Entity( "&Ocirc;",	'Ô' ),
		Entity( "&Otilde;",	'Õ' ),
		Entity( "&Ouml;",	'Ö' ),
		Entity( "&215;",	'×' ),
		Entity( "&Oslash;",	'Ø' ),
		Entity( "&Ugrave;",	'Ù' ),
		Entity( "&Uacute;",	'Ú' ),
		Entity( "&Ucirc;",	'Û' ),
		Entity( "&Uuml;",	'Ü' ),
		Entity( "&Yacute;",	'Ý' ),
		Entity( "&THORN;",	'Þ' ),
		Entity( "&szlig;",	'ß' ),
		Entity( "&agrave;",	'à' ),
		Entity( "&aacute;",	'á' ),
		Entity( "&acirc;",	'â' ),
		Entity( "&atilde;",	'ã' ),
		Entity( "&auml;",	'ä' ),
		Entity( "&aring;",	'å' ),
		Entity( "&aelig;",	'æ' ),
		Entity( "&ccedil;",	'ç' ),
		Entity( "&egrave;",	'è' ),
		Entity( "&eacute;",	'é' ),
		Entity( "&ecirc;",	'ê' ),
		Entity( "&euml;",	'ë' ),
		Entity( "&igrave;",	'ì' ),
		Entity( "&iacute;",	'í' ),
		Entity( "&icirc;",	'î' ),
		Entity( "&iuml;",	'ï' ),
		Entity( "&eth;",	'ð' ),
		Entity( "&ntilde;",	'ñ' ),
		Entity( "&ograve;",	'ò' ),
		Entity( "&oacute;",	'ó' ),
		Entity( "&ocirc;",	'ô' ),
		Entity( "&otilde;",	'õ' ),
		Entity( "&ouml;",	'ö' ),
		Entity( "&247;",	'÷' ),
		Entity( "&oslash;",	'ø' ),
		Entity( "&ugrave;",	'ù' ),
		Entity( "&uacute;",	'ú' ),
		Entity( "&ucirc;",	'û' ),
		Entity( "&uuml;",	'ü' ),
		Entity( "&yacute;",	'ý' ),
		Entity( "&thorn;",	'þ' ),
		Entity( "&yuml;",	'ÿ' ),		# &#255;

		Entity( "&#SPACE;",	' ' ),
		Entity( "&#RS;",	'\n' ),
		Entity( "&#RE;",	'\r' ),
		Entity( "&quot;",	'"' ),
		Entity( "&amp;",	'&' ),
		Entity( "&lt;",	'<' ),
		Entity( "&gt;",	'>' ),

		Entity( "CAP-DELTA",	'Δ' ),
		Entity( "ALPHA",	'α' ),
		Entity( "BETA",	'β' ),
		Entity( "DELTA",	'δ' ),
		Entity( "EPSILON",	'ε' ),
		Entity( "THETA",	'θ' ),
		Entity( "MU",		'μ' ),
		Entity( "PI",		'π' ),
		Entity( "TAU",	'τ' ),
		Entity( "CHI",	'χ' ),

		Entity( "<-",		'←' ),
		Entity( "^",		'↑' ),
		Entity( "->",		'→' ),
		Entity( "v",		'↓' ),
		Entity( "!=",		'≠' ),
		Entity( "<=",		'≤' ),
		Entity( nil, 0 ),
};


Hit: adt {
	glob: string;
	chap: string;
	mtype: string;
	page: string;
};

Lnone, Lordered, Lunordered, Ldef, Lother: con iota;	# list types

Chaps: adt {
	name: string;
	primary: int;
};

Types: adt {
	name: string;
	desc: string;
};


# having two separate flags here allows for inclusion of old-style formatted pages
# under a new-style three-level tree
Oldstyle: adt {
	names: int;	# two-level directory tree?
	fmt: int;		# old internal formats: e.g., "B" font means "L"; name in .TH in all caps
};

Href: adt {
	title: string;
	chap: string;
	mtype: string;
	man: string;
};

# per-thread global data
Global: adt {
	bufio: Bufio;
	bin: ref Bufio->Iobuf;
	bout: ref Bufio->Iobuf;
	topname: string;		# name of the top level categories in the manual
	chaps: array of Chaps;	# names of top-level partitions of this manual
	types: array of Types;	# names of second-level partitions
	oldstyle: Oldstyle;
	mantitle: string;
	mandir: string;
	thisone: Hit;		# man page we're displaying
	mtime: int;			# last modification time of thisone
	href: Href;			# hrefs of components of this man page
	hits: array of Hit;
	nhits: int;
	list_type: int;
	pm: string;			# proprietary marking
	def_goobie: string;	# deferred goobie
	sop: int;			# output at start of paragraph?
	sol: int;			# input at start of line?
	broken: int;		# output at a break?
	fill: int;			# in fill mode?
 	pre: int;			# in PRE block?
	example: int;		# an example active?
	ipd: int;			# emit inter-paragraph distance?
	indents: int;
	hangingdt: int;
	curfont: string;		# current font
	prevfont: string;		# previous font
	lastc: int;			# previous char from input scanner
	def_sm: int;		# amount of deferred "make smaller" request

	mk_href_chap: fn(g: self ref Global, chap: string);
	mk_href_man: fn(g: self ref Global, man: string, oldstyle: int);
	mk_href_mtype: fn(g: self ref Global, chap, mtype: string);
	dobreak: fn(g: self ref Global);
	print: fn(g: self ref Global, s: string);
	softbr: fn(g: self ref Global): string;
	softp: fn(g: self ref Global): string;
};


usage()
{
	sys->fprint(stderr, "Usage: man2html file [section]\n");
	raise "fail:usage";
}


init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	str = load String String->PATH;
	dt = load Daytime Daytime->PATH;
	g := Global_init();
	if(args != nil)
		args = tl args;
	if(args == nil)
		usage();
	page := hd args;
	args = tl args;
	section := "1";
	if(args != nil)
		section = hd args;
	hit := Hit ("", "man", section, page);
	domanpage(g, hit);
	g.bufio->g.bout.flush();
}

# remove markup from a string
# doesn't handle nested/quoted delimiters
demark(s: string): string
{
	t: string;
	clean := true;
	for (i := 0; i < len s; i++) {
		case s[i] {
		'<' =>
			clean = false;
		'>' =>
			clean = true;
		* =>
			if (clean)
				t[len t] = s[i];
		}		
	}
	return t;
}


#
#  Convert an individual man page to HTML and output.
#
domanpage(g: ref Global, man: Hit)
{
	file := man.page;
	g.bin = g.bufio->open(file, Bufio->OREAD);
	g.bout = g.bufio->fopen(sys->fildes(1), Bufio->OWRITE);
	if (g.bin == nil) {
		fprint(stderr, "Cannot open %s: %r\n", file);
		return;
	}
	(err, info) := sys->fstat(g.bin.fd);
	if (! err) {
		g.mtime = info.mtime;
	}
	g.thisone = man;
	while ((p := getnext(g)) != nil) {
		c := p[0];
		if (c == '.' && g.sol) {
			if (g.pre) {
				g.print("</PRE>");
				g.pre = false;
			}
			dogoobie(g, false);
			dohangingdt(g);
		} else if (g.def_goobie != nil || g.def_sm != 0) {
			g.bufio->g.bin.ungetc();
			dogoobie(g, true);
		} else if (c == '\n') {
			g.print(p);
			dohangingdt(g);
		} else
			g.print(p);
	}
	if (g.pm != nil) {
		g.print("<BR><BR><BR><FONT SIZE=-2><CENTER>\n");
		g.print(g.pm);
		g.print("<BR></CENTER></FONT>\n");
	}
	closeall(g, 0);
	rev(g, g.bin);
}

dogoobie(g: ref Global, deferred: int)
{
	# read line, translate special chars
	line: string;
	while ((token := getnext(g)) != "\n") {
		if (token == nil)
			return;
		line += token;
	}

	# parse into arguments
	argl, rargl: list of string;	# create reversed version, then invert
	while ((line = str->drop(line, " \t")) != nil)
		if (line[0] == '"') {
			(token, line) = split(line[1:], '"');
			rargl = token :: rargl;
		} else {
			(token, line) = str->splitl(line, " \t");
			rargl = token :: rargl;
		}

	if (rargl == nil && !deferred)
		return;
	for ( ; rargl != nil; rargl = tl rargl)
		argl = hd rargl :: argl;

	def_sm := g.def_sm;
	if (deferred && def_sm > 0) {
		g.print(sprint("<FONT SIZE=-%d>", def_sm));
		if (g.def_goobie == nil)
			argl = "dS" :: argl;	# dS is our own local creation
	}

	subgoobie(g, argl);

	if (deferred && def_sm > 0) {
		g.def_sm = 0;
		g.print("</FONT>");
	}
}

subgoobie(g: ref Global, argl: list of string)
{
	if (g.def_goobie != nil) {
		argl = g.def_goobie :: argl;
		g.def_goobie = nil;
		if (tl argl == nil)
			return;
	}

	# the command part is at most two characters, but may be concatenated with the first arg
	cmd := hd argl;
	argl = tl argl;
	if (len cmd > 2) {
		cmd = cmd[0:2];
		argl =  cmd[2:] :: argl;
	}

	case cmd {

	"B" or "I" or "L" or "R" =>
		font(g, cmd, argl);		# "R" macro implicitly generated by deferred R* macros

	"BI" or "BL" or "BR" or
	"IB" or "IL" or
	"LB" or "LI" or
	"RB" or "RI" or "RL" =>
		altfont(g, cmd[0:1], cmd[1:2], argl, true);

	"IR" or "LR" =>
		anchor(g, cmd[0:1], cmd[1:2], argl);		# includes man page refs ("IR" is old style, "LR" is new)

	"dS" =>
		printargs(g, argl);
		g.print("\n");

	"1C" or "2C" or "DT" or "TF" =>	 # ignore these
		return;

	"P" or "PP" or "LP" =>
			g_PP(g);

	"EE" =>	g_EE(g);
	"EX" =>	g_EX(g);
	"HP" =>	g_HP_TP(g, 1);
	"IP" =>	g_IP(g, argl);
	"PD" =>	g_PD(g, argl);
	"PM" =>	g_PM(g, argl);
	"RE" =>	g_RE(g);
	"RS" =>	g_RS(g);
	"SH" =>	g_SH(g, argl);
	"SM" =>	g_SM(g, argl);
	"SS" =>	g_SS(g, argl);
	"TH" =>	g_TH(g, argl);
	"TP" =>	g_HP_TP(g, 3);

	"br" =>	g_br(g);
	"sp" =>	g_sp(g, argl);
	"ti" =>	g_br(g);
	"nf" =>	g_nf(g);
	"fi" =>	g_fi(g);
	"ft" =>	g_ft(g, argl);

	* =>		return;		# ignore unrecognized commands
	}

}

g_br(g: ref Global)
{
	if (g.hangingdt != 0) {
		g.print("<DD>");
		g.hangingdt = 0;
	} else if (g.fill && ! g.broken)
		g.print("<BR>\n");
	g.broken = true;
}

g_EE(g: ref Global)
{
	g.print("</PRE>\n");
	g.fill = true;
	g.broken = true;
	g.example = false;
}

g_EX(g: ref Global)
{
	g.print("<PRE>");
	if (! g.broken)
		g.print("\n");
	g.sop = true;
	g.fill = false;
	g.broken = true;
	g.example = true;
}

g_fi(g: ref Global)
{
	if (g.fill)
		return;
	g.fill = true;
	g.print("<P style=\"display: inline; white-space: normal\">\n");
	g.broken = true;
	g.sop = true;
}

g_ft(g: ref Global, argl: list of string)
{
	font: string;
	arg: string;

	if (argl == nil)
		arg = "P";
	else
		arg = hd argl;

	if (g.curfont != nil)
		g.print(sprint("</%s>", g.curfont));

	case arg {
	"2" or "I" =>
		font = "I";
	"3" or "B" =>
		font = "B";
	"5" or "L" =>
		font = "TT";
	"P" =>
		font = g.prevfont;
	* =>
		font = nil;
	}
	g.prevfont = g.curfont;
	g.curfont = font;
	if (g.curfont != nil)
		if (g.fill)
			g.print(sprint("<%s>", g.curfont));
		else
			g.print(sprint("<%s style=\"white-space: pre\">", g.curfont));
}

# level == 1 is a .HP; level == 3 is a .TP
g_HP_TP(g: ref Global, level: int)
{
	case g.list_type {
	Ldef =>
		if (g.hangingdt != 0)
			g.print("<DD>");
		g.print(g.softbr() + "<DT>");
	* =>
		closel(g);
		g.list_type = Ldef;
		g.print("<DL compact>\n" + g.softbr() + "<DT>");
	}
	g.hangingdt = level;
	g.broken = true;
}

g_IP(g: ref Global, argl: list of string)
{
	case g.list_type {

	Lordered or Lunordered or Lother =>
		;	# continue with an existing list

	* =>
		# figure out the type of a new list and start it
		closel(g);
		arg := "";
		if (argl != nil)
			arg = hd argl;
		case arg {
			"1" or "i" or "I" or "a" or "A" =>
				g.list_type = Lordered;
				g.print(sprint("<OL type=%s>\n", arg));
			"*" or "•" or "&#8226;" =>
				g.list_type = Lunordered;
				g.print("<UL type=disc>\n");
			"○" or "&#9675;"=>
				g.list_type = Lunordered;
				g.print("<UL type=circle>\n");
			"□" or "&#9633;" =>
				g.list_type = Lunordered;
				g.print("<UL type=square>\n");
			* =>
				g.list_type = Lother;
				g.print("<DL compact>\n");
			}
	}

	# actually do this list item
	case g.list_type {
	Lother =>
		g.print(g.softp());	# make sure there's space before each list item
		if (argl != nil) {
			g.print("<DT>");
			printargs(g, argl);
		}
		g.print("\n<DD>");

	Lordered or Lunordered =>
		g.print(g.softp() + "<LI>");
	}
	g.broken = true;
}

g_nf(g: ref Global)
{
	if (! g.fill)
		return;
	g.fill = false;
	g.print("<PRE>\n");
	g.broken = true;
	g.sop = true;
	g.pre = true;
}

g_PD(g: ref Global, argl: list of string)
{
	if (len argl == 1 && hd argl == "0")
		g.ipd = false;
	else
		g.ipd = true;
}

g_PM(g: ref Global, argl: list of string)
{
	code := "P";
	if (argl != nil)
		code = hd argl;
	case code {
	* =>		# includes "1" and "P"
		g.pm = "<B>Lucent Technologies - Proprietary</B>\n" +
			"<BR>Use pursuant to Company Instructions.\n";
	"2" or "RS" =>
		g.pm = "<B>Lucent Technologies - Proprietary (Restricted)</B>\n" +
			"<BR>Solely for authorized persons having a need to know\n" +
			"<BR>pursuant to Company Instructions.\n";
	"3" or "RG" =>
		g.pm = "<B>Lucent Technologies - Proprietary (Registered)</B>\n" +
			"<BR>Solely for authorized persons having a need to know\n" +
			"<BR>and subject to cover sheet instructions.\n";
	"4" or "CP" =>
		g.pm = "SEE PROPRIETARY NOTICE ON COVER PAGE\n";
	"5" or "CR" =>
		g.pm = "Copyright xxxx Lucent Technologies\n" +	# should fill in the year from the date register
			"<BR>All Rights Reserved.\n";
	"6" or "UW" =>
		g.pm = "THIS DOCUMENT CONTAINS PROPRIETARY INFORMATION OF\n" +
			"<BR>LUCENT TECHNOLOGIES INC. AND IS NOT TO BE DISCLOSED OR USED EXCEPT IN\n" +
			"<BR>ACCORDANCE WITH APPLICABLE AGREEMENTS.\n" +
			"<BR>Unpublished & Not for Publication\n";
	}
}

g_PP(g: ref Global)
{
	closel(g);
	reset_font(g);
	p := g.softp();
	if (p != nil)
		g.print(p);
	g.sop = true;
	g.broken = true;
}

g_RE(g: ref Global)
{
	g.print("</DL>\n");
	g.indents--;
	g.broken = true;
}

g_RS(g: ref Global)
{
	g.print("<DL>\n<DT><DD>");
	g.indents++;
	g.broken = true;
}

g_SH(g: ref Global, argl: list of string)
{
	closeall(g, 1);		# .SH is top-level list item
	if (g.example)
		g_EE(g);
	if (g.fill && ! g.sop)
		g.print("<P>");
	g.print("<DT><H4>");
	printargs(g, argl);
	g.print("</H4>\n");
	g.print("<DD>\n");
	g.sop = true;
	g.broken = true;
}

g_SM(g: ref Global, argl: list of string)
{
	g.def_sm++;		# can't use def_goobie, lest we collide with a deferred font macro
	if (argl == nil)
		return;
	g.print(sprint("<FONT SIZE=-%d>", g.def_sm));
	printargs(g, argl);
	g.print("</FONT>\n");
	g.def_sm = 0;
}

g_sp(g: ref Global, argl: list of string)
{
	if (g.sop && g.fill)
		return;
	count := 1;
	if (argl != nil) {
		rcount := real hd argl;
		count = int rcount;	# may be 0 (e.g., ".sp .5")
		if (count == 0 && rcount > 0.0)
			count = 1;		# force whitespace for fractional lines
	}
	g.dobreak();
	for (i := 0; i < count; i++)
		g.print("&nbsp;<BR>\n");
	g.broken = true;
	g.sop = count > 0;
}

g_SS(g: ref Global, argl: list of string)
{
	closeall(g, 1);
	g.indents++;
	g.print(g.softp() + "<DL><DT><FONT SIZE=3><B>");
	printargs(g, argl);
	g.print("</B></FONT>\n");
	g.print("<DD>\n");
	g.sop = true;
	g.broken = true;
}

g_TH(g: ref Global, argl: list of string)
{
	if (g.oldstyle.names && len argl > 2)
		argl = hd argl :: hd tl argl :: nil;	# ignore extra .TH args on pages in oldstyle trees
	case len argl {
	0 =>
		g.oldstyle.fmt = true;
		title(g, sprint("%s", g.href.title), false);
	1 =>
		g.oldstyle.fmt = true;
		title(g, sprint("%s", hd argl), false);	# any pages use this form?
	2 =>
		g.oldstyle.fmt = true;
		g.thisone.page = hd argl;
		g.thisone.mtype = hd tl argl;
		g.mk_href_man(hd argl, true);
		g.mk_href_mtype(nil, hd tl argl);
		title(g, sprint("%s(%s)", g.href.man, g.href.mtype), false);
	* =>
		g.oldstyle.fmt = false;
		chap := hd tl tl argl;
		g.mk_href_chap(chap);
		g.mk_href_man(hd argl, false);
		g.mk_href_mtype(chap, hd tl argl);
		title(g, sprint("%s/%s/%s(%s)", g.href.title, g.href.chap, g.href.man, g.href.mtype), false);
	}
	g.print("[<a href=\"../index.html\">manual index</a>]");
	g.print("[<a href=\"INDEX.html\">section index</a>]<p>");
	g.print("<DL>\n");	# whole man page is just one big list
	g.indents = 1;
	g.sop = true;
	g.broken = true;
}

dohangingdt(g: ref Global)
{
	case g.hangingdt {
	3 =>
		g.hangingdt--;
	2 =>
		g.print("<DD>");
		g.hangingdt = 0;
		g.broken = true;
	}
}

# close a list, if there's one active
closel(g: ref Global)
{
	case g.list_type {
	Lordered =>
		g.print("</OL>\n");
		g.broken = true;
	Lunordered =>
		g.print("</UL>\n");
		g.broken = true;
	Lother or Ldef =>
		g.print("</DL>\n");
		g.broken = true;
	}
	g.list_type = Lnone;
}

closeall(g: ref Global, level: int)
{
	closel(g);
	reset_font(g);
	while (g.indents > level) {
		g.indents--;
		g.print("</DL>\n");
		g.broken = true;
	}
}

#
# Show last revision date for a file.
#
rev(g: ref Global, filebuf: ref Bufio->Iobuf)
{
	if (g.mtime == 0) {
		(err, info) := sys->fstat(filebuf.fd);
		if (! err)
			g.mtime = info.mtime;
	}
	if (g.mtime != 0) {
		g.print("<P><TABLE width=\"100%\" border=0 cellpadding=10 cellspacing=0 bgcolor=\"#E0E0E0\">\n");
		g.print("<TR>");
		g.print(sprint("<TD align=left><FONT SIZE=-1>"));
		g.print(sprint("%s(%s)", g.thisone.page, g.thisone.mtype));
		g.print("</FONT></TD>\n");
		g.print(sprint("<TD align=right><FONT SIZE=-1><I>Rev:&nbsp;&nbsp;%s</I></FONT></TD></TR></TABLE>\n",
			dt->text(dt->gmt(g.mtime))));
	}
}

#
# Some font alternation macros are references to other man pages;
# detect them (second arg contains balanced parens) and make them into hot links.
#
anchor(g: ref Global, f1, f2: string, argl: list of string)
{
	final := "";
	link := false;
	if (len argl == 2) {
		(s, e) := str->splitl(hd tl argl, ")");
		if (str->prefix("(", s) && e != nil) {
			# emit href containing search for target first
			# if numeric, do old style
			link = true;
			file := hd argl;
			(chap, man) := split(httpunesc(file), '/');
			if (man == nil) {
				# given no explicit chapter prefix, use current chapter
				man = chap;
				chap = g.thisone.chap;
			}
			mtype := s[1:];
			if (mtype == nil)
				mtype = "-";
			(n, toks) := sys->tokenize(mtype, ".");	# Fix section 10
			if (n > 1) mtype = hd toks;
			g.print(sprint("<A href=\"../%s/%s.html\">", mtype, fixlink(man)));

			#
			# now generate the name the user sees, with terminal punctuation
			# moved after the closing </A>.
			#
			if (len e > 1)
				final = e[1:];
			argl = hd argl :: s + ")" :: nil;
		}
	}
	altfont(g, f1, f2, argl, false);
	if (link) {
		g.print("</A>");
		font(g, f2, final :: nil);
	} else
		g.print("\n");
}


#
# Fix up a link
#

fixlink(l: string): string
{
	ll := str->tolower(l);
	if (ll == "copyright") ll = "1" + ll;
	(a, b) := str->splitstrl(ll, "intro");
	if (len b == 5) ll = a + "0" + b;
	return ll;
}


#
# output argl in font f
#
font(g: ref Global, f: string, argl: list of string)
{
	if (argl == nil) {
		g.def_goobie = f;
		return;
	}
	case f {
	"L" => 	f = "TT";
	"R" =>	f = nil;
	}
	if (f != nil) 			# nil == default (typically Roman)
		g.print(sprint("<%s>", f));
	printargs(g, argl);
	if (f != nil)
		g.print(sprint("</%s>", f));
	g.print("\n");
	g.prevfont = f;
}

#
# output concatenated elements of argl, alternating between fonts f1 and f2
#
altfont(g: ref Global, f1, f2: string, argl: list of string, newline: int)
{
	reset_font(g);
	if (argl == nil) {
		g.def_goobie = f1;
		return;
	}
	case f1 {
	"L" =>	f1 = "TT";
	"R" =>	f1 = nil;
	}
	case f2 {
	"L" =>	f2 = "TT";
	"R" =>	f2 = nil;
	}
	f := f1;
	for (; argl != nil; argl = tl argl) {
		if (f != nil)
			g.print(sprint("<%s>%s</%s>", f, hd argl, f));
		else
			g.print(hd argl);
		if (f == f1)
			f = f2;
		else
			f = f1;
	}
	if (newline)
		g.print("\n");
	g.prevfont = f;
}

# not yet implemented
map_font(nil: ref Global, nil: string)
{
}

reset_font(g: ref Global)
{
	if (g.curfont != nil) {
		g.print(sprint("</%s>", g.curfont));
		g.prevfont = g.curfont;
		g.curfont = nil;
	}
}

printargs(g: ref Global, argl: list of string)
{
	for (; argl != nil; argl = tl argl)
		if (tl argl != nil)
			g.print(hd argl + " ");
		else
			g.print(hd argl);
}

# any parameter can be nil
addhit(g: ref Global, chap, mtype, page: string)
{
	# g.print(sprint("Adding %s / %s (%s) . . .", chap, page, mtype));		# debug
	# always keep a spare slot at the end
	if (g.nhits >= len g.hits - 1)
		g.hits = (array[len g.hits + 32] of Hit)[0:] = g.hits;
	g.hits[g.nhits].glob = chap + " " + mtype + " " + page;
	g.hits[g.nhits].chap = chap;
	g.hits[g.nhits].mtype = mtype;
	g.hits[g.nhits++].page = page;
}

Global.dobreak(g: self ref Global)
{
	if (! g.broken) {
		g.broken = true;
		g.print("<BR>\n");
	}
}

Global.print(g: self ref Global, s: string)
{
	g.bufio->g.bout.puts(s);
	if (g.sop || g.broken) {
		# first non-white space, non-HTML we print takes us past the start of the paragraph & line
		# (or even white space, if we're in no-fill mode)
		for (i := 0; i < len s; i++) {
			case s[i] {
			'<' =>
				while (++i < len s && s[i] != '>')
					;
				continue;
			' ' or '\t' or '\n' =>
				if (g.fill)
					continue;
			}
			g.sop = false;
			g.broken = false;
			break;
		}
	}
}

Global.softbr(g: self ref Global): string
{
	if (g.broken)
		return nil;
	g.broken = true;
	return "<BR>";
}

# provide a paragraph marker, unless we're already at the start of a section
Global.softp(g: self ref Global): string
{
	if (g.sop)
		return nil;
	else if (! g.ipd)
		return "<BR>";
	if (g.fill)
		return "<P>";
	else
		return "<P style=\"white-space: pre\">";
}

#
# Get next logical character.  Expand it with escapes.
#
getnext(g: ref Global): string
{
	iob := g.bufio;
	Iobuf: import iob;

	font: string;
	token: string;
	bin := g.bin;

	g.sol = (g.lastc == '\n');

	c := bin.getc();
	if (c < 0)
		return nil;
	g.lastc = c;
	if (c >= Runeself) {
		for (i := 0;  i < len Entities; i++)
			if (Entities[i].value == c)
				return Entities[i].name;
		return sprint("&#%d;", c);
	}
	case c {
	'<' =>
		return "&lt;";
	'>' =>
		return "&gt;";
	'\\' =>
		c = bin.getc();
		if (c < 0)
			return nil;
		g.lastc = c;
		case c {

		# chars to ignore
		'|' or '&' or '^' =>
			return getnext(g);

		# ignore arg
		'k' =>
			nil = bin.getc();
			return getnext(g);

		# defined strings
		'*' =>
			case bin.getc() {
			'R' =>
				return "&#174;";
			}
			return getnext(g);

		# special chars
		'(' =>
			token[0] = bin.getc();
			token[1] = bin.getc();
			for (i := 0; i < len tspec; i++)
				if (token == tspec[i].name)
					return tspec[i].value;
			return "&#191;";
		'c' =>
			c = bin.getc();
			if (c < 0)
				return nil;
			else if (c == '\n') {
				g.lastc = c;
				g.sol = true;
				token[0] = bin.getc();
				return token;
			}
			# DEBUG: should there be a "return xxx" here?
		'e' =>
			return "\\";
		'f' =>
			g.lastc = c = bin.getc();
			if (c < 0)
				return nil;
			case c {
			'2' or 	'I' =>
				font = "I";
			'3' or 	'B' =>
				font = "B";
			'5' or 	'L' =>
				font = "TT";
			'P' =>
				font = g.prevfont;
			* =>					# includes '1' and 'R'
				font = nil;
			}
# There are serious problems with this. We don't know the fonts properly at this stage.
#			g.prevfont = g.curfont;
#			g.curfont = font;
#			if (g.prevfont != nil)
#				token = sprint("</%s>", g.prevfont);
#			if (g.curfont != nil)
#				token += sprint("<%s>", g.curfont);
			if (token == nil)
				return " ";	# shouldn't happen - maybe a \fR inside a font macro - just do something!
			return token;
		's' =>
			sign := '+';
			size := 0;
			relative := false;
		getsize:
			for (;;) {
				c = bin.getc();
				if (c < 0)
					return nil;
				case c {
				'+' =>
					relative = true;
				'-' =>
					sign = '-';
					relative = true;
				'0' to '9' =>
					size = size * 10 + (c - '0');
				* =>
					bin.ungetc();
					break getsize;
				}
				g.lastc = c;
			}
			if (size == 0)
				token = "</FONT>";
			else if (relative)
				token = sprint("<FONT SIZE=%c%d>", sign, size);
			else
				token = sprint("<FONT SIZE=%d>", size);
			return token;
		}
	}
	token[0] = c;
	return token;
}

#
# Return strings before and after the left-most instance of separator;
# (s, nil) if no match or separator is last char in s.
#
split(s: string, sep: int): (string, string)
{
	for (i := 0; i < len s; i++)
		if (s[i] == sep)
			return (s[:i], s[i+1:]);	# s[len s:] is a valid slice, with value == nil
 	return (s, nil);
}

Global_init(): ref Global
{
	g := ref Global;
	g.bufio = load Bufio Bufio->PATH;
	g.chaps = array[20] of Chaps;
	g.types = array[20] of Types;
	g.mantitle = "";
	g.href.title = g.mantitle;		# ??
	g.mtime = 0;
	g.nhits = 0;
	g.oldstyle.names = false;
	g.oldstyle.fmt = false;
	g.topname = "System";
	g.list_type = Lnone;
	g.def_sm = 0;
	g.hangingdt = 0;
	g.indents = 0;
	g.sop = true;
	g.broken = true;
	g.ipd = true;
	g.fill = true;
	g.example = false;
	g.pre = false;
	g.lastc = '\n';
	return g;
}

Global.mk_href_chap(g: self ref Global, chap: string)
{
	if (chap != nil)
		g.href.chap = sprint("<A href=\"%s/%s?man=*\"><B>%s</B></A>", g.mandir, chap, chap);
}

Global.mk_href_man(g: self ref Global, man: string, oldstyle: int)
{
	rman := man;
	if (oldstyle)
		rman = str->tolower(man);	# compensate for tradition of putting titles in all CAPS
	g.href.man = sprint("<A href=\"%s?man=%s\"><B>%s</B></A>", g.mandir, rman, man);
}

Global.mk_href_mtype(g: self ref Global, chap, mtype: string)
{
	g.href.mtype = sprint("<A href=\"%s/%s/%s\"><B>%s</B></A>", g.mandir, chap, mtype, mtype);
}

# We assume that anything >= Runeself is already in UTF.
#
httpunesc(s: string): string
{
	t := "";
	for (i := 0; i < len s; i++) {
		c := s[i];
		if (c == '&' && i + 1 < len s) {
			(char, rem) := str->splitl(s[i+1:], ";");
			if (rem == nil)
				break;	# require the terminating ';'
			if (char == nil)
				continue;
			if (char[0] == '#' && len char > 1) {
				c = int char[1:];
				i += len char;
				if (c < 256 && c >= 161) {
					t[len t] = Entities[c-161].value;
					continue;
				}
			} else {
				for (j := 0; j < len Entities; j++)
					if (Entities[j].name == char)
						break;
				if (j < len Entities) {
					i += len char;
					t[len t] = Entities[j].value;
					continue;
				}
			}
		}
		t[len t] = c;
	}
	return t;
}



title(g: ref Global, t: string, search: int)
{
	if(search)
		;	# not yet used
	g.print("<HTML><HEAD>\n");
	g.print(sprint("<TITLE>Inferno's %s</TITLE>\n", demark(t)));
	g.print("</HEAD>\n");
	g.print("<BODY bgcolor=\"#FFFFFF\">\n");

}
