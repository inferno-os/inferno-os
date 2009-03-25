	.file	"asm-Linux-arm.S"
#include "syscall.h"
	.text

/*
 * void executeonnewstack(void *tos, void (*tramp)(void *arg), void *arg)
 */

        .align  2
        .global executeonnewstack
        .type   executeonnewstack, %function
executeonnewstack:
        @ args = 0, pretend = 0, frame = 12
        @ frame_needed = 1, uses_anonymous_args = 0
        mov     ip, sp
        stmfd   sp!, {fp, ip, lr, pc}
        sub     fp, ip, #4
        sub     sp, sp, #12
        str     r0, [fp, #-16] /* store tos */
        str     r1, [fp, #-20] /* store tramp */
        str     r2, [fp, #-24] /* store arg */
        ldr     r0, [fp, #-24] /* get arg */
        ldr     r2, [fp, #-16] /* get tos */
        mov     sp, r2         /* set new stack */
        mov     lr, pc
        blx     r1             /* call tramp*/

        /* if we return here, tramp didn't do it's job */
        swi     SYS_exit
        ldmea   fp, {fp, sp, pc}
        .size   executeonnewstack, .-executeonnewstack

/*
 * void unlockandexit(int *key)
 *
 * NB: the return status may be garbaged if the stack is reused
 *	between the unlock and the system call, but this should
 *	not matter since no task is waiting for the result
 */

        .align  2
        .global unlockandexit
        .type   unlockandexit, %function
unlockandexit:
        @ args = 0, pretend = 0, frame = 4
        @ frame_needed = 1, uses_anonymous_args = 0
        mov     ip, sp
        stmfd   sp!, {fp, ip, lr, pc}
        sub     fp, ip, #4
        sub     sp, sp, #4
        mov     r1, #0
        str     r1, [r0]
        swi     SYS_exit
        ldmea   fp, {fp, sp, pc}
        .size   unlockandexit, .-unlockandexit

/*
 * ulong umult(ulong m1, ulong m2, ulong *hi)
 */

        .align  2
        .global umult
        .type   umult, %function
umult:
        @ args = 0, pretend = 0, frame = 12
        @ frame_needed = 1, uses_anonymous_args = 0
        mov     ip, sp
        stmfd   sp!, {fp, ip, lr, pc}
        sub     fp, ip, #4
        sub     sp, sp, #12
        str     r0, [fp, #-16]
        str     r1, [fp, #-20]
        str     r2, [fp, #-24]
        ldr     r1, [fp, #-16]
        ldr     r2, [fp, #-20]
        umull   r0, r3, r1, r2
        ldr     r1, [fp, #-24]
        str     r3, [r1]
        ldmea   fp, {fp, sp, pc}
        .size   umult, .-umult

/*
 *  void		FPsave(void*);
 */

        .align  2
        .global FPsave
        .type   FPsave, %function
FPsave:
        @ args = 0, pretend = 0, frame = 4
        @ frame_needed = 1, uses_anonymous_args = 0
        mov     ip, sp
        stmfd   sp!, {fp, ip, lr, pc}
        sub     fp, ip, #4
        sub     sp, sp, #4
        str     r0, [fp, #-16]
        ldmea   fp, {fp, sp, pc}
        .size   FPsave, .-FPsave

/*
 * void		FPrestore(void*);
 */
        .align  2
        .global FPrestore
        .type   FPrestore, %function
FPrestore:
        @ args = 0, pretend = 0, frame = 4
        @ frame_needed = 1, uses_anonymous_args = 0
        mov     ip, sp
        stmfd   sp!, {fp, ip, lr, pc}
        sub     fp, ip, #4
        sub     sp, sp, #4
        str     r0, [fp, #-16]
        ldmea   fp, {fp, sp, pc}
        .size   FPrestore, .-FPrestore

/*
 * ulong _tas(ulong*);
 */
	.align	2
	.global	_tas
	.type	_tas, %function
_tas:
	@ args = 0, pretend = 0, frame = 0
	@ frame_needed = 0, uses_anonymous_args = 0
	@ link register save eliminated.
	@ lr needed for prologue
	mov	r3, #1
	mov	r1, r0
	swp	r0, r3, [r1]
	mov	pc, lr
	.size	_tas, .-_tas
