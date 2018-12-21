.set r0,0; .set SP,1; .set RTOC,2; .set r3,3; .set r4,4
.set r5,5; .set r6,6; .set r7,7; .set r8,8; .set r9,9
.set r10,10; .set r11,11; .set r12,12; .set r13,13; .set r14,14
.set r15,15; .set r16,16; .set r17,17; .set r18,18; .set r19,19
.set r20,20; .set r21,21; .set r22,22; .set r23,23; .set r24,24
.set r25,25; .set r26,26; .set r27,27; .set r28,28; .set r29,29
.set r30,30; .set r31,31
.set fp0,0; .set fp1,1; .set fp2,2; .set fp3,3; .set fp4,4
.set fp5,5; .set fp6,6; .set fp7,7; .set fp8,8; .set fp9,9
.set fp10,10; .set fp11,11; .set fp12,12; .set fp13,13; .set fp14,14
.set fp15,15; .set fp16,16; .set fp17,17; .set fp18,18; .set fp19,19
.set fp20,20; .set fp21,21; .set fp22,22; .set fp23,23; .set fp24,24
.set fp25,25; .set fp26,26; .set fp27,27; .set fp28,28; .set fp29,29
.set fp30,30; .set fp31,31
.set v0,0; .set v1,1; .set v2,2; .set v3,3; .set v4,4
.set v5,5; .set v6,6; .set v7,7; .set v8,8; .set v9,9
.set v10,10; .set v11,11; .set v12,12; .set v13,13; .set v14,14
.set v15,15; .set v16,16; .set v17,17; .set v18,18; .set v19,19
.set v20,20; .set v21,21; .set v22,22; .set v23,23; .set v24,24
.set v25,25; .set v26,26; .set v27,27; .set v28,28; .set v29,29
.set v30,30; .set v31,31
.set LR,8; .set CTR,9; .set TID,17; .set DSISR,18; .set DAR,19; .set TO_RTCU,20

.machine "ppc"

	.align	2
	.globl	.FPsave
.FPsave:
	stfd	fp14,0*8(r3)
	stfd	fp15,1*8(r3)
	stfd	fp16,2*8(r3)
	stfd	fp17,3*8(r3)
	stfd	fp18,4*8(r3)
	stfd	fp19,5*8(r3)
	stfd	fp20,6*8(r3)
	stfd	fp21,7*8(r3)
	stfd	fp22,8*8(r3)
	stfd	fp23,9*8(r3)
	stfd	fp24,10*8(r3)
	stfd	fp25,11*8(r3)
	stfd	fp26,12*8(r3)
	stfd	fp27,13*8(r3)
	stfd	fp28,14*8(r3)
	stfd	fp29,15*8(r3)
	stfd	fp30,16*8(r3)
	stfd	fp31,17*8(r3)
	blr

	.align	2
	.globl	.FPrestore
.FPrestore:
	lfd		fp14,0*8(r3)
	lfd		fp15,1*8(r3)
	lfd		fp16,2*8(r3)
	lfd		fp17,3*8(r3)
	lfd		fp18,4*8(r3)
	lfd		fp19,5*8(r3)
	lfd		fp20,6*8(r3)
	lfd		fp21,7*8(r3)
	lfd		fp22,8*8(r3)
	lfd		fp23,9*8(r3)
	lfd		fp24,10*8(r3)
	lfd		fp25,11*8(r3)
	lfd		fp26,12*8(r3)
	lfd		fp27,13*8(r3)
	lfd		fp28,14*8(r3)
	lfd		fp29,15*8(r3)
	lfd		fp30,16*8(r3)
	lfd		fp31,17*8(r3)
	blr

	.align	2
	.globl	._tas
._tas:
	sync
	mr		r4, r3
	addi		r5,0,0x1	
_tas_1:
	lwarx	r3, 0, r4
	cmpwi	r3, 0
	bne-	_tas_2
	stwcx.	r5, 0, r4
	bne-	_tas_1
_tas_2:
	sync
	blr

	.align	2
	.globl	.executeonnewstack
.executeonnewstack:
	mr		SP,r3	# change stacks
	stwu 	LR,-16(SP)	# save lr to aid the traceback
	li		r0,0
	stw 	r0,20(SP)
	mr		r3,r5
	mtctr 	r4
	bctrl	# tramp(arg)
	br

	.align	2
	.globl	.unlockandexit
.unlockandexit:
	li	r0,0x0
	stw	r0,0(r3)	# unlock
	li	r0,1		# sys exit; 234 is exit group
	li	r3,0		# exit status
	sc
	br
