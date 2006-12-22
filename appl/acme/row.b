implement Rowm;

include "common.m";

sys : Sys;
bufio : Bufio;
utils : Utils;
drawm : Draw;
acme : Acme;
graph : Graph;
gui : Gui;
dat : Dat;
bufferm : Bufferm;
textm : Textm;
filem : Filem;
windowm : Windowm;
columnm : Columnm;
exec : Exec;
look : Look;
edit : Edit;
ecmd : Editcmd;

ALLLOOPER, ALLTOFILE, ALLMATCHFILE, ALLFILECHECK, ALLELOGTERM, ALLEDITINIT, ALLUPDATE: import Edit;
sprint : import sys;
FALSE, TRUE, XXX : import Dat;
Border, BUFSIZE, Astring : import Dat;
Reffont, reffont, Lock, Ref : import dat;
row, home, mouse : import dat;
fontnames : import acme;
font, draw : import graph;
Point, Rect, Image : import drawm;
min, max, abs, error, warning, clearmouse, stralloc, strfree : import utils;
black, white, mainwin : import gui;
Buffer : import bufferm;
Tag, Rowtag, Text : import textm;
Window : import windowm;
File : import filem;
Column : import columnm;
Iobuf : import bufio;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	bufio = mods.bufio;
	dat = mods.dat;
	utils = mods.utils;
	drawm = mods.draw;
	acme = mods.acme;
	graph = mods.graph;
	gui = mods.gui;
	bufferm = mods.bufferm;
	textm = mods.textm;
	filem = mods.filem;
	windowm = mods.windowm;
	columnm = mods.columnm;
	exec = mods.exec;
	look = mods.look;
	edit = mods.edit;
	ecmd = mods.editcmd;
}

newrow() : ref Row
{
	r := ref Row;
	r.qlock = Lock.init();
	r.r = ((0, 0), (0, 0));
	r.tag = nil;
	r.col = nil;
	r.ncol = 0;
	return r;
}

Row.init(row : self ref Row, r : Rect)
{
	r1 : Rect;
	t : ref Text;
	dummy : ref File = nil;

	draw(mainwin, r, white, nil, (0, 0));
	row.r = r;
	row.col = nil;
	row.ncol = 0;
	r1 = r;
	r1.max.y = r1.min.y + font.height;
	row.tag = textm->newtext();
	t = row.tag;
	t.init(dummy.addtext(t), r1, Reffont.get(FALSE, FALSE, FALSE, nil), acme->tagcols);
	t.what = Rowtag;
	t.row = row;
	t.w = nil;
	t.col = nil;
	r1.min.y = r1.max.y;
	r1.max.y += Border;
	draw(mainwin, r1, black, nil, (0, 0));
	t.insert(0, "Newcol Kill Putall Dump Exit ", 29, TRUE, 0);
	t.setselect(t.file.buf.nc, t.file.buf.nc);
}

Row.add(row : self ref Row, c : ref Column, x : int) : ref Column
{
	r, r1 : Rect;
	d : ref Column;
	i : int;

	d = nil;
	r = row.r;
	r.min.y = row.tag.frame.r.max.y+Border;
	if(x<r.min.x && row.ncol>0){	#steal 40% of last column by default 
		d = row.col[row.ncol-1];
		x = d.r.min.x + 3*d.r.dx()/5;
	}
	# look for column we'll land on 
	for(i=0; i<row.ncol; i++){
		d = row.col[i];
		if(x < d.r.max.x)
			break;
	}
	if(row.ncol > 0){
		if(i < row.ncol)
			i++;	# new column will go after d 
		r = d.r;
		if(r.dx() < 100)
			return nil;
		draw(mainwin, r, white, nil, (0, 0));
		r1 = r;
		r1.max.x = min(x, r.max.x-50);
		if(r1.dx() < 50)
			r1.max.x = r1.min.x+50;
		d.reshape(r1);
		r1.min.x = r1.max.x;
		r1.max.x = r1.min.x+Border;
		draw(mainwin, r1, black, nil, (0, 0));
		r.min.x = r1.max.x;
	}
	if(c == nil){
		c = ref Column;
		c.init(r);
		reffont.r.inc();
	}else
		c.reshape(r);
	c.row = row;
	c.tag.row = row;
	orc := row.col;
	row.col = array[row.ncol+1] of ref Column;
	row.col[0:] = orc[0:i];
	row.col[i+1:] = orc[i:row.ncol];
	orc = nil;
	row.col[i] = c;
	row.ncol++;
	clearmouse();
	return c;
}

