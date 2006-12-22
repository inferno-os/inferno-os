implement Debug;

include "sys.m";
sys: Sys;
sprint, FD: import sys;

include "string.m";
str: String;

include "draw.m";

include "debug.m";

include "dis.m";
	dism: Dis;

Command: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Spin: adt
{
	spin:	int;
	pspin:	int;
};

SrcState: adt
{
	files:	array of string;
	lastf:	int;
	lastl:	int;
	vers:	int;			# version number
					# 11 => more source states
};

typenames := array[] of {
	Terror => "error",
	Tid => "id",
	Tadt => "adt",
	Tadtpick => "adtpick",
	Tarray => "array",
	Tbig => "big",
	Tbyte => "byte",
	Tchan => "chan",
	Treal => "real",
	Tfn => "fn",
	Targ => "arg",
	Tlocal => "local",
	Tglobal => "global",
	Tint => "int",
	Tlist => "list",
	Tmodule => "module",
	Tnil => "nil",
	Tnone => "none",
	Tref => "ref",
	Tstring => "string",
	Ttuple => "tuple",
	Tend => "end",
	Targs => "args",
	Tslice => "slice",
	Tpoly => "poly",
};

tnone:		ref Type;
tnil:		ref Type;
tint:		ref Type;
tbyte:		ref Type;
tbig:		ref Type;
treal:		ref Type;
tstring:	ref Type;
tpoly:	ref Type;

IBY2WD:		con 4;
IBY2LG:		con 8;
H:		con int 16rffffffff;

ModHash:	con 32;
SymHash:	con 32;
mods:=		array[ModHash] of list of ref Module;
syms:=		array[SymHash] of list of ref Sym;

sblpath :=	array[] of
{
	("/dis/",	"/appl/cmd/"),
	("/dis/",	"/appl/"),
};

init(): int
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	if(sys == nil || str == nil)
		return 0;
	tnone = ref Type(nil, Tnone, 0, "", nil, nil, nil);
	tnil = ref Type(nil, Tnil, IBY2WD, "nil", nil, nil, nil);
	tint = ref Type(nil, Tint, IBY2WD, "int", nil, nil, nil);
	tbyte = ref Type(nil, Tbyte, 1, "byte", nil, nil, nil);
	tbig = ref Type(nil, Tbig, IBY2LG, "big", nil, nil, nil);
	treal = ref Type(nil, Treal, IBY2LG, "real", nil, nil, nil);
	tstring = ref Type(nil, Tstring, IBY2WD, "string", nil, nil, nil);
	tpoly = ref Type(nil, Tpoly, IBY2WD, "polymorphic", nil, nil, nil);
	return 1;
}

prog(pid: int): (ref Prog, string)
{
	spid := string pid;
	h := sys->open("/prog/"+spid+"/heap", sys->ORDWR);
	if(h == nil)
		return (nil, sprint("can't open heap file: %r"));
	c := sys->open("/prog/"+spid+"/ctl", sys->OWRITE);
	if(c == nil)
		return (nil, sprint("can't open ctl file: %r"));
	d := sys->open("/prog/"+spid+"/dbgctl", sys->ORDWR);
	if(d == nil)
		return (nil, sprint("can't open debug ctl file: %r"));
	s := sys->open("/prog/"+spid+"/stack", sys->OREAD);
	if(s == nil)
		return (nil, sprint("can't open stack file: %r"));
	return (ref Prog(pid, h, c, d, s), "");
}

startprog(dis, dir: string, ctxt: ref Draw->Context, argv: list of string): (ref Prog, string)
{
	c := load Command dis;
	if(c == nil)
		return (nil, "module not loaded");

	ack := chan of int;
	spin := ref Spin(1, 1);
	end := chan of int;
	spawn execer(ack, dir, c, ctxt, argv, spin, end);
	kid := <-ack;

	fd := sys->open("/prog/"+string kid+"/dbgctl", sys->ORDWR);
	if(fd == nil){
		spin.spin = -1;
		<- end;
		return (nil, sprint("can't open debug ctl file: %r"));
	}
	done := chan of string;
	spawn stepper(done, fd, spin);

wait:	for(;;){
		alt{
		<-ack =>
			sys->sleep(0);
		err := <-done =>
			if(err != ""){
				<- end;
				return(nil, err);
			}
			break wait;
		}
	}

	b := array[20] of byte;
	n := sys->read(fd, b, len b);
	if(n <= 0){
		<- end;
		return(nil, sprint("%r"));
	}
	msg := string b[:n];
	if(!str->prefix("new ", msg)){
		<- end;
		return (nil, msg);
	}

	kid = int msg[len "new ":];

	# clean up the execer slave
	b = array of byte "start";
	sys->write(fd, b, len b);

	<- end;
	return prog(kid);
}

stepper(done: chan of string, ctl: ref FD, spin: ref Spin)
{
	b := array of byte "step1";
	while(spin.pspin){
		if(sys->write(ctl, b, len b) != len b)
			done <-= sprint("can't start new thread: %r");
		spin.spin = 0;
	}
	done <-= "";
}

execer(ack: chan of int, dir: string, c: Command, ctxt: ref Draw->Context, args: list of string, spin: ref Spin, end: chan of int)
{
	pid := sys->pctl(Sys->NEWPGRP|Sys->FORKNS|Sys->NEWFD, 0::1::2::nil);
	sys->chdir(dir);
	while(spin.spin == 1)
		ack <-= pid;
	if(spin.spin == -1){
		end <-= 0;
		exit;
	}
	spawn c->init(ctxt, args);
	spin.pspin = 0;
	end <-= 0;
	exit;
}

