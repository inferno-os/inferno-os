/*
 * All the goo for PC ethernet cards.
 */
typedef struct Card Card;
typedef struct Type Type;
typedef struct Ctlr Ctlr;

/*
 * Hardware interface.
 */
struct Card {
	ISAConf;

	int	(*reset)(Ctlr*);
	void	(*attach)(Ctlr*);

	void	*(*read)(Ctlr*, void*, ulong, ulong);
	void	*(*write)(Ctlr*, ulong, void*, ulong);

	void	(*receive)(Ctlr*);
	void	(*transmit)(Ctlr*);
	void	(*intr)(Ureg*, void*);
	void	(*overflow)(Ctlr*);

	uchar	bit16;			/* true if a 16 bit interface */
	uchar	ram;			/* true if card has shared memory */

	ulong	dp8390;			/* I/O address of 8390 (if any) */
	ulong	data;			/* I/O data port if no shared memory */
	uchar	nxtpkt;			/* software bndry */
	uchar	tstart;			/* 8390 ring addresses */
	uchar	pstart;
	uchar	pstop;

	uchar	dummyrr;		/* do dummy remote read */
};

/*
 * Software controller.
 */
struct Ctlr {
	Card	card;			/* hardware info */
	int	ctlrno;
	int	present;

	Queue*	iq;
	Queue*	oq;

	int	inpackets;
	int	outpackets;
	int	crcs;			/* input crc errors */
	int	oerrs;			/* output errors */
	int	frames;			/* framing errors */
	int	overflows;		/* packet overflows */
	int	buffs;			/* buffering errors */
};

extern int sccethreset(Ctlr*);
extern int	etheriq(Ctlr*, Block*, int);
