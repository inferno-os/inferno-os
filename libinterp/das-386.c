#include <lib9.h>
#include <kernel.h>

int	i386inst(ulong, char, char*, int);
int	i386das(ulong, char*, int);
int	i386instlen(ulong);

static uchar *dasdata;

static char *
_hexify(char *buf, ulong p, int zeros)
{
	ulong d;

	d = p/16;
	if(d)
		buf = _hexify(buf, d, zeros-1);
	else
		while(zeros--)
			*buf++ = '0';
	*buf++ = "0123456789abcdef"[p&0x0f];
	return buf;
}

/*
 *  an instruction
 */
typedef struct Instr Instr;
struct	Instr
{
	uchar	mem[1+1+1+1+2+1+1+4+4];		/* raw instruction */
	ulong	addr;		/* address of start of instruction */
	int	n;		/* number of bytes in instruction */
	char	*prefix;	/* instr prefix */
	char	*segment;	/* segment override */
	uchar	jumptype;	/* set to the operand type for jump/ret/call */
	char	osize;		/* 'W' or 'L' */
	char	asize;		/* address size 'W' or 'L' */
	uchar	mod;		/* bits 6-7 of mod r/m field */
	uchar	reg;		/* bits 3-5 of mod r/m field */
	char	ss;		/* bits 6-7 of SIB */
	char	index;		/* bits 3-5 of SIB */
	char	base;		/* bits 0-2 of SIB */
	short	seg;		/* segment of far address */
	ulong	disp;		/* displacement */
	ulong 	imm;		/* immediate */
	ulong 	imm2;		/* second immediate operand */
	char	*curr;		/* fill level in output buffer */
	char	*end;		/* end of output buffer */
	char	*err;		/* error message */
};

	/* 386 register (ha!) set */
enum{
	AX=0,
	CX,
	DX,
	BX,
	SP,
	BP,
	SI,
	DI,
};
	/* Operand Format codes */
/*
%A	-	address size register modifier (!asize -> 'E')
%C	-	Control register CR0/CR1/CR2
%D	-	Debug register DR0/DR1/DR2/DR3/DR6/DR7
%I	-	second immediate operand
%O	-	Operand size register modifier (!osize -> 'E')
%T	-	Test register TR6/TR7
%S	-	size code ('W' or 'L')
%X	-	Weird opcode: OSIZE == 'W' => "CBW"; else => "CWDE"
%d	-	displacement 16-32 bits
%e	-	effective address - Mod R/M value
%f	-	floating point register F0-F7 - from Mod R/M register
%g	-	segment register
%i	-	immediate operand 8-32 bits
%p	-	PC-relative - signed displacement in immediate field
%r	-	Reg from Mod R/M
%x	-	Weird opcode: OSIZE == 'W' => "CWD"; else => "CDQ"
*/

typedef struct Optable Optable;
struct Optable
{
	char	operand[2];
	void	*proto;		/* actually either (char*) or (Optable*) */
};
	/* Operand decoding codes */
enum {
	Ib = 1,			/* 8-bit immediate - (no sign extension)*/
	Ibs,			/* 8-bit immediate (sign extended) */
	Jbs,			/* 8-bit sign-extended immediate in jump or call */
	Iw,			/* 16-bit immediate -> imm */
	Iw2,			/* 16-bit immediate -> imm2 */
	Iwd,			/* Operand-sized immediate (no sign extension)*/
	Awd,			/* Address offset */
	Iwds,			/* Operand-sized immediate (sign extended) */
	RM,			/* Word or long R/M field with register (/r) */
	RMB,			/* Byte R/M field with register (/r) */
	RMOP,			/* Word or long R/M field with op code (/digit) */
	RMOPB,			/* Byte R/M field with op code (/digit) */
	RMR,			/* R/M register only (mod = 11) */
	RMM,			/* R/M memory only (mod = 0/1/2) */
	R0,			/* Base reg of Mod R/M is literal 0x00 */
	R1,			/* Base reg of Mod R/M is literal 0x01 */
	FRMOP,			/* Floating point R/M field with opcode */
	FRMEX,			/* Extended floating point R/M field with opcode */
	JUMP,			/* Jump or Call flag - no operand */
	RET,			/* Return flag - no operand */
	OA,			/* literal 0x0a byte */
	PTR,			/* Seg:Displacement addr (ptr16:16 or ptr16:32) */
	AUX,			/* Multi-byte op code - Auxiliary table */
	PRE,			/* Instr Prefix */
	SEG,			/* Segment Prefix */
	OPOVER,			/* Operand size override */
	ADDOVER,		/* Address size override */
};
	
static Optable optab0F00[8]=
{
	0,0,		"MOVW	LDT,%e",
	0,0,		"MOVW	TR,%e",
	0,0,		"MOVW	%e,LDT",
	0,0,		"MOVW	%e,TR",
	0,0,		"VERR	%e",
	0,0,		"VERW	%e",
};

static Optable optab0F01[8]=
{
	0,0,		"MOVL	GDTR,%e",
	0,0,		"MOVL	IDTR,%e",
	0,0,		"MOVL	%e,GDTR",
	0,0,		"MOVL	%e,IDTR",
	0,0,		"MOVW	MSW,%e",	/* word */
	0,0,		nil,
	0,0,		"MOVW	%e,MSW",	/* word */
};

static Optable optab0FBA[8]=
{
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	Ib,0,		"BT%S	%i,%e",
	Ib,0,		"BTS%S	%i,%e",
	Ib,0,		"BTR%S	%i,%e",
	Ib,0,		"BTC%S	%i,%e",
};

