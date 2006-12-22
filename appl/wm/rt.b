implement WmRt;

include "sys.m";
	sys: Sys;
	sprint: import sys;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "draw.m";

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include "tkclient.m";
	tkclient: Tkclient;

include "dialog.m";
	dialog: Dialog;

include "selectfile.m";
	selectfile: Selectfile;

include "dis.m";
	dis: Dis;
	Inst, Type, Data, Link, Mod: import dis;
	XMAGIC: import Dis;
	MUSTCOMPILE, DONTCOMPILE: import Dis;
	AMP, AFP, AIMM, AXXX, AIND, AMASK: import Dis;
	ARM, AXNON, AXIMM, AXINF, AXINM: import Dis;
	DEFB, DEFW, DEFS, DEFF, DEFA, DIND, DAPOP, DEFL: import Dis;

WmRt: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

gctxt: ref Draw->Context;
t: ref Toplevel;
disfile: string;

TK:	con 1;

m: ref Mod;
rt := 0;
ss := -1;

rt_cfg := array[] of {
	"frame .m",
	"menubutton .m.open -text File -menu .file",
	"menubutton .m.prop -text Properties -menu .prop",
	"menubutton .m.view -text View -menu .view",
	"label .m.l",
	"pack .m.open .m.view .m.prop -side left",
	"pack .m.l -side right",
	"frame .b",
	"text .b.t -width 12c -height 7c -yscrollcommand {.b.s set} -bg white",
	"scrollbar .b.s -command {.b.t yview}",
	"pack .b.s -fill y -side left",
	"pack .b.t -fill both -expand 1",
	"pack .m -anchor w -fill x",
	"pack .b -fill both -expand 1",
	"pack propagate . 0",
	"update",

	"menu .prop",
	".prop add checkbutton -text {Must compile} -command {send cmd must}",
	".prop add checkbutton -text {Don't compile} -command {send cmd dont}",
	".prop add separator",
	".prop add command -text {Set stack extent} -command {send cmd stack}",
	".prop add command -text {Sign module} -command {send cmd sign}",

	"menu .view",
	".view add command -text {Header} -command {send cmd hdr}",
	".view add command -text {Code segment} -command {send cmd code}",
	".view add command -text {Data segment} -command {send cmd data}",
	".view add command -text {Type descriptors} -command {send cmd type}",
	".view add command -text {Link descriptors} -command {send cmd link}",
	".view add command -text {Import descriptors} -command {send cmd imports}",
	".view add command -text {Exception handlers} -command {send cmd handlers}",

	"menu .file",
	".file add command -text {Open module} -command {send cmd open}",
	".file add separator",
	".file add command -text {Write .dis module} -command {send cmd save}",
	".file add command -text {Write .s file} -command {send cmd list}",
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "rt: no window context\n");
		raise "fail:bad context";
	}
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	dialog = load Dialog Dialog->PATH;
	selectfile = load Selectfile Selectfile->PATH;

	sys->pctl(Sys->NEWPGRP, nil);

	tkclient->init();
	dialog->init();
	selectfile->init();

	gctxt = ctxt;

	menubut: chan of string;
	(t, menubut) = tkclient->toplevel(ctxt, "", "Dis Module Manager", Tkclient->Appl);

	cmd := chan of string;

	tk->namechan(t, cmd, "cmd");
	tkcmds(t, rt_cfg);
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd"::"ptr"::nil);

	dis = load Dis Dis->PATH;
	if(dis == nil) {
		dialog->prompt(ctxt, t.image, "error -fg red", "Load Module",
				"wmrt requires Dis",
				0, "Exit"::nil);
		return;
	}
	dis->init();

	for(;;) alt {
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or
	s = <-t.wreq =>
		tkclient->wmctl(t, s);
	menu := <-menubut =>
		if(menu == "exit")
			return;
		tkclient->wmctl(t, menu);
	s := <-cmd =>
		case s {
		"open" =>
			openfile(ctxt);
		"save" =>
			writedis();
		"list" =>
			writeasm();
		"hdr" =>
			hdr();
		"code" =>
			das(TK);
		"data" =>
			dat(TK);
		"type" =>
			desc(TK);
		"link" =>
			link(TK);
		"imports" =>
			imports(TK);
		"handlers" =>
			handlers(TK);
		"must" =>
			rt ^= MUSTCOMPILE;
		"dont" =>
			rt ^= DONTCOMPILE;
		"stack" =>
			spawn stack(ctxt);
		"sign" =>
			dialog->prompt(ctxt, t.image, "error -fg red", "Signed Modules",
				"not implemented",
				0, "Continue"::nil);
		}
	}
}

