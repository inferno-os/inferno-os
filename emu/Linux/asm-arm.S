	.file	"asm-Linux-arm.S"
	.text

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