static Optable optab0F[256]=
{
	RMOP,0,		optab0F00,
	RMOP,0,		optab0F01,
	RM,0,		"LAR	%e,%r",
	RM,0,		"LSL	%e,%r",
	0,0,		nil,
	0,0,		nil,
	0,0,		"CLTS",
	0,0,		nil,
	0,0,		"INVD",
	0,0,		"WBINVD",
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,

	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,

	RMR,0,		"MOVL	%C,%e",		/* [0x20] */
	RMR,0,		"MOVL	%D,%e",
	RMR,0,		"MOVL	%e,%C",
	RMR,0,		"MOVL	%e,%D",
	RMR,0,		"MOVL	%T,%e",
	0,0,		nil,
	RMR,0,		"MOVL	%e,%T",
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,

	0,0,		"WRMSR",		/* [0x30] */
	0,0,		"RDTSC",
	0,0,		"RDMSR",
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,

	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,

	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,

	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,

	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,

	Iwds,0,		"JOS	%p",	/* [0x80] */
	Iwds,0,		"JOC	%p",
	Iwds,0,		"JCS	%p",
	Iwds,0,		"JCC	%p",
	Iwds,0,		"JEQ	%p",
	Iwds,0,		"JNE	%p",
	Iwds,0,		"JLS	%p",
	Iwds,0,		"JHI	%p",
	Iwds,0,		"JMI	%p",
	Iwds,0,		"JPL	%p",
	Iwds,0,		"JPS	%p",
	Iwds,0,		"JPC	%p",
	Iwds,0,		"JLT	%p",
	Iwds,0,		"JGE	%p",
	Iwds,0,		"JLE	%p",
	Iwds,0,		"JGT	%p",

	RMB,0,		"SETOS	%e",	/* [0x90] */
	RMB,0,		"SETOC	%e",
	RMB,0,		"SETCS	%e",
	RMB,0,		"SETCC	%e",
	RMB,0,		"SETEQ	%e",
	RMB,0,		"SETNE	%e",
	RMB,0,		"SETLS	%e",
	RMB,0,		"SETHI	%e",
	RMB,0,		"SETMI	%e",
	RMB,0,		"SETPL	%e",
	RMB,0,		"SETPS	%e",
	RMB,0,		"SETPC	%e",
	RMB,0,		"SETLT	%e",
	RMB,0,		"SETGE	%e",
	RMB,0,		"SETLE	%e",
	RMB,0,		"SETGT	%e",

	0,0,		"PUSHL	FS",	/* [0xa0] */
	0,0,		"POPL	FS",
	0,0,		"CPUID",
	RM,0,		"BT%S	%r,%e",
	RM,Ib,		"SHLD%S	%r,%i,%e",
	RM,0,		"SHLD%S	%r,CL,%e",
	0,0,		nil,
	0,0,		nil,
	0,0,		"PUSHL	GS",
	0,0,		"POPL	GS",
	0,0,		nil,
	RM,0,		"BTS%S	%r,%e",
	RM,Ib,		"SHRD%S	%r,%i,%e",
	RM,0,		"SHRD%S	%r,CL,%e",
	0,0,		nil,
	RM,0,		"IMUL%S	%e,%r",

	0,0,		nil,
	0,0,		nil,
	RMM,0,		"LSS	%e,%r",	/* [0xb2] */
	RM,0,		"BTR%S	%r,%e",
	RMM,0,		"LFS	%e,%r",
	RMM,0,		"LGS	%e,%r",
	RMB,0,		"MOVBZX	%e,%R",
	RM,0,		"MOVWZX	%e,%R",
	0,0,		nil,
	0,0,		nil,
	RMOP,0,		optab0FBA,
	RM,0,		"BTC%S	%e,%r",
	RM,0,		"BSF%S	%e,%r",
	RM,0,		"BSR%S	%e,%r",
	RMB,0,		"MOVBSX	%e,%R",
	RM,0,		"MOVWSX	%e,%R",
};

static Optable optab80[8]=
{
	Ib,0,		"ADDB	%i,%e",
	Ib,0,		"ORB	%i,%e",
	Ib,0,		"ADCB	%i,%e",
	Ib,0,		"SBBB	%i,%e",
	Ib,0,		"ANDB	%i,%e",
	Ib,0,		"SUBB	%i,%e",
	Ib,0,		"XORB	%i,%e",
	Ib,0,		"CMPB	%e,%i",
};

static Optable optab81[8]=
{
	Iwd,0,		"ADD%S	%i,%e",
	Iwd,0,		"OR%S	%i,%e",
	Iwd,0,		"ADC%S	%i,%e",
	Iwd,0,		"SBB%S	%i,%e",
	Iwd,0,		"AND%S	%i,%e",
	Iwd,0,		"SUB%S	%i,%e",
	Iwd,0,		"XOR%S	%i,%e",
	Iwd,0,		"CMP%S	%e,%i",
};

static Optable optab83[8]=
{
	Ibs,0,		"ADD%S	%i,%e",
	Ibs,0,		"OR%S	%i,%e",
	Ibs,0,		"ADC%S	%i,%e",
	Ibs,0,		"SBB%S	%i,%e",
	Ibs,0,		"AND%S	%i,%e",
	Ibs,0,		"SUB%S	%i,%e",
	Ibs,0,		"XOR%S	%i,%e",
	Ibs,0,		"CMP%S	%e,%i",
};

static Optable optabC0[8] =
{
	Ib,0,		"ROLB	%i,%e",
	Ib,0,		"RORB	%i,%e",
	Ib,0,		"RCLB	%i,%e",
	Ib,0,		"RCRB	%i,%e",
	Ib,0,		"SHLB	%i,%e",
	Ib,0,		"SHRB	%i,%e",
	0,0,		nil,
	Ib,0,		"SARB	%i,%e",
};

static Optable optabC1[8] =
{
	Ib,0,		"ROL%S	%i,%e",
	Ib,0,		"ROR%S	%i,%e",
	Ib,0,		"RCL%S	%i,%e",
	Ib,0,		"RCR%S	%i,%e",
	Ib,0,		"SHL%S	%i,%e",
	Ib,0,		"SHR%S	%i,%e",
	0,0,		nil,
	Ib,0,		"SAR%S	%i,%e",
};

static Optable optabD0[8] =
{
	0,0,		"ROLB	%e",
	0,0,		"RORB	%e",
	0,0,		"RCLB	%e",
	0,0,		"RCRB	%e",
	0,0,		"SHLB	%e",
	0,0,		"SHRB	%e",
	0,0,		nil,
	0,0,		"SARB	%e",
};

static Optable optabD1[8] =
{
	0,0,		"ROL%S	%e",
	0,0,		"ROR%S	%e",
	0,0,		"RCL%S	%e",
	0,0,		"RCR%S	%e",
	0,0,		"SHL%S	%e",
	0,0,		"SHR%S	%e",
	0,0,		nil,
	0,0,		"SAR%S	%e",
};