# format of each line is
# fp pc mp prog compiled path
# fp, pc, mp, and prog are %.8lux
# compile is  or 1
# path is a string
Prog.stack(p: self ref Prog): (array of ref Exp, string)
{
	buf := array[8192] of byte;
	sys->seek(p.stk, big 0, 0);
	n := sys->read(p.stk, buf, len buf - 1);
	if(n < 0)
		return (nil, sprint("can't read stack file: %r"));
	buf[n] = byte 0;

	t := 0;
	nf := 0;
	for(s := 0; s < n; s = t+1){
		t = strchr(buf, s, '\n');
		if(buf[t] != byte '\n' || t-s < 40)
			continue;
		nf++;
	}

	e := array[nf] of ref Exp;
	nf = 0;
	for(s = 0; s < n; s = t+1){
		t = strchr(buf, s, '\n');
		if(buf[t] != byte '\n' || t-s < 40)
			continue;
		e[nf] = ref Exp("unknown fn",
				hex(buf[s+0:s+8]), 
				hex(buf[s+9:s+17]),
				mkmod(hex(buf[s+18:s+26]), hex(buf[s+27:s+35]), buf[36] != byte '0', string buf[s+38:t]),
				p,
				nil);
		nf++;
	}

	return (e, "");
}

Prog.step(p: self ref Prog, how: int): string
{
	(stack, nil) := p.stack();
	if(stack == nil)
		return "can't find initial pc";
	src := stack[0].srcstr();
	stmt := ftostmt(stack[0]);

	if(stack[0].m.sym == nil)
		how = -1;

	buf := array of byte("step1");
	if(how == StepOut)
		buf = array of byte("toret");
	while(sys->write(p.dbgctl, buf, len buf) == len buf){
		(stk, err) := p.stack();
		if(err != nil)
			return "";
		case how{
		StepExp =>
			if(src != stk[0].srcstr())
				return "";
		StepStmt =>
			if(stmt != ftostmt(stk[0]))
				return "";
			if(stk[0].offset != stack[0].offset)
				return "";
		StepOut =>
			if(returned(stack, stk))
				return "";
		StepOver =>
			if(stk[0].offset == stack[0].offset){
				if(stmt != ftostmt(stk[0]))
					return "";
				buf = array of byte("step1");
				break;
			}
			if(returned(stack, stk))
				return "";
			buf = array of byte("toret");
		* =>
			return "";
		}
	}
	return sprint("%r");
}

Prog.stop(p: self ref Prog): string
{
	return dbgctl(p, "stop");
}

Prog.unstop(p: self ref Prog): string
{
	return dbgctl(p, "unstop");
}

Prog.grab(p: self ref Prog): string
{
	return dbgctl(p, "step0");
}

Prog.start(p: self ref Prog): string
{
	return dbgctl(p, "start");
}

Prog.cont(p: self ref Prog): string
{
	return dbgctl(p, "cont");
}

dbgctl(p: ref Prog, msg: string): string
{
	b := array of byte msg;
	while(sys->write(p.dbgctl, b, len b) != len b)
		return sprint("%r");
	return "";
}

returned(old, new: array of ref Exp): int
{
	n := len old;
	if(n > len new)
		return 1;
	return 0;
}

Prog.setbpt(p: self ref Prog, dis: string, pc:int): string
{
	b := array of byte("bpt set "+dis+" "+string pc);
	if(sys->write(p.dbgctl, b, len b) != len b)
		return sprint("can't set breakpoint: %r");
	return "";
}

Prog.delbpt(p: self ref Prog, dis: string, pc:int): string
{
	b := array of byte("bpt del "+dis+" "+string pc);
	if(sys->write(p.dbgctl, b, len b) != len b)
		return sprint("can't del breakpoint: %r");
	return "";
}

Prog.kill(p: self ref Prog): string
{
	b := array of byte "kill";
	if(sys->write(p.ctl, b, len b) != len b)
		return sprint("can't kill process: %r");
	return "";
}

Prog.event(p: self ref Prog): string
{
	b := array[100] of byte;
	n := sys->read(p.dbgctl, b, len b);
	if(n < 0)
		return sprint("error: %r");
	return string b[:n];
}

ftostmt(e: ref Exp): int
{
	m := e.m;
	if(!m.comp && m.sym != nil && e.pc < len m.sym.srcstmt)
		return m.sym.srcstmt[e.pc];
	return -1;
}

Exp.srcstr(e: self ref Exp): string
{
	m := e.m;
	if(!m.comp && m.sym != nil && e.pc < len m.sym.src){
		src := m.sym.src[e.pc];
		ss := src.start.file+":"+string src.start.line+"."+string src.start.pos+", ";
		if(src.stop.file != src.start.file)
			ss += src.stop.file+":"+string src.stop.line+".";
		else if(src.stop.line != src.start.line)
			ss += string src.stop.line+".";
		return ss+string src.stop.pos;
	}
	return sprint("Module %s PC %d", e.m.path, e.pc);
}

