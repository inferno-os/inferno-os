/*
 * basic Flash Translation Layer driver
 *	see for instance the Intel technical paper
 *	``Understanding the Flash Translation Layer (FTL) Specification''
 *	Order number 297816-001 (online at www.intel.com)
 *
 * a public driver by David Hinds, dhinds@allegro.stanford.edu
 * further helps with some details.
 *
 * this driver uses the common simplification of never storing
 * the VBM on the medium (a waste of precious flash!) but
 * rather building it on the fly as the block maps are read.
 *
 * Plan 9 driver (c) 1997 by C H Forsyth (forsyth@terzarima.net)
 *	This driver may be used or adapted by anyone for any non-commercial purpose.
 *
 * adapted for Inferno 1998 by C H Forsyth, Vita Nuova Limited, York, England (forsyth@vitanuova.com)
 *
 * TO DO:
 *	check error handling details for get/put flash
 *	bad block handling
 *	reserved space in formatted size
 *	possibly block size as parameter
 */

#include "u.h"
#include "../port/lib.h"
#include "../port/error.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"

#include "kernel.h"

#ifndef offsetof
#define	offsetof(s, m)	(ulong)(&(((s*)0)->m))
#endif

typedef struct Ftl Ftl;
typedef struct Merase Merase;
typedef struct Terase Terase;

enum {
	Eshift = 18,	/* 2^18=256k; log2(eraseunit) */
	Flashseg = 1<<Eshift,
	Bshift = 9,		/* 2^9=512 */
	Bsize = 1<<Bshift,
	BAMoffset = 0x100,
	Nolimit = ~0,
	USABLEPCT = 95,	/* release only this % to client */

	FTLDEBUG = 0,

	NPART = 4,
};

/* erase unit header (defined by FTL specification) */
struct Merase {
	uchar	linktuple[5];
	uchar	orgtuple[10];
	uchar	nxfer;
	uchar	nerase[4];
	uchar	id[2];
	uchar	bshift;
	uchar	eshift;
	uchar	pstart[2];
	uchar	nunits[2];
	uchar	psize[4];
	uchar	vbmbase[4];
	uchar	nvbm[2];
	uchar	flags;
	uchar	code;
	uchar	serial[4];
	uchar	altoffset[4];
	uchar	bamoffset[4];
	uchar	rsv2[12];
};
#define	ERASEHDRLEN	64

enum {
	/* special unit IDs */
	XferID = 0xffff,
	XferBusy = 0x7fff,

	/* special BAM addresses */
	Bfree = 0xffffffff,
	Bwriting = 0xfffffffe,
	Bdeleted = 0,

	/* block types */
	TypeShift = 7,
	BlockType = (1<<TypeShift)-1,
	ControlBlock = 0x30,
	DataBlock = 0x40,
	ReplacePage = 0x60,
	BadBlock = 0x70,
};

#define	BTYPE(b)	((b) & BlockType)
#define	BADDR(b)	((b) & ~BlockType)
#define	BNO(va)	(((ulong)(va))>>Bshift)
#define	MKBAM(b,t)	(((b)<<Bshift)|(t))

struct Terase {
	int	x;
	int	id;
	ulong	offset;
	ulong	bamoffset;
	ulong	nbam;
	ulong*	bam;
	ulong	bamx;
	ulong	nfree;
	ulong	nused;
	ulong	ndead;
	ulong	nbad;
	ulong	nerase;
};

struct Ftl {
	QLock;
	Ref;

	Chan*	flash;
	Chan*	flashctl;
	ulong	base;	/* base of flash region */
	ulong	size;	/* size of flash region */
	ulong	segsize;	/* size of flash segment (erase unit) */
	int	eshift;	/* log2(erase-unit-size) */
	int	bshift;	/* log2(bsize) */
	int	bsize;
	int	nunit;	/* number of segments (erase units) */
	Terase**	unit;
	int	lastx;	/* index in unit of last allocation */
	int	xfer;		/* index in unit of current transfer unit (-1 if none) */
	ulong	nfree;	/* total free space in blocks */
	ulong	nblock;	/* total space in blocks */
	ulong	rwlimit;	/* user-visible block limit (`formatted size') */
	ulong*	vbm;		/* virtual block map */
	ulong	fstart;	/* address of first block of data in a segment */
	int	trace;	/* (debugging) trace of read/write actions */
	int	detach;	/* free Ftl on last close */

	/* scavenging variables */
	QLock	wantq;
	Rendez	wantr;
	Rendez	workr;
	int	needspace;
	int	hasproc;
	int	npart;		/* over and above ftldata */
	struct {
		ulong start, size;
		ulong rwlimit;
		char *name;	/* nil if slot unused */
	} part[NPART];
};

enum {
	/* Ftl.detach */
	Detached = 1,	/* detach on close */
	Deferred	/* scavenger must free it */
};

/* little endian */
#define	GET2(p)	(((p)[1]<<8)|(p)[0])
#define	GET4(p)	(((((((p)[3]<<8)|(p)[2])<<8)|(p)[1])<<8)|(p)[0])
#define	PUT2(p,v)	(((p)[1]=(v)>>8),((p)[0]=(v)))
#define	PUT4(p,v)	(((p)[3]=(v)>>24),((p)[2]=(v)>>16),((p)[1]=(v)>>8),((p)[0]=(v)))