static Optable optabD2[8] =
{
	0,0,		"ROLB	CL,%e",
	0,0,		"RORB	CL,%e",
	0,0,		"RCLB	CL,%e",
	0,0,		"RCRB	CL,%e",
	0,0,		"SHLB	CL,%e",
	0,0,		"SHRB	CL,%e",
	0,0,		nil,
	0,0,		"SARB	CL,%e",
};

static Optable optabD3[8] =
{
	0,0,		"ROL%S	CL,%e",
	0,0,		"ROR%S	CL,%e",
	0,0,		"RCL%S	CL,%e",
	0,0,		"RCR%S	CL,%e",
	0,0,		"SHL%S	CL,%e",
	0,0,		"SHR%S	CL,%e",
	0,0,		nil,
	0,0,		"SAR%S	CL,%e",
};

static Optable optabD8[8+8] =
{
	0,0,		"FADDF	%e,F0",
	0,0,		"FMULF	%e,F0",
	0,0,		"FCOMF	%e,F0",
	0,0,		"FCOMFP	%e,F0",
	0,0,		"FSUBF	%e,F0",
	0,0,		"FSUBRF	%e,F0",
	0,0,		"FDIVF	%e,F0",
	0,0,		"FDIVRF	%e,F0",
	0,0,		"FADDD	%f,F0",
	0,0,		"FMULD	%f,F0",
	0,0,		"FCOMD	%f,F0",
	0,0,		"FCOMPD	%f,F0",
	0,0,		"FSUBD	%f,F0",
	0,0,		"FSUBRD	%f,F0",
	0,0,		"FDIVD	%f,F0",
	0,0,		"FDIVRD	%f,F0",
};
/*
 *	optabD9 and optabDB use the following encoding: 
 *	if (0 <= modrm <= 2) instruction = optabDx[modrm&0x07];
 *	else instruction = optabDx[(modrm&0x3f)+8];
 *
 *	the instructions for MOD == 3, follow the 8 instructions
 *	for the other MOD values stored at the front of the table.
 */
static Optable optabD9[64+8] =
{
	0,0,		"FMOVF	%e,F0",
	0,0,		nil,
	0,0,		"FMOVF	F0,%e",
	0,0,		"FMOVFP	F0,%e",
	0,0,		"FLDENV%S %e",
	0,0,		"FLDCW	%e",
	0,0,		"FSTENV%S %e",
	0,0,		"FSTCW	%e",
	0,0,		"FMOVD	F0,F0",		/* Mod R/M = 11xx xxxx*/
	0,0,		"FMOVD	F1,F0",
	0,0,		"FMOVD	F2,F0",
	0,0,		"FMOVD	F3,F0",
	0,0,		"FMOVD	F4,F0",
	0,0,		"FMOVD	F5,F0",
	0,0,		"FMOVD	F6,F0",
	0,0,		"FMOVD	F7,F0",
	0,0,		"FXCHD	F0,F0",
	0,0,		"FXCHD	F1,F0",
	0,0,		"FXCHD	F2,F0",
	0,0,		"FXCHD	F3,F0",
	0,0,		"FXCHD	F4,F0",
	0,0,		"FXCHD	F5,F0",
	0,0,		"FXCHD	F6,F0",
	0,0,		"FXCHD	F7,F0",
	0,0,		"FNOP",
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		"FCHS",		/* [0x28] */
	0,0,		"FABS",
	0,0,		nil,
	0,0,		nil,
	0,0,		"FTST",
	0,0,		"FXAM",
	0,0,		nil,
	0,0,		nil,
	0,0,		"FLD1",
	0,0,		"FLDL2T",
	0,0,		"FLDL2E",
	0,0,		"FLDPI",
	0,0,		"FLDLG2",
	0,0,		"FLDLN2",
	0,0,		"FLDZ",
	0,0,		nil,
	0,0,		"F2XM1",
	0,0,		"FYL2X",
	0,0,		"FPTAN",
	0,0,		"FPATAN",
	0,0,		"FXTRACT",
	0,0,		"FPREM1",
	0,0,		"FDECSTP",
	0,0,		"FNCSTP",
	0,0,		"FPREM",
	0,0,		"FYL2XP1",
	0,0,		"FSQRT",
	0,0,		"FSINCOS",
	0,0,		"FRNDINT",
	0,0,		"FSCALE",
	0,0,		"FSIN",
	0,0,		"FCOS",
};

static Optable optabDA[8+8] =
{
	0,0,		"FADDL	%e,F0",
	0,0,		"FMULL	%e,F0",
	0,0,		"FCOML	%e,F0",
	0,0,		"FCOMLP	%e,F0",
	0,0,		"FSUBL	%e,F0",
	0,0,		"FSUBRL	%e,F0",
	0,0,		"FDIVL	%e,F0",
	0,0,		"FDIVRL	%e,F0",
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	R1,0,		"FUCOMPP",	/* [0x0d] */
};

static Optable optabDB[8+64] =
{
	0,0,		"FMOVL	%e,F0",
	0,0,		nil,
	0,0,		"FMOVL	F0,%e",
	0,0,		"FMOVLP	F0,%e",
	0,0,		nil,
	0,0,		"FMOVX	%e,F0",
	0,0,		nil,
	0,0,		"FMOVXP	F0,%e",
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		"FCLEX",	/* [0x2a] */
	0,0,		"FINIT",
};

static Optable optabDC[8+8] =
{
	0,0,		"FADDD	%e,F0",
	0,0,		"FMULD	%e,F0",
	0,0,		"FCOMD	%e,F0",
	0,0,		"FCOMDP	%e,F0",
	0,0,		"FSUBD	%e,F0",
	0,0,		"FSUBRD	%e,F0",
	0,0,		"FDIVD	%e,F0",
	0,0,		"FDIVRD	%e,F0",
	0,0,		"FADDD	F0,%f",
	0,0,		"FMULD	F0,%f",
	0,0,		nil,
	0,0,		nil,
	0,0,		"FSUBRD	F0,%f",
	0,0,		"FSUBD	F0,%f",
	0,0,		"FDIVRD	F0,%f",
	0,0,		"FDIVD	F0,%f",
};

static Optable optabDD[8+8] =
{
	0,0,		"FMOVD	%e,F0",
	0,0,		nil,
	0,0,		"FMOVD	F0,%e",
	0,0,		"FMOVDP	F0,%e",
	0,0,		"FRSTOR%S %e",
	0,0,		nil,
	0,0,		"FSAVE%S %e",
	0,0,		"FSTSW	%e",
	0,0,		"FFREED	%f",
	0,0,		nil,
	0,0,		"FMOVD	%f,F0",
	0,0,		"FMOVDP	%f,F0",
	0,0,		"FUCOMD	%f,F0",
	0,0,		"FUCOMDP %f,F0",
};

