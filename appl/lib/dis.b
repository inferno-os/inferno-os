implement Dis;

#
# Derived by Vita Nuova Limited 1998 from /appl/wm/rt.b, which is
# Copyright © 1996-1999 Lucent Technologies Inc.  All rights reserved.
#

include "sys.m";
	sys: Sys;
	sprint: import sys;

include "math.m";
	math: Math;

include "dis.m";

disptr: int;
disobj: array of byte;

optab := array[] of {
	"nop",
	"alt",
	"nbalt",
	"goto",
	"call",
	"frame",
	"spawn",
	"runt",
	"load",
	"mcall",
	"mspawn",
	"mframe",
	"ret",
	"jmp",
	"case",
	"exit",
	"new",
	"newa",
	"newcb",
	"newcw",
	"newcf",
	"newcp",
	"newcm",
	"newcmp",
	"send",
	"recv",
	"consb",
	"consw",
	"consp",
	"consf",
	"consm",
	"consmp",
	"headb",
	"headw",
	"headp",
	"headf",
	"headm",
	"headmp",
	"tail",
	"lea",
	"indx",
	"movp",
	"movm",
	"movmp",
	"movb",
	"movw",
	"movf",
	"cvtbw",
	"cvtwb",
	"cvtfw",
	"cvtwf",
	"cvtca",
	"cvtac",
	"cvtwc",
	"cvtcw",
	"cvtfc",
	"cvtcf",
	"addb",
	"addw",
	"addf",
	"subb",
	"subw",
	"subf",
	"mulb",
	"mulw",
	"mulf",
	"divb",
	"divw",
	"divf",
	"modw",
	"modb",
	"andb",
	"andw",
	"orb",
	"orw",
	"xorb",
	"xorw",
	"shlb",
	"shlw",
	"shrb",
	"shrw",
	"insc",
	"indc",
	"addc",
	"lenc",
	"lena",
	"lenl",
	"beqb",
	"bneb",
	"bltb",
	"bleb",
	"bgtb",
	"bgeb",
	"beqw",
	"bnew",
	"bltw",
	"blew",
	"bgtw",
	"bgew",
	"beqf",
	"bnef",
	"bltf",
	"blef",
	"bgtf",
	"bgef",
	"beqc",
	"bnec",
	"bltc",
	"blec",
	"bgtc",
	"bgec",
	"slicea",
	"slicela",
	"slicec",
	"indw",
	"indf",
	"indb",
	"negf",
	"movl",
	"addl",
	"subl",
	"divl",
	"modl",
	"mull",
	"andl",
	"orl",
	"xorl",
	"shll",
	"shrl",
	"bnel",
	"bltl",
	"blel",
	"bgtl",
	"bgel",
	"beql",
	"cvtlf",
	"cvtfl",
	"cvtlw",
	"cvtwl",
	"cvtlc",
	"cvtcl",
	"headl",
	"consl",
	"newcl",
	"casec",
	"indl",
	"movpc",
	"tcmp",
	"mnewz",
	"cvtrf",
	"cvtfr",
	"cvtws",
	"cvtsw",
	"lsrw",
	"lsrl",
	"eclr",
	"newz",
	"newaz",
	"raise",
	"casel",
	"mulx",
	"divx",
	"cvtxx",
	"mulx0",
	"divx0",
	"cvtxx0",
	"mulx1",
	"divx1",
	"cvtxx1",
	"cvtfx",
	"cvtxf",
	"expw",
	"expl",
	"expf",
	"self",
};

init()
{
	sys = load Sys  Sys->PATH;
	math = load Math Math->PATH;	# optional
}