Row.reshape(row : self ref Row, r : Rect)
{
	i, dx, odx : int;
	r1, r2 : Rect;
	c : ref Column;

	dx = r.dx();
	odx = row.r.dx();
	row.r = r;
	r1 = r;
	r1.max.y = r1.min.y + font.height;
	row.tag.reshape(r1);
	r1.min.y = r1.max.y;
	r1.max.y += Border;
	draw(mainwin, r1, black, nil, (0, 0));
	r.min.y = r1.max.y;
	r1 = r;
	r1.max.x = r1.min.x;
	for(i=0; i<row.ncol; i++){
		c = row.col[i];
		r1.min.x = r1.max.x;
		if(i == row.ncol-1)
			r1.max.x = r.max.x;
		else
			r1.max.x = r1.min.x+c.r.dx()*dx/odx;
		r2 = r1;
		r2.max.x = r2.min.x+Border;
		draw(mainwin, r2, black, nil, (0, 0));
		r1.min.x = r2.max.x;
		c.reshape(r1);
	}
}

Row.dragcol(row : self ref Row, c : ref Column)
{
	r : Rect;
	i, b, x : int;
	p, op : Point;
	d : ref Column;

	clearmouse();
	graph->cursorswitch(dat->boxcursor);
	b = mouse.buttons;
	op = mouse.xy;
	while(mouse.buttons == b)
		acme->frgetmouse();
	graph->cursorswitch(dat->arrowcursor);
	if(mouse.buttons){
		while(mouse.buttons)
			acme->frgetmouse();
		return;
	}

	for(i=0; i<row.ncol; i++)
		if(row.col[i] == c)
			break;
	if (i == row.ncol)
		error("can't find column");

	if(i == 0)
		return;
	p = mouse.xy;
	if((abs(p.x-op.x)<5 && abs(p.y-op.y)<5))
		return;
	if((i>0 && p.x<row.col[i-1].r.min.x) || (i<row.ncol-1 && p.x>c.r.max.x)){
		# shuffle 
		x = c.r.min.x;
		row.close(c, FALSE);
		if(row.add(c, p.x) == nil)	# whoops! 
		if(row.add(c, x) == nil)		# WHOOPS! 
		if(row.add(c, -1)==nil){		# shit! 
			row.close(c, TRUE);
			return;
		}
		c.mousebut();
		return;
	}
	d = row.col[i-1];
	if(p.x < d.r.min.x+80+Dat->Scrollwid)
		p.x = d.r.min.x+80+Dat->Scrollwid;
	if(p.x > c.r.max.x-80-Dat->Scrollwid)
		p.x = c.r.max.x-80-Dat->Scrollwid;
	r = d.r;
	r.max.x = c.r.max.x;
	draw(mainwin, r, white, nil, (0, 0));
	r.max.x = p.x;
	d.reshape(r);
	r = c.r;
	r.min.x = p.x;
	r.max.x = r.min.x;
	r.max.x += Border;
	draw(mainwin, r, black, nil, (0, 0));
	r.min.x = r.max.x;
	r.max.x = c.r.max.x;
	c.reshape(r);
	c.mousebut();
}

Row.close(row : self ref Row, c : ref Column, dofree : int)
{
	r : Rect;
	i : int;

	for(i=0; i<row.ncol; i++)
		if(row.col[i] == c)
			break;
	if (i == row.ncol)
		error("can't find column");

	r = c.r;
	if(dofree)
		c.closeall();
	orc := row.col;
	row.col = array[row.ncol-1] of ref Column;
	row.col[0:] = orc[0:i];
	row.col[i:] = orc[i+1:row.ncol];
	orc = nil;
	row.ncol--;
	if(row.ncol == 0){
		draw(mainwin, r, white, nil, (0, 0));
		return;
	}
	if(i == row.ncol){		# extend last column right 
		c = row.col[i-1];
		r.min.x = c.r.min.x;
		r.max.x = row.r.max.x;
	}else{			# extend next window left 
		c = row.col[i];
		r.max.x = c.r.max.x;
	}
	draw(mainwin, r, white, nil, (0, 0));
	c.reshape(r);
}

Row.whichcol(row : self ref Row, p : Point) : ref Column
{
	i : int;
	c : ref Column;

	for(i=0; i<row.ncol; i++){
		c = row.col[i];
		if(p.in(c.r))
			return c;
	}
	return nil;
}

Row.which(row : self ref Row, p : Point) : ref Text
{
	c : ref Column;

	if(p.in(row.tag.all))
		return row.tag;
	c = row.whichcol(p);
	if(c != nil)
		return c.which(p);
	return nil;
}

