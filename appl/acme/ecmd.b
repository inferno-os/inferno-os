implement Editcmd;

include "common.m";

sys: Sys;
utils: Utils;
edit: Edit;
editlog: Editlog;
windowm: Windowm;
look: Look;
columnm: Columnm;
bufferm: Bufferm;
exec: Exec;
dat: Dat;
textm: Textm;
regx: Regx;
filem: Filem;
rowm: Rowm;

Dir: import Sys;
Allwin, Filecheck, Tofile, Looper, Astring: import Dat;
aNo, aDot, aAll: import Edit;
C_nl, C_a, C_b, C_c, C_d, C_B, C_D, C_e, C_f, C_g, C_i, C_k, C_m, C_n, C_p, C_s, C_u, C_w, C_x, C_X, C_pipe, C_eq: import Edit;
TRUE, FALSE: import Dat;
Inactive, Inserting, Collecting: import Dat;
BUFSIZE, Runestr: import Dat;
Addr, Address, String, Cmd: import Edit;
Window: import windowm;
File: import filem;
NRange, Range, Rangeset: import Dat;
Text: import textm;
Column: import columnm;
Buffer: import bufferm;

sprint: import sys;
elogterm, elogclose, eloginsert, elogdelete, elogreplace, elogapply: import editlog;
cmdtab, allocstring, freestring, Straddc, curtext, editing, newaddr, cmdlookup, editerror: import edit;
error, stralloc, strfree, warning, skipbl, findbl: import utils;
lookfile, cleanname, dirname: import look;
undo, run: import exec;
Ref, Lock, row, cedit: import dat;
rxcompile, rxexecute, rxbexecute: import regx;
allwindows: import rowm;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	utils = mods.utils;
	edit = mods.edit;
	editlog = mods.editlog;
	windowm = mods.windowm;
	look = mods.look;
	columnm = mods.columnm;
	bufferm = mods.bufferm;
	exec = mods.exec;
	dat = mods.dat;
	textm = mods.textm;
	regx = mods.regx;
	filem = mods.filem;
	rowm = mods.rowm;

	none.r.q0 = none.r.q1 = 0;
	none.f = nil;
}

cmdtabexec(i: int, t: ref Text, cp: ref Cmd): int
{
	case (cmdtab[i].fnc){
		C_nl	=> i = nl_cmd(t, cp);
		C_a 	=> i = a_cmd(t, cp);
		C_b	=> i = b_cmd(t, cp);
		C_c	=> i = c_cmd(t, cp);
		C_d	=> i = d_cmd(t, cp);
		C_e	=> i = e_cmd(t, cp);
		C_f	=> i = f_cmd(t, cp);
		C_g	=> i = g_cmd(t, cp);
		C_i	=> i = i_cmd(t, cp);
		C_m	=> i = m_cmd(t, cp);
		C_p	=> i = p_cmd(t, cp);
		C_s	=> i = s_cmd(t, cp);
		C_u	=> i = u_cmd(t, cp);
		C_w	=> i = w_cmd(t, cp);
		C_x	=> i = x_cmd(t, cp);
		C_eq => i = eq_cmd(t, cp);
		C_B	=> i = B_cmd(t, cp);
		C_D	=> i = D_cmd(t, cp);
		C_X	=> i = X_cmd(t, cp);
		C_pipe	=> i = pipe_cmd(t, cp);
		* =>	error("bad case in cmdtabexec");
	}
	return i;
}

Glooping: int;
nest: int;
Enoname := "no file name given";

addr: Address;
menu: ref File;
sel: Rangeset;
collection: string;
ncollection: int;

clearcollection()
{
	collection = nil;
	ncollection = 0;
}

resetxec()
{
	Glooping = nest = 0;
	clearcollection();
}

mkaddr(f: ref File): Address
{
	a: Address;

	a.r.q0 = f.curtext.q0;
	a.r.q1 = f.curtext.q1;
	a.f = f;
	return a;
}

none: Address;