static	Lock	ftllock;
static	Ftl	*ftls;
static	int	ftlpct = USABLEPCT;

static	ulong	allocblk(Ftl*);
static	int	erasedetect(Ftl *ftl, ulong base, ulong size, ushort *pstart, ushort *nunits);
static	void	eraseflash(Ftl*, ulong);
static	void	erasefree(Terase*);
static	void	eraseinit(Ftl*, ulong, int, int);
static	Terase*	eraseload(Ftl*, int, ulong);
static	void	ftlfree(Ftl*);
static	void	getflash(Ftl*, void*, ulong, long);
static	int	mapblk(Ftl*, ulong, Terase**, ulong*);
static	Ftl*	mkftl(char*, ulong, ulong, int, char*);
static	void	putbam(Ftl*, Terase*, int, ulong);
static	void	putflash(Ftl*, ulong, void*, long);
static	int	scavenge(Ftl*);

enum {
	Qdir,
	Qctl,
	Qdata,
};

#define DATAQID(q) ((q) >= Qdata && (q) <= Qdata + NPART)

static void
ftlpartcmd(Ftl *ftl, char **fields, int nfields)
{
	ulong start, end;
	char *p;
	int n, newn;

	/* name start [end] */
	if(nfields < 2 || nfields > 3)
		error(Ebadarg);
	if(ftl->npart >= NPART)
		error("table full");
	if(strcmp(fields[0], "ctl") == 0 || strcmp(fields[0], "data") == 0)
		error(Ebadarg);
	newn = -1;
	for(n = 0; n < NPART; n++){
		if(ftl->part[n].name == nil){
			if(newn < 0)
				newn = n;
			continue;
		}
		if(strcmp(fields[0], ftl->part[n].name + 3) == 0)
			error(Ebadarg);
	}
	start = strtoul(fields[1], 0, 0);
	if(nfields > 2)
		end = strtoul(fields[2], 0, 0);
	else
		end = ftl->rwlimit * Bsize;
	if(start >= end || start % Bsize || end % Bsize)
		error(Ebadarg);
	ftl->part[newn].start = start;
	ftl->part[newn].size = end - start;
	ftl->part[newn].rwlimit = end / Bsize;
	free(ftl->part[newn].name);
	p = malloc(strlen(fields[0]) + 3 + 1);
	strcpy(p, "ftl");
	strcat(p, fields[0]);
	ftl->part[newn].name = p;
	ftl->npart++;
}
		
static void
ftldelpartcmd(Ftl *ftl, char **fields, int nfields)
{
	int n;
	// name
	if(nfields != 1)
		error(Ebadarg);
	for(n = 0; n < NPART; n++)
		if(strcmp(fields[0], ftl->part[n].name + 3) == 0){
			free(ftl->part[n].name);
			ftl->part[n].name = nil;
			ftl->npart--;
			return;
		}
	error(Ebadarg);
}

static int
ftlgen(Chan *c, char*, Dirtab*, int, int i, Dir *dp)
{
	int n;
	switch(i){
	case DEVDOTDOT:
		devdir(c, (Qid){Qdir, 0, QTDIR}, "#X", 0, eve, 0555, dp);
		break;
	case 0:
		devdir(c, (Qid){Qctl, 0, QTFILE}, "ftlctl", 0, eve, 0660, dp);
		break;
	case 1:
		devdir(c, (Qid){Qdata, 0, QTFILE}, "ftldata", ftls ? ftls->rwlimit * Bsize : 0, eve, 0660, dp);
		break;
	default:
		if(ftls == nil)
			return -1;
		i -= 2;
		if(i >= ftls->npart)
			return -1;
		for(n = 0; n < NPART; n++)
			if(ftls->part[n].name != nil){
				if(i == 0)
					break;
				i--;
			}
		if(i != 0){
			print("wierd\n");
			return -1;
		}
		devdir(c, (Qid){Qdata + 1 + n, 0, QTFILE}, ftls->part[n].name, ftls->part[n].size, eve, 0660, dp);
	}
	return 1;
}

static Ftl *
ftlget(void)
{
	Ftl *ftl;

	lock(&ftllock);
	ftl = ftls;
	if(ftl != nil)
		incref(ftl);
	unlock(&ftllock);
	return ftl;
}

static void
ftlput(Ftl *ftl)
{
	if(ftl != nil){
		lock(&ftllock);
		if(decref(ftl) == 0 && ftl->detach == Detached){
			ftls = nil;
			if(ftl->hasproc){	/* no lock needed: can't change if ftl->ref==0 */
				ftl->detach = Deferred;
				wakeup(&ftl->workr);
			}else
				ftlfree(ftl);
		}
		unlock(&ftllock);
	}
}

static Chan *
ftlattach(char *spec)
{
	return devattach('X', spec);
}

static Walkqid*
ftlwalk(Chan *c, Chan *nc, char **name, int nname)
{
	Walkqid *wq;

	wq = devwalk(c, nc, name, nname, 0, 0, ftlgen);
	if(wq != nil && wq->clone != nil && wq->clone != c)
		if(DATAQID(wq->clone->qid.path))
			wq->clone->aux = ftlget();
	return wq;
}

