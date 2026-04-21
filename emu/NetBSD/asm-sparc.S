        .section        ".text", #alloc, #execinstr
        .align          8
        .skip           16
        .global FPsave
        .type   FPsave, #function
FPsave:
	retl
	st	%fsr,[%o0]
        .size   FPsave,(.-FPsave)


        .section        ".text", #alloc, #execinstr
        .align          8
        .skip           16
        .global FPrestore
        .type   FPrestore, #function
FPrestore:
	retl
	ld	[%o0],%fsr
        .size   FPrestore,(.-FPrestore)


	.section	".text", #alloc, #execinstr
	.align		8
	.skip		16
	.global getcallerpc
	.type getcallerpc, #function
getcallerpc:                  ! ignore argument
	retl
	add %i7,0,%o0
	.size   getcallerpc,(.-getcallerpc)


	.section	".text", #alloc, #execinstr
	.align	8
	.skip	16
	.global	_tas
	.type	_tas, #function
_tas:
	or	%g0,1,%o1
	swap	[%o0],%o1
	retl
	or	%g0,%o1,%o0
	.size	_tas,(.-_tas)