stack_cfg := array[] of {
	"scale .s -length 200 -to 32768 -resolution 128 -orient horizontal",
	"frame .f",
	"pack .s .f -pady 5 -fill x -expand 1",
};

stack(ctxt: ref Draw->Context)
{
	# (s, sbut) := tkclient->toplevel(ctxt, tkclient->geom(t), "Dis Stack", 0);
	(s, sbut) := tkclient->toplevel(ctxt, "", "Dis Stack", 0);

	cmd := chan of string;
	tk->namechan(s, cmd, "cmd");
	tkcmds(s, stack_cfg);
	tk->cmd(s, ".s set " + string ss);
	tk->cmd(s, "update");
	tkclient->onscreen(s, nil);
	tkclient->startinput(s, "kbd"::"ptr"::nil);

	for(;;) alt {
	c := <-s.ctxt.kbd =>
		tk->keyboard(s, c);
	c := <-s.ctxt.ptr =>
		tk->pointer(s, *c);
	c := <-s.ctxt.ctl or
	c = <-s.wreq =>
		tkclient->wmctl(s, c);
	wmctl := <-sbut =>
		if(wmctl == "exit") {
			ss = int tk->cmd(s, ".s get");
			return;
		}
		tkclient->wmctl(s, wmctl);
	}	
}

openfile(ctxt: ref Draw->Context)
{
	pattern := list of {
		"*.dis (Dis VM module)",
		"* (All files)"
	};

	for(;;) {
		disfile = selectfile->filename(ctxt, t.image, "Dis file", pattern, nil);
		if(disfile == "")
			break;

		s: string;
		(m, s) = dis->loadobj(disfile);
		if(s == nil) {
			ss = m.ssize;
			rt = m.rt;
			tk->cmd(t, ".m.l configure -text {"+m.name+"}");
			das(TK);
			return;
		}

		r := dialog->prompt(ctxt, t.image, "error -fg red", "Open Dis File",
				s,
				0, "Retry" :: "Abort" :: nil);
		if(r == 1)
			return;
	}
}

writedis()
{
	if(m == nil || m.magic == 0) {
		dialog->prompt(gctxt, t.image, "error -fg red", "Write .dis",
				"no module loaded",
				0, "Continue"::nil);
		return;
	}
	if(rt < 0)
		rt = m.rt;
	if(ss < 0)
		ss = m.ssize;
	if(rt == m.rt && ss == m.ssize)
		return;
	while((fd := sys->open(disfile, Sys->OREAD)) == nil){
		if(dialog->prompt(gctxt, t.image, "error -fg red", "Open Dis File", "open failed: "+sprint("%r"),
		     0, "Retry" :: "Abort" :: nil))
			return;
	}
	if(len discona(rt) == len discona(m.rt) && len discona(ss) == len discona(m.ssize)){
		sys->seek(fd, big 4, Sys->SEEKSTART);	# skip magic
		discon(fd, rt);
		discon(fd, ss);
		m.rt = rt;
		m.ssize = ss;
		return;
	}
	# rt and ss representations changed in length: read the file in,
	# make a copy and update rt and ss when copying
	(ok, d) := sys->fstat(fd);
	if(ok < 0){
		ioerror("Reading Dis file "+disfile, "can't find file length: "+sprint("%r"));
		return;
	}
	length := int d.length;
	disbuf := array[length] of byte;
	if(sys->read(fd, disbuf, length) != length){
		ioerror("Reading Dis file "+disfile, "read error: "+sprint("%r"));
		return;
	}
	outbuf := array[length+2*4] of byte;	# could avoid this buffer if required, by writing portions of disbuf
	(magic, i) := operand(disbuf, 0);
	o := putoperand(outbuf, magic);
	if(magic == Dis->SMAGIC){
		ns: int;
		(ns, i) = operand(disbuf, i);
		o += putoperand(outbuf[o:], ns);
		sign := disbuf[i:i+ns];
		i += ns;
		outbuf[o:] = sign;
		o += ns;
	}
	(nil, i) = operand(disbuf, i);
	(nil, i) = operand(disbuf, i);
	if(i < 0){
		ioerror("Reading Dis file "+disfile, "Dis header too short");
		return;
	}
	o += putoperand(outbuf[o:], rt);
	o += putoperand(outbuf[o:], ss);
	outbuf[o:] = disbuf[i:];
	o += len disbuf - i;
	fd = sys->create(disfile, Sys->OWRITE, 8r666);
	if(fd == nil){
		ioerror("Rewriting "+disfile, sys->sprint("can't create %s: %r",disfile));
		return;
	}
	if(sys->write(fd, outbuf, o) != o)
		ioerror("Rewriting "+disfile, "write error: "+sprint("%r"));
	m.rt = rt;
	m.ssize = ss;
}