static Optable optabDE[8+8] =
{
	0,0,		"FADDW	%e,F0",
	0,0,		"FMULW	%e,F0",
	0,0,		"FCOMW	%e,F0",
	0,0,		"FCOMWP	%e,F0",
	0,0,		"FSUBW	%e,F0",
	0,0,		"FSUBRW	%e,F0",
	0,0,		"FDIVW	%e,F0",
	0,0,		"FDIVRW	%e,F0",
	0,0,		"FADDDP	F0,%f",
	0,0,		"FMULDP	F0,%f",
	0,0,		nil,
	R1,0,		"FCOMPDP",
	0,0,		"FSUBRDP F0,%f",
	0,0,		"FSUBDP	F0,%f",
	0,0,		"FDIVRDP F0,%f",
	0,0,		"FDIVDP	F0,%f",
};

static Optable optabDF[8+8] =
{
	0,0,		"FMOVW	%e,F0",
	0,0,		nil,
	0,0,		"FMOVW	F0,%e",
	0,0,		"FMOVWP	F0,%e",
	0,0,		"FBLD	%e",
	0,0,		"FMOVL	%e,F0",
	0,0,		"FBSTP	%e",
	0,0,		"FMOVLP	F0,%e",
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	0,0,		nil,
	R0,0,		"FSTSW	%OAX",
};

static Optable optabF6[8] =
{
	Ib,0,		"TESTB	%i,%e",
	0,0,		nil,
	0,0,		"NOTB	%e",
	0,0,		"NEGB	%e",
	0,0,		"MULB	AL,%e",
	0,0,		"IMULB	AL,%e",
	0,0,		"DIVB	AL,%e",
	0,0,		"IDIVB	AL,%e",
};

static Optable optabF7[8] =
{
	Iwd,0,		"TEST%S	%i,%e",
	0,0,		nil,
	0,0,		"NOT%S	%e",
	0,0,		"NEG%S	%e",
	0,0,		"MUL%S	%OAX,%e",
	0,0,		"IMUL%S	%OAX,%e",
	0,0,		"DIV%S	%OAX,%e",
	0,0,		"IDIV%S	%OAX,%e",
};

static Optable optabFE[8] =
{
	0,0,		"INCB	%e",
	0,0,		"DECB	%e",
};

static Optable optabFF[8] =
{
	0,0,		"INC%S	%e",
	0,0,		"DEC%S	%e",
	JUMP,0,		"CALL*%S %e",
	JUMP,0,		"CALLF*%S %e",
	JUMP,0,		"JMP*%S	%e",
	JUMP,0,		"JMPF*%S %e",
	0,0,		"PUSHL	%e",
};

