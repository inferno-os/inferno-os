struct Ureg
{
	uvlong	r15;	/* general registers */
	uvlong	r14;
	uvlong	r13;
	uvlong	r12;
	uvlong	r11;
	uvlong	r10;
	uvlong	r9;
	uvlong	r8;
	uvlong	di;
	uvlong	si;		/* ... */
	uvlong	bp;		/* ... */
	uvlong	nsp;
	uvlong	bx;		/* ... */
	uvlong	dx;		/* ... */
	uvlong	cx;		/* ... */
	uvlong	ax;		/* ... */
	uvlong	gs;		/* data segments */
	uvlong	fs;		/* ... */
	uvlong	es;		/* ... */
	uvlong	ds;		/* ... */
	uvlong	trap;		/* trap type */
	uvlong	ecode;		/* error code (or zero) */
	uvlong	pc;		/* pc */
	uvlong	cs;		/* old context */
	uvlong	flags;		/* old flags */
	uvlong	sp;
	uvlong	ss;		/* old stack segment */
};