Row.typex(row : self ref Row, r : int, p : Point) : ref Text
{
	w : ref Window;
	t : ref Text;

	clearmouse();
	row.qlock.lock();
	if(dat->bartflag)
		t = dat->barttext;
	else
		t = row.which(p);
	if(t!=nil && !(t.what==Tag && p.in(t.scrollr))){
		w = t.w;
		if(w == nil)
			t.typex(r, 0);
		else{
			w.lock('K');
			w.typex(t, r);
			w.unlock();
		}
	}
	row.qlock.unlock();
	return t;
}

Row.clean(row : self ref Row, exiting : int) : int
{
	clean : int;
	i : int;

	clean = TRUE;
	for(i=0; i<row.ncol; i++)
		clean &= row.col[i].clean(exiting);
	return clean;
}

Row.dump(row : self ref Row, file : string)
{
	i, j, m, n, dumped : int;
	q0, q1 : int;
	b : ref Iobuf;
	buf, fontname, a : string;
	r : ref Astring;
	c : ref Column;
	w, w1 : ref Window;
	t : ref Text;

	if(row.ncol == 0)
		return;
	
	{
		if(file == nil){
			if(home == nil){
				warning(nil, "can't find file for dump: $home not defined\n");
				raise "e";
			}
			buf = sprint("%s/acme.dump", home);
			file = buf;
		}
		b = bufio->create(file, Bufio->OWRITE, 8r600);
		if(b == nil){
			warning(nil, sprint("can't open %s: %r\n", file));
			raise "e";
		}
		r = stralloc(BUFSIZE);
		b.puts(acme->wdir); b.putc('\n');
		b.puts(fontnames[0]); b.putc('\n');
		b.puts(fontnames[1]); b.putc('\n');
		for(i=0; i<row.ncol; i++){
			c = row.col[i];
			b.puts(sprint("%11d", 100*(c.r.min.x-row.r.min.x)/row.r.dx()));
			if(i == row.ncol-1)
				b.putc('\n');
			else
				b.putc(' ');
		}
		for(i=0; i<row.ncol; i++){
			c = row.col[i];
			for(j=0; j<c.nw; j++)
				c.w[j].body.file.dumpid = 0;
		}
		for(i=0; i<row.ncol; i++){
			c = row.col[i];
			for(j=0; j<c.nw; j++){
				w = c.w[j];
				w.commit(w.tag);
				t = w.body;
				# windows owned by others get special treatment 
				if(w.nopen[Dat->QWevent] > byte 0)
					if(w.dumpstr == nil)
						continue;
				# zeroxes of external windows are tossed 
				if(t.file.ntext > 1)
					for(n=0; n<t.file.ntext; n++){
						w1 = t.file.text[n].w;
						if(w == w1)
							continue;
						if(w1.nopen[Dat->QWevent] != byte 0) {
							j = c.nw;
							continue;
						}
					}
				fontname = "";
				if(t.reffont.f != font)
					fontname = t.reffont.f.name;
				a = t.file.name;
				if(t.file.dumpid){
					dumped = FALSE;
					b.puts(sprint("x%11d %11d %11d %11d %11d %s\n", i, t.file.dumpid,
						w.body.q0, w.body.q1,
						100*(w.r.min.y-c.r.min.y)/c.r.dy(),
						fontname));
				}else if(w.dumpstr != nil){
					dumped = FALSE;
					b.puts(sprint("e%11d %11d %11d %11d %11d %s\n", i, t.file.dumpid,
						0, 0,
						100*(w.r.min.y-c.r.min.y)/c.r.dy(),
						fontname));
				}else if(len a == 0){	# don't save unnamed windows 
					continue;
				}else if((!w.dirty && utils->access(a)==0) || w.isdir){
					dumped = FALSE;
					t.file.dumpid = w.id;
					b.puts(sprint("f%11d %11d %11d %11d %11d %s\n", i, w.id,
						w.body.q0, w.body.q1,
						100*(w.r.min.y-c.r.min.y)/c.r.dy(),
						fontname));
				}else{
					dumped = TRUE;
					t.file.dumpid = w.id;
					b.puts(sprint("F%11d %11d %11d %11d %11d %11d %s\n", i, j,
						w.body.q0, w.body.q1,
						100*(w.r.min.y-c.r.min.y)/c.r.dy(),
						w.body.file.buf.nc, fontname));
				}
				a = nil;
				buf = w.ctlprint();
				b.puts(buf);
				m = min(BUFSIZE, w.tag.file.buf.nc);
				w.tag.file.buf.read(0, r, 0, m);
				n = 0;
				while(n<m && r.s[n]!='\n')
					n++;
				r.s[n++] = '\n';
				b.puts(r.s[0:n]);
				if(dumped){
					q0 = 0;
					q1 = t.file.buf.nc;
					while(q0 < q1){
						n = q1 - q0;
						if(n > Dat->BUFSIZE)
							n = Dat->BUFSIZE;
						t.file.buf.read(q0, r, 0, n);
						b.puts(r.s[0:n]);
						q0 += n;
					}
				}
				if(w.dumpstr != nil){
					if(w.dumpdir != nil)
						b.puts(sprint("%s\n%s\n", w.dumpdir, w.dumpstr));
					else
						b.puts(sprint("\n%s\n", w.dumpstr));
				}
			}
		}
		b.close();
		b = nil;
		strfree(r);
		r = nil;
	}
	exception{
		* =>
			return;
	}
}