static Optable optable[256] =
{
	RMB,0,		"ADDB	%r,%e",
	RM,0,		"ADD%S	%r,%e",
	RMB,0,		"ADDB	%e,%r",
	RM,0,		"ADD%S	%e,%r",
	Ib,0,		"ADDB	%i,AL",
	Iwd,0,		"ADD%S	%i,%OAX",
	0,0,		"PUSHL	ES",
	0,0,		"POPL	ES",
	RMB,0,		"ORB	%r,%e",
	RM,0,		"OR%S	%r,%e",
	RMB,0,		"ORB	%e,%r",
	RM,0,		"OR%S	%e,%r",
	Ib,0,		"ORB	%i,AL",
	Iwd,0,		"OR%S	%i,%OAX",
	0,0,		"PUSHL	CS",
	AUX,0,		optab0F,
	RMB,0,		"ADCB	%r,%e",
	RM,0,		"ADC%S	%r,%e",
	RMB,0,		"ADCB	%e,%r",
	RM,0,		"ADC%S	%e,%r",
	Ib,0,		"ADCB	%i,AL",
	Iwd,0,		"ADC%S	%i,%OAX",
	0,0,		"PUSHL	SS",
	0,0,		"POPL	SS",
	RMB,0,		"SBBB	%r,%e",
	RM,0,		"SBB%S	%r,%e",
	RMB,0,		"SBBB	%e,%r",
	RM,0,		"SBB%S	%e,%r",
	Ib,0,		"SBBB	%i,AL",
	Iwd,0,		"SBB%S	%i,%OAX",
	0,0,		"PUSHL	DS",
	0,0,		"POPL	DS",
	RMB,0,		"ANDB	%r,%e",
	RM,0,		"AND%S	%r,%e",
	RMB,0,		"ANDB	%e,%r",
	RM,0,		"AND%S	%e,%r",
	Ib,0,		"ANDB	%i,AL",
	Iwd,0,		"AND%S	%i,%OAX",
	SEG,0,		"ES:",
	0,0,		"DAA",
	RMB,0,		"SUBB	%r,%e",
	RM,0,		"SUB%S	%r,%e",
	RMB,0,		"SUBB	%e,%r",
	RM,0,		"SUB%S	%e,%r",
	Ib,0,		"SUBB	%i,AL",
	Iwd,0,		"SUB%S	%i,%OAX",
	SEG,0,		"CS:",
	0,0,		"DAS",
	RMB,0,		"XORB	%r,%e",
	RM,0,		"XOR%S	%r,%e",
	RMB,0,		"XORB	%e,%r",
	RM,0,		"XOR%S	%e,%r",
	Ib,0,		"XORB	%i,AL",
	Iwd,0,		"XOR%S	%i,%OAX",
	SEG,0,		"SS:",
	0,0,		"AAA",
	RMB,0,		"CMPB	%r,%e",
	RM,0,		"CMP%S	%r,%e",
	RMB,0,		"CMPB	%e,%r",
	RM,0,		"CMP%S	%e,%r",
	Ib,0,		"CMPB	%i,AL",
	Iwd,0,		"CMP%S	%i,%OAX",
	SEG,0,		"DS:",
	0,0,		"AAS",
	0,0,		"INC%S	%OAX",
	0,0,		"INC%S	%OCX",
	0,0,		"INC%S	%ODX",
	0,0,		"INC%S	%OBX",
	0,0,		"INC%S	%OSP",
	0,0,		"INC%S	%OBP",
	0,0,		"INC%S	%OSI",
	0,0,		"INC%S	%ODI",
	0,0,		"DEC%S	%OAX",
	0,0,		"DEC%S	%OCX",
	0,0,		"DEC%S	%ODX",
	0,0,		"DEC%S	%OBX",
	0,0,		"DEC%S	%OSP",
	0,0,		"DEC%S	%OBP",
	0,0,		"DEC%S	%OSI",
	0,0,		"DEC%S	%ODI",
	0,0,		"PUSH%S	%OAX",
	0,0,		"PUSH%S	%OCX",
	0,0,		"PUSH%S	%ODX",
	0,0,		"PUSH%S	%OBX",
	0,0,		"PUSH%S	%OSP",
	0,0,		"PUSH%S	%OBP",
	0,0,		"PUSH%S	%OSI",
	0,0,		"PUSH%S	%ODI",
	0,0,		"POP%S	%OAX",
	0,0,		"POP%S	%OCX",
	0,0,		"POP%S	%ODX",
	0,0,		"POP%S	%OBX",
	0,0,		"POP%S	%OSP",
	0,0,		"POP%S	%OBP",
	0,0,		"POP%S	%OSI",
	0,0,		"POP%S	%ODI",
	0,0,		"PUSHA%S",
	0,0,		"POPA%S",
	RMM,0,		"BOUND	%e,%r",
	RM,0,		"ARPL	%r,%e",
	SEG,0,		"FS:",
	SEG,0,		"GS:",
	OPOVER,0,	"",
	ADDOVER,0,	"",
	Iwd,0,		"PUSH%S	%i",
	RM,Iwd,		"IMUL%S	%e,%i,%r",
	Ib,0,		"PUSH%S	%i",
	RM,Ibs,		"IMUL%S	%e,%i,%r",
	0,0,		"INSB	DX,(%ODI)",
	0,0,		"INS%S	DX,(%ODI)",
	0,0,		"OUTSB	(%ASI),DX",
	0,0,		"OUTS%S	(%ASI),DX",
	Jbs,0,		"JOS	%p",
	Jbs,0,		"JOC	%p",
	Jbs,0,		"JCS	%p",
	Jbs,0,		"JCC	%p",
	Jbs,0,		"JEQ	%p",
	Jbs,0,		"JNE	%p",
	Jbs,0,		"JLS	%p",
	Jbs,0,		"JHI	%p",
	Jbs,0,		"JMI	%p",
	Jbs,0,		"JPL	%p",
	Jbs,0,		"JPS	%p",
	Jbs,0,		"JPC	%p",
	Jbs,0,		"JLT	%p",
	Jbs,0,		"JGE	%p",
	Jbs,0,		"JLE	%p",
	Jbs,0,		"JGT	%p",
	RMOPB,0,	optab80,
	RMOP,0,		optab81,
	0,0,		nil,
	RMOP,0,		optab83,
	RMB,0,		"TESTB	%r,%e",
	RM,0,		"TEST%S	%r,%e",
	RMB,0,		"XCHGB	%r,%e",
	RM,0,		"XCHG%S	%r,%e",
	RMB,0,		"MOVB	%r,%e",
	RM,0,		"MOV%S	%r,%e",
	RMB,0,		"MOVB	%e,%r",
	RM,0,		"MOV%S	%e,%r",
	RM,0,		"MOVW	%g,%e",
	RM,0,		"LEA	%e,%r",
	RM,0,		"MOVW	%e,%g",
	RM,0,		"POP%S	%e",
	0,0,		"NOP",
	0,0,		"XCHG	%OCX,%OAX",
	0,0,		"XCHG	%ODX,%OAX",
	0,0,		"XCHG	%OBX,%OAX",
	0,0,		"XCHG	%OSP,%OAX",
	0,0,		"XCHG	%OBP,%OAX",
	0,0,		"XCHG	%OSI,%OAX",
	0,0,		"XCHG	%ODI,%OAX",
	0,0,		"%X",			/* miserable CBW or CWDE */
	0,0,		"%x",			/* idiotic CWD or CDQ */
	PTR,0,		"CALL%S	%d",
	0,0,		"WAIT",
	0,0,		"PUSH	FLAGS",
	0,0,		"POP	FLAGS",
	0,0,		"SAHF",
	0,0,		"LAHF",
	Awd,0,		"MOVB	%i,AL",
	Awd,0,		"MOV%S	%i,%OAX",
	Awd,0,		"MOVB	AL,%i",
	Awd,0,		"MOV%S	%OAX,%i",
	0,0,		"MOVSB	(%ASI),(%ADI)",
	0,0,		"MOVS%S	(%ASI),(%ADI)",
	0,0,		"CMPSB	(%ASI),(%ADI)",
	0,0,		"CMPS%S	(%ASI),(%ADI)",
	Ib,0,		"TESTB	%i,AL",
	Iwd,0,		"TEST%S	%i,%OAX",
	0,0,		"STOSB	AL,(%ADI)",
	0,0,		"STOS%S	%OAX,(%ADI)",
	0,0,		"LODSB	(%ASI),AL",
	0,0,		"LODS%S	(%ASI),%OAX",
	0,0,		"SCASB	(%ADI),AL",
	0,0,		"SCAS%S	(%ADI),%OAX",
	Ib,0,		"MOVB	%i,AL",
	Ib,0,		"MOVB	%i,CL",
	Ib,0,		"MOVB	%i,DL",
	Ib,0,		"MOVB	%i,BL",
	Ib,0,		"MOVB	%i,AH",
	Ib,0,		"MOVB	%i,CH",
	Ib,0,		"MOVB	%i,DH",
	Ib,0,		"MOVB	%i,BH",
	Iwd,0,		"MOV%S	%i,%OAX",
	Iwd,0,		"MOV%S	%i,%OCX",
	Iwd,0,		"MOV%S	%i,%ODX",
	Iwd,0,		"MOV%S	%i,%OBX",
	Iwd,0,		"MOV%S	%i,%OSP",
	Iwd,0,		"MOV%S	%i,%OBP",
	Iwd,0,		"MOV%S	%i,%OSI",
	Iwd,0,		"MOV%S	%i,%ODI",
	RMOPB,0,	optabC0,
	RMOP,0,		optabC1,
	Iw,0,		"RET	%i",
	RET,0,		"RET",
	RM,0,		"LES	%e,%r",
	RM,0,		"LDS	%e,%r",
	RMB,Ib,		"MOVB	%i,%e",
	RM,Iwd,		"MOV%S	%i,%e",
	Iw2,Ib,		"ENTER	%i,%I",		/* loony ENTER */
	RET,0,		"LEAVE",		/* bizarre LEAVE */
	Iw,0,		"RETF	%i",
	RET,0,		"RETF",
	0,0,		"INT	3",
	Ib,0,		"INTB	%i",
	0,0,		"INTO",
	0,0,		"IRET",
	RMOPB,0,	optabD0,
	RMOP,0,		optabD1,
	RMOPB,0,	optabD2,
	RMOP,0,		optabD3,
	OA,0,		"AAM",
	OA,0,		"AAD",
	0,0,		nil,
	0,0,		"XLAT",
	FRMOP,0,	optabD8,
	FRMEX,0,	optabD9,
	FRMOP,0,	optabDA,
	FRMEX,0,	optabDB,
	FRMOP,0,	optabDC,
	FRMOP,0,	optabDD,
	FRMOP,0,	optabDE,
	FRMOP,0,	optabDF,
	Jbs,0,		"LOOPNE	%p",
	Jbs,0,		"LOOPE	%p",
	Jbs,0,		"LOOP	%p",
	Jbs,0,		"JCXZ	%p",
	Ib,0,		"INB	%i,AL",
	Ib,0,		"IN%S	%i,%OAX",
	Ib,0,		"OUTB	AL,%i",
	Ib,0,		"OUT%S	%OAX,%i",
	Iwds,0,		"CALL	%p",
	Iwds,0,		"JMP	%p",
	PTR,0,		"JMP	%d",
	Jbs,0,		"JMP	%p",
	0,0,		"INB	DX,AL",
	0,0,		"IN%S	DX,%OAX",
	0,0,		"OUTB	AL,DX",
	0,0,		"OUT%S	%OAX,DX",
	PRE,0,		"LOCK",
	0,0,		nil,
	PRE,0,		"REPNE",
	PRE,0,		"REP",
	0,0,		"HALT",
	0,0,		"CMC",
	RMOPB,0,	optabF6,
	RMOP,0,		optabF7,
	0,0,		"CLC",
	0,0,		"STC",
	0,0,		"CLI",
	0,0,		"STI",
	0,0,		"CLD",
	0,0,		"STD",
	RMOPB,0,	optabFE,
	RMOP,0,		optabFF,
};