ioerror(title: string, err: string)
{
	dialog->prompt(gctxt, t.image, "error -fg red", title, err, 0, "Dismiss" :: nil);
}

putoperand(out: array of byte, v: int): int
{
	a := discona(v);
	out[0:] = a;
	return len a;
}

discona(val: int): array of byte
{
	if(val >= -64 && val <= 63)
		return array[] of { byte(val & ~16r80) };
	else if(val >= -8192 && val <= 8191)
		return array[] of { byte((val>>8) & ~16rC0 | 16r80), byte val };
	else
		return array[] of { byte(val>>24 | 16rC0), byte(val>>16), byte(val>>8), byte val };
}

discon(fd: ref Sys->FD, val: int)
{
	a := discona(val);
	sys->write(fd, a, len a);
}

operand(disobj: array of byte, o: int): (int, int)
{
	if(o >= len disobj)
		return (-1, -1);
	b := int disobj[o++];
	case b & 16rC0 {
	16r00 =>
		return (b, o);
	16r40 =>
		return (b | ~16r7F, o);
	16r80 =>
		if(o >= len disobj)
			return (-1, -1);
		if(b & 16r20)
			b |= ~16r3F;
		else
			b &= 16r3F;
		b = (b<<8) | int disobj[o++];
		return (b, o);
	16rC0 =>
		if(o+2 >= len disobj)
			return (-1, -1);
		if(b & 16r20)
			b |= ~16r3F;
		else
			b &= 16r3F;
		b = b<<24 |
			(int disobj[o]<<16) |
		    	(int disobj[o+1]<<8)|
		    	int disobj[o+2];
		o += 3;
		return (b, o);
	}
	return (0, -1);	# can't happen
}

fasm: ref Iobuf;

writeasm()
{
	if(m == nil || m.magic == 0) {
		dialog->prompt(gctxt, t.image, "error -fg red", "Write .s",
				"no module loaded",
				0, "Continue"::nil);
		return;
	}

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil) {
		dialog->prompt(gctxt, t.image, "error -fg red", "Write .s",
				"Bufio load failed: "+sprint("%r"),
				0, "Exit"::nil);
		return;
	}

	for(;;) {
		asmfile: string;
		if(len disfile > 4 && disfile[len disfile-4:] == ".dis")
			asmfile = disfile[0:len disfile-3] + "s";
		else
			asmfile = disfile + ".s";
		fasm = bufio->create(asmfile, Sys->OWRITE|Sys->OTRUNC, 8r666);
		if(fasm != nil)
			break;
		r := dialog->prompt(gctxt, t.image, "error -fg red", "Create .s file",
			"open failed: "+sprint("%r"),
			0, "Retry" :: "Abort" :: nil);
		if(r == 0)
			continue;
		else
			return;
	}
	das(!TK);
	fasm.puts("\tentry\t" + string m.entry + "," + string m.entryt + "\n");
	desc(!TK);
	dat(!TK);
	fasm.puts("\tmodule\t" + m.name + "\n");
	link(!TK);
	imports(!TK);
	handlers(!TK);
	fasm.close();
}