Exp.findsym(e: self ref Exp): string
{
	m := e.m;
	if(m.comp)
		return "compiled module";
	if(m.sym != nil){
		n := e.pc;
		fns := m.sym.fns;
		for(i := 0; i < len fns; i++){
			if(n >= fns[i].offset && n < fns[i].stoppc){
				e.name = fns[i].name;
				e.id = fns[i];
				return "";
			}
		}
		return "pc out of bounds";
	}
	return "no symbol file";
}

Exp.src(e: self ref Exp): ref Src
{
	m := e.m;
	if(e.id == nil || m.sym == nil)
		return nil;
	src := e.id.src;
	if(src != nil)
		return src;
	if(e.id.t.kind == Tfn && !m.comp && e.pc < len m.sym.src && e.pc >= 0)
		return m.sym.src[e.pc];
	return nil;
}

Type.getkind(t: self ref Type, sym: ref Sym): int
{
	if(t == nil)
		return -1;
	if(t.kind == Tid)
		return sym.adts[int t.name].getkind(sym);
	return t.kind;
}

Type.text(t: self ref Type, sym: ref Sym): string
{
	if (t == nil)
		return "no type";
	s := typenames[t.kind];
	case t.kind {
	Tadt or
	Tadtpick or
	Tmodule =>
		s = t.name;
	Tid =>
		return sym.adts[int t.name].text(sym);
	Tarray or
	Tlist or
	Tchan or
	Tslice =>
		s += " of " + t.Of.text(sym);
	Tref =>
		s += " " + t.Of.text(sym);
	Tfn =>
		s += "(";	
		for(i := 0; i < len t.ids; i++)
			s += t.ids[i].name + ": " + t.ids[i].t.text(sym);
		s += "): " + t.Of.text(sym);
	Ttuple or
	Tlocal or
	Tglobal or
	Targ =>
		if(t.kind == Ttuple)
			s = "";
		s += "(";
		for (i := 0; i < len t.ids; i++) {
			s += t.ids[i].t.text(sym);
			if (i < len t.ids - 1)
				s += ", ";
		}
		s += ")";
	}
	return s;
}

Exp.typename(e: self ref Exp): string
{
	if (e.id == nil)
		return "no info";
	return e.id.t.text(e.m.sym);
}

Exp.kind(e: self ref Exp): int
{
	if(e.id == nil)
		return -1;
	return e.id.t.getkind(e.m.sym);
}

EXPLISTMAX : con	32;	# what's a good value for this ?

Exp.expand(e: self ref Exp): array of ref Exp
{
	if(e.id == nil)
		return nil;

	t := e.id.t;
	if(t.kind == Tid)
		t = e.m.sym.adts[int t.name];

	off := e.offset;
	ids := t.ids;
	case t.kind{
	Tadt or Tfn or Targ or Tlocal or Ttuple =>
		break;
	Tadtpick =>
		break;
	Tglobal =>
		ids = e.m.sym.vars;
		off = e.m.data;
	Tmodule =>
		(s, err) := pdata(e.p, off, "M");
		if(s == "nil" || err != "")
			return nil;
		off = hex(array of byte s);
	Tref =>
		(s, err) := pdata(e.p, off, "P");
		if(s == "nil" || err != "")
			return nil;
		off = hex(array of byte s);
		et := t.Of;
		if(et.kind == Tid)
			et = e.m.sym.adts[int et.name];
		ids = et.ids;
		if(et.kind == Tadtpick){
			(s, err) = pdata(e.p, off, "W");
			tg := int s;
			if(tg < 0 || tg > len et.tags || err != "" )
				return nil;
			k := array[1 + len ids + len et.tags[tg].ids] of ref Exp;
			k[0] = ref Exp(et.tags[tg].name, off+0, e.pc, e.m, e.p, ref Id(et.src, et.tags[tg].name, 0, 0, tint));
			x := 1;
			for(i := 0; i < len ids; i++){
				id := ids[i];
				k[i+x] = ref Exp(id.name, off+id.offset, e.pc, e.m, e.p, id);
			}
			x += len ids;
			ids = et.tags[tg].ids;
			for(i = 0; i < len ids; i++){
				id := ids[i];
				k[i+x] = ref Exp(id.name, off+id.offset, e.pc, e.m, e.p, id);
			}
			return k;
		}
	Tlist =>
		(s, err) := pdata(e.p, off, "L");
		if(err != "")
			return nil;
		(tloff, hdoff) := str->splitl(s, ".");
		hdoff = hdoff[1:];
		k := array[2] of ref Exp;
		k[0] = ref Exp("hd", hex(array of byte hdoff), e.pc, e.m, e.p, ref Id(nil, "hd", H, H, t.Of));
		k[1] = ref Exp("tl", hex(array of byte tloff), e.pc, e.m, e.p, ref Id(nil, "tl", H, H, t));
		return k;
	Tarray =>
		(s, err) := pdata(e.p, e.offset, "A");
		if(s == "nil")
			return nil;
		(sn, sa) := str->splitl(s, ".");
		n := int sn;
		if(sa == "" || n <= 0)
			return nil;
		(off, nil) = str->toint(sa[1:], 16);
		et := t.Of;
		if(et.kind == Tid)
			et = e.m.sym.adts[int et.name];
		esize := et.size;
		if (n <= EXPLISTMAX || EXPLISTMAX == 0) {
			k := array[n] of ref Exp;
			for(i := 0; i < n; i++){
				name := string i;
				k[i] = ref Exp(name, off+i*esize, e.pc, e.m, e.p, ref Id(nil, name, H, H, et));
			}
			return k;
		}
		else {
			# slice it
			(p, q, r) := partition(n, EXPLISTMAX);
			lb := 0;
			k := array[p] of ref Exp;
			st := ref Type(et.src, Tslice, 0, nil, et, nil, nil);
			for (i := 0; i < p; i++){
				ub := lb+q-1;
				if (--r >= 0)
					ub++;
				name := string lb + ".." + string ub;
				k[i] = ref Exp(name, off+lb*esize, e.pc, e.m, e.p, ref Id(nil, name, H, H, st));
				lb = ub+1;
			}
			return k;	
		}
	Tslice =>
		(lb, ub) := bounds(e.name);
		if (lb > ub)
			return nil;
		n := ub-lb+1;
		et := t.Of;
		if(et.kind == Tid)
			et = e.m.sym.adts[int et.name];
		esize := et.size;
		if (n <= EXPLISTMAX || EXPLISTMAX == 0) {
			k := array[n] of ref Exp;
			for(i := 0; i < n; i++){
				name := string (i+lb);
				k[i] = ref Exp(name, off+i*esize, e.pc, e.m, e.p, ref Id(nil, name, H, H, et));
			}
			return k;
		}
		else {
			# slice it again
			(p, q, r) := partition(n, EXPLISTMAX);
			lb0 := lb;
			k := array[p] of ref Exp;
			st := ref Type(et.src, Tslice, 0, nil, et, nil, nil);
			for (i := 0; i < p; i++){
				ub = lb+q-1;
				if (--r >= 0)
					ub++;
				name := string lb + ".." + string ub;
				k[i] = ref Exp(name, off+(lb-lb0)*esize, e.pc, e.m, e.p, ref Id(nil, name, H, H, st));
				lb = ub+1;
			}
			return k;
		}	
	Tchan =>
		(s, err) := pdata(e.p, e.offset, "c");
		if(s == "nil")
			return nil;
		(sn, sa) := str->splitl(s, ".");
		n := int sn;
		if(sa == "" || n <= 0)
			return nil;
		(off, nil) = str->toint(sa[1:], 16);
		(nil, sa) = str->splitl(sa[1:], ".");
		(sn, sa) = str->splitl(sa[1:], ".");
		f := int sn;
		sz := int sa[1:];
		et := t.Of;
		if(et.kind == Tid)
			et = e.m.sym.adts[int et.name];
		esize := et.size;
		k := array[sz] of ref Exp;
		for(i := 0; i < sz; i++){
			name := string i;
			j := (f+i)%n;
			k[i] = ref Exp(name, off+j*esize, e.pc, e.m, e.p, ref Id(nil, name, H, H, et));
		}
		return k;
	* =>
		return nil;
	}
	k := array[len ids] of ref Exp;
	for(i := 0; i < len k; i++){
		id := ids[i];
		k[i] = ref Exp(id.name, off+id.offset, e.pc, e.m, e.p, id);
	}
	return k;
}

