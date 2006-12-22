implement Brutusext;

# <Extension excerpt file [start [end]]>

Name:	con "Brutus entry";

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Context: import draw;

include	"bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include	"regex.m";
	regex: Regex;

include "tk.m";
	tk: Tk;

include	"tkclient.m";
	tkclient: Tkclient;

include	"brutus.m";
include	"brutusext.m";

init(s: Sys, d: Draw, b: Bufio, t: Tk, w: Tkclient)
{
	sys = s;
	draw = d;
	bufio = b;
	tk = t;
	tkclient = w;
	regex = load Regex Regex->PATH;
}

create(parent: string, t: ref Tk->Toplevel, name, args: string): string
{
	(text, err) := gather(parent, args);
	if(err != nil)
		return err;
	err = tk->cmd(t, "text "+name+" -tabs {1c} -wrap none -font /fonts/pelm/latin1.9.font");
	if(len err > 0 && err[0] == '!')
		return err;
	(n, maxw) := nlines(text);
	if(maxw < 40)
		maxw = 40;
	if(maxw > 70)
		maxw = 70;
	tk->cmd(t, name+" configure -height "+string n+".01h -width "+string maxw+"w");
	return tk->cmd(t, name+" insert end '"+text);
}

gather(parent, args: string): (string, string)
{
	argl := tokenize(args);
	nargs := len argl;
	if(nargs == 0)
		return (nil, "usage: excerpt [start] [end] file");
	file := hd argl;
	argl = tl argl;
	b := bufio->open(fullname(parent, file), Bufio->OREAD);
	if(b == nil)
		return (nil, sys->sprint("can't open %s: %r", file));
	start := "";
	end := "";
	if(argl != nil){
		start = hd argl;
		if(tl argl != nil)
			end = hd tl argl;
	}
	(text, err) := readall(b, start, end);
	return (text, err);
}

tokenize(s: string): list of string
{
	l: list of string;
	i := 0;
	a := "";
	first := 1;
	while(i < len s){
		(a, i) = arg(first, s, i);
		if(a != "")
			l = a :: l;
		first = 0;
	}
	rl: list of string;
	while(l != nil){
		rl = hd l :: rl;
		l = tl l;
	}
	return rl;
}

arg(first: int, s: string, i: int): (string, int)
{
	while(i<len s && (s[i]==' ' || s[i]=='\t'))
		i++;
	if(i == len s)
		return ("", i);
	j := i+1;
	if(first || s[i] != '/'){
		while(j<len s && (s[j]!=' ' && s[j]!='\t'))
			j++;
		return (s[i:j], j);
	}
	while(j<len s && s[j]!='/')
		if(s[j++] == '\\')
			j++;
	if(j == len s)
		return (s[i:j], j);
	return (s[i:j+1], j+1);
}

readall(b: ref Iobuf, start, end: string): (string, string)
{
	revlines : list of string = nil;
	appending := 0;
	lineno := 0;
	for(;;){
		line := b.gets('\n');
		if(line == nil)
			break;
		lineno++;
		if(!appending){
			m := match(start, line, lineno);
			if(m < 0)
				return (nil, "error in pattern");
			if(m)
				appending = 1;
		}
		if(appending){
			revlines = line :: revlines;
			if(start != ""){
				m := match(end, line, lineno);
				if(m < 0)
					return (nil, "error in pattern");
				if(m)
					break;
			}
		}
	}
	return (prep(revlines), "");
}

prep(revlines: list of string) : string
{
	tabstrip := -1;
	for(l:=revlines; l != nil; l = tl l) {
		s := hd l;
		if(len s > 1) {
			n := nleadtab(hd l);
			if(tabstrip == -1 || n < tabstrip)
				tabstrip = n;
		}
	}
	# remove tabstrip tabs from each line
	# and concatenate in reverse order
	ans := "";
	for(l=revlines; l != nil; l = tl l) {
		s := hd l;
		if(tabstrip > 0 && len s > 1)
			s = s[tabstrip:];
		ans = s + ans;
	}
	return ans;
}

nleadtab(s: string) : int
{
	slen := len s;
	for(i:=0; i<slen; i++)
		if(s[i] != '\t')
			break;
	return i;
}

nlines(s: string): (int, int)
{
	n := 0;
	maxw := 0;
	w := 0;
	for(i:=0; i<len s; i++) {
		if(s[i] == '\n') {
			n++;
			if(w > maxw)
				maxw = w;
			w = 0;
		}
		else if(s[i] == '\t')
			w += 5;
		else
			w++;
	}
	if(len s>0 && s[len s-1]!='\n') {
		n++;
		if(w > maxw)
			maxw = w;
	}
	return (n, maxw);
}

match(pat, line: string, lineno: int): int
{
	if(pat == "")
		return 1;
	case pat[0] {
	'0' to '9' =>
		return int pat <= lineno;
	'/' =>
		if(len pat < 3 || pat[len pat-1]!='/')
			return -1;
		re := compile(pat[1:len pat-1]);
		if(re == nil)
			return -1;
		match := regex->execute(re, line);
		return match != nil;
	}
	return -1;
}

pats: list of (string, Regex->Re);

compile(pat: string): Regex->Re
{
	l := pats;
	while(l != nil){
		(p, r) := hd l;
		if(p == pat)
			return r;
		l = tl l;
	}
	(re, nil) := regex->compile(pat, 0);
	pats = (pat, re) :: pats;
	return re;
}

cook(parent: string, nil: int, args: string): (ref Brutusext->Celem, string)
{
	(text, err) := gather(parent, args);
	if(err != nil)
		return (nil, err);
	el1 := ref Brutusext->Celem(Brutusext->Text, text, nil, nil, nil, nil);
	el2 := ref Brutusext->Celem(Brutus->Type*Brutus->NSIZE+Brutus->Size10, "", el1, nil, nil, nil);
	el1.parent = el2;
	ans := ref Brutusext->Celem(Brutus->Example, "", el2, nil, nil, nil);
	el2.parent = ans;
	return (ans, "");
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
