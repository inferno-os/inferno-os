/*
 * Solaris 2.5/sparc
 */

/*
 * This structure must agree with FPsave and FPrestore asm routines
 */
typedef struct FPU FPU;
struct FPU
{
        ulong   fsr;
};

extern Proc *getup();
#define up (getup())

#define BIGEND
