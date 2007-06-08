implement Mc;

include "sys.m";
	sys: Sys;
	open, read, fprint, fildes, tokenize,
	ORDWR, OREAD, OWRITE: import sys;
include "draw.m";
	draw: Draw;
	Font: import draw;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "arg.m";

font: ref Font;
columns := 65;
tabwid := 0;
mintab := 1;

Mc: module{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if((bufio = load Bufio Bufio->PATH) == nil)
		fatal("can't load " + Bufio->PATH);
	draw = load Draw Draw->PATH;
	if((arg := load Arg Arg->PATH) == nil)
		fatal("can't load " + Arg->PATH);

	getwidth(ctxt);
	arg->init(argv);
	arg->setusage("mc [-c columns] [file ...]");
	while((c:=arg->opt()) != 0)
		case c {
		'c' =>	columns = int arg->earg() * mintab;
		* =>		arg->usage();
		}
	argv = arg->argv();
	if(len argv == 0)
		argv = "/fd/0" :: nil;

	a := array[1024] of (string, int);
	n := 0;
	maxwidth := 0;
	for(; argv!=nil; argv=tl argv){
		if((bin:=bufio->open(hd argv, OREAD)) == nil){
			fprint(fildes(2), "mc: can't open %s: %r\n", hd argv);
			continue;
		}
		while((s:=bin.gets('\n')) != nil){
			if(s[len s-1] == '\n')
				s = s[0:len s-1];
			if(n == len a)
				a = (array[n+1024] of (string, int))[0:] = a;
			a[n].t0 = s;
			a[n].t1 = wordsize(s);
			if(a[n].t1 > maxwidth)
				maxwidth = a[n].t1;
			n++;
		}
		bin.close();
	}
	outcols(a[:n], maxwidth);
}

outcols(words: array of (string, int), maxwidth: int)
{
	maxwidth = nexttab(maxwidth+mintab-1);
	numcols := columns / maxwidth;
	if(numcols <= 0)
		numcols = 1;
	nwords := len words;
	nlines := (nwords+numcols-1) / numcols;
	bout := bufio->fopen(fildes(1), OWRITE);
	for(i := 0; i < nlines; i++){
		col := endcol := 0;
		for(j:=i; j<nwords; j+=nlines){
			endcol += maxwidth;
			bout.puts(words[j].t0);
			col += words[j].t1;
			if(j+nlines < nwords){
				while(col < endcol){
					if(tabwid)
						bout.putc('\t');
					else
						bout.putc(' ');
					col = nexttab(col);
				}
			}
		}
		bout.putc('\n');
	}
	bout.close();
}

wordsize(s: string): int
{
	if(font != nil)
		return font.width(s);
	return len s;
}

nexttab(col: int): int
{
	if(tabwid){
		col += tabwid;
		col -= col%tabwid;
		return col;
	}
	return col+1;
}

getwidth(ctxt: ref Draw->Context)
{
	if(ctxt == nil || draw == nil)
		return;
	if((wid := rf("/env/acmewin")) == nil)
		return;
	if((fd := open("/chan/" + wid + "/ctl", ORDWR)) == nil)
		return;
	buf := array[256] of byte;
	if((n := read(fd, buf, len buf)) <= 0)
		return;
	(nf, f) := tokenize(string buf[:n], " ");
	if(nf != 8)
		return;
	f0 := tl tl tl tl tl f;
	if((font = Font.open(ctxt.display, hd tl f0)) == nil)
		return;
	tabwid = int hd tl tl f0;
	mintab = font.width("0");	
	columns = int hd f0;
}

fatal(s: string)
{
	fprint(fildes(2), "mc: %s: %r\n", s);
	raise "fail:"+s;
}

rf(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return nil;
	b := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, b, len b);
	if(n < 0)
		return nil;
	return string b[0:n];
}
