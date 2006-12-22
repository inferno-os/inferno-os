#
# VM instruction set
#
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
	# add new operators here
	MAXDIS: con iota;

XMAGIC:		con 819248;	# Normal magic
SMAGIC:		con 923426;	# Signed module

AMP:		con 16r00;	# Src/Dst op addressing 
AFP:		con 16r01;
AIMM:		con 16r2;
AXXX:		con 16r03;
AIND:		con 16r04;
AMASK:		con 16r07;
AOFF:		con 16r08;
AVAL:		con 16r10;

ARM:		con 16rC0;	# Middle op addressing 
AXNON:		con 16r00;
AXIMM:		con 16r40;
AXINF:		con 16r80;
AXINM:		con 16rC0;

DEFZ:		con 0;
DEFB:		con 1;		# Byte 
DEFW:		con 2;		# Word 
DEFS:		con 3;		# Utf-string 
DEFF:		con 4;		# Real value 
DEFA:		con 5;		# Array 
DIND:		con 6;		# Set index 
DAPOP:		con 7;		# Restore address register 
DEFL:		con 8;		# BIG 

DADEPTH:	con 4;		# Array address stack size 

REGLINK:	con 0;
REGFRAME:	con 1;
REGMOD:		con 2;
REGTYP:		con 3;
REGRET:		con 4;
NREG:		con 5;

IBY2WD:		con 4;
IBY2FT:		con 8;
IBY2LG:		con 8;

MUSTCOMPILE:	con 1<<0;
DONTCOMPILE:	con 1<<1;
SHAREMP:	con 1<<2;
DYNMOD:	con	1<<3;
HASLDT0:	con	1<<4;
HASEXCEPT:	con	1<<5;
HASLDT:	con	1<<6;

DMAX:		con 1 << 4;

#define DTYPE(x)	(x>>4)
#define DBYTE(x, l)	((x<<4)|l)
#define DMAX		(1<<4)
#define DLEN(x)		(x& (DMAX-1))

DBYTE:		con 4;
SRC:		con 3;
DST:		con 0;

#define SRC(x)		((x)<<3)
#define DST(x)		((x)<<0)
#define USRC(x)		(((x)>>3)&AMASK)
#define UDST(x)		((x)&AMASK)
#define UXSRC(x)	((x)&(AMASK<<3))
#define UXDST(x)	((x)&(AMASK<<0))