static int
ftlstat(Chan *c, uchar *dp, int n)
{
	return devstat(c, dp, n, 0, 0, ftlgen);
}

static Chan*
ftlopen(Chan *c, int omode)
{
	Ftl *ftl;
	omode = openmode(omode);
	if(DATAQID(c->qid.path)){
		ftl = ftls;
		if(ftl == nil)
			error(Enodev);
		if(strcmp(up->env->user, eve)!=0)
			error(Eperm);
	}
	else if(c->qid.path == Qctl){
		if(strcmp(up->env->user, eve)!=0)
			error(Eperm);
	}
	c = devopen(c, omode, 0, 0, ftlgen);
	if(DATAQID(c->qid.path)){
		c->aux = ftlget();
		if(c->aux == nil)
			error(Enodev);
	}
	return c;
}

static void	 
ftlclose(Chan *c)
{
	if(DATAQID(c->qid.path) && (c->flag&COPEN) != 0)
		ftlput((Ftl*)c->aux);
}

static long	 
ftlread(Chan *c, void *buf, long n, vlong offset)
{
	Ftl *ftl;
	Terase *e;
	int nb;
	uchar *a;
	ulong pb;
	if(c->qid.type & QTDIR)
		return devdirread(c, buf, n, 0, 0, ftlgen);

	if(DATAQID(c->qid.path)){
		ulong rwlimit;

		if(n <= 0 || n%Bsize || offset%Bsize)
			error(Eio);
		ftl = c->aux;
		if(c->qid.path > Qdata){
			int p = c->qid.path - Qdata - 1;
			offset += ftl->part[p].start;
			rwlimit = ftl->part[p].rwlimit;
		}
		else
			rwlimit = ftl->rwlimit;
		nb = n/Bsize;
		offset /= Bsize;
		if(offset >= rwlimit)
			return 0;
		if(offset+nb > rwlimit)
			nb = rwlimit - offset;
		a = buf;
		for(n = 0; n < nb; n++){
			qlock(ftl);
			if(waserror()){
				qunlock(ftl);
				nexterror();
			}
			if(mapblk(ftl, offset+n, &e, &pb))
				getflash(ftl, a, e->offset + pb*Bsize, Bsize);
			else
				memset(a, 0, Bsize);
			poperror();
			qunlock(ftl);
			a += Bsize;
		}
		return a-(uchar*)buf;
	}

	if(c->qid.path != Qctl)
		error(Egreg);

	return 0;
}

static long	 
ftlwrite(Chan *c, void *buf, long n, vlong offset)
{
	char cmd[64], *fields[6];
	int ns, i, k, nb;
	uchar *a;
	Terase *e, *oe;
	ulong ob, v, base, size, segsize;
	Ftl *ftl;

	if(n <= 0)
		return 0;

	if(DATAQID(c->qid.path)){
		ulong rwlimit;
		ftl = c->aux;
		if(n <= 0 || n%Bsize || offset%Bsize)
			error(Eio);
		if(c->qid.path > Qdata){
			int p = c->qid.path - Qdata - 1;
			offset += ftl->part[p].start;
			rwlimit = ftl->part[p].rwlimit;
		}
		else
			rwlimit = ftl->rwlimit;
		nb = n/Bsize;
		offset /= Bsize;
		if(offset >= rwlimit)
			return 0;
		if(offset+nb > rwlimit)
			nb = rwlimit - offset;
		a = buf;
		for(n = 0; n < nb; n++){
			ns = 0;
			while((v = allocblk(ftl)) == 0)
				if(!scavenge(ftl) || ++ns > 3){
					static int stop;

					if(stop < 3){
						stop++;
						print("ftl: flash memory full\n");
					}
					error("flash memory full");
				}
			qlock(ftl);
			if(waserror()){
				qunlock(ftl);
				nexterror();
			}
			if(!mapblk(ftl, offset+n, &oe, &ob))
				oe = nil;
			e = ftl->unit[v>>16];
			v &= 0xffff;
			putflash(ftl, e->offset + v*Bsize, a, Bsize);
			putbam(ftl, e, v, MKBAM(offset+n, DataBlock));
			/* both old and new block references exist in this window (can't be closed?) */
			ftl->vbm[offset+n] = (e->x<<16) | v;
			if(oe != nil){
				putbam(ftl, oe, ob, Bdeleted);
				oe->ndead++;
			}
			poperror();
			qunlock(ftl);
			a += Bsize;
		}
		return a-(uchar*)buf;
	}
	else if(c->qid.path == Qctl){
		if(n > sizeof(cmd)-1)
			n = sizeof(cmd)-1;
		memmove(cmd, buf, n);
		cmd[n] = 0;
		i = getfields(cmd, fields, 6, 1, " \t\n");
		if(i <= 0)
			error(Ebadarg);
		if(i >= 2 && (strcmp(fields[0], "init") == 0 || strcmp(fields[0], "format") == 0)){
			if(i > 2)
				base = strtoul(fields[2], nil, 0);
			else
				base = 0;	/* TO DO: hunt for signature */
			if(i > 3)
				size = strtoul(fields[3], nil, 0);
			else
				size = Nolimit;
			if(i > 4)
				segsize = strtoul(fields[4], nil, 0);
			else
				segsize = 0;
			/* segsize must be power of two and size and base must be multiples of it
			 * if segsize is zero, then use whatever the device returns
			 */
			if(segsize != 0 && (segsize > size
				|| segsize&(segsize-1)
				|| (base != Nolimit && base&(segsize-1))
				|| size == 0
				|| (size != Nolimit && size&(segsize-1))))
				error(Ebadarg);
			if(segsize == 0)
				k = 0;
			else {
				for(k=0; k<32 && (1<<k) != segsize; k++)
					;
			}
			if(ftls != nil)
				error(Einuse);
			ftls = mkftl(fields[1], base, size, k, fields[0]);
		}else if(strcmp(fields[0], "scavenge") == 0){
			if(ftls != nil)
				print("scavenge %d\n", scavenge(ftls));
		}else if(strcmp(fields[0], "trace") == 0){
			if(ftls != nil)
				ftls->trace = i>1? strtol(fields[1], nil, 0): 1;
		}else if(strcmp(fields[0], "detach") == 0){
			if((ftl = ftlget()) != nil){
				if(ftl->ref > 1){
					ftlput(ftl);
					error(Einuse);
				}
				ftl->detach = Detached;
				ftlput(ftl);
			}else
				error(Enodev);
		}else if(strcmp(fields[0], "part")==0){
			if((ftl = ftlget()) != nil){
				if(ftl->ref > 1){
					ftlput(ftl);
					error(Einuse);
				}
				if(waserror()){
					ftlput(ftl);
					nexterror();
				}
				ftlpartcmd(ftl, fields + 1, i - 1);
				poperror();
				ftlput(ftl);
			}else
				error(Enodev);
		}else if(strcmp(fields[0], "delpart")==0){
			if((ftl = ftlget()) != nil){
				if(ftl->ref > 1){
					ftlput(ftl);
					error(Einuse);
				}
				if(waserror()){
					ftlput(ftl);
					nexterror();
				}
				ftldelpartcmd(ftls, fields + 1, i - 1);
				poperror();
				ftlput(ftl);
			}else
				error(Enodev);
		}else if(i >= 2 && strcmp(fields[0], "pct")==0){
			v = strtoul(fields[1], nil, 0);
			if(v >= 50)
				ftlpct = v;
		}else
			error(Ebadarg);
		return n;
	}
	error(Egreg);
	return 0;		/* not reached */
}

