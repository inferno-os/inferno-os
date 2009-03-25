;	
;	/*
;	 * To get lock routine, compile this into a .s, then SUBSTITUTE
;	 * a LOAD AND CLEAR WORD instruction for the load and store of
;	 * l->key.
;	 *
;	 */
;	typedef struct Lock {
;		int	key;
;		int	pid;
;	} Lock;
;	
;	int
;	mutexlock(Lock *l)
;	{
;		int key;
;	
;		key = l->key;
;		l->key = 0;
;		return key != 0;
;	}

	.LEVEL	1.1

	.SPACE	$TEXT$,SORT=8
	.SUBSPA	$CODE$,QUAD=0,ALIGN=8,ACCESS=0x2c,CODE_ONLY,SORT=24
mutexlock
	.PROC
	.CALLINFO FRAME=0,ARGS_SAVED
	.ENTRY
; SUBSTITUTED	LDW	0(%r26),%r31
; SUBSTITUTED	STWS	%r0,0(%r26)
	LDCWS	0(%r26),%r31	; SUBSTITUTED
	COMICLR,=	0,%r31,%r28
	LDI	1,%r28
	.EXIT
	BV,N	%r0(%r2)
	.PROCEND

;
;	JIT help
;
	.SPACE	$TEXT$,SORT=8
	.SUBSPA	$CODE$,QUAD=0,ALIGN=8,ACCESS=0x2c,CODE_ONLY,SORT=24
calldata
	.PROC
	.CALLINFO CALLER,FRAME=16,SAVE_RP
        .ENTRY
        STW     %r2,-20(%r30)
        LDO     64(%r30),%r30
        ADDIL   LR'dataptr-$global$,%r27
        LDW     RR'dataptr-$global$(%r1),%r31
        BLE     0(%sr5,%r31)
        COPY    %r31,%r2
        LDW     -84(%r30),%r2
        BV      %r0(%r2)
        .EXIT
        LDO     -64(%r30),%r30
	.PROCEND

	.SPACE	$PRIVATE$
	.SUBSPA	$SHORTBSS$
dataptr	.COMM	4
	.SUBSPA	$SHORTDATA$,QUAD=1,ALIGN=8,ACCESS=0x1f,SORT=24
dyncall
	.WORD  $$dyncall
	.EXPORT	calldata
	.EXPORT	dyncall
	.IMPORT	$$dyncall,MILLICODE

	.SPACE	$TEXT$
	.SUBSPA	$CODE$
	.SPACE	$PRIVATE$,SORT=16
	.SUBSPA	$DATA$,QUAD=1,ALIGN=8,ACCESS=0x1f,SORT=16
	.SPACE	$TEXT$
	.SUBSPA	$CODE$
	.EXPORT	mutexlock,ENTRY,PRIV_LEV=3,ARGW0=GR,RTNVAL=GR

	.code
;	segflush(addr,len)
	.proc
	.callinfo
	.export segflush,entry
segflush
	.enter
	ldsid	(0,%arg0),%r1
	mtsp	%r1,%sr0
	ldo	-1(%arg1),%arg1
	copy	%arg0,%arg2	
	copy	%arg1,%arg3	
	fdc	%arg1(0,%arg0)

loop1
	addib,>,n -16,%arg1,loop1
	fdc	%arg1(0,%arg0)
	fdc	0(0,%arg0)
	sync
	fic	%arg3(%sr0,%arg2)
loop2
	addib,>,n -16,%arg3,loop2
	fic	%arg3(%sr0,%arg2)
	fic	0(%sr0,%arg2)
	sync
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	.leave
	.procend
	.end