link(flag: int)
{
	if(m == nil || m.magic == 0) {
		dialog->prompt(gctxt, t.image, "error -fg red", "Link Descriptors",
				"no module loaded",
				0, "Continue"::nil);
		return;
	}

	if(flag == TK)
		tk->cmd(t, ".b.t delete 1.0 end");

	for(i := 0; i < m.lsize; i++) {
		l := m.links[i];
		s := sprint("	link %d,%d, 0x%ux, \"%s\"\n",
					l.desc, l.pc, l.sig, l.name);
		if(flag == TK)
			tk->cmd(t, ".b.t insert end '"+s);
		else
			fasm.puts(s);
	}
	if(flag == TK)
		tk->cmd(t, ".b.t see 1.0; update");
}

imports(flag: int)
{
	if(m == nil || m.magic == 0) {
		dialog->prompt(gctxt, t.image, "error -fg red", "Import Descriptors",
				"no module loaded",
				0, "Continue"::nil);
		return;
	}

	if(flag == TK)
		tk->cmd(t, ".b.t delete 1.0 end");

	mi := m.imports;
	for(i := 0; i < len mi; i++) {
		a := mi[i];
		for(j := 0; j < len a; j++) {
			ai := a[j];
			s := sprint("	import 0x%ux, \"%s\"\n", ai.sig, ai.name);
			if(flag == TK)
				tk->cmd(t, ".b.t insert end '"+s);
			else
				fasm.puts(s);
		}
	}
	if(flag == TK)
		tk->cmd(t, ".b.t see 1.0; update");
}

handlers(flag: int)
{
	if(m == nil || m.magic == 0) {
		dialog->prompt(gctxt, t.image, "error -fg red", "Exception Handlers",
				"no module loaded",
				0, "Continue"::nil);
		return;
	}

	if(flag == TK)
		tk->cmd(t, ".b.t delete 1.0 end");

	hs := m.handlers;
	for(i := 0; i < len hs; i++) {
		h := hs[i];
		tt := -1;
		for(j := 0; j < len m.types; j++) {
			if(h.t == m.types[j]) {
				tt = j;
				break;
			}
		}
		s := sprint("	%d-%d, o=%d, e=%d t=%d\n", h.pc1, h.pc2, h.eoff, h.ne, tt);
		if(flag == TK)
			tk->cmd(t, ".b.t insert end '"+s);
		else
			fasm.puts(s);
		et := h.etab;
		for(j = 0; j < len et; j++) {
			e := et[j];
			if(e.s == nil)
				s = sprint("		%d	*\n", e.pc);
			else
				s = sprint("		%d	\"%s\"\n", e.pc, e.s);
			if(flag == TK)
				tk->cmd(t, ".b.t insert end '"+s);
			else
				fasm.puts(s);
		}
	}
	if(flag == TK)
		tk->cmd(t, ".b.t see 1.0; update");
}

desc(flag: int)
{
	if(m == nil || m.magic == 0) {
		dialog->prompt(gctxt, t.image, "error -fg red", "Type Descriptors",
				"no module loaded",
				0, "Continue"::nil);
		return;
	}

	if(flag == TK)
		tk->cmd(t, ".b.t delete 1.0 end");

	for(i := 0; i < m.tsize; i++) {
		h := m.types[i];
		s := sprint("	desc $%d, %d, \"", i, h.size);
		for(j := 0; j < h.np; j++)
			s += sprint("%.2ux", int h.map[j]);
		s += "\"\n";
		if(flag == TK)
			tk->cmd(t, ".b.t insert end '"+s);
		else
			fasm.puts(s);
	}
	if(flag == TK)
		tk->cmd(t, ".b.t see 1.0; update");
}