Exp.val(e: self ref Exp): (string, int)
{
	if(e.id == nil)
		return (e.m.path+" unknown fn", 0);
	t := e.id.t;
	if(t.kind == Tid)
		t = e.m.sym.adts[int t.name];

	w := 0;
	s := "";
	err := "";
	p := e.p;
	case t.kind{
	Tfn =>
		if(t.ids != nil)
			w = 1;
		src := e.m.sym.src[e.pc];
		ss := src.start.file+":"+string src.start.line+"."+string src.start.pos+", ";
		if(src.stop.file != src.start.file)
			ss += src.stop.file+":"+string src.stop.line+".";
		else if(src.stop.line != src.start.line)
			ss += string src.stop.line+".";
		return (ss+string src.stop.pos, w);
	Targ or Tlocal or Tglobal or Tadtpick or Ttuple =>
		return ("", 1);
	Tadt =>
		return ("#" + string e.offset, 1);
	Tnil =>
		s = "nil";
	Tbyte =>
		(s, err) = pdata(p, e.offset, "B");
	Tint =>
		(s, err) = pdata(p, e.offset, "W");
	Tbig =>
		(s, err) = pdata(p, e.offset, "V");
	Treal =>
		(s, err) = pdata(p, e.offset, "R");
	Tarray =>
		(s, err) = pdata(p, e.offset, "A");
		if(s == "nil")
			break;
		(n, a) := str->splitl(s, ".");
		if(a == "")
			return ("", 0);
		s = "["+n+"] @"+a[1:];
		w = 1;
	Tslice =>
		(lb, ub) := bounds(e.name);
		s = sys->sprint("[:%d] @ %x", ub-lb+1, e.offset);
		w = 1;
	Tstring =>
		n : int;
		(n, s, err) = pstring(p, e.offset);
		if(err != "")
			return ("", 0);
		for(i := 0; i < len s; i++)
			if(s[i] == '\n')
				s[i] = '\u008a';
		s = "["+string n+"] \""+s+"\"";
	Tref or Tlist or Tmodule or Tpoly=>
		(s, err) = pdata(p, e.offset, "P");
		if(s == "nil")
			break;
		s = "@" + s;
		w = 1;
	Tchan =>
		(s, err) = pdata(p, e.offset, "c");
		if(s == "nil")
			break;
		(n, a) := str->splitl(s, ".");
		if(a == "")
			return ("", 0);
		if(n == "0"){
			s = "@" + a[1:];
			w = 0;
		}
		else{
			(a, nil) = str->splitl(a[1:], ".");
			s = "["+n+"] @"+a;
			w = 1;
		}
	}
	if(err != "")
		return ("", 0);
	return (s, w);
}