cmdexec(t: ref Text, cp: ref Cmd): int
{
	i: int;
	ap: ref Addr;
	f: ref File;
	w: ref Window;
	dot: Address;

	if(t == nil)
		w = nil;
	else
		w = t.w;
	if(w==nil && (cp.addr==nil || cp.addr.typex!='"') &&
	    utils->strchr("bBnqUXY!", cp.cmdc) < 0&&
	    !(cp.cmdc=='D' && cp.text!=nil))
		editerror("no current window");
	i = cmdlookup(cp.cmdc);	# will be -1 for '{' 
	f = nil;
	if(t!=nil && t.w!=nil){
		t = t.w.body;
		f = t.file;
		f.curtext = t;
	}
	if(i>=0 && cmdtab[i].defaddr != aNo){
		if((ap=cp.addr)==nil && cp.cmdc!='\n'){
			cp.addr = ap = newaddr();
			ap.typex = '.';
			if(cmdtab[i].defaddr == aAll)
				ap.typex = '*';
		}else if(ap!=nil && ap.typex=='"' && ap.next==nil && cp.cmdc!='\n'){
			ap.next = newaddr();
			ap.next.typex = '.';
			if(cmdtab[i].defaddr == aAll)
				ap.next.typex = '*';
		}
		if(cp.addr!=nil){	# may be false for '\n' (only)
			if(f!=nil){
				dot = mkaddr(f);
				addr = cmdaddress(ap, dot, 0);
			}else	# a "
				addr = cmdaddress(ap, none, 0);
			f = addr.f;
			t = f.curtext;
		}
	}
	case(cp.cmdc){
	'{' =>
		dot = mkaddr(f);
		if(cp.addr != nil)
			dot = cmdaddress(cp.addr, dot, 0);
		for(cp = cp.cmd; cp!=nil; cp = cp.next){
			t.q0 = dot.r.q0;
			t.q1 = dot.r.q1;
			cmdexec(t, cp);
		}
		break;
	* =>
		if(i < 0)
			editerror(sprint("unknown command %c in cmdexec", cp.cmdc));
		i = cmdtabexec(i, t, cp);
		return i;
	}
	return 1;
}

edittext(f: ref File, q: int, r: string, nr: int): string
{
	case(editing){
	Inactive =>
		return "permission denied";
	Inserting =>
		eloginsert(f, q, r, nr);
		return nil;
	Collecting =>
		collection += r[0: nr];
		ncollection += nr;
		return nil;
	* =>
		return "unknown state in edittext";
	}
}

# string is known to be NUL-terminated
filelist(t: ref Text, r: string, nr: int): string
{
	if(nr == 0)
		return nil;
	(r, nr) = skipbl(r, nr);
	if(r[0] != '<')
		return r;
	# use < command to collect text 
	clearcollection();
	runpipe(t, '<', r[1:], nr-1, Collecting);
	return collection;
}

a_cmd(t: ref Text, cp: ref Cmd): int
{
	return append(t.file, cp, addr.r.q1);
}

b_cmd(nil: ref Text, cp: ref Cmd): int
{
	f: ref File;

	f = tofile(cp.text);
	if(nest == 0)
		pfilename(f);
	curtext = f.curtext;
	return TRUE;
}

B_cmd(t: ref Text, cp: ref Cmd): int
{
	listx, r, s: string;
	nr: int;

	listx = filelist(t, cp.text.r, cp.text.n);
	if(listx == nil)
		editerror(Enoname);
	r = listx;
	nr = len r;
	(r, nr) = skipbl(r, nr);
	if(nr == 0)
		look->new(t, t, nil, 0, 0, r, 0);
	else while(nr > 0){
		(s, nr) = findbl(r, nr);
		look->new(t, t, nil, 0, 0, r, len r);
		if(nr > 0)
			(r, nr) = skipbl(s[1:], nr-1);
	}
	clearcollection();
	return TRUE;
}

c_cmd(t: ref Text, cp: ref Cmd): int
{
	elogreplace(t.file, addr.r.q0, addr.r.q1, cp.text.r, cp.text.n);
	return TRUE;
}

d_cmd(t: ref Text, nil: ref Cmd): int
{
	if(addr.r.q1 > addr.r.q0)
		elogdelete(t.file, addr.r.q0, addr.r.q1);
	return TRUE;
}

D1(t: ref Text)
{
	if(t.w.body.file.ntext>1 || t.w.clean(FALSE, FALSE))
		t.col.close(t.w, TRUE);
}

D_cmd(t: ref Text, cp: ref Cmd): int
{
	listx, r, s, n: string;
	nr, nn: int;
	w: ref Window;
	dir, rs: Runestr;
	buf: string;

	listx = filelist(t, cp.text.r, cp.text.n);
	if(listx == nil){
		D1(t);
		return TRUE;
	}
	dir = dirname(t, nil, 0);
	r = listx;
	nr = len r;
	(r, nr) = skipbl(r, nr);
	do{
		(s, nr) = findbl(r, nr);
		# first time through, could be empty string, meaning delete file empty name
		nn = len r;
		if(r[0]=='/' || nn==0 || dir.nr==0){
			rs.r = r;
			rs.nr = nn;
		}else{
			n = dir.r + "/" + r;
			rs = cleanname(n, dir.nr+1+nn);
		}
		w = lookfile(rs.r, rs.nr);
		if(w == nil){
			buf = sprint("no such file %s", rs.r);
			rs.r = nil;
			editerror(buf);
		}
		rs.r = nil;
		D1(w.body);
		if(nr > 0)
			(r, nr) = skipbl(s[1:], nr-1);
	}while(nr > 0);
	clearcollection();
	dir.r = nil;
	return TRUE;
}