hdr()
{
	if(m == nil || m.magic == 0) {
		dialog->prompt(gctxt, t.image, "error -fg red", "Header",
				"no module loaded",
				0, "Continue"::nil);
		return;
	}

	tk->cmd(t, ".b.t delete 1.0 end");

	s := sprint("%.8ux Version %d Dis VM\n", m.magic, m.magic - XMAGIC + 1);
	s += sprint("%.8ux Runtime flags %s\n", m.rt, rtflag(m.rt));
	s += sprint("%8d bytes per stack extent\n\n", m.ssize);


	s += sprint("%8d instructions\n", m.isize);
	s += sprint("%8d data size\n", m.dsize);
	s += sprint("%8d heap type descriptors\n", m.tsize);
	s += sprint("%8d link directives\n", m.lsize);
	s += sprint("%8d entry pc\n", m.entry);
	s += sprint("%8d entry type descriptor\n\n", m.entryt);

	if(m.sign == nil)
		s += "Module is Insecure\n";

	tk->cmd(t, ".b.t insert end '"+s);
	tk->cmd(t, ".b.t see 1.0; update");
}

rtflag(flag: int): string
{
	if(flag == 0)
		return "";

	s := "[";

	if(flag & MUSTCOMPILE)
		s += "MustCompile";
	if(flag & DONTCOMPILE) {
		if(flag & MUSTCOMPILE)
			s += "|";
		s += "DontCompile";
	}
	s[len s] = ']';

	return s;
}

das(flag: int)
{
	if(m == nil || m.magic == 0) {
		dialog->prompt(gctxt, t.image, "error -fg red", "Assembly",
				"no module loaded",
				0, "Continue"::nil);
		return;
	}

	if(flag == TK)
		tk->cmd(t, ".b.t delete 1.0 end");

	for(i := 0; i < m.isize; i++) {
		prefix := "";
		if(flag == TK)
			prefix = sprint(".b.t insert end '%4d   ", i);
		else {
			if(i % 10 == 0)
				fasm.puts("#" + string i + "\n");
			prefix = sprint("\t");
		}
		s := prefix + dis->inst2s(m.inst[i]) + "\n";

		if(flag == TK)
			tk->cmd(t, s);
		else
			fasm.puts(s);
	}
	if(flag == TK)
		tk->cmd(t, ".b.t see 1.0; update");
}

dat(flag: int)
{
	if(m == nil || m.magic == 0) {
		dialog->prompt(gctxt, t.image, "error -fg red", "Module Data",
				"no module loaded",
				0, "Continue"::nil);
		return;
	}
	s := sprint("	var @mp, %d\n", m.types[0].size);
	if(flag == TK) {
		tk->cmd(t, ".b.t delete 1.0 end");
		tk->cmd(t, ".b.t insert end '"+s);
	} else
		fasm.puts(s);

	s = "";
	for(d := m.data; d != nil; d = tl d) {
		pick dat := hd d {
		Bytes =>
			s = sprint("\tbyte @mp+%d", dat.off);
			for(n := 0; n < dat.n; n++)
				s += sprint(",%d", int dat.bytes[n]);
		Words =>
			s = sprint("\tword @mp+%d", dat.off);
			for(n := 0; n < dat.n; n++)
				s += sprint(",%d", dat.words[n]);
		String =>
			s = sprint("\tstring @mp+%d, \"%s\"", dat.off, mapstr(dat.str));
		Reals =>
			s = sprint("\treal @mp+%d", dat.off);
			for(n := 0; n < dat.n; n++)
				s += sprint(", %g", dat.reals[n]);
			break;
		Array =>
			s = sprint("\tarray @mp+%d,$%d,%d", dat.off, dat.typex, dat.length);
		Aindex =>
			s = sprint("\tindir @mp+%d,%d", dat.off, dat.index);
		Arestore =>
			s = "\tapop";
			break;
		Bigs =>
			s = sprint("\tlong @mp+%d", dat.off);
			for(n := 0; n < dat.n; n++)
				s += sprint(", %bd", dat.bigs[n]);
		}
		if(flag == TK)
			tk->cmd(t, ".b.t insert end '"+s+"\n");
		else
			fasm.puts(s+"\n");
	}

	if(flag == TK)
		tk->cmd(t, ".b.t see 1.0; update");
}

mapstr(s: string): string
{
	for(i := 0; i < len s; i++) {
		if(s[i] == '\n')
			s = s[0:i] + "\\n" + s[i+1:];
	}
	return s;
}

tkcmds(t: ref Toplevel, cfg: array of string)
{
	for(i := 0; i < len cfg; i++)
		tk->cmd(t, cfg[i]);
}