Sym.srctopc(s: self ref Sym, src: ref Src): int
{
	srcs := s.src;
	line := src.start.line;
	pos := src.start.pos;
	(nil, file) := str->splitr(src.start.file, "/");
	backup := -1;
	delta := 80;
	for(i := 0; i < len srcs; i++){
		ss := srcs[i];
		if(ss.start.file != file)
			continue;
		if(ss.start.line <= line && ss.start.pos <= pos
		&& ss.stop.line >= line && ss.stop.pos >= pos)
			return i;
		d := ss.start.line - line;
		if(d >= 0 && d < delta){
			delta = d;
			backup = i;
		}
	}
	return backup;
}

Sym.pctosrc(s: self ref Sym, pc: int): ref Src
{
	if(pc < 0 || pc >= len s.src)
		return nil;
	return s.src[pc];
}

sym(sbl: string): (ref Sym, string)
{
	h := 0;
	for(i := 0; i < len sbl; i++)
		h = (h << 1) + sbl[i];
	h &= SymHash - 1;
	for(sl := syms[h]; sl != nil; sl = tl sl){
		s := hd sl;
		if(sbl == s.path)
			return (s, "");
	}
	(sy, err) := loadsyms(sbl);
	if(err != "")
		return (nil, err);
	syms[h] = sy :: syms[h];
	return (sy, "");
}

Module.addsym(m: self ref Module, sym: ref Sym)
{
	m.sym = sym;
}

Module.sbl(m: self ref Module): string
{
	if(m.sym != nil)
		return m.sym.path;
	return "";
}

Module.dis(m: self ref Module): string
{
	return m.path;
}

findsbl(dis: string): string
{
	n  := len dis;
	if(n <= 4 || dis[n-4: n] != ".dis")
		dis += ".dis";
	if(dism == nil){
		dism = load Dis Dis->PATH;
		if(dism != nil)
			dism->init();
	}
	if(dism != nil && (b := dism->src(dis)) != nil){
		n = len b;
		if(n > 2 && b[n-2: n] == ".b"){
			sbl := b[0: n-2] + ".sbl";
			if(sys->open(sbl, Sys->OREAD) != nil)
				return sbl;
		}
	}	
	return nil;	
}

Module.stdsym(m: self ref Module)
{
	if(m.sym != nil)
		return;
	if((sbl := findsbl(m.path)) != nil){
		(m.sym, nil) = sym(sbl);
		return;
	}
	sbl = m.path;
	n := len sbl;
	if(n > 4 && sbl[n-4:n] == ".dis")
		sbl = sbl[:n-4]+".sbl";
	else
		sbl = sbl+".sbl";
	path := sbl;
	fd := sys->open(sbl, sys->OREAD);
	for(i := 0; fd == nil && i < len sblpath; i++){
		(dis, src) := sblpath[i];
		nd := len dis;
		if(len sbl > nd && sbl[:nd] == dis){
			path = src + sbl[nd:];
			fd = sys->open(path, sys->OREAD);
		}
	}
	if(fd == nil)
		return;
	(m.sym, nil) = sym(path);
}

mkmod(data, code, comp: int, dis: string): ref Module
{
	h := 0;
	for(i := 0; i < len dis; i++)
		h = (h << 1) + dis[i];
	h &= ModHash - 1;
	sym : ref Sym;
	for(ml := mods[h]; ml != nil; ml = tl ml){
		m := hd ml;
		if(m.path == dis && m.code == code && m.comp == comp){
			sym = m.sym;
			if(m.data == data)
				return m;
		}
	}
	m := ref Module(dis, code, data, comp, sym);
	mods[h] = m :: mods[h];
	return m;
}

pdata(p: ref Prog, a: int, fmt: string): (string, string)
{
	b := array of byte sprint("0x%ux.%s1", a, fmt);
	if(sys->write(p.heap, b, len b) != len b)
		return ("", sprint("can't write heap: %r"));

	buf := array[64] of byte;
	sys->seek(p.heap, big 0, 0);
	n := sys->read(p.heap, buf, len buf);
	if(n <= 1)
		return ("", sprint("can't read heap: %r"));
	return (string buf[:n-1], "");
}

pstring0(p: ref Prog, a: int, blen: int): (int, string, string)
{
	b := array of byte sprint("0x%ux.C1", a);
	if(sys->write(p.heap, b, len b) != len b)
		return (-1, "", sprint("can't write heap: %r"));

	buf := array[blen] of byte;
	sys->seek(p.heap, big 0, 0);
	n := sys->read(p.heap, buf, len buf-1);
	if(n <= 1)
		return (-1, "", sprint("can't read heap: %r"));
	buf[n] = byte 0;
	m := strchr(buf, 0, '.');
	if(buf[m++] != byte '.')
		m = 0;
	return (int string buf[0:m], string buf[m:n], "");
}

pstring(p: ref Prog, a: int): (int, string, string)
{
	m, n: int;
	s, err: string;

	m = 64;
	for(;;){
		(n, s, err) = pstring0(p, a, m);
		if(err != "" || n <= len s)
			break;
		m *= 2;
	}
	return (n, s, err);
}

