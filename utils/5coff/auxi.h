#define	COFFCVT
#define	Sym	Symx
#include "../5l/l.h"
#undef Sym
#include	<mach.h>

/*
 * auxi.c
 */
extern	Symx *hash[NHASH];
Symx	*lookupsym(char*, int);
void	beginsym(void);
void	endsym(void);
void	newsym(int, char*, long, int);

extern	long	autosize;
extern	Prog *firstp, *textp, *curtext, *lastp, *etextp;

/*
 * coff.c
 */
void	coffhdr(void);
void	coffsym(void);
void	cofflc(void);
void	endsym(void);

/*
 * 5coff.c
 */
void	cflush(void);
void	lput(long);
void	cput(int);
void	hputl(int);
void	lputl(long);
long	entryvalue(void);
void	diag(char*, ...);
extern	long	HEADR;			/* length of header */
extern	long	INITDAT;		/* data location */
extern	long	INITRND;		/* data round above text location */
extern	long	INITTEXT;		/* text location */
extern	long	INITENTRY;		/* entry point */
extern	long	textsize;
extern	long	datsize;
extern	long	bsssize;
extern	int	cout;
extern	int	thumb;