/*
 *  get a byte of the instruction
 */
static int
igetc(Instr *ip, uchar *c)
{
	if(ip->n+1 > sizeof(ip->mem)){
		kwerrstr("instruction too long");
		return -1;
	}
	*c = dasdata[ip->addr+ip->n];
	ip->mem[ip->n++] = *c;
	return 1;
}

/*
 *  get two bytes of the instruction
 */
static int
igets(Instr *ip, ushort *sp)
{
	uchar	c;
	ushort s;

	if (igetc(ip, &c) < 0)
		return -1;
	s = c;
	if (igetc(ip, &c) < 0)
		return -1;
	s |= (c<<8);
	*sp = s;
	return 1;
}

/*
 *  get 4 bytes of the instruction
 */
static int
igetl(Instr *ip, ulong *lp)
{
	ushort s;
	long	l;

	if (igets(ip, &s) < 0)
		return -1;
	l = s;
	if (igets(ip, &s) < 0)
		return -1;
	l |= (s<<16);
	*lp = l;
	return 1;
}

static int
getdisp(Instr *ip, int mod, int rm, int code)
{
	uchar c;
	ushort s;

	if (mod > 2)
		return 1;
	if (mod == 1) {
		if (igetc(ip, &c) < 0)
			return -1;
		if (c&0x80)
			ip->disp = c|0xffffff00;
		else
			ip->disp = c&0xff;
	} else if (mod == 2 || rm == code) {
		if (ip->asize == 'E') {
			if (igetl(ip, &ip->disp) < 0)
				return -1;
		} else {
			if (igets(ip, &s) < 0)
				return -1;
			if (s&0x8000)
				ip->disp = s|0xffff0000;
			else
				ip->disp = s;
		}
		if (mod == 0)
			ip->base = -1;
	}
	return 1;
}

static int
modrm(Instr *ip, uchar c)
{
	uchar rm, mod;

	mod = (c>>6)&3;
	rm = c&7;
	ip->mod = mod;
	ip->base = rm;
	ip->reg = (c>>3)&7;
	if (mod == 3)			/* register */
		return 1;
	if (ip->asize == 0) {		/* 16-bit mode */
		switch(rm)
		{
		case 0:
			ip->base = BX; ip->index = SI;
			break;
		case 1:
			ip->base = BX; ip->index = DI;
			break;
		case 2:
			ip->base = BP; ip->index = SI;
			break;
		case 3:
			ip->base = BP; ip->index = DI;
			break;
		case 4:
			ip->base = SI;
			break;
		case 5:
			ip->base = DI;
			break;
		case 6:
			ip->base = BP;
			break;
		case 7:
			ip->base = BX;
			break;
		default:
			break;
		}
		return getdisp(ip, mod, rm, 6);
	}
	if (rm == 4) {	/* scummy sib byte */
		if (igetc(ip, &c) < 0)
			return -1;
		ip->ss = (c>>6)&0x03;
		ip->index = (c>>3)&0x07;
		if (ip->index == 4)
			ip->index = -1;
		ip->base = c&0x07;
		return getdisp(ip, mod, ip->base, 5);
	}
	return getdisp(ip, mod, rm, 5);
}

