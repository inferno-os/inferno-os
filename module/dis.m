Dis: module
{
	PATH:	con "/dis/lib/dis.dis";

	XMAGIC:		con	819248;
	SMAGIC:		con	923426;
	MUSTCOMPILE:	con	1<<0;
	DONTCOMPILE:	con 	1<<1;
	SHAREMP:	con 	1<<2;
	DYNMOD:	con	1<<3;
	HASLDT0:	con	1<<4;
	HASEXCEPT:	con	1<<5;
	HASLDT:	con	1<<6;

	AMP:	con 16r00;	# Src/Dst op addressing
	AFP:	con 16r01;
	AIMM:	con 16r02;
	AXXX:	con 16r03;
	AIND:	con 16r04;
	AMASK:	con 16r07;

	ARM:	con 16rC0;	# Middle op addressing
	AXNON:	con 16r00;
	AXIMM:	con 16r40;
	AXINF:	con 16r80;
	AXINM:	con 16rC0;

	DEFZ:	con 0;
	DEFB:	con 1;		# Byte
	DEFW:	con 2;		# Word
	DEFS:	con 3;		# Utf-string
	DEFF:	con 4;		# Real value
	DEFA:	con 5;		# Array
	DIND:	con 6;		# Set index
	DAPOP:	con 7;		# Restore address register
	DEFL:	con 8;		# BIG
	DMAX:	con 1<<4;

	Inst: adt
	{
		op:	int;
		addr:	int;
		mid:	int;
		src:	int;
		dst:	int;
	};

	Type: adt
	{
		size:	int;
		np:	int;
		map:	array of byte;
	};

	Data: adt
	{
		op:	int;		# encoded op
		n:	int;		# number of elements
		off:	int;		# byte offset in data space
		pick {
		Zero =>		# DEFZ
		Bytes =>		# DEFB
			bytes:	array of byte;
		Words =>		# DEFW
			words:	array of int;
		String =>		# DEFS
			str:	string;
		Reals =>		# DEFF
			reals:	array of real;
		Array =>		# DEFA
			typex:	int;
			length:	int;
		Aindex =>		# DIND
			index:	int;
		Arestore =>	# DAPOP
		Bigs =>		# DEFL
			bigs:		array of big;
		}
	};

	Link: adt
	{
		pc:	int;
		desc:	int;
		sig:	int;
		name:	string;
	};

	Import: adt
	{
		sig:	int;
		name:	string;
	};

	Except: adt
	{
		s:	string;
		pc:	int;
	};

	Handler: adt
	{
		pc1:	int;
		pc2:	int;
		eoff:	int;
		ne:	int;
		t:	ref Type;
		etab:	array of ref Except;
	};

	Mod: adt
	{
		name:	string;
		srcpath:	string;

		magic:	int;
		rt:	int;
		ssize:	int;
		isize:	int;
		dsize:	int;
		tsize:	int;
		lsize:	int;
		entry:	int;
		entryt:	int;

		inst:	array of ref Inst;
		types:	array of ref Type;
		data:	list of ref Data;
		links:	array of ref Link;
		imports:	array of array of ref Import;
		handlers:	array of ref Handler;

		sign:	array of byte;
	};

	INOP,
	IALT,
	INBALT,
	IGOTO,
	ICALL,
	IFRAME,
	ISPAWN,
	IRUNT,
	ILOAD,
	IMCALL,
	IMSPAWN,
	IMFRAME,
	IRET,
	IJMP,
	ICASE,
	IEXIT,
	INEW,
	INEWA,
	INEWCB,
	INEWCW,
	INEWCF,
	INEWCP,
	INEWCM,
	INEWCMP,
	ISEND,
	IRECV,
	ICONSB,
	ICONSW,
	ICONSP,
	ICONSF,
	ICONSM,
	ICONSMP,
	IHEADB,
	IHEADW,
	IHEADP,
	IHEADF,
	IHEADM,
	IHEADMP,
	ITAIL,
	ILEA,
	IINDX,
	IMOVP,
	IMOVM,
	IMOVMP,
	IMOVB,
	IMOVW,
	IMOVF,
	ICVTBW,
	ICVTWB,
	ICVTFW,
	ICVTWF,
	ICVTCA,
	ICVTAC,
	ICVTWC,
	ICVTCW,
	ICVTFC,
	ICVTCF,
	IADDB,
	IADDW,
	IADDF,
	ISUBB,
	ISUBW,
	ISUBF,
	IMULB,
	IMULW,
	IMULF,
	IDIVB,
	IDIVW,
	IDIVF,
	IMODW,
	IMODB,
	IANDB,
	IANDW,
	IORB,
	IORW,
	IXORB,
	IXORW,
	ISHLB,
	ISHLW,
	ISHRB,
	ISHRW,
	IINSC,
	IINDC,
	IADDC,
	ILENC,
	ILENA,
	ILENL,
	IBEQB,
	IBNEB,
	IBLTB,
	IBLEB,
	IBGTB,
	IBGEB,
	IBEQW,
	IBNEW,
	IBLTW,
	IBLEW,
	IBGTW,
	IBGEW,
	IBEQF,
	IBNEF,
	IBLTF,
	IBLEF,
	IBGTF,
	IBGEF,
	IBEQC,
	IBNEC,
	IBLTC,
	IBLEC,
	IBGTC,
	IBGEC,
	ISLICEA,
	ISLICELA,
	ISLICEC,
	IINDW,
	IINDF,
	IINDB,
	INEGF,
	IMOVL,
	IADDL,
	ISUBL,
	IDIVL,
	IMODL,
	IMULL,
	IANDL,
	IORL,
	IXORL,
	ISHLL,
	ISHRL,
	IBNEL,
	IBLTL,
	IBLEL,
	IBGTL,
	IBGEL,
	IBEQL,
	ICVTLF,
	ICVTFL,
	ICVTLW,
	ICVTWL,
	ICVTLC,
	ICVTCL,
	IHEADL,
	ICONSL,
	INEWCL,
	ICASEC,
	IINDL,
	IMOVPC,
	ITCMP,
	IMNEWZ,
	ICVTRF,
	ICVTFR,
	ICVTWS,
	ICVTSW,
	ILSRW,
	ILSRL,
	IECLR,
	INEWZ,
	INEWAZ,
	IRAISE,
	ICASEL,
	IMULX,
	IDIVX,
	ICVTXX,
	IMULX0,
	IDIVX0,
	ICVTXX0,
	IMULX1,
	IDIVX1,
	ICVTXX1,
	ICVTFX,
	ICVTXF,
	IEXPW,
	IEXPL,
	IEXPF,
	ISELF,
	# add new instructions here
	MAXDIS: con iota;

	init:		fn();
	loadobj:	fn(file: string): (ref Mod, string);
	op2s:	fn(op: int): string;
	inst2s:	fn(ins: ref Inst): string;
	src:		fn(file: string): string;
};
#
# derived by Vita Nuova Limited 1998 from /appl/wm/rt.b and /include/isa.h, both
# Copyright © 1996-1999 Lucent Technologies Inc.  All rights reserved.
#
