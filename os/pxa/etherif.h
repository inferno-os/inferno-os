enum {
	MaxEther	= 3,
	Ntypes		= 8,
};

typedef struct Ether Ether;
struct Ether {
RWlock;	/* TO DO */
	ISAConf;			/* hardware info */
	int	ctlrno;
	int	minmtu;
	int	maxmtu;
	uchar	ea[Eaddrlen];
	int	encry;

	void	(*attach)(Ether*);	/* filled in by reset routine */
	void	(*closed)(Ether*);
	void	(*detach)(Ether*);
	void	(*transmit)(Ether*);
	void	(*interrupt)(Ureg*, void*);
	long	(*ifstat)(Ether*, void*, long, ulong);
	long	(*ctl)(Ether*, void*, long); /* custom ctl messages */
	void	(*power)(Ether*, int);	/* power on/off */
	void	(*shutdown)(Ether*);	/* shutdown hardware before reboot */
	void	*ctlr;
	int	pcmslot;		/* PCMCIA */
	int	fullduplex;	/* non-zero if full duplex */

	Queue*	oq;

	Netif;
};

extern Block* etheriq(Ether*, Block*, int);
extern void addethercard(char*, int(*)(Ether*));
extern int archether(int, Ether*);

#define NEXT(x, l)	(((x)+1)%(l))
#define PREV(x, l)	(((x) == 0) ? (l)-1: (x)-1)
#define	HOWMANY(x, y)	(((x)+((y)-1))/(y))
#define ROUNDUP(x, y)	(HOWMANY((x), (y))*(y))
