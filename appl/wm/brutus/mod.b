implement Brutusext;

# <Extension mod file>
# For module descriptions (in book)

Name:	con "Brutus mod";

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Context, Font: import draw;

include	"bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

include "string.m";
	S : String;

include	"brutus.m";
	Size8, Index, Roman, Italic, Bold, Type, NFONT, NSIZE: import Brutus;

include	"brutusext.m";

Mstring: adt
{
	s: string;
	style: int;
	indexed: int;
	width: int;
	next: cyclic ref Mstring;
};

fontname :=  array[NFONT] of {
	"/fonts/lucidasans/unicode.7.font",
	"/fonts/lucidasans/italiclatin1.7.font",
	"/fonts/lucidasans/boldlatin1.7.font",
	"/fonts/lucidasans/typelatin1.7.font",
	};

fontswitch :=  array[NFONT] of {
	"\\fontseries{m}\\rmfamily ",
	"\\itshape ",
	"\\fontseries{b}\\rmfamily ",
	"\\fontseries{mc}\\ttfamily ",
	};

fontref := array[NFONT] of ref Font;

LEFTCHARS: con 45;
LEFTPIX: con LEFTCHARS*7;	# 7 is width of lucidasans/typelatin1.7 chars

init(s: Sys, d: Draw, b: Bufio, t: Tk, w: Tkclient)
{
	sys = s;
	draw = d;
	bufio = b;
	tk = t;
	tkclient = w;
	S = load String String->PATH;
}

create(parent: string, t: ref Tk->Toplevel, name, args: string): string
{
	(spec, err) := getspec(parent, args);
	if(err != nil)
		return err;
	n := len spec;
	if(n == 0)
		return "empty spec";
	d := t.image.display;
	for(i:=0; i < NFONT; i++) {
		if(i == Bold || fontref[i] != nil)
			continue;
		fontref[i] = Font.open(d, fontname[i]);
		if(fontref[i] == nil)
			return sys->sprint("can't open font %s: %r\n", fontname[i]);
	}
	(nil, nil, rw, nil) := measure(spec, 1);
	lw := LEFTPIX;
	wd := lw + rw;
	fnt := fontref[Roman];
	ht := n * fnt.height;
	err = tk->cmd(t, "canvas " + name + " -width " + string wd
			+ " -height " + string ht
			+ " -font " + fontname[Type]);
	if(len err > 0 && err[0] == '!')
		return "problem creating canvas";
	y := 0;
	xl := 0;
	xr := lw;
	for(l := spec; l != nil; l = tl l) {
		(lm, rm) := hd l;
		canvmstring(t, name, lm, xl, y);
		canvmstring(t, name, rm, xr, y);
		y += fnt.height;
	}
	tk->cmd(t, "update");
	return "";
}

canvmstring(t: ref Tk->Toplevel, canv: string, m: ref Mstring, x, y: int)
{
	# assume fonts all have same ascent
	while(m != nil) {
		pos := string x + " " + string y;
		font := "";
		if(m.style != Type)
			font = " -font " + fontname[m.style];
		e := tk->cmd(t, canv + " create text " + pos + " -anchor nw "
			+ font + " -text '" + m.s);
		x += m.width;
		m = m.next;
	}
}

getspec(parent, args: string) : (list of (ref Mstring, ref Mstring), string)
{
	(n, argl) := sys->tokenize(args, " ");
	if(n != 1)
		return (nil, "usage: " + Name + " file");
	b := bufio->open(fullname(parent, hd argl), Sys->OREAD);
	if(b == nil)
		return (nil, sys->sprint("can't open %s, the error was: %r", hd argl));
	mm : list of (ref Mstring, ref Mstring) = nil;
	for(;;) {
		s := b.gets('\n');
		if(s == "")
			break;
		(nf, fl) := sys->tokenize(s, "	");
		if(nf == 0)
			mm = (nil, nil) :: mm;
		else {
			sleft := "";
			sright := "";
			if(nf == 1) {
				f := hd fl;
				if(s[0] == '\t')
					sright = f;
				else
					sleft = f;
			}
			else {
				sleft = hd fl;
				sright = hd tl fl;
			}
			mm = (tom(sleft, Type, Roman, 1), tom(sright, Italic, Type, 0)) :: mm;
		}
	}
	ans : list of (ref Mstring, ref Mstring) = nil;
	while(mm != nil) {
		ans = hd mm :: ans;
		mm = tl mm;
	}
	return (ans, "");
}