static Chan *
ftlkopen(char *name, char *suffix, int mode)
{
	Chan *c;
	char *fn;
	int fd;

	if(suffix != nil && *suffix){
		fn = smalloc(strlen(name)+strlen(suffix)+1);
		if(fn == nil)
			return nil;
		strcpy(fn, name);
		strcat(fn, suffix);
		fd = kopen(fn, mode);
		free(fn);
	}else
		fd = kopen(name, mode);
	if(fd < 0)
		return nil;
	c = fdtochan(up->env->fgrp, fd, mode, 0, 1);
	kclose(fd);
	return c;
}

static ulong
ftlfsize(Chan *c)
{
	uchar dbuf[STATFIXLEN+32*4];
	Dir d;
	int n;

	n = devtab[c->type]->stat(c, dbuf, sizeof(dbuf));
	if(convM2D(dbuf, n, &d, nil) == 0)
		return 0;
	return d.length;
}

static Ftl *
mkftl(char *fname, ulong base, ulong size, int eshift, char *op)
{
	int i, j, nov, segblocks, n, badseg, old, valid;
	ulong limit;
	Terase *e;
	Ftl *ftl;
	char buf[64], *fields[8];
	ulong ea;
	Chan *statfd;

	ftl = malloc(sizeof(*ftl));
	if(ftl == nil)
		error(Enomem);
	e = nil;
	if(waserror()){
		ftlfree(ftl);
		if(e)
			free(e);
		nexterror();
	}
	ftl->lastx = 0;
	ftl->trace = 0;
	ftl->flash = ftlkopen(fname, "", ORDWR);
	if(ftl->flash == nil)
		error(up->env->errstr);
	ftl->flashctl = ftlkopen(fname, "ctl", ORDWR);
	if(ftl->flashctl == nil)
		error(up->env->errstr);
	old = 1;
	statfd = ftlkopen(fname, "stat", OREAD);	/* old scheme */
	if(statfd == nil){
		statfd = ftl->flashctl;	/* new just uses ctl */
		old = 0;
	}
	statfd->offset = 0;
	if((n = kchanio(statfd, buf, sizeof(buf), OREAD)) <= 0){
		print("ftl: read stat/ctl failed: %s\n", up->env->errstr);
		error(up->env->errstr);
	}
	if(n >= sizeof(buf))
		n = sizeof(buf)-1;
	buf[n] = 0;
	if(statfd != ftl->flashctl)
		cclose(statfd);

	n = getfields(buf, fields, nelem(fields), 1, " \t\n");
	ea = 0;
	if(old){
		if(n >= 4)
			if((ea = strtoul(fields[3], nil, 16)) < 8*1024)
				ea = 0;	/* assume the format is wrong */
	}else{
		if(n >= 7)
			if((ea = strtoul(fields[6], nil, 0)) < 2*1024)
				ea = 0;	/* assume the format is wrong */
	}
	if(ea != 0){
		for(i=0; i < 32 && (1<<i) != ea; i++)
			;
		if(eshift && i != eshift)
			print("ftl: overriding erasesize %d with %d\n", 1 << eshift, 1 << i);
		eshift = i;
		if(FTLDEBUG)
			print("ftl: e=%lud eshift=%d\n", ea, i);
	}
	if(eshift == 0)
		error("no erasesize");

	limit = ftlfsize(ftl->flash);
	if(limit == 0)
		error("no space for flash translation");
	ftl->segsize = 1 << eshift;
	if(base == Nolimit){
		ushort pstart, nunits;
		erasedetect(ftl, 0, limit, &pstart, &nunits);
		base = pstart * ftl->segsize;
		size = nunits * ftl->segsize;
		print("ftl: partition in %s at 0x%.8lux, length 0x%.8lux\n", fname, base, size);
	} else if(size == Nolimit)
		size = limit-base;
	if(base >= limit || size > limit || base+size > limit || eshift < 8 || (1<<eshift) > size){
		print("ftl: bad: base=%#lux limit=%#lux size=%ld eshift=%d\n", base, limit, size, eshift);
		error("bad flash space parameters");
	}
	if(FTLDEBUG)
		print("%s flash %s #%lux:#%lux limit #%lux\n", op, fname, base, size, limit);
	ftl->base = base;
	ftl->size = size;
	ftl->bshift = Bshift;
	ftl->bsize = Bsize;
	ftl->eshift = eshift;
	ftl->nunit = size>>eshift;
	nov = ((ftl->segsize/Bsize)*4 + BAMoffset + Bsize - 1)/Bsize;	/* number of overhead blocks per segment (header, and BAM itself) */
	ftl->fstart = nov;
	segblocks = ftl->segsize/Bsize - nov;
	ftl->nblock = ftl->nunit*segblocks;
	if(ftl->nblock > 0x10000){
		/* oops - too many blocks */
		ftl->nunit = 0x10000 / segblocks;
		ftl->nblock = ftl->nunit * segblocks;
		size = ftl->nunit * ftl->segsize;
		ftl->size = size;
		print("ftl: too many blocks - limiting to %ld bytes %d units %lud blocks\n",
		    size, ftl->nunit, ftl->nblock);
	}
	ftl->vbm = malloc(ftl->nblock*sizeof(*ftl->vbm));
	ftl->unit = malloc(ftl->nunit*sizeof(*ftl->unit));
	if(ftl->vbm == nil || ftl->unit == nil)
		error(Enomem);
	if(strcmp(op, "format") == 0){
		for(i=0; i<ftl->nunit-1; i++)
			eraseinit(ftl, i*ftl->segsize, i, 1);
		eraseinit(ftl, i*ftl->segsize, XferID, 1);
	}
	badseg = -1;
	ftl->xfer = -1;
	valid = 0;
	for(i=0; i<ftl->nunit; i++){
		e = eraseload(ftl, i, i*ftl->segsize);
		if(e == nil){
			print("ftl: logical segment %d: bad format\n", i);
			if(badseg == -1)
				badseg = i;
			else
				badseg = -2;
			continue;
		}
		if(e->id == XferBusy){
			e->nerase++;
			eraseinit(ftl, e->offset, XferID, e->nerase);
			e->id = XferID;
		}
		for(j=0; j<ftl->nunit; j++)
			if(ftl->unit[j] != nil && ftl->unit[j]->id == e->id){
				print("ftl: duplicate erase unit #%x\n", e->id);
				erasefree(e);
				e = nil;
				break;
			}
		if(e){
			valid++;
			ftl->unit[e->x] = e;
			if(e->id == XferID)
				ftl->xfer = e->x;
			if(FTLDEBUG)
				print("ftl: unit %d:#%x used %lud free %lud dead %lud bad %lud nerase %lud\n",
					e->x, e->id, e->nused, e->nfree, e->ndead, e->nbad, e->nerase);
			e = nil;
			USED(e);
		}
	}
	if(badseg >= 0){
		if(ftl->xfer >= 0)
			error("invalid ftl format");
		i = badseg;
		eraseinit(ftl, i*ftl->segsize, XferID, 1);
		e = eraseload(ftl, i, i*ftl->segsize);
		if(e == nil)
			error("bad ftl format");
		ftl->unit[e->x] = e;
		ftl->xfer = e->x;
		print("ftl: recovered transfer unit %d\n", e->x);
		valid++;
		e = nil;
		USED(e);
	}
	if(ftl->xfer < 0 && valid <= 0 || ftl->xfer >= 0 && valid <= 1)
		error("no valid flash data units");
	if(ftl->xfer < 0)
		error("ftl: no transfer unit: device is WORM\n");
	else
		ftl->nblock -= segblocks;	/* discount transfer segment */
	if(ftl->nblock >= 1000)
		ftl->rwlimit = ftl->nblock-100;	/* TO DO: variable reserve */
	else
		ftl->rwlimit = ftl->nblock*ftlpct/100;
	poperror();
	return ftl;
}