readloader(f: ref File, q0: int, r: string, nr: int): int
{
	if(nr > 0)
		eloginsert(f, q0, r, nr);
	return 0;
}

e_cmd(t: ref Text , cp: ref Cmd): int
{
	name: string;
	f: ref File;
	i, q0, q1, nulls, samename, allreplaced, ok: int;
	fd: ref Sys->FD;
	s, tmp: string;
	d: Dir;

	f = t.file;
	q0 = addr.r.q0;
	q1 = addr.r.q1;
	if(cp.cmdc == 'e'){
		if(t.w.clean(TRUE, FALSE)==FALSE)
			editerror("");	# winclean generated message already 
		q0 = 0;
		q1 = f.buf.nc;
	}
	allreplaced = (q0==0 && q1==f.buf.nc);
	name = cmdname(f, cp.text, cp.cmdc=='e');
	if(name == nil)
		editerror(Enoname);
	i = len name;
	samename = name == t.file.name;
	s = name;
	name = nil;
	fd = sys->open(s, Sys->OREAD);
	if(fd == nil){
		tmp = sprint("can't open %s: %r", s);
		s = nil;
		editerror(tmp);
	}
	(ok, d) = sys->fstat(fd);
	if(ok >=0 && (d.mode&Sys->DMDIR)){
		fd = nil;
		tmp = sprint("%s is a directory", s);
		s = nil;
		editerror(tmp);
	}
	elogdelete(f, q0, q1);
	nulls = 0;
	bufferm->loadfile(fd, q1, Dat->READL, nil, f);
	s = nil;
	fd = nil;
	if(nulls)
		warning(nil, sprint("%s: NUL bytes elided\n", s));
	else if(allreplaced && samename)
		f.editclean = TRUE;
	return TRUE;
}

f_cmd(t: ref Text, cp: ref Cmd): int
{
	name: string;

	name = cmdname(t.file, cp.text, TRUE);
	name = nil;
	pfilename(t.file);
	return TRUE;
}

g_cmd(t: ref Text, cp: ref Cmd): int
{
	ok: int;

	if(t.file != addr.f){
		warning(nil, "internal error: g_cmd f!=addr.f\n");
		return FALSE;
	}
	if(rxcompile(cp.re.r) == FALSE)
		editerror("bad regexp in g command");
	(ok, sel) = rxexecute(t, nil, addr.r.q0, addr.r.q1);
	if(ok ^ cp.cmdc=='v'){
		t.q0 = addr.r.q0;
		t.q1 = addr.r.q1;
		return cmdexec(t, cp.cmd);
	}
	return TRUE;
}

i_cmd(t: ref Text, cp: ref Cmd): int
{
	return append(t.file, cp, addr.r.q0);
}

# int
# k_cmd(File *f, Cmd *cp)
# {
# 	USED(cp);
#	f->mark = addr.r;
#	return TRUE;
# }

copy(f: ref File, addr2: Address)
{
	p: int;
	ni: int;
	buf: ref Astring;

	buf = stralloc(BUFSIZE);
	for(p=addr.r.q0; p<addr.r.q1; p+=ni){
		ni = addr.r.q1-p;
		if(ni > BUFSIZE)
			ni = BUFSIZE;
		f.buf.read(p, buf, 0, ni);
		eloginsert(addr2.f, addr2.r.q1, buf.s, ni);
	}
	strfree(buf);
}

move(f: ref File, addr2: Address)
{
	if(addr.f!=addr2.f || addr.r.q1<=addr2.r.q0){
		elogdelete(f, addr.r.q0, addr.r.q1);
		copy(f, addr2);
	}else if(addr.r.q0 >= addr2.r.q1){
		copy(f, addr2);
		elogdelete(f, addr.r.q0, addr.r.q1);
	}else
		error("move overlaps itself");
}

m_cmd(t: ref Text, cp: ref Cmd): int
{
	dot, addr2: Address;

	dot = mkaddr(t.file);
	addr2 = cmdaddress(cp.mtaddr, dot, 0);
	if(cp.cmdc == 'm')
		move(t.file, addr2);
	else
		copy(t.file, addr2);
	return TRUE;
}

# int
# n_cmd(File *f, Cmd *cp)
# {
#	int i;
#	USED(f);
#	USED(cp);
#	for(i = 0; i<file.nused; i++){
#		if(file.filepptr[i] == cmd)
#			continue;
#		f = file.filepptr[i];
#		Strduplstr(&genstr, &f->name);
#		filename(f);
#	}
#	return TRUE;
#}

p_cmd(t: ref Text, nil: ref Cmd): int
{
	return pdisplay(t.file);
}