loadobj(disfile: string): (ref Mod, string)
{
	fd := sys->open(disfile, sys->OREAD);
	if(fd == nil)
		return (nil, "open failed: "+sprint("%r"));

	(ok, d) := sys->fstat(fd);
	if(ok < 0)
		return (nil, "stat failed: "+sprint("%r"));

	objlen := int d.length;
	disobj = array[objlen] of byte;

	if(sys->read(fd, disobj, objlen) != objlen){
		disobj = nil;
		return (nil, "read failed: "+sprint("%r"));
	}

	disptr = 0;
	m := ref Mod;
	m.magic = operand();
	if(m.magic == SMAGIC) {
		n := operand();
		m.sign = disobj[disptr:disptr+n];
		disptr += n;
		m.magic = operand();
	}
	if(m.magic != XMAGIC){
		disobj = nil;
		return (nil, "bad magic number");
	}

	m.rt = operand();
	m.ssize = operand();
	m.isize = operand();
	m.dsize = operand();
	m.tsize = operand();
	m.lsize = operand();
	m.entry = operand();
	m.entryt = operand();

	m.inst = array[m.isize] of ref Inst;
	for(i := 0; i < m.isize; i++) {
		o := ref Inst;
		o.op = int disobj[disptr++];
		o.addr = int disobj[disptr++];
		case o.addr & ARM {
		AXIMM or
		AXINF or
		AXINM =>
			o.mid = operand();
		}

		case (o.addr>>3) & 7 {
		AFP or
		AMP or
		AIMM =>
			o.src = operand();
		AIND|AFP or
		AIND|AMP =>
			o.src = operand()<<16;
			o.src |= operand();
		}

		case o.addr & 7	 {
		AFP or
		AMP or
		AIMM =>
			o.dst = operand();
		AIND|AFP or
		AIND|AMP =>
			o.dst = operand()<<16;
			o.dst |= operand();
		}
		m.inst[i] = o;
	}

	m.types = array[m.tsize] of ref Type;
	for(i = 0; i < m.tsize; i++) {
		h := ref Type;
		id := operand();
		h.size = operand();
		h.np = operand();
		h.map = disobj[disptr:disptr+h.np];
		disptr += h.np;
		m.types[i] = h;
	}

	for(;;) {
		op := int disobj[disptr++];
		if(op == 0)
			break;

		n := op & (DMAX-1);
		if(n == 0)
			n = operand();

		offset := operand();

		dat: ref Data;
		case op>>4 {
		DEFB =>
			dat = ref Data.Bytes(op, n, offset, disobj[disptr:disptr+n]);
			disptr += n;
		DEFW =>
			words := array[n] of int;
			for(i = 0; i < n; i++)
				words[i] = getw();
			dat = ref Data.Words(op, n, offset, words);
		DEFS =>
			dat = ref Data.String(op, n, offset, string disobj[disptr:disptr+n]);
			disptr += n;
		DEFF =>
			if(math != nil){
				reals := array[n] of real;
				for(i = 0; i < n; i++)
					reals[i] = math->bits64real(getl());
				dat = ref Data.Reals(op, n, offset, reals);
			} else {
				disptr += 8*n;	# skip it
				dat = ref Data.Reals(op, n, offset, nil);
			}
			break;
		DEFA =>
			typex := getw();
			length := getw();
			dat = ref Data.Array(op, n, offset, typex, length);
		DIND =>
			dat = ref Data.Aindex(op, n, offset, getw());
		DAPOP =>
			dat = ref Data.Arestore(op, n, offset);
		DEFL =>
			bigs := array[n] of big;
			for(i = 0; i < n; i++)
				bigs[i] = getl();
			dat = ref Data.Bigs(op, n, offset, bigs);
		* =>
			dat = ref Data.Zero(op, n, offset);
		}
		m.data = dat :: m.data;
	}

	m.data = revdat(m.data);

	m.name = gets();

	m.links = array[m.lsize] of ref Link;
	for(i = 0; i < m.lsize; i++) {
		l := ref Link;
		l.pc = operand();
		l.desc = operand();
		l.sig = getw();
		l.name = gets();

		m.links[i] = l;
	}

	if(m.rt & Dis->HASLDT0)
		raise "obsolete dis";

	if(m.rt & Dis->HASLDT){
		nl := operand();
		imps := array[nl] of array of ref Import;
		for(i = 0; i < nl; i++){
			n := operand();
			imps[i] = array[n] of ref Import;
			for(j := 0; j < n; j++){
				imps[i][j] = im := ref Import;
				im.sig = getw();
				im.name = gets();
			}
		}
		disptr++;
		m.imports = imps;
	}

	if(m.rt & Dis->HASEXCEPT){
		nh := operand();	# number of handlers
		hs := array[nh] of ref Handler;
		for(i = 0; i < nh; i++){
			h := hs[i] = ref Handler;
			h.eoff = operand();
			h.pc1 = operand();
			h.pc2 = operand();
			t := operand();
			if(t >= 0)
				h.t = m.types[t];
			n := operand();	
			h.ne = n>>16;
			n &= 16rffff;	# number of cases
			h.etab = array[n+1] of ref Except;
			for(j := 0; j < n; j++){
				e := h.etab[j] = ref Except;
				k := disptr;
				while(int disobj[disptr++])	# pattern
					;
				e.s = string disobj[k: disptr-1];
				e.pc = operand();
			}
			e := h.etab[j] = ref Except;
			e.pc = operand();	# * pc
		}
		disptr++;	# 0 byte
		m.handlers = hs;
	}

	m.srcpath = gets();

	disobj = nil;
	return (m, nil);
}