rdline(b : ref Iobuf, line : int) : (int, string)
{
	l : string;

	l = b.gets('\n');
	if(l != nil)
		line++;
	return (line, l);
}

Row.loadx(row : self ref Row, file : string, initing : int)
{
	i, j, line, percent, y, nr, nfontr, n, ns, ndumped, dumpid, x : int;
	b, bout : ref Iobuf;
	fontname : string;
	l, buf, t : string;
	rune : int;
	r, fontr : string;
	c, c1, c2 : ref Column;
	q0, q1 : int;
	r1, r2 : Rect;
	w : ref Window;

	{
		if(file == nil){
			if(home == nil){
				warning(nil, "can't find file for load: $home not defined\n");
				raise "e";
			}
			buf = sprint("%s/acme.dump", home);
			file = buf;
		}
		b = bufio->open(file, Bufio->OREAD);
		if(b == nil){
			warning(nil, sprint("can't open load file %s: %r\n", file));
			raise "e";
		}
		
		{
			# current directory 
			(line, l) = rdline(b, 0);
			if(l == nil)
				raise "e";
			l = l[0:len l - 1];
			if(sys->chdir(l) < 0){
				warning(nil, sprint("can't chdir %s\n", l));
				b.close();
				return;
			}
			# global fonts 
			for(i=0; i<2; i++){
				(line, l) = rdline(b, line);
				if(l == nil)
					raise "e";
				l = l[0:len l -1];
				if(l != nil && l != fontnames[i])
					Reffont.get(i, TRUE, i==0 && initing, l);
			}
			if(initing && row.ncol==0)
				row.init(mainwin.clipr);
			(line, l) = rdline(b, line);
			if(l == nil)
				raise "e";
			j = len l/12;
			if(j<=0 || j>10)
				raise "e";
			for(i=0; i<j; i++){
				percent = int l[12*i:12*i+11];
				if(percent<0 || percent>=100)
					raise "e";
				x = row.r.min.x+percent*row.r.dx()/100;
				if(i < row.ncol){
					if(i == 0)
						continue;
					c1 = row.col[i-1];
					c2 = row.col[i];
					r1 = c1.r;
					r2 = c2.r;
					r1.max.x = x;
					r2.min.x = x+Border;
					if(r1.dx() < 50 || r2.dx() < 50)
						continue;
					draw(mainwin, (r1.min, r2.max), white, nil, (0, 0));
					c1.reshape(r1);
					c2.reshape(r2);
					r2.min.x = x;
					r2.max.x = x+Border;
					draw(mainwin, r2, black, nil, (0, 0));
				}
				if(i >= row.ncol)
					row.add(nil, x);
			}
			for(;;){
				(line, l) = rdline(b, line);
				if(l == nil)
					break;
				dumpid = 0;
				case(l[0]){
				'e' =>
					if(len l < 1+5*12+1)
						raise "e";
					(line, l) = rdline(b, line);	# ctl line; ignored 
					if(l == nil)
						raise "e";
					(line, l) = rdline(b, line);	# directory 
					if(l == nil)
						raise "e";
					l = l[0:len l -1];
					if(len l != 0)
						r = l;
					else{
						if(home == nil)
							r = "./";
						else
							r = home+"/";
					}
					nr = len r;
					(line, l) = rdline(b, line);	# command 
					if(l == nil)
						raise "e";
					t = l[0:len l -1];
					spawn exec->run(nil, t, r, nr, TRUE, nil, nil, FALSE);
					# r is freed in run() 
					continue;
				'f' =>
					if(len l < 1+5*12+1)
						raise "e";
					fontname = l[1+5*12:len l - 1];
					ndumped = -1;
				'F' =>
					if(len l < 1+6*12+1)
						raise "e";
					fontname = l[1+6*12:len l - 1];
					ndumped = int l[1+5*12:1+5*12+11];
				'x' =>
					if(len l < 1+5*12+1)
						raise "e";
					fontname = l[1+5*12: len l - 1];
					ndumped = -1;
					dumpid = int l[1+1*12:1+1*12+11];
				* =>
					raise "e";
				}
				l = l[0:len l -1];
				if(len fontname != 0) {
					fontr = fontname;
					nfontr = len fontname;
				}
				else
					(fontr, nfontr) = (nil, 0);
				i = int l[1+0*12:1+0*12+11];
				j = int l[1+1*12:1+1*12+11];
				q0 = int l[1+2*12:1+2*12+11];
				q1 = int l[1+3*12:1+3*12+11];
				percent = int l[1+4*12:1+4*12+11];
				if(i<0 || i>10)
					raise "e";
				if(i > row.ncol)
					i = row.ncol;
				c = row.col[i];
				y = c.r.min.y+(percent*c.r.dy())/100;
				if(y<c.r.min.y || y>=c.r.max.y)
					y = -1;
				if(dumpid == 0)
					w = c.add(nil, nil, y);
				else
					w = c.add(nil, look->lookid(dumpid, TRUE), y);
				if(w == nil)
					continue;
				w.dumpid = j;
				(line, l) = rdline(b, line);
				if(l == nil)
					raise "e";
				l = l[0:len l - 1];
				r = l[5*12:len l];
				nr = len r;
				ns = -1;
				for(n=0; n<nr; n++){
					if(r[n] == '/')
						ns = n;
					if(r[n] == ' ')
						break;
				}
				if(dumpid == 0)
					w.setname(r, n);
				for(; n<nr; n++)
					if(r[n] == '|')
						break;
				w.cleartag();
				w.tag.insert(w.tag.file.buf.nc, r[n+1:len r], nr-(n+1), TRUE, 0);
				if(ndumped >= 0){
					# simplest thing is to put it in a file and load that 
					buf = sprint("/tmp/d%d.%.4sacme", sys->pctl(0, nil), utils->getuser());
					bout = bufio->create(buf, Bufio->OWRITE, 8r600);
					if(bout == nil){
						warning(nil, "can't create temp file: %r\n");
						b.close();
						return;
					}
					for(n=0; n<ndumped; n++){
						rune = b.getc();
						if(rune == '\n')
							line++;
						if(rune == Bufio->EOF){
							bout.close();
							bout = nil;
							raise "e";
						}
						bout.putc(rune);
					}
					bout.close();
					bout = nil;
					w.body.loadx(0, buf, 1);
					w.body.file.mod = TRUE;
					for(n=0; n<w.body.file.ntext; n++)
						w.body.file.text[n].w.dirty = TRUE;
					w.settag();
					sys->remove(buf);
					buf = nil;
				}else if(dumpid==0 && r[ns+1]!='+' && r[ns+1]!='-')
					exec->get(w.body, nil, nil, FALSE, nil, 0);
				l = r = nil;
				if(fontr != nil){
					exec->fontx(w.body, nil, nil, fontr, nfontr);
					fontr = nil;
				}
				if(q0>w.body.file.buf.nc || q1>w.body.file.buf.nc || q0>q1)
					q0 = q1 = 0;
				w.body.show(q0, q1);
				w.maxlines = min(w.body.frame.nlines, max(w.maxlines, w.body.frame.maxlines));
			}
			b.close();
		}
		exception{
			* =>
			 	warning(nil, sprint("bad load file %s:%d\n", file, line));
				b.close();
				raise "e";
		}
	}
	exception{
		* =>
			return;
	}
}

allwindows(o: int, aw: ref  Dat->Allwin)
{
	for(i:=0; i<row.ncol; i++){
		c := row.col[i];
		for(j:=0; j<c.nw; j++){
			w := c.w[j];
			case (o){
			ALLLOOPER =>
				pick k := aw{
					LP => ecmd->alllooper(w, k.lp);
				}
			ALLTOFILE =>
				pick k := aw{
					FF => ecmd->alltofile(w, k.ff);
				}
			ALLMATCHFILE =>
				pick k := aw{
					FF => ecmd->allmatchfile(w, k.ff);
				}
			ALLFILECHECK =>
				pick k := aw{
					FC => ecmd->allfilecheck(w, k.fc);
				}
			ALLELOGTERM =>
				edit->allelogterm(w);
			ALLEDITINIT =>
				edit->alleditinit(w);
			ALLUPDATE =>
				edit->allupdate(w);
			}
		}
	}
}