s_cmd(t: ref Text, cp: ref Cmd): int
{
	i, j, k, c, m, n, nrp, didsub, ok: int;
	p1, op, delta: int;
	buf: ref String;
	rp: array of Rangeset;
	err: string;
	rbuf: ref Astring;

	n = cp.num;
	op= -1;
	if(rxcompile(cp.re.r) == FALSE)
		editerror("bad regexp in s command");
	nrp = 0;
	rp = nil;
	delta = 0;
	didsub = FALSE;
	for(p1 = addr.r.q0; p1<=addr.r.q1; ){
		(ok, sel) = rxexecute(t, nil, p1, addr.r.q1);
		if(!ok)
			break;
		if(sel[0].q0 == sel[0].q1){	# empty match?
			if(sel[0].q0 == op){
				p1++;
				continue;
			}
			p1 = sel[0].q1+1;
		}else
			p1 = sel[0].q1;
		op = sel[0].q1;
		if(--n>0)
			continue;
		nrp++;
		orp := rp;
		rp = array[nrp] of Rangeset;
		rp[0: ] = orp[0:nrp-1];
		rp[nrp-1] = copysel(sel);
		orp = nil;
	}
	rbuf = stralloc(BUFSIZE);
	buf = allocstring(0);
	for(m=0; m<nrp; m++){
		buf.n = 0;
		buf.r = nil;
		sel = rp[m];
		for(i = 0; i<cp.text.n; i++)
			if((c = cp.text.r[i])=='\\' && i<cp.text.n-1){
				c = cp.text.r[++i];
				if('1'<=c && c<='9') {
					j = c-'0';
					if(sel[j].q1-sel[j].q0>BUFSIZE){
						err = "replacement string too long";
						rp = nil;
						freestring(buf);
						strfree(rbuf);
						editerror(err);
						return FALSE;
					}
					t.file.buf.read(sel[j].q0, rbuf, 0, sel[j].q1-sel[j].q0);
					for(k=0; k<sel[j].q1-sel[j].q0; k++)
						Straddc(buf, rbuf.s[k]);
				}else
				 	Straddc(buf, c);
			}else if(c!='&')
				Straddc(buf, c);
			else{
				if(sel[0].q1-sel[0].q0>BUFSIZE){
					err = "right hand side too long in substitution";
					rp = nil;
					freestring(buf);
					strfree(rbuf);
					editerror(err);
					return FALSE;
				}
				t.file.buf.read(sel[0].q0, rbuf, 0, sel[0].q1-sel[0].q0);
				for(k=0; k<sel[0].q1-sel[0].q0; k++)
					Straddc(buf, rbuf.s[k]);
			}
		elogreplace(t.file, sel[0].q0, sel[0].q1, buf.r, buf.n);
		delta -= sel[0].q1-sel[0].q0;
		delta += buf.n;
		didsub = 1;
		if(!cp.flag)
			break;
	}
	rp = nil;
	freestring(buf);
	strfree(rbuf);
	if(!didsub && nest==0)
		editerror("no substitution");
	t.q0 = addr.r.q0;
	t.q1 = addr.r.q1+delta;
	return TRUE;
}

u_cmd(t: ref Text, cp: ref Cmd): int
{
	n, oseq, flag: int;

	n = cp.num;
	flag = TRUE;
	if(n < 0){
		n = -n;
		flag = FALSE;
	}
	oseq = -1;
	while(n-->0 && t.file.seq!=0 && t.file.seq!=oseq){
		oseq = t.file.seq;
warning(nil, sprint("seq %d\n", t.file.seq));
		undo(t, flag);
	}
	return TRUE;
}

w_cmd(t: ref Text, cp: ref Cmd): int
{
	r: string;
	f: ref File;

	f = t.file;
	if(f.seq == dat->seq)
		editerror("can't write file with pending modifications");
	r = cmdname(f, cp.text, FALSE);
	if(r == nil)
		editerror("no name specified for 'w' command");
	exec->putfile(f, addr.r.q0, addr.r.q1, r);
	# r is freed by putfile
	return TRUE;
}

x_cmd(t: ref Text, cp: ref Cmd): int
{
	if(cp.re!=nil)
		looper(t.file, cp, cp.cmdc=='x');
	else
		linelooper(t.file, cp);
	return TRUE;
}

X_cmd(nil: ref Text, cp: ref Cmd): int
{
	filelooper(cp, cp.cmdc=='X');
	return TRUE;
}