operand(): int
{
	if(disptr >= len disobj)
		return -1;

	b := int disobj[disptr++];

	case b & 16rC0 {
	16r00 =>
		return b;
	16r40 =>
		return b | ~16r7F;
	16r80 =>
		if(disptr >= len disobj)
			return -1;
		if(b & 16r20)
			b |= ~16r3F;
		else
			b &= 16r3F;
		return (b<<8) | int disobj[disptr++];
	16rC0 =>
		if(disptr+2 >= len disobj)
			return -1;
		if(b & 16r20)
			b |= ~16r3F;
		else
			b &= 16r3F;
		b = b<<24 |
			(int disobj[disptr]<<16) |
		    	(int disobj[disptr+1]<<8)|
		    	int disobj[disptr+2];
		disptr += 3;
		return b;
	}
	return 0;
}

get4(a: array of byte, i: int): int
{
	return (int a[i+0] << 24) | (int a[i+1] << 16) | (int a[i+2] << 8) | int a[i+3];
}

getw(): int
{
	if(disptr+3 >= len disobj)
		return -1;
	i := (int disobj[disptr+0]<<24) |
	     (int disobj[disptr+1]<<16) |
	     (int disobj[disptr+2]<<8) |
	      int disobj[disptr+3];

	disptr += 4;
	return i;
}

getl(): big
{
	if(disptr+7 >= len disobj)
		return big -1;
	i := (big disobj[disptr+0]<<56) |
	     (big disobj[disptr+1]<<48) |
	     (big disobj[disptr+2]<<40) |
	     (big disobj[disptr+3]<<32) |
	     (big disobj[disptr+4]<<24) |
	     (big disobj[disptr+5]<<16) |
	     (big disobj[disptr+6]<<8) |
	      big disobj[disptr+7];

	disptr += 8;
	return i;
}

gets(): string
{
	s := disptr;
	while(disptr < len disobj && disobj[disptr] != byte 0)
		disptr++;

	v := string disobj[s:disptr];
	disptr++;
	return v;
}

revdat(d: list of ref Data): list of ref Data
{
	t: list of ref Data;

	while(d != nil) {
		t = hd d :: t;
		d = tl d;
	}
	return t;
}

op2s(op: int): string
{
	if(op < 0 || op >= len optab)
		return sys->sprint("OP%d", op);
	return optab[op];
}

inst2s(o: ref Inst): string
{
	fi := 0;
	si := 0;
	s := sprint("%-10s", optab[o.op]);
	src := "";
	dst := "";
	mid := "";
	case (o.addr>>3) & 7 {
	AFP =>
		src = sprint("%d(fp)", o.src);
	AMP =>
		src = sprint("%d(mp)", o.src);
	AIMM =>
		src = sprint("$%d", o.src);
	AIND|AFP =>
		fi = (o.src>>16) & 16rFFFF;
		si = o.src & 16rFFFF;
		src = sprint("%d(%d(fp))", si, fi);
	AIND|AMP =>
		fi = (o.src>>16) & 16rFFFF;
		si = o.src & 16rFFFF;
		src = sprint("%d(%d(mp))", si, fi);
	}

	case o.addr & ARM {
	AXIMM =>
		mid = sprint("$%d", o.mid);
	AXINF =>
		mid = sprint("%d(fp)", o.mid);
	AXINM =>
		mid = sprint("%d(mp)", o.mid);
	}

	case o.addr & 7 {
	AFP =>
		dst = sprint("%d(fp)", o.dst);
	AMP =>
		dst = sprint("%d(mp)", o.dst);
	AIMM =>
		dst = sprint("$%d", o.dst);
	AIND|AFP =>
		fi = (o.dst>>16) & 16rFFFF;
		si = o.dst & 16rFFFF;
		dst = sprint("%d(%d(fp))", si, fi);
	AIND|AMP =>
		fi = (o.dst>>16) & 16rFFFF;
		si = o.dst & 16rFFFF;
		dst = sprint("%d(%d(mp))", si, fi);
	}
	if(mid == "") {
		if(src == "")
			s += sprint("%s", dst);
		else if(dst == "")
			s += sprint("%s", src);
		else
			s += sprint("%s, %s", src, dst);
	}
	else
		s += sprint("%s, %s, %s", src, mid, dst);

	return s;
}

getsb(fd: ref Sys->FD, o: int): (string, int)
{
	b := array[1] of byte;
	buf := array[8192] of byte;
	p := len buf;
	for( ; ; o++){
		sys->seek(fd, big -o, Sys->SEEKEND);
		if(sys->read(fd, b, 1) != 1)
			return (nil, 0);
		if(b[0] == byte 0){
			if(p < len buf)
				break;
		}
		else if(p > 0)
			buf[--p] = b[0];
	}
	return (string buf[p: ], o);
}

src(disf: string): string
{
	fd := sys->open(disf, sys->OREAD);
	if(fd == nil)
		return nil;
	(s, nil) := getsb(fd, 1);
	if(s != nil && s[0] == '/')
		return s;
	return nil;
}