Prog.status(p: self ref Prog): (int, string, string, string)
{
	fd := sys->open(sprint("/prog/%d/status", p.id), sys->OREAD);
	if(fd == nil)
		return (-1, "", sprint("can't open status file: %r"), "");
	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return (-1, "", sprint("can't read status file: %r"), "");
	(ni, info) := sys->tokenize(string buf[:n], " \t");
	if(ni != 6 && ni != 7)
		return (-1, "", "can't parse status file", "");
	info = tl info;
	if(ni == 6)
		return (int hd info, hd tl info, hd tl tl info, hd tl tl tl tl info);
	return (int hd info, hd tl info, hd tl tl tl info, hd tl tl tl tl tl info);
}

loadsyms(sbl: string): (ref Sym, string)
{
	fd := sys->open(sbl, sys->OREAD);
	if(fd == nil)
		return (nil, sprint("Can't open symbol file '%s': %r", sbl));

	(ok, dir) := sys->fstat(fd);
	if(ok < 0)
		return (nil, sprint("Can't read symbol file '%s': %r", sbl));
	n := int dir.length;
	buf := array[n+1] of byte;
	if(sys->read(fd, buf, n) != n)
		return (nil, sprint("Can't read symbol file '%s': %r", sbl));
	fd = nil;
	buf[n] = byte 0;

	s := ref Sym;
	s.path = sbl;

	n = strchr(buf, 0, '\n');
	vers := 0;
	if(string buf[:n] == "limbo .sbl 1.")
		vers = 10;
	else if(string buf[:n] == "limbo .sbl 1.1")
		vers = 11;
	else if(string buf[:n] == "limbo .sbl 2.0")
		vers = 20;
	else if(string buf[:n] == "limbo .sbl 2.1")
		vers = 21;
	else
		return (nil, "Symbol file "+sbl+" out of date");
	o := n += 1;
	n = strchr(buf, o, '\n');
	if(buf[n] != byte '\n')
		return (nil, "Corrupted symbol file "+sbl);
	s.name = string buf[o:n++];
	ss := ref SrcState(nil, 0, 0, vers);
	err : string;
	if(n >= 0){
		err = "file";
		n = debugfiles(ss, buf, n);
	}
	if(n >= 0){
		err = "pc";
		n = debugpc(ss, s, buf, n);
	}
	if(n >= 0){
		err = "types";
		n = debugtys(ss, s, buf, n);
	}
	if(n >= 0){
		err = "fn";
		n = debugfns(ss, s, buf, n);
	}
	vs: array of ref Id;
	if(n >= 0){
		err = "global";
		(vs, n) = debugid(ss, buf, n);
	}
	if(n < 0)
		return (nil, "Corrupted "+err+" symbol table in "+sbl);
	s.vars = vs;
	return (s, "");
}

#
# parse a source location
# format[file:][line.]pos,[file:][line.]pos' '
#
debugsrc(ss: ref SrcState, buf: array of byte, p: int): (ref Src, int)
{
	n: int;
	src: ref Src;

	(n, p) = strtoi(buf, p);
	if(buf[p] == byte ':'){
		ss.lastf = n;
		(n, p) = strtoi(buf, p + 1);
	}
	if(buf[p] == byte '.'){
		ss.lastl = n;
		(n, p) = strtoi(buf, p + 1);
	}
	if(buf[p++] != byte ',' || ss.lastf >= len ss.files || ss.lastf < 0)
		return (nil, -1);
	src = ref Src;
	src.start.file = ss.files[ss.lastf];
	src.start.line = ss.lastl;
	src.start.pos = n;

	(n, p) = strtoi(buf, p);
	if(buf[p] == byte ':'){
		ss.lastf = n;
		(n, p) = strtoi(buf, p+1);
	}
	if(buf[p] == byte '.'){
		ss.lastl = n;
		(n, p) = strtoi(buf, p + 1);
	}
	if(buf[p++] != byte ' ' || ss.lastf >= len ss.files || ss.lastf < 0)
		return (nil, -1);
	src.stop.file = ss.files[ss.lastf];
	src.stop.line = ss.lastl;
	src.stop.pos = n;
	return (src, p);
}

#
# parse the file table
# item format: file: string
#
debugfiles(ss: ref SrcState, buf: array of byte, p: int): int
{
	n, q: int;

	(n, p) = strtoi(buf, p);
	if(buf[p++] != byte '\n')
		return -1;
	ss.files = array[n] of string;
	for(i := 0; i < n; i++){
		q = strchr(buf, p, '\n');
		ss.files[i] = string buf[p:q];
		p = q + 1;
	}
	return p;
}

#
# parse the pc to source table
# item format: Source stmt
#
debugpc(ss: ref SrcState, s: ref Sym, buf: array of byte, p: int): int
{
	ns: int;

	(ns, p) = strtoi(buf, p);
	if(buf[p++] != byte '\n')
		return -1;
	s.src = array[ns] of ref Src;
	s.srcstmt = array[ns] of int;
	for(i := 0; i < ns; i++){
		(s.src[i], p) = debugsrc(ss, buf, p);
		if(p < 0)
			return -1;
		(s.srcstmt[i], p) = strtoi(buf, p);
		if(buf[p++] != byte '\n')
			return -1;
	}
	return p;
}