tom(str: string, defstyle, altstyle, doindex: int) : ref Mstring
{
	if(str == "")
		return nil;
	if(str[len str - 1] == '\n')
		str = str[0: len str - 1];
	if(str == "")
		return nil;
	style := defstyle;
	if(str[0] == '|')
		style = altstyle;
	(nil, l) := sys->tokenize(str, "|");
	dummy := ref Mstring;
	last := dummy;
	if(doindex && l != nil && S->prefix("  ", hd l))
		doindex = 0;	# continuation line
	while(l != nil) {
		s := hd l;
		m : ref Mstring;
		if(doindex && style == defstyle) {
			# index 'words' in defstyle, but not past : or (
			(sl,sr) := S->splitl(s, ":(");
			while(sl != nil) {
				a : string;
				(a,sl) = S->splitl(sl, "a-zA-Z");
				if(a != "") {
					m = ref Mstring(a, style, 0, 0, nil);
					last.next = m;
					last = m;
				}
				if(sl != "") {
					b : string;
					(b,sl) = S->splitl(sl, "^a-zA-Z0-9_");
					if(b != "") {
						m = ref Mstring(b, style, 1, 0, nil);
						last.next = m;
						last = m;
					}
				}
			}
			if(sr != "") {
				m = ref Mstring(sr, style, 0, 0, nil);
				last.next = m;
				last = m;
				doindex = 0;
			}
		}
		else {
			m = ref Mstring(s, style, 0, 0, nil);
			last.next = m;
			last = m;
		}
		l = tl l;
		if(style == defstyle)
			style = altstyle;
		else
			style = defstyle;
	}
	return dummy.next;
}

measure(spec: list of (ref Mstring, ref Mstring), pixels: int) : (int, ref Mstring,  int, ref Mstring)
{
	maxl := 0;
	maxr := 0;
	maxlm : ref Mstring = nil;
	maxrm : ref Mstring = nil;
	while(spec != nil) {
		(lm, rm) := hd spec;
		spec = tl spec;
		(maxl, maxlm) = measuremax(lm, maxl, maxlm, pixels);
		(maxr, maxrm) = measuremax(rm, maxr, maxrm, pixels);
	}
	return (maxl, maxlm, maxr, maxrm);
}

measuremax(m: ref Mstring, maxw: int, maxm: ref Mstring, pixels: int) : (int, ref Mstring)
{
	w := 0;
	for(mm := m; mm != nil; mm = mm.next) {
		if(pixels)
			mm.width = fontref[mm.style].width(mm.s);
		else
			mm.width = len mm.s;
		w += mm.width;
	}
	if(w > maxw) {
		maxw = w;
		maxm = m;
	}
	return (maxw, maxm);
}

cook(parent: string, nil: int, args: string): (ref Celem, string)
{
	(spec, err) := getspec(parent, args);
	if(err != nil)
		return (nil, err);
	(nil, maxlm, nil, nil) := measure(spec, 0);
	ans := fontce(Roman);
	tail := specialce("\\begin{tabbing}\\hspace{3in}\\=\\kill\n");
	tail = add(ans, nil, tail);
	for(l := spec; l != nil; l = tl l) {
		(lm, rm) := hd l;
		tail = cookmstring(ans, tail, lm, 1);
		tail = add(ans, tail, specialce("\\>"));
		tail = cookmstring(ans, tail, rm, 0);
		tail = add(ans, tail, specialce("\\\\\n"));
	}
	add(ans, tail, specialce("\\end{tabbing}"));
	return (ans, "");
}

cookmstring(par, tail: ref Celem, m: ref Mstring, doindex: int) : ref Celem
{
	s := "";
	if(m == nil)
		return tail;
	while(m != nil) {
		e := fontce(m.style);
		te := textce(m.s);
		add(e, nil, te);
		if(doindex && m.indexed) {
			ie := ref Celem(Index, nil, nil, nil, nil, nil);
			add(ie, nil, e);
			e = ie;
		}
		tail = add(par, tail, e);
		m = m.next;
	}
	return tail;
}

specialce(s: string) : ref Celem
{
	return ref Celem(Special, s, nil, nil, nil, nil);
}

textce(s: string) : ref Celem
{
	return ref Celem(Text, s, nil, nil, nil, nil);
}

fontce(sty: int) : ref Celem
{
	return ref Celem(sty*NSIZE+Size8, nil, nil, nil, nil, nil);
}

add(par, tail: ref Celem, e: ref Celem) : ref Celem
{
	if(tail == nil) {
		par.contents = e;
		e.parent = par;
	}
	else
		tail.next = e;
	e.prev = tail;
	return e;
}

fullname(parent, file: string): string
{
	if(len parent==0 || (len file>0 && (file[0]=='/' || file[0]=='#')))
		return file;

	for(i:=len parent-1; i>=0; i--)
		if(parent[i] == '/')
			return parent[0:i+1] + file;
	return file;
}
