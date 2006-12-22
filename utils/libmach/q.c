/*
 * PowerPC definition
 *	forsyth@terzarima.net
 */
#include <lib9.h>
#include <bio.h>
#include "uregq.h"
#include "mach.h"


#define	REGOFF(x)	(ulong) (&((struct Ureg *) 0)->x)

#define SP		REGOFF(sp)
#define PC		REGOFF(pc)
#define	R3		REGOFF(r3)	/* return reg */
#define	LR		REGOFF(lr)
#define R31		REGOFF(r31)
#define FP_REG(x)	(R31+4+8*(x))

#define	REGSIZE	sizeof(struct Ureg)
#define	FPREGSIZE	(8*33)

Reglist powerreglist[] = {
	{"CAUSE",	REGOFF(cause), RINT|RRDONLY, 'X'},
	{"SRR1",	REGOFF(status), RINT|RRDONLY, 'X'},
	{"PC",		REGOFF(pc), RINT, 'X'},
	{"LR",		REGOFF(lr), RINT, 'X'},
	{"CR",		REGOFF(cr), RINT, 'X'},
	{"XER",		REGOFF(xer), RINT, 'X'},
	{"CTR",		REGOFF(ctr), RINT, 'X'},
	{"PC",		PC, RINT, 'X'},
	{"SP",		SP, RINT, 'X'},
	{"R0",		REGOFF(r0), RINT, 'X'},
	/* R1 is SP */
	{"R2",		REGOFF(r2), RINT, 'X'},
	{"R3",		REGOFF(r3), RINT, 'X'},
	{"R4",		REGOFF(r4), RINT, 'X'},
	{"R5",		REGOFF(r5), RINT, 'X'},
	{"R6",		REGOFF(r6), RINT, 'X'},
	{"R7",		REGOFF(r7), RINT, 'X'},
	{"R8",		REGOFF(r8), RINT, 'X'},
	{"R9",		REGOFF(r9), RINT, 'X'},
	{"R10",		REGOFF(r10), RINT, 'X'},
	{"R11",		REGOFF(r11), RINT, 'X'},
	{"R12",		REGOFF(r12), RINT, 'X'},
	{"R13",		REGOFF(r13), RINT, 'X'},
	{"R14",		REGOFF(r14), RINT, 'X'},
	{"R15",		REGOFF(r15), RINT, 'X'},
	{"R16",		REGOFF(r16), RINT, 'X'},
	{"R17",		REGOFF(r17), RINT, 'X'},
	{"R18",		REGOFF(r18), RINT, 'X'},
	{"R19",		REGOFF(r19), RINT, 'X'},
	{"R20",		REGOFF(r20), RINT, 'X'},
	{"R21",		REGOFF(r21), RINT, 'X'},
	{"R22",		REGOFF(r22), RINT, 'X'},
	{"R23",		REGOFF(r23), RINT, 'X'},
	{"R24",		REGOFF(r24), RINT, 'X'},
	{"R25",		REGOFF(r25), RINT, 'X'},
	{"R26",		REGOFF(r26), RINT, 'X'},
	{"R27",		REGOFF(r27), RINT, 'X'},
	{"R28",		REGOFF(r28), RINT, 'X'},
	{"R29",		REGOFF(r29), RINT, 'X'},
	{"R30",		REGOFF(r30), RINT, 'X'},
	{"R31",		REGOFF(r31), RINT, 'X'},
	{"F0",		FP_REG(0), RFLT, 'D'},
	{"F1",		FP_REG(1), RFLT, 'D'},
	{"F2",		FP_REG(2), RFLT, 'D'},
	{"F3",		FP_REG(3), RFLT, 'D'},
	{"F4",		FP_REG(4), RFLT, 'D'},
	{"F5",		FP_REG(5), RFLT, 'D'},
	{"F6",		FP_REG(6), RFLT, 'D'},
	{"F7",		FP_REG(7), RFLT, 'D'},
	{"F8",		FP_REG(8), RFLT, 'D'},
	{"F9",		FP_REG(9), RFLT, 'D'},
	{"F10",		FP_REG(10), RFLT, 'D'},
	{"F11",		FP_REG(11), RFLT, 'D'},
	{"F12",		FP_REG(12), RFLT, 'D'},
	{"F13",		FP_REG(13), RFLT, 'D'},
	{"F14",		FP_REG(14), RFLT, 'D'},
	{"F15",		FP_REG(15), RFLT, 'D'},
	{"F16",		FP_REG(16), RFLT, 'D'},
	{"F17",		FP_REG(17), RFLT, 'D'},
	{"F18",		FP_REG(18), RFLT, 'D'},
	{"F19",		FP_REG(19), RFLT, 'D'},
	{"F20",		FP_REG(20), RFLT, 'D'},
	{"F21",		FP_REG(21), RFLT, 'D'},
	{"F22",		FP_REG(22), RFLT, 'D'},
	{"F23",		FP_REG(23), RFLT, 'D'},
	{"F24",		FP_REG(24), RFLT, 'D'},
	{"F25",		FP_REG(25), RFLT, 'D'},
	{"F26",		FP_REG(26), RFLT, 'D'},
	{"F27",		FP_REG(27), RFLT, 'D'},
	{"F28",		FP_REG(28), RFLT, 'D'},
	{"F29",		FP_REG(29), RFLT, 'D'},
	{"F30",		FP_REG(30), RFLT, 'D'},
	{"F31",		FP_REG(31), RFLT, 'D'},
	{"FPSCR",	FP_REG(32)+4, RFLT, 'X'},
	{  0 }
};

	/* the machine description */
Mach mpower =
{
	"power",
	MPOWER,		/* machine type */
	powerreglist,	/* register set */
	REGSIZE,	/* register set size in bytes */
	FPREGSIZE,	/* floating point register size in bytes */
	"PC",		/* name of PC */
	"SP",		/* name of SP */
	"LR",		/* name of link register */
	"setSB",	/* static base register name */
	0,		/* value */
	0x1000,		/* page size */
	0x20000000,	/* kernel base */
	0,		/* kernel text mask */
	4,		/* quantization of pc */
	4,		/* szaddr */
	4,		/* szreg */
	4,		/* szfloat */
	8,		/* szdouble */
};