static void
ftlfree(Ftl *ftl)
{
	int i, n;

	if(ftl != nil){
		if(ftl->flashctl != nil)
			cclose(ftl->flashctl);
		if(ftl->flash != nil)
			cclose(ftl->flash);

		if(ftl->unit){
			for(i = 0; i < ftl->nunit; i++)
				erasefree(ftl->unit[i]);
			free(ftl->unit);
		}
		free(ftl->vbm);
		for(n = 0; n < NPART; n++)
			free(ftl->part[n].name);
		free(ftl);
	}
}

/*
 * this simple greedy algorithm weighted by nerase does seem to lead
 * to even wear of erase units (cf. the eNVy file system)
 */
static Terase *
bestcopy(Ftl *ftl)
{
	Terase *e, *be;
	int i;

	be = nil;
	for(i=0; i<ftl->nunit; i++)
		if((e = ftl->unit[i]) != nil && e->id != XferID && e->id != XferBusy && e->ndead+e->nbad &&
		    (be == nil || e->nerase <= be->nerase && e->ndead >= be->ndead))
			be = e;
	return be;
}

static int
copyunit(Ftl *ftl, Terase *from, Terase *to)
{
	int i, nb;
	uchar id[2];
	ulong *bam;
	uchar *buf;
	ulong v, bno;

	if(FTLDEBUG || ftl->trace)
		print("ftl: copying %d (#%lux) to #%lux\n", from->id, from->offset, to->offset);
	to->nbam = 0;
	free(to->bam);
	to->bam = nil;
	bam = nil;
	buf = malloc(Bsize);
	if(buf == nil)
		return 0;
	if(waserror()){
		free(buf);
		free(bam);
		return 0;
	}
	PUT2(id, XferBusy);
	putflash(ftl, to->offset+offsetof(Merase,id[0]), id, 2);
	/* make new BAM */
	nb = from->nbam*sizeof(*to->bam);
	bam = malloc(nb);
	if(bam == nil)
		error(Enomem);
	memmove(bam, from->bam, nb);
	to->nused = 0;
	to->nbad = 0;
	to->nfree = 0;
	to->ndead = 0;
	for(i = 0; i < from->nbam; i++)
		switch(bam[i]){
		case Bwriting:
		case Bdeleted:
		case Bfree:
			bam[i] = Bfree;
			to->nfree++;
			break;
		default:
			switch(bam[i]&BlockType){
			default:
			case BadBlock:	/* it isn't necessarily bad in this unit */
				to->nfree++;
				bam[i] = Bfree;
				break;
			case DataBlock:
			case ReplacePage:
				v = bam[i];
				bno = BNO(v & ~BlockType);
				if(i < ftl->fstart || bno >= ftl->nblock){
					print("ftl: unit %d:#%x bad bam[%d]=#%lux\n", from->x, from->id, i, v);
					to->nfree++;
					bam[i] = Bfree;
					break;
				}
				getflash(ftl, buf, from->offset+i*Bsize, Bsize);
				putflash(ftl, to->offset+i*Bsize, buf, Bsize);
				to->nused++;
				break;
			case ControlBlock:
				to->nused++;
				break;
			}
		}
	for(i=0; i<from->nbam; i++){
		uchar *p = (uchar*)&bam[i];
		v = bam[i];
		if(v != Bfree && ftl->trace > 1)
			print("to[%d]=#%lux\n", i, v);
		PUT4(p, v);
	}
	putflash(ftl, to->bamoffset, bam, nb);	/* BUG: PUT4 */
	for(i=0; i<from->nbam; i++){
		uchar *p = (uchar*)&bam[i];
		v = bam[i];
		PUT4(p, v);
	}
	to->id = from->id;
	PUT2(id, to->id);
	putflash(ftl, to->offset+offsetof(Merase,id[0]), id, 2);
	to->nbam = from->nbam;
	to->bam = bam;
	ftl->nfree += to->nfree - from->nfree;
	poperror();
	free(buf);
	return 1;
}