#
# parse the type table
# format: linear list of types
#
debugtys(ss: ref SrcState, s: ref Sym, buf: array of byte, p: int): int
{
	na: int;

	(na, p) = strtoi(buf, p);
	if(buf[p++] != byte '\n')
		return -1;
	s.adts = array[na] of ref Type;
	adts := s.adts;
	for(i := 0; i < na; i++){
		if(ss.vers < 20)
			(adts[i], p) = debugadt(ss, buf, p);
		else
			(adts[i], p) = debugtype(ss, buf, p);
		if(p < 0)
			return -1;
	}
	return p;
}

#
# parse the function table
# format: pc:name:argids localids rettype
#
debugfns(ss: ref SrcState, s: ref Sym, buf: array of byte, p: int): int
{
	t: ref Type;
	args, locals: array of ref Id;
	nf, pc, q: int;

	(nf, p) = strtoi(buf, p);
	if(buf[p++] != byte '\n')
		return -1;
	s.fns = array[nf] of ref Id;
	fns := s.fns;
	for(i := 0; i < nf; i++){
		(pc, p) = strtoi(buf, p);
		if(buf[p++] != byte ':')
			return -2;
		q = strchr(buf, p, '\n');
		if(buf[q] != byte '\n')
			return -3;
		name := string buf[p:q];
		(args, p) = debugid(ss, buf, q + 1);
		if(p == -1)
			return -4;
		(locals, p) = debugid(ss, buf, p);
		if(p == -1)
			return -5;
		(t, p) = debugtype(ss, buf, p);
		if(p == -1)
			return -6;
		nk := 1 + (len args != 0) + (len locals != 0);
		kids := array[nk] of ref Id;
		nk = 0;
		if(len locals != 0)
			kids[nk++] = ref Id(nil, "locals", 0, 0, ref Type(nil, Tlocal, 0, nil, nil, locals, nil));
		if(len args != 0)
			kids[nk++] = ref Id(nil, "args", 0, 0, ref Type(nil, Targ, 0, nil, nil, args, nil));
		kids[nk++] = ref Id(nil, "module", 0, 0, ref Type(nil, Tglobal, 0, nil, nil, nil, nil));
		args = nil;
		locals = nil;
		fns[i] = ref Id(nil, name, pc, 0, ref Type(nil, Tfn, 0, name, t, kids, nil));
	}
	for(i = 1; i < nf; i++)
		fns[i-1].stoppc = fns[i].offset;
	fns[i-1].stoppc = len s.src;
	return p;
}

#
# parse a list of ids
# format: offset ':' name ':' src type '\n'
#
debugid(ss: ref SrcState, buf: array of byte, p: int): (array of ref Id, int)
{
	t: ref Type;
	off, nd, q, qq, tq: int;
	src: ref Src;

	(nd, p) = strtoi(buf, p);
	if(buf[p++] != byte '\n')
		return (nil, -1);
	d := array[nd] of ref Id;
	for(i := 0; i < nd; i++){
		(off, q) = strtoi(buf, p);
		if(buf[q++] != byte ':')
			return (nil, -1);
		qq = strchr(buf, q, ':');
		if(buf[qq] != byte ':')
			return (nil, -1);
		tq = qq + 1;
		if(ss.vers > 10){
			(src, tq) = debugsrc(ss, buf, tq);
			if(tq < 0)
				return (nil, -1);
		}
		(t, p) = debugtype(ss, buf, tq);
		if(p == -1 || buf[p++] != byte '\n')
			return (nil, -1);
		d[i] = ref Id(src, string buf[q:qq], off, 0, t);
	}
	return (d, p);
}

idlist(a: array of ref Id): list of ref Id
{
	n := len a;
	ids : list of ref Id = nil;
	while(n-- > 0)
		ids = a[n] :: ids;
	return ids;
}

#
# parse a type description
#
debugtype(ss: ref SrcState, buf: array of byte, p: int): (ref Type, int)
{
	t: ref Type;
	d: array of ref Id;
	q, k: int;
	src: ref Src;

	size := 0;
	case int buf[p++]{
	'@' =>
		k = Tid;
	'A' =>
		k = Tarray;
		size = IBY2WD;
	'B' =>
		return (tbig, p);
	'C' =>	k = Tchan;
		size = IBY2WD;
	'L' =>
		k = Tlist;
		size = IBY2WD;
	'N' =>
		return (tnil, p);
	'R' =>
		k = Tref;
		size = IBY2WD;
	'a' =>
		k = Tadt;
		if(ss.vers < 20)
			size = -1;
	'b' =>
		return (tbyte, p);
	'f' =>
		return (treal, p);
	'i' =>
		return (tint, p);
	'm' =>
		k = Tmodule;
		size = IBY2WD;
	'n' =>
		return (tnone, p);
	'p' =>
		k = Tadtpick;
	's' =>
		return (tstring, p);
	't' =>
		k = Ttuple;
	 	size = -1;
	'F' =>
		k = Tfn;
		size = IBY2WD;
	'P' =>
		return (tpoly, p);
	* =>
		k = Terror;
	}

	if(size == -1){
		q = strchr(buf, p, '.');
		if(buf[q] == byte '.'){
			size = int string buf[p:q];
			p = q+1;
		}
	}

	case k{
	Tid =>
		q = strchr(buf, p, '\n');
		if(buf[q] != byte '\n')
			return (nil, -1);
		t = ref Type(nil, Tid, -1, string buf[p:q], nil, nil, nil);
		p = q + 1;
	Tadt =>
		if(ss.vers < 20){
			q = strchr(buf, p, '\n');
			if(buf[q] != byte '\n')
				return (nil, -1);
			t = ref Type(nil, Tid, size, string buf[p:q], nil, nil, nil);
			p = q + 1;
		}else
			(t, p) = debugadt(ss, buf, p);
	Tadtpick =>
		(t, p) = debugadt(ss, buf, p);
		t.kind = Tadtpick;
		(t.tags, p) = debugtag(ss, buf, p);
	Tmodule =>
		q = strchr(buf, p, '\n');
		if(buf[q] != byte '\n')
			return (nil, -1);
		t = ref Type(nil, k, size, string buf[p:q], nil, nil, nil);
		p = q + 1;
		if(ss.vers > 10){
			(src, p) = debugsrc(ss, buf, p);
			t.src = src;
		}
		if(ss.vers > 20)
			(t.ids, p) = debugid(ss, buf, p);
	Tref or Tarray or Tlist or Tchan =>		# ref, array, list, chan
		(t, p) = debugtype(ss, buf, p);
		t = ref Type(nil, k, size, "", t, nil, nil);

	Ttuple =>						# tuple
		(d, p) = debugid(ss, buf, p);
		t = ref Type(nil, k, size, "", nil, d, nil);

	Tfn =>						# fn
		(d, p) = debugid(ss, buf, p);
		(t, p) = debugtype(ss, buf, p);
		t = ref Type(nil, k, size, "", t, d, nil);

	* =>
		p = -1;
	}
	return (t, p);
}