runpipe(t: ref Text, cmd: int, cr: string, ncr: int, state: int)
{
	r, s: string;
	n: int;
	dir: Runestr;
	w: ref Window;

	(r, n) = skipbl(cr, ncr);
	if(n == 0)
		editerror("no command specified for >");
	w = nil;
	if(state == Inserting){
		w = t.w;
		t.q0 = addr.r.q0;
		t.q1 = addr.r.q1;
		if(cmd == '<' || cmd=='|')
			elogdelete(t.file, t.q0, t.q1);
	}
	tmps := "z";
	tmps[0] = cmd;
	s = tmps + r;
	n++;
	dir.r = nil;
	dir.nr = 0;
	if(t != nil)
		dir = dirname(t, nil, 0);
	if(dir.nr==1 && dir.r[0]=='.'){	# sigh 
		dir.r = nil;
		dir.nr = 0;
	}
	editing = state;
	if(t!=nil && t.w!=nil)
		t.w.refx.inc();	# run will decref
	spawn run(w, s, dir.r, dir.nr, TRUE, nil, nil, TRUE);
	s = nil;
	if(t!=nil && t.w!=nil)
		t.w.unlock();
	row.qlock.unlock();
	<- cedit;
	row.qlock.lock();
	editing = Inactive;
	if(t!=nil && t.w!=nil)
		t.w.lock('M');
}

pipe_cmd(t: ref Text, cp: ref Cmd): int
{
	runpipe(t, cp.cmdc, cp.text.r, cp.text.n, Inserting);
	return TRUE;
}

nlcount(t: ref Text, q0: int, q1: int): int
{
	nl: int;
	buf: ref Astring;
	i, nbuf: int;

	buf = stralloc(BUFSIZE);
	nbuf = 0;
	i = nl = 0;
	while(q0 < q1){
		if(i == nbuf){
			nbuf = q1-q0;
			if(nbuf > BUFSIZE)
				nbuf = BUFSIZE;
			t.file.buf.read(q0, buf, 0, nbuf);
			i = 0;
		}
		if(buf.s[i++] == '\n')
			nl++;
		q0++;
	}
	strfree(buf);
	return nl;
}

printposn(t: ref Text, charsonly: int)
{
	l1, l2: int;

	if(t != nil && t.file != nil && t.file.name != nil)
		warning(nil, t.file.name + ":");
	if(!charsonly){
		l1 = 1+nlcount(t, 0, addr.r.q0);
		l2 = l1+nlcount(t, addr.r.q0, addr.r.q1);
		# check if addr ends with '\n' 
		if(addr.r.q1>0 && addr.r.q1>addr.r.q0 && t.readc(addr.r.q1-1)=='\n')
			--l2;
		warning(nil, sprint("%ud", l1));
		if(l2 != l1)
			warning(nil, sprint(",%ud", l2));
		warning(nil, "\n");
		# warning(nil, "; ");
		return;
	}
	warning(nil, sprint("#%d", addr.r.q0));
	if(addr.r.q1 != addr.r.q0)
		warning(nil, sprint(",#%d", addr.r.q1));
	warning(nil, "\n");
}

eq_cmd(t: ref Text, cp: ref Cmd): int
{
	charsonly: int;

	case(cp.text.n){
	0 =>
		charsonly = FALSE;
		break;
	1 =>
		if(cp.text.r[0] == '#'){
			charsonly = TRUE;
			break;
		}
	* =>
		charsonly = TRUE;
		editerror("newline expected");
	}
	printposn(t, charsonly);
	return TRUE;
}

nl_cmd(t: ref Text, cp: ref Cmd): int
{
	a: Address;
	f: ref File;

	f = t.file;
	if(cp.addr == nil){
		# First put it on newline boundaries
		a = mkaddr(f);
		addr = lineaddr(0, a, -1);
		a = lineaddr(0, a, 1);
		addr.r.q1 = a.r.q1;
		if(addr.r.q0==t.q0 && addr.r.q1==t.q1){
			a = mkaddr(f);
			addr = lineaddr(1, a, 1);
		}
	}
	t.show(addr.r.q0, addr.r.q1);
	return TRUE;
}

append(f: ref File, cp: ref Cmd, p: int): int
{
	if(cp.text.n > 0)
		eloginsert(f, p, cp.text.r, cp.text.n);
	return TRUE;
}

pdisplay(f: ref File): int
{
	p1, p2: int;
	np: int;
	buf: ref Astring;

	p1 = addr.r.q0;
	p2 = addr.r.q1;
	if(p2 > f.buf.nc)
		p2 = f.buf.nc;
	buf = stralloc(BUFSIZE);
	while(p1 < p2){
		np = p2-p1;
		if(np>BUFSIZE-1)
			np = BUFSIZE-1;
		f.buf.read(p1, buf, 0, np);
		warning(nil, sprint("%s", buf.s[0:np]));
		p1 += np;
	}
	strfree(buf);
	f.curtext.q0 = addr.r.q0;
	f.curtext.q1 = addr.r.q1;
	return TRUE;
}

pfilename(f: ref File)
{
	dirty: int;
	w: ref Window;

	w = f.curtext.w;
	# same check for dirty as in settag, but we know ncache==0
	dirty = !w.isdir && !w.isscratch && f.mod;
	warning(nil, sprint("%c%c%c %s\n", " '"[dirty],
		'+', " ."[curtext!=nil && curtext.file==f], f.name));
}

