/*
 * All the goo for PC ethernet cards.
 */
typedef struct Card Card;
typedef struct RingBuf RingBuf;
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
	void	(*intr)(Ureg*, Ctlr*);
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
 * Software ring buffer.
 */
struct RingBuf {
	uchar	owner;
	uchar	busy;			/* unused */
	ushort	len;
	uchar	pkt[sizeof(Etherpkt)];
};

enum {
	Host		= 0,		/* buffer owned by host */
	Interface	= 1,		/* buffer owned by card */

	Nrb		= 16,		/* default number of receive buffers */
	Ntb		= 2,		/* default number of transmit buffers */
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

#define NEXT(x, l)	(((x)+1)%(l))
#define	HOWMANY(x, y)	(((x)+((y)-1))/(y))
#define ROUNDUP(x, y)	(HOWMANY((x), (y))*(y))

extern int cs8900reset(Ctlr*);
extern int	etheriq(Ctlr*, Block*, int);