#
# parse an adt type spec
# format: name ' ' src size '\n' ids
#
debugadt(ss: ref SrcState, buf: array of byte, p: int): (ref Type, int)
{
	src: ref Src;

	q := strchr(buf, p, ' ');
	if(buf[q] != byte ' ')
		return (nil, -1);
	sq := q + 1;
	if(ss.vers > 10){
		(src, sq) = debugsrc(ss, buf, sq);
		if(sq < 0)
			return (nil, -1);
	}
	qq := strchr(buf, sq, '\n');
	if(buf[qq] != byte '\n')
		return (nil, -1);
	(d, pp) := debugid(ss, buf, qq + 1);
	if(pp == -1)
		return (nil, -1);
	t := ref Type(src, Tadt, int string buf[sq:qq], string buf[p:q], nil, d, nil);
	return (t, pp);
}

#
# parse a list of tags
# format:
#	name ':' src size '\n' ids
# or	
#	name ':' src '\n'
#
debugtag(ss: ref SrcState, buf: array of byte, p: int): (array of ref Type, int)
{
	d: array of ref Id;
	ntg, q, pp, np: int;
	src: ref Src;

	(ntg, p) = strtoi(buf, p);
	if(buf[p++] != byte '\n')
		return (nil, -1);
	tg := array[ntg] of ref Type;
	for(i := 0; i < ntg; i++){
		pp = strchr(buf, p, ':');
		if(buf[pp] != byte ':')
			return (nil, -1);
		q = pp + 1;
		(src, q) = debugsrc(ss, buf, q);
		if(q < 0)
			return (nil, -1);
		if(buf[q] == byte '\n'){
			np = q + 1;
			if(i <= 0)
				return (nil, -1);
			tg[i] = ref Type(src, Tadt, tg[i-1].size, string buf[p:pp], nil, tg[i-1].ids, nil);
		}else{
			np = strchr(buf, q, '\n');
			if(buf[np] != byte '\n')
				return (nil, -1);
			size := int string buf[q:np];
			(d, np) = debugid(ss, buf, np+1);
			if(np == -1)
				return (nil, -1);
			tg[i] = ref Type(src, Tadt, size, string buf[p:pp], nil, d, nil);
		}
		p = np;
	}
	return (tg, p);
}

strchr(a: array of byte, p, c: int): int
{
	bc := byte c;
	while((b := a[p]) != byte 0 && b != bc)
		p++;
	return p;
}

strtoi(a: array of byte, start: int): (int, int)
{
	p := start;
	for(; c := int a[p]; p++){
		case c{
		' ' or '\t' or '\n' or '\r' =>
			continue;
		}
		break;
	}

	# sign
	neg := c == '-';
	if(neg || c == '+')
		p++;

	# digits
	n := 0;
	nn := 0;
	ndig := 0;
	over := 0;
	for(; c = int a[p]; p++){
		if(c < '0' || c > '9')
			break;
		ndig++;
		nn = n * 10 + (c - '0');
		if(nn < n)
			over = 1;
		n = nn;
	}
	if(ndig == 0)
		return (0, start);
	if(neg)
		n = -n;
	if(over)
		if(neg)
			n = 2147483647;
		else
			n = int -2147483648;
	return (n, p);
}

hex(a: array of byte): int
{
	n := 0;
	for(i := 0; i < len a; i++){
		c := int a[i];
		if(c >= '0' && c <= '9')
			c -= '0';
		else
			c -= 'a' - 10;
		n = (n << 4) + (c & 15);
	}
	return n;
}

partition(n : int, max : int) : (int, int, int)
{
	p := n/max; 
	if (n%max != 0)
		p++;
	if (p > max)
		p = max;
	q := n/p;
	r := n-p*q;
	return (p, q, r);
}

bounds(s : string) : (int, int)
{
	lb := int s;
	for (i := 0; i < len s; i++)
		if (s[i] == '.')
			break;
	if (i+1 >= len s || s[i] != '.' || s[i+1] != '.')
		return (1, 0);
	ub := int s[i+2:];
	return (lb, ub);
}