static Optable *
mkinstr(Instr *ip, ulong pc)
{
	int i, n;
	uchar c;
	ushort s;
	Optable *op, *obase;
	char buf[128];

	memset(ip, 0, sizeof(*ip));
	ip->base = -1;
	ip->index = -1;
	ip->osize = 'L';
	ip->asize = 'E';
	ip->addr = pc;
	if (igetc(ip, &c) < 0)
		return 0;
	obase = optable;
newop:
	op = &obase[c];
	if (op->proto == 0) {
badop:
		n = snprint(buf, sizeof(buf), "opcode: ??");
		for (i = 0; i < ip->n && n < sizeof(buf)-3; i++, n+=2)
			_hexify(buf+n, ip->mem[i], 1);
		strcpy(buf+n, "??");
		kwerrstr(buf);
		return 0;
	}
	for(i = 0; i < 2 && op->operand[i]; i++) {
		switch(op->operand[i])
		{
		case Ib:	/* 8-bit immediate - (no sign extension)*/
			if (igetc(ip, &c) < 0)
				return 0;
			ip->imm = c&0xff;
			break;
		case Jbs:	/* 8-bit jump immediate (sign extended) */
			if (igetc(ip, &c) < 0)
				return 0;
			if (c&0x80)
				ip->imm = c|0xffffff00;
			else
				ip->imm = c&0xff;
			ip->jumptype = Jbs;
			break;
		case Ibs:	/* 8-bit immediate (sign extended) */
			if (igetc(ip, &c) < 0)
				return 0;
			if (c&0x80)
				if (ip->osize == 'L')
					ip->imm = c|0xffffff00;
				else
					ip->imm = c|0xff00;
			else
				ip->imm = c&0xff;
			break;
		case Iw:	/* 16-bit immediate -> imm */
			if (igets(ip, &s) < 0)
				return 0;
			ip->imm = s&0xffff;
			ip->jumptype = Iw;
			break;
		case Iw2:	/* 16-bit immediate -> in imm2*/
			if (igets(ip, &s) < 0)
				return 0;
			ip->imm2 = s&0xffff;
			break;
		case Iwd:	/* Operand-sized immediate (no sign extension)*/
			if (ip->osize == 'L') {
				if (igetl(ip, &ip->imm) < 0)
					return 0;
			} else {
				if (igets(ip, &s)< 0)
					return 0;
				ip->imm = s&0xffff;
			}
			break;
		case Awd:	/* Address-sized immediate (no sign extension)*/
			if (ip->asize == 'E') {
				if (igetl(ip, &ip->imm) < 0)
					return 0;
			} else {
				if (igets(ip, &s)< 0)
					return 0;
				ip->imm = s&0xffff;
			}
			break;
		case Iwds:	/* Operand-sized immediate (sign extended) */
			if (ip->osize == 'L') {
				if (igetl(ip, &ip->imm) < 0)
					return 0;
			} else {
				if (igets(ip, &s)< 0)
					return 0;
				if (s&0x8000)
					ip->imm = s|0xffff0000;
				else
					ip->imm = s&0xffff;
			}
			ip->jumptype = Iwds;
			break;
		case OA:	/* literal 0x0a byte */
			if (igetc(ip, &c) < 0)
				return 0;
			if (c != 0x0a)
				goto badop;
			break;
		case R0:	/* base register must be R0 */
			if (ip->base != 0)
				goto badop;
			break;
		case R1:	/* base register must be R1 */
			if (ip->base != 1)
				goto badop;
			break;
		case RMB:	/* R/M field with byte register (/r)*/
			if (igetc(ip, &c) < 0)
				return 0;
			if (modrm(ip, c) < 0)
				return 0;
			ip->osize = 'B';
			break;
		case RM:	/* R/M field with register (/r) */
			if (igetc(ip, &c) < 0)
				return 0;
			if (modrm(ip, c) < 0)
				return 0;
			break;
		case RMOPB:	/* R/M field with op code (/digit) */
			if (igetc(ip, &c) < 0)
				return 0;
			if (modrm(ip, c) < 0)
				return 0;
			c = ip->reg;		/* secondary op code */
			obase = (Optable*)op->proto;
			ip->osize = 'B';
			goto newop;
		case RMOP:	/* R/M field with op code (/digit) */
			if (igetc(ip, &c) < 0)
				return 0;
			if (modrm(ip, c) < 0)
				return 0;
			c = ip->reg;
			obase = (Optable*)op->proto;
			goto newop;
		case FRMOP:	/* FP R/M field with op code (/digit) */
			if (igetc(ip, &c) < 0)
				return 0;
			if (modrm(ip, c) < 0)
				return 0;
			if ((c&0xc0) == 0xc0)
				c = ip->reg+8;		/* 16 entry table */
			else
				c = ip->reg;
			obase = (Optable*)op->proto;
			goto newop;
		case FRMEX:	/* Extended FP R/M field with op code (/digit) */
			if (igetc(ip, &c) < 0)
				return 0;
			if (modrm(ip, c) < 0)
				return 0;
			if ((c&0xc0) == 0xc0)
				c = (c&0x3f)+8;		/* 64-entry table */
			else
				c = ip->reg;
			obase = (Optable*)op->proto;
			goto newop;
		case RMR:	/* R/M register only (mod = 11) */
			if (igetc(ip, &c) < 0)
				return 0;
			if ((c&0xc0) != 0xc0) {
				kwerrstr("invalid R/M register: %x", c);
				return 0;
			}
			if (modrm(ip, c) < 0)
				return 0;
			break;
		case RMM:	/* R/M register only (mod = 11) */
			if (igetc(ip, &c) < 0)
				return 0;
			if ((c&0xc0) == 0xc0) {
				kwerrstr("invalid R/M memory mode: %x", c);
				return 0;
			}
			if (modrm(ip, c) < 0)
				return 0;
			break;
		case PTR:	/* Seg:Displacement addr (ptr16:16 or ptr16:32) */
			if (ip->osize == 'L') {
				if (igetl(ip, &ip->disp) < 0)
					return 0;
			} else {
				if (igets(ip, &s)< 0)
					return 0;
				ip->disp = s&0xffff;
			}
			if (igets(ip, (ushort*)&ip->seg) < 0)
				return 0;
			ip->jumptype = PTR;
			break;
		case AUX:	/* Multi-byte op code - Auxiliary table */
			obase = (Optable*)op->proto;
			if (igetc(ip, &c) < 0)
				return 0;
			goto newop;
		case PRE:	/* Instr Prefix */
			ip->prefix = (char*)op->proto;
			if (igetc(ip, &c) < 0)
				return 0;
			goto newop;
		case SEG:	/* Segment Prefix */
			ip->segment = (char*)op->proto;
			if (igetc(ip, &c) < 0)
				return 0;
			goto newop;
		case OPOVER:	/* Operand size override */
			ip->osize = 'W';
			if (igetc(ip, &c) < 0)
				return 0;
			goto newop;
		case ADDOVER:	/* Address size override */
			ip->asize = 0;
			if (igetc(ip, &c) < 0)
				return 0;
			goto newop;
		case JUMP:	/* mark instruction as JUMP or RET */
		case RET:
			ip->jumptype = op->operand[i];
			break;
		default:
			kwerrstr("bad operand type %d", op->operand[i]);
			return 0;
		}
	}
	return op;
}