loopcmd(f: ref File, cp: ref Cmd, rp: array of Range, nrp: int)
{
	i: int;

	for(i=0; i<nrp; i++){
		f.curtext.q0 = rp[i].q0;
		f.curtext.q1 = rp[i].q1;
		cmdexec(f.curtext, cp);
	}
}

looper(f: ref File, cp: ref Cmd, xy: int)
{
	p, op, nrp, ok: int;
	r, tr: Range;
	rp: array of  Range;

	r = addr.r;
	if(xy)
		op = -1;
	else
		op = r.q0;
	nest++;
	if(rxcompile(cp.re.r) == FALSE)
		editerror(sprint("bad regexp in %c command", cp.cmdc));
	nrp = 0;
	rp = nil;
	for(p = r.q0; p<=r.q1; ){
		(ok, sel) = rxexecute(f.curtext, nil, p, r.q1);
		if(!ok){ # no match, but y should still run
			if(xy || op>r.q1)
				break;
			tr.q0 = op;
			tr.q1 = r.q1;
			p = r.q1+1;	# exit next loop
		}else{
			if(sel[0].q0==sel[0].q1){	# empty match?
				if(sel[0].q0==op){
					p++;
					continue;
				}
				p = sel[0].q1+1;
			}else
				p = sel[0].q1;
			if(xy)
				tr = sel[0];
			else{
				tr.q0 = op;
				tr.q1 = sel[0].q0;
			}
		}
		op = sel[0].q1;
		nrp++;
		orp := rp;
		rp = array[nrp] of Range;
		rp[0: ] = orp[0: nrp-1];
		rp[nrp-1] = tr;
		orp = nil;
	}
	loopcmd(f, cp.cmd, rp, nrp);
	rp = nil;
	--nest;
}

linelooper(f: ref File, cp: ref Cmd)
{
	nrp, p: int;
	r, linesel: Range;
	a, a3: Address;
	rp: array of Range;

	nest++;
	nrp = 0;
	rp = nil;
	r = addr.r;
	a3.f = f;
	a3.r.q0 = a3.r.q1 = r.q0;
	a = lineaddr(0, a3, 1);
	linesel = a.r;
	for(p = r.q0; p<r.q1; p = a3.r.q1){
		a3.r.q0 = a3.r.q1;
		if(p!=r.q0 || linesel.q1==p){
			a = lineaddr(1, a3, 1);
			linesel = a.r;
		}
		if(linesel.q0 >= r.q1)
			break;
		if(linesel.q1 >= r.q1)
			linesel.q1 = r.q1;
		if(linesel.q1 > linesel.q0)
			if(linesel.q0>=a3.r.q1 && linesel.q1>a3.r.q1){
				a3.r = linesel;
				nrp++;
				orp := rp;
				rp = array[nrp] of Range;
				rp[0: ] = orp[0: nrp-1];
				rp[nrp-1] = linesel;
				orp = nil;
				continue;
			}
		break;
	}
	loopcmd(f, cp.cmd, rp, nrp);
	rp = nil;
	--nest;
}

loopstruct: ref Looper;

alllooper(w: ref Window, lp: ref Looper)
{
	t: ref Text;
	cp: ref Cmd;

	cp = lp.cp;
#	if(w.isscratch || w.isdir)
#		return;
	t = w.body;
	# only use this window if it's the current window for the file
	if(t.file.curtext != t)
		return;
#	if(w.nopen[QWevent] > 0)
#		return;
	# no auto-execute on files without names
	if(cp.re==nil && t.file.name==nil)
		return;
	if(cp.re==nil || filematch(t.file, cp.re)==lp.XY){
		olpw := lp.w;
		lp.w = array[lp.nw+1] of ref Window;
		lp.w[0: ] = olpw[0: lp.nw];
		lp.w[lp.nw++] = w;
		olpw = nil;
	}
}

filelooper(cp: ref Cmd, XY: int)
{
	i: int;

	if(Glooping++)
		editerror(sprint("can't nest %c command", "YX"[XY]));
	nest++;

	if(loopstruct == nil)
		loopstruct = ref Looper;
	loopstruct.cp = cp;
	loopstruct.XY = XY;
	if(loopstruct.w != nil)	# error'ed out last time
		loopstruct.w = nil;
	loopstruct.w = nil;
	loopstruct.nw = 0;
	aw := ref Allwin.LP(loopstruct);
	allwindows(Edit->ALLLOOPER, aw);
	aw = nil;
	for(i=0; i<loopstruct.nw; i++)
		cmdexec(loopstruct.w[i].body, cp.cmd);
	loopstruct.w = nil;

	--Glooping;
	--nest;
}