static int
mustscavenge(void *a)
{
	return ((Ftl*)a)->needspace || ((Ftl*)a)->detach == Deferred;
}

static int
donescavenge(void *a)
{
	return ((Ftl*)a)->needspace == 0;
}

static void
scavengeproc(void *arg)
{
	Ftl *ftl;
	int i;
	Terase *e, *ne;

	ftl = arg;
	if(waserror()){
		print("ftl: kproc noted\n");
		pexit("ftldeath", 0);
	}
	for(;;){
		sleep(&ftl->workr, mustscavenge, ftl);
		if(ftl->detach == Deferred){
			ftlfree(ftl);
			pexit("", 0);
		}
		if(FTLDEBUG || ftl->trace)
			print("ftl: scavenge %ld\n", ftl->nfree);
		qlock(ftl);
		if(waserror()){
			qunlock(ftl);
			nexterror();
		}
		e = bestcopy(ftl);
		if(e == nil || ftl->xfer < 0 || (ne = ftl->unit[ftl->xfer]) == nil || ne->id != XferID || e == ne)
			goto Fail;
		if(copyunit(ftl, e, ne)){
			i = ne->x; ne->x = e->x; e->x = i;
			ftl->unit[ne->x] = ne;
			ftl->unit[e->x] = e;
			ftl->xfer = e->x;
			e->id = XferID;
			e->nbam = 0;
			free(e->bam);
			e->bam = nil;
			e->bamx = 0;
			e->nerase++;
			eraseinit(ftl, e->offset, XferID, e->nerase);
		}
	Fail:
		if(FTLDEBUG || ftl->trace)
			print("ftl: end scavenge %ld\n", ftl->nfree);
		ftl->needspace = 0;
		wakeup(&ftl->wantr);
		poperror();
		qunlock(ftl);
	}
}

