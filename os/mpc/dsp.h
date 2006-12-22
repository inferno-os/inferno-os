/*
 * MPC82x/QUICC DSP support
 */

typedef struct DSP DSP;
typedef struct FnD FnD;

typedef short Real;
typedef struct Complex Complex;

struct Complex {
	Real	im;
	Real	re;
};

struct FnD {
	ushort	status;
	ushort	param[7];
};

enum {
	FnDsize =	8*2,	/* each function descriptor is 8 shorts */

	/* standard bits in FnD.status */
	FnStop = 	1<<15,
	FnWrap =	1<<13,
	FnInt =	1<<12,

	/* optional bits */
	FnZ =	1<<11,	/* FIR[35], MOD */
	FnIALL =	1<<10,	/* FIRx */
	FnXinc0 =	0<<8,	/* FIRx, IRR */
	FnXinc1 =	1<<8,
	FnXinc2 =	2<<8,
	FnXinc3 =	3<<8,
	FnPC =	1<<7,	/* FIRx */


	/* DSP functions (table 16-6) */
	FnFIR1 =	0x01,
	FnFIR2 =	0x02,
	FnFIR3 =	0x03,
	FnFIR5 = 	0x03,
	FnFIR6 =	0x06,
	FnIIR =	0x07,
	FnMOD =	0x08,
	FnDEMOD = 0x09,
	FnLMS1 =	0x0A,
	FnLMS2 =	0x0B,
	FnWADD = 0x0C,
};

void	dspinitialise(void);
DSP*	dspacquire(void (*)(void*), void*);
void	dspexec(DSP*, FnD*, ulong);
void*	dspmalloc(ulong);
void	dspfree(void*, ulong);
void	dspsetfn(DSP*, FnD*, ulong);
void	dspstart(DSP*);
void	dsprelease(DSP*);
FnD*	fndalloc(ulong);
void	fndfree(FnD*, ulong);