nextmatch(f: ref File, r: ref String, p: int, sign: int)
{
	ok: int;

	if(rxcompile(r.r) == FALSE)
		editerror("bad regexp in command address");
	if(sign >= 0){
		(ok, sel) = rxexecute(f.curtext, nil, p, 16r7FFFFFFF);
		if(!ok)
			editerror("no match for regexp");
		if(sel[0].q0==sel[0].q1 && sel[0].q0==p){
			if(++p>f.buf.nc)
				p = 0;
			(ok, sel) = rxexecute(f.curtext, nil, p, 16r7FFFFFFF);
			if(!ok)
				editerror("address");
		}
	}else{
		(ok, sel) = rxbexecute(f.curtext, p);
		if(!ok)
			editerror("no match for regexp");
		if(sel[0].q0==sel[0].q1 && sel[0].q1==p){
			if(--p<0)
				p = f.buf.nc;
			(ok, sel) = rxbexecute(f.curtext, p);
			if(!ok)
				editerror("address");
		}
	}
}

cmdaddress(ap: ref Addr, a: Address, sign: int): Address
{
	f := a.f;
	a1, a2: Address;

	do{
		case(ap.typex){
		'l' or
		'#' =>
			if(ap.typex == '#')
				a = charaddr(ap.num, a, sign);
			else
				a = lineaddr(ap.num, a, sign);
			break;

		'.' =>
			a = mkaddr(f);
			break;

		'$' =>
			a.r.q0 = a.r.q1 = f.buf.nc;
			break;

		'\'' =>
editerror("can't handle '");
#			a.r = f.mark;
			break;

		'?' =>
			sign = -sign;
			if(sign == 0)
				sign = -1;
			if(sign >= 0)
				v := a.r.q1;
			else
				v = a.r.q0;
			nextmatch(f, ap.re, v, sign);
			a.r = sel[0];
			break;

		'/' =>
			if(sign >= 0)
				v := a.r.q1;
			else
				v = a.r.q0;
			nextmatch(f, ap.re, v, sign);
			a.r = sel[0];
			break;

		'"' =>
			f = matchfile(ap.re);
			a = mkaddr(f);
			break;

		'*' =>
			a.r.q0 = 0;
			a.r.q1 = f.buf.nc;
			return a;

		',' or
		';' =>
			if(ap.left!=nil)
				a1 = cmdaddress(ap.left, a, 0);
			else{
				a1.f = a.f;
				a1.r.q0 = a1.r.q1 = 0;
			}
			if(ap.typex == ';'){
				f = a1.f;
				a = a1;
				f.curtext.q0 = a1.r.q0;
				f.curtext.q1 = a1.r.q1;
			}
			if(ap.next!=nil)
				a2 = cmdaddress(ap.next, a, 0);
			else{
				a2.f = a.f;
				a2.r.q0 = a2.r.q1 = f.buf.nc;
			}
			if(a1.f != a2.f)
				editerror("addresses in different files");
			a.f = a1.f;
			a.r.q0 = a1.r.q0;
			a.r.q1 = a2.r.q1;
			if(a.r.q1 < a.r.q0)
				editerror("addresses out of order");
			return a;

		'+' or
		'-' =>
			sign = 1;
			if(ap.typex == '-')
				sign = -1;
			if(ap.next==nil || ap.next.typex=='+' || ap.next.typex=='-')
				a = lineaddr(1, a, sign);
			break;
		* =>
			error("cmdaddress");
			return a;
		}
	}while((ap = ap.next)!=nil);	# assign =
	return a;
}

alltofile(w: ref Window, tp: ref Tofile)
{
	t: ref Text;

	if(tp.f != nil)
		return;
	if(w.isscratch || w.isdir)
		return;
	t = w.body;
	# only use this window if it's the current window for the file
	if(t.file.curtext != t)
		return;
#	if(w.nopen[QWevent] > 0)
#		return;
	if(tp.r.r == t.file.name)
		tp.f = t.file;
}

tofile(r: ref String): ref File
{
	t: ref Tofile;
	rr: String;

	(rr.r, r.n) = skipbl(r.r, r.n);
	t = ref Tofile;
	t.f = nil;
	t.r = ref String;
	*t.r = rr;
	aw := ref Allwin.FF(t);
	allwindows(Edit->ALLTOFILE, aw);
	aw = nil;
	if(t.f == nil)
		editerror(sprint("no such file\"%s\"", rr.r));
	return t.f;
}

allmatchfile(w: ref Window, tp: ref Tofile)
{
	t: ref Text;

	if(w.isscratch || w.isdir)
		return;
	t = w.body;
	# only use this window if it's the current window for the file
	if(t.file.curtext != t)
		return;
#	if(w.nopen[QWevent] > 0)
#		return;
	if(filematch(w.body.file, tp.r)){
		if(tp.f != nil)
			editerror(sprint("too many files match \"%s\"", tp.r.r));
		tp.f = w.body.file;
	}
}