static int
scavenge(Ftl *ftl)
{
	if(ftl->xfer < 0 || bestcopy(ftl) == nil)
		return 0;	/* you worm! */

	qlock(ftl);
	if(waserror()){
		qunlock(ftl);
		return 0;
	}
	if(!ftl->hasproc){
		ftl->hasproc = 1;
		kproc("ftl.scavenge", scavengeproc, ftl, 0);
	}
	ftl->needspace = 1;
	wakeup(&ftl->workr);
	poperror();
	qunlock(ftl);

	qlock(&ftl->wantq);
	if(waserror()){
		qunlock(&ftl->wantq);
		nexterror();
	}
	while(ftl->needspace)
		sleep(&ftl->wantr, donescavenge, ftl);
	poperror();
	qunlock(&ftl->wantq);

	return ftl->nfree;
}

static void
putbam(Ftl *ftl, Terase *e, int n, ulong entry)
{
	uchar b[4];

	e->bam[n] = entry;
	PUT4(b, entry);
	putflash(ftl, e->bamoffset + n*4, b, 4);
}

static ulong
allocblk(Ftl *ftl)
{
	Terase *e;
	int i, j;

	qlock(ftl);
	i = ftl->lastx;
	do{
		e = ftl->unit[i];
		if(e != nil && e->id != XferID && e->nfree){
			ftl->lastx = i;
			for(j=e->bamx; j<e->nbam; j++)
				if(e->bam[j] == Bfree){
					putbam(ftl, e, j, Bwriting);
					ftl->nfree--;
					e->nfree--;
					e->bamx = j+1;
					qunlock(ftl);
					return (e->x<<16) | j;
				}
			e->nfree = 0;
			qunlock(ftl);
			print("ftl: unit %d:#%x nfree %ld but not free in BAM\n", e->x, e->id, e->nfree);
			qlock(ftl);
		}
		if(++i >= ftl->nunit)
			i = 0;
	}while(i != ftl->lastx);
	qunlock(ftl);
	return 0;
}

static int
mapblk(Ftl *ftl, ulong bno, Terase **ep, ulong *bp)
{
	ulong v;
	int x;

	if(bno < ftl->nblock){
		v = ftl->vbm[bno];
		if(v == 0 || v == ~0)
			return 0;
		x = v>>16;
		if(x >= ftl->nunit || x == ftl->xfer || ftl->unit[x] == nil){
			print("ftl: corrupt format: bad block mapping %lud -> unit #%x\n", bno, x);
			return 0;
		}
		*ep = ftl->unit[x];
		*bp = v & 0xFFFF;
		return 1;
	}
	return 0;
}

static void
eraseinit(Ftl *ftl, ulong offset, int id, int nerase)
{
	union {
		Merase;
		uchar	block[ERASEHDRLEN];
	} *m;
	uchar *bam, *p;
	int i, nov;

	nov = ((ftl->segsize/Bsize)*4 + BAMoffset + Bsize - 1)/Bsize;	/* number of overhead blocks (header, and BAM itself) */
	if(nov*Bsize >= ftl->segsize)
		error("ftl -- too small for files");
	eraseflash(ftl, offset);
	m = malloc(sizeof(*m));
	if(m == nil)
		error(Enomem);
	memset(m, 0xFF, sizeof(*m));
	m->linktuple[0] = 0x13;
	m->linktuple[1] = 0x3;
	memmove(m->linktuple+2, "CIS", 3);
	m->orgtuple[0] = 0x46;
	m->orgtuple[1] = 0x57;
	m->orgtuple[2] = 0x00;
	memmove(m->orgtuple+3, "FTL100", 7);
	m->nxfer = 1;
	PUT4(m->nerase, nerase);
	PUT2(m->id, id);
	m->bshift = ftl->bshift;
	m->eshift = ftl->eshift;
	PUT2(m->pstart, ftl->base >> ftl->eshift);
	PUT2(m->nunits, ftl->nunit);
	PUT4(m->psize, ftl->size - nov*Bsize*ftl->nunit);
	PUT4(m->vbmbase, 0xffffffff);	/* we always calculate the VBM */
	PUT2(m->nvbm, 0);
	m->flags = 0;
	m->code = 0xFF;
	memmove(m->serial, "Inf1", 4);
	PUT4(m->altoffset, 0);
	PUT4(m->bamoffset, BAMoffset);
	putflash(ftl, offset, m, ERASEHDRLEN);
	free(m);
	if(id == XferID)
		return;
	nov *= 4;	/* now bytes of BAM */
	bam = malloc(nov);
	if(bam == nil)
		error(Enomem);
	for(i=0; i<nov; i += 4){
		p = bam+i;
		PUT4(p, ControlBlock);	/* reserve them */
	}
	putflash(ftl, offset+BAMoffset, bam, nov);
	free(bam);
}

static int
erasedetect(Ftl *ftl, ulong base, ulong size, ushort *pstart, ushort *nunits)
{
	ulong o;
	int rv;

	union {
		Merase;
		uchar	block[ERASEHDRLEN];
	} *m;
	m = malloc(sizeof(*m));
	if(m == nil)
		error(Enomem);
	rv  = 0;
	for(o = base; o < base + size; o += ftl->segsize){
		if(waserror())
			continue;
		getflash(ftl, m, o, ERASEHDRLEN);
		poperror();
		if(memcmp(m->orgtuple + 3, "FTL100", 7) == 0
		    && memcmp(m->serial, "Inf1", 4) == 0){
			*pstart = GET2(m->pstart);
			*nunits = GET2(m->nunits);
			rv = 1;
			break;
		}
	}
	free(m);
	return rv;
}

static Terase *
eraseload(Ftl *ftl, int x, ulong offset)
{
	union {
		Merase;
		uchar	block[ERASEHDRLEN];
	} *m;
	Terase *e;
	uchar *p;
	int i, nbam;
	ulong bno, v;

	m = malloc(sizeof(*m));
	if(m == nil)
		error(Enomem);
	if(waserror()){
		free(m);
		return nil;
	}
	getflash(ftl, m, offset, ERASEHDRLEN);
	poperror();
	if(memcmp(m->orgtuple+3, "FTL100", 7) != 0 ||
	   memcmp(m->serial, "Inf1", 4) != 0){
		free(m);
print("%8.8lux: bad sig\n", offset);
		return nil;
	}
	e = malloc(sizeof(*e));
	if(e == nil){
		free(m);
		error(Enomem);
	}
	e->x = x;
	e->id = GET2(m->id);
	e->offset = offset;
	e->bamoffset = GET4(m->bamoffset);
	e->nerase = GET4(m->nerase);
	free(m);
	m = nil;
	USED(m);
	if(e->bamoffset != BAMoffset){
		free(e);
print("%8.8lux: bad bamoffset %8.8lux\n", offset, e->bamoffset);
		return nil;
	}
	e->bamoffset += offset;
	if(e->id == XferID || e->id == XferBusy){
		e->bam = nil;
		e->nbam = 0;
		return e;
	}
	nbam = ftl->segsize/Bsize;
	e->bam = malloc(nbam*sizeof(*e->bam));
	e->nbam = nbam;
	if(waserror()){
		free(e);
		nexterror();
	}
	getflash(ftl, e->bam, e->bamoffset, nbam*4);
	poperror();
	/* scan BAM to build VBM */
	e->bamx = 0;
	for(i=0; i<nbam; i++){
		p = (uchar*)&e->bam[i];
		e->bam[i] = v = GET4(p);
		if(v == Bwriting || v == Bdeleted)
			e->ndead++;
		else if(v == Bfree){
			if(e->bamx == 0)
				e->bamx = i;
			e->nfree++;
			ftl->nfree++;
		}else{
			switch(v & BlockType){
			case ControlBlock:
				break;
			case DataBlock:
				/* add to VBM */
				if(v & (1<<31))
					break;	/* negative => VBM page, ignored */
				bno = BNO(v & ~BlockType);
				if(i < ftl->fstart || bno >= ftl->nblock){
					print("ftl: unit %d:#%x bad bam[%d]=#%lux\n", e->x, e->id, i, v);
					e->nbad++;
					break;
				}
				ftl->vbm[bno] = (e->x<<16) | i;
				e->nused++;
				break;
			case ReplacePage:
				/* replacement VBM page; ignored */
				break;
			default:
				print("ftl: unit %d:#%x bad bam[%d]=%lux\n", e->x, e->id, i, v);
			case BadBlock:
				e->nbad++;
				break;
			}
		}
	}
	return e;
}

static void
erasefree(Terase *e)
{
	if(e){
		free(e->bam);
		free(e);
	}
}

static void
eraseflash(Ftl *ftl, ulong offset)
{
	char cmd[40];

	offset += ftl->base;
	if(FTLDEBUG || ftl->trace)
		print("ftl: erase seg @#%lux\n", offset);
	snprint(cmd, sizeof(cmd), "erase 0x%8.8lux", offset);
	if(kchanio(ftl->flashctl, cmd, strlen(cmd), OWRITE) <= 0){
		print("ftl: erase failed: %s\n", up->env->errstr);
		error(up->env->errstr);
	}
}

static void
putflash(Ftl *ftl, ulong offset, void *buf, long n)
{
	offset += ftl->base;
	if(ftl->trace)
		print("ftl: write(#%lux, %ld)\n", offset, n);
	ftl->flash->offset = offset;
	if(kchanio(ftl->flash, buf, n, OWRITE) != n){
		print("ftl: flash write error: %s\n", up->env->errstr);
		error(up->env->errstr);
	}
}

static void
getflash(Ftl *ftl, void *buf, ulong offset, long n)
{
	offset += ftl->base;
	if(ftl->trace)
		print("ftl: read(#%lux, %ld)\n", offset, n);
	ftl->flash->offset = offset;
	if(kchanio(ftl->flash, buf, n, OREAD) != n){
		print("ftl: flash read error %s\n", up->env->errstr);
		error(up->env->errstr);
	}
}

Dev ftldevtab = {
	'X',	/* TO DO */
	"ftl",

	devreset,
	devinit,
	devshutdown,
	ftlattach,
	ftlwalk,
	ftlstat,
	ftlopen,
	devcreate,
	ftlclose,
	ftlread,
	devbread,
	ftlwrite,
	devbwrite,
	devremove,
	devwstat,
};