static void
bprint(Instr *ip, char *fmt, ...)
{
	va_list arg;

	va_start(arg, fmt);
	ip->curr = vseprint(ip->curr, ip->end, fmt, arg);
	va_end(arg);
}

/*
 *  if we want to call 16 bit regs AX,BX,CX,...
 *  and 32 bit regs EAX,EBX,ECX,... then
 *  change the defs of ANAME and ONAME to:
 *  #define	ANAME(ip)	((ip->asize == 'E' ? "E" : "")
 *  #define	ONAME(ip)	((ip)->osize == 'L' ? "E" : "")
 */
#define	ANAME(ip)	""
#define	ONAME(ip)	""

static char *reg[] =  {
	"AX",
	"CX",
	"DX",
	"BX",
	"SP",
	"BP",
	"SI",
	"DI",
};

static char *breg[] = { "AL", "CL", "DL", "BL", "AH", "CH", "DH", "BH" };
static char *sreg[] = { "ES", "CS", "SS", "DS", "FS", "GS" };

static void
plocal(Instr *ip)
{
	int offset;

	offset = ip->disp;

	bprint(ip, "%lux(SP)", offset);
}

static void
pea(Instr *ip)
{
	if (ip->mod == 3) {
		if (ip->osize == 'B')
			bprint(ip, breg[ip->base]);
		else
			bprint(ip, "%s%s", ANAME(ip), reg[ip->base]);
		return;
	}
	if (ip->segment)
		bprint(ip, ip->segment);
	if (ip->asize == 'E' && ip->base == SP)
		plocal(ip);
	else {
		bprint(ip,"%lux", ip->disp);
		if (ip->base >= 0)
			bprint(ip,"(%s%s)", ANAME(ip), reg[ip->base]);
	}
	if (ip->index >= 0)
		bprint(ip,"(%s%s*%d)", ANAME(ip), reg[ip->index], 1<<ip->ss);
}

static void
immediate(Instr *ip, long val)
{
	bprint(ip, "%lux", val);
}

static void
prinstr(Instr *ip, char *fmt)
{
	if (ip->prefix)
		bprint(ip, "%s ", ip->prefix);
	for (; *fmt && ip->curr < ip->end; fmt++) {
		if (*fmt != '%')
			*ip->curr++ = *fmt;
		else switch(*++fmt)
		{
		case '%':
			*ip->curr++ = '%';
			break;
		case 'A':
			bprint(ip, "%s", ANAME(ip));
			break;
		case 'C':
			bprint(ip, "CR%d", ip->reg);
			break;
		case 'D':
			if (ip->reg < 4 || ip->reg == 6 || ip->reg == 7)
				bprint(ip, "DR%d",ip->reg);
			else
				bprint(ip, "???");
			break;
		case 'I':
			bprint(ip, "$");
			immediate(ip, ip->imm2);
			break;
		case 'O':
			bprint(ip,"%s", ONAME(ip));
			break;
		case 'i':
			bprint(ip, "$");
			immediate(ip,ip->imm);
			break;
		case 'R':
			bprint(ip, "%s%s", ONAME(ip), reg[ip->reg]);
			break;
		case 'S':
			bprint(ip, "%c", ip->osize);
			break;
		case 'T':
			if (ip->reg == 6 || ip->reg == 7)
				bprint(ip, "TR%d",ip->reg);
			else
				bprint(ip, "???");
			break;
		case 'X':
			if (ip->osize == 'L')
				bprint(ip,"CWDE");
			else
				bprint(ip, "CBW");
			break;
		case 'd':
			bprint(ip,"%lux:%lux",ip->seg,ip->disp);
			break;
		case 'e':
			pea(ip);
			break;
		case 'f':
			bprint(ip, "F%d", ip->base);
			break;
		case 'g':
			if (ip->reg < 6)
				bprint(ip,"%s",sreg[ip->reg]);
			else
				bprint(ip,"???");
			break;
		case 'p':
			immediate(ip, ip->imm+ip->addr+ip->n);
			break;
		case 'r':
			if (ip->osize == 'B')
				bprint(ip,"%s",breg[ip->reg]);
			else
				bprint(ip, reg[ip->reg]);
			break;
		case 'x':
			if (ip->osize == 'L')
				bprint(ip,"CDQ");
			else
				bprint(ip, "CWD");
			break;
		default:
			bprint(ip, "%%%c", *fmt);
			break;
		}
	}
	*ip->curr = 0;		/* there's always room for 1 byte */
}

int
i386inst(ulong pc, char modifier, char *buf, int n)
{
	Instr	instr;
	Optable *op;

	USED(modifier);
	op = mkinstr(&instr, pc);
	if (op == 0) {
		kgerrstr(buf, n);
		return -1;
	}
	instr.curr = buf;
	instr.end = buf+n-1;
	prinstr(&instr, op->proto);
	return instr.n;
}

int
i386das(ulong pc, char *buf, int n)
{
	Instr	instr;
	int i;

	if (mkinstr(&instr, pc) == 0) {
		kgerrstr(buf, n);
		return -1;
	}
	for(i = 0; i < instr.n && n > 2; i++) {
		_hexify(buf, instr.mem[i], 1);
		buf += 2;
		n -= 2;
	}
	*buf = 0;
	return instr.n;
}

int
i386instlen(ulong pc)
{
	Instr i;

	if (mkinstr(&i, pc))
		return i.n;
	return -1;
}

void
das(uchar *x, int n)
{
	int l, pc;
	char buf[128];
/*
	int i;
	for(i = 0; i < n; i++)
		print("%.2ux", x[i]);
	print("\n");
*/

	dasdata = x;
	pc = 0;
	while(n > 0) {
		i386das(pc, buf, sizeof(buf));
		print("%.8lux %2x %-20s ", (ulong)(dasdata+pc), pc, buf);
		l = i386inst(pc, 'i', buf, sizeof(buf));
		print("\t%s\n", buf);

		pc += l;
		n -= l;
	}
}