matchfile(r: ref String): ref File
{
	tf: ref Tofile;

	tf = ref Tofile;
	tf.f = nil;
	tf.r = r;
	aw := ref Allwin.FF(tf);
	allwindows(Edit->ALLMATCHFILE, aw);
	aw = nil;

	if(tf.f == nil)
		editerror(sprint("no file matches \"%s\"", r.r));
	return tf.f;
}

filematch(f: ref File, r: ref String): int
{
	buf: string;
	w: ref Window;
	match, i, dirty: int;
	s: Rangeset;

	# compile expr first so if we get an error, we haven't allocated anything
	if(rxcompile(r.r) == FALSE)
		editerror("bad regexp in file match");
	w = f.curtext.w;
	# same check for dirty as in settag, but we know ncache==0
	dirty = !w.isdir && !w.isscratch && f.mod;
	buf = sprint("%c%c%c %s\n", " '"[dirty],
		'+', " ."[curtext!=nil && curtext.file==f], f.name);
	(match, s) = rxexecute(nil, buf, 0, i);
	buf = nil;
	return match;
}

charaddr(l: int, addr: Address, sign: int): Address
{
	if(sign == 0)
		addr.r.q0 = addr.r.q1 = l;
	else if(sign < 0)
		addr.r.q1 = addr.r.q0 -= l;
	else if(sign > 0)
		addr.r.q0 = addr.r.q1 += l;
	if(addr.r.q0<0 || addr.r.q1>addr.f.buf.nc)
		editerror("address out of range");
	return addr;
}

lineaddr(l: int, addr: Address, sign: int): Address
{
	n: int;
	c: int;
	f := addr.f;
	a: Address;
	p: int;

	a.f = f;
	if(sign >= 0){
		if(l == 0){
			if(sign==0 || addr.r.q1==0){
				a.r.q0 = a.r.q1 = 0;
				return a;
			}
			a.r.q0 = addr.r.q1;
			p = addr.r.q1-1;
		}else{
			if(sign==0 || addr.r.q1==0){
				p = 0;
				n = 1;
			}else{
				p = addr.r.q1-1;
				n = f.curtext.readc(p++)=='\n';
			}
			while(n < l){
				if(p >= f.buf.nc)
					editerror("address out of range");
				if(f.curtext.readc(p++) == '\n')
					n++;
			}
			a.r.q0 = p;
		}
		while(p < f.buf.nc && f.curtext.readc(p++)!='\n')
			;
		a.r.q1 = p;
	}else{
		p = addr.r.q0;
		if(l == 0)
			a.r.q1 = addr.r.q0;
		else{
			for(n = 0; n<l; ){	# always runs once
				if(p == 0){
					if(++n != l)
						editerror("address out of range");
				}else{
					c = f.curtext.readc(p-1);
					if(c != '\n' || ++n != l)
						p--;
				}
			}
			a.r.q1 = p;
			if(p > 0)
				p--;
		}
		while(p > 0 && f.curtext.readc(p-1)!='\n')	# lines start after a newline
			p--;
		a.r.q0 = p;
	}
	return a;
}

allfilecheck(w: ref Window, fp: ref Filecheck)
{
	f: ref File;

	f = w.body.file;
	if(w.body.file == fp.f)
		return;
	if(fp.r == f.name)
		warning(nil, sprint("warning: duplicate file name \"%s\"\n", fp.r));
}

cmdname(f: ref File, str: ref String , set: int): string
{
	r, s: string;
	n: int;
	fc: ref Filecheck;
	newname: Runestr;

	r = nil;
	n = str.n;
	s = str.r;
	if(n == 0){
		# no name; use existing
		if(f.name == nil)
			return nil;
		return f.name;
	}
	(s, n) = skipbl(s, n);
	if(n == 0)
		;
	else{
		if(s[0] == '/'){
			r = s;
		}else{
			newname = dirname(f.curtext, s, n);
			r = newname.r;
			n = newname.nr;
		}
		fc = ref Filecheck;
		fc.f = f;
		fc.r = r;
		fc.nr = n;
		aw := ref Allwin.FC(fc);
		allwindows(Edit->ALLFILECHECK, aw);
		aw = nil;
		if(f.name == nil)
			set = TRUE;
	}

	if(set && r[0: n] != f.name){
		f.mark();
		f.mod = TRUE;
		f.curtext.w.dirty = TRUE;
		f.curtext.w.setname(r, n);
	}
	return r;
}

copysel(rs: Rangeset): Rangeset
{
	nrs := array[NRange] of Range;
	for(i := 0; i < NRange; i++)
		nrs[i] = rs[i];
	return nrs;
}
	