#include	<lib9.h>
#include	<bio.h>
#include	"bootexec.h"
#include	"mach.h"
#include	"elf.h"

/*
 *	All a.out header types.  The dummy entry allows canonical
 *	processing of the union as a sequence of longs
 */

typedef struct {
	union{
		Exec exec;			/* in a.out.h */
		Ehdr ehdr;			/* in elf.h */
		struct mipsexec mipsexec;
		struct mips4kexec mips4kexec;
		struct sparcexec sparcexec;
		struct nextexec nextexec;
	} e;
	long dummy;		/* padding to ensure extra long */
} ExecHdr;

static	int	nextboot(int, Fhdr*, ExecHdr*);
static	int	sparcboot(int, Fhdr*, ExecHdr*);
static	int	mipsboot(int, Fhdr*, ExecHdr*);
static	int	mips4kboot(int, Fhdr*, ExecHdr*);
static	int	common(int, Fhdr*, ExecHdr*);
static	int	adotout(int, Fhdr*, ExecHdr*);
static	int	elfdotout(int, Fhdr*, ExecHdr*);
static	int	armdotout(int, Fhdr*, ExecHdr*);
static	void	setsym(Fhdr*, long, long, long, long);
static	void	setdata(Fhdr*, long, long, long, long);
static	void	settext(Fhdr*, long, long, long, long);
static	void	hswal(long*, int, long(*)(long));
static	long	_round(long, long);

/*
 *	definition of per-executable file type structures
 */

typedef struct Exectable{
	long	magic;			/* big-endian magic number of file */
	char	*name;			/* executable identifier */
	int	type;			/* Internal code */
	Mach	*mach;			/* Per-machine data */
	ulong	hsize;			/* header size */
	long	(*swal)(long);		/* beswal or leswal */
	int	(*hparse)(int, Fhdr*, ExecHdr*);
} ExecTable;

extern	Mach	mmips;
extern	Mach	mmips2le;
extern	Mach	mmips2be;
extern	Mach	msparc;
extern	Mach	m68020;
extern	Mach	mi386;
extern	Mach	marm;
extern	Mach	mpower;

ExecTable exectab[] =
{
	{ V_MAGIC,			/* Mips v.out */
		"mips plan 9 executable",
		FMIPS,
		&mmips,
		sizeof(Exec),
		beswal,
		adotout },
	{ M_MAGIC,			/* Mips 4.out */
		"mips 4k plan 9 executable BE",
		FMIPS2BE,
		&mmips2be,
		sizeof(Exec),
		beswal,
		adotout },
	{ N_MAGIC,			/* Mips 0.out */
		"mips 4k plan 9 executable LE",
		FMIPS2LE,
		&mmips2le,
		sizeof(Exec),
		beswal,
		adotout },
	{ 0x160<<16,			/* Mips boot image */
		"mips plan 9 boot image",
		FMIPSB,
		&mmips,
		sizeof(struct mipsexec),
		beswal,
		mipsboot },
	{ (0x160<<16)|3,		/* Mips boot image */
		"mips 4k plan 9 boot image",
		FMIPSB,
		&mmips,
		sizeof(struct mips4kexec),
		beswal,
		mips4kboot },
	{ K_MAGIC,			/* Sparc k.out */
		"sparc plan 9 executable",
		FSPARC,
		&msparc,
		sizeof(Exec),
		beswal,
		adotout },
	{ 0x01030107, 			/* Sparc boot image */
		"sparc plan 9 boot image",
		FSPARCB,
		&msparc,
		sizeof(struct sparcexec),
		beswal,
		sparcboot },
	{ A_MAGIC,			/* 68020 2.out & boot image */
		"68020 plan 9 executable",
		F68020,
		&m68020,
		sizeof(Exec),
		beswal,
		common },
	{ 0xFEEDFACE,			/* Next boot image */
		"next plan 9 boot image",
		FNEXTB,
		&m68020,
		sizeof(struct nextexec),
		beswal,
		nextboot },
	{ I_MAGIC,			/* I386 8.out & boot image */
		"386 plan 9 executable",
		FI386,
		&mi386,
		sizeof(Exec),
		beswal,
		common },
	{ ELF_MAG,
		"Irix 5.X Elf executable",
		FMIPS,
		&mmips,
		sizeof(Ehdr),
		beswal,
		elfdotout },
	{ E_MAGIC,			/* Arm 5.out */
		"Arm plan 9 executable",
		FARM,
		&marm,
		sizeof(Exec),
		beswal,
		common },
	{ (143<<16)|0413,		/* (Free|Net)BSD Arm */
		"Arm *BSD executable",
		FARM,
		&marm,
		sizeof(Exec),
		leswal,
		armdotout },
	{ Q_MAGIC,			/* PowerPC q.out */
		"power plan 9 executable",
		FPOWER,
		&mpower,
		sizeof(Exec),
		beswal,
		common },
	{ 0 },
};

Mach	*mach = &mmips;			/* Global current machine table */

ExecTable*
couldbe4k(ExecTable *mp)
{
	Dir *d;
	ExecTable *f;

	if((d=dirstat("/proc/1/regs")) == nil)
		return mp;
	if(d->length < 32*8){		/* R3000 */
		free(d);
		return mp;
	}
	free(d);
	for (f = exectab; f->magic; f++)
		if(f->magic == M_MAGIC) {
			f->name = "mips plan 9 executable on mips2 kernel";
			return f;
		}
	return mp;
}


int
crackhdr(int fd, Fhdr *fp)
{
	ExecTable *mp;
	ExecHdr d;
	int nb, magic, ret;

	fp->type = FNONE;
	nb = read(fd, (char *)&d.e, sizeof(d.e));
	if (nb <= 0)
		return 0;

	ret = 0;
	fp->magic = magic = beswal(d.e.exec.magic);		/* big-endian */
	for (mp = exectab; mp->magic; mp++) {
		if (mp->magic == magic && nb >= mp->hsize) {
			if(mp->magic == V_MAGIC)
				mp = couldbe4k(mp);

			hswal((long *) &d, sizeof(d.e)/sizeof(long), mp->swal);
			fp->type = mp->type;
			fp->name = mp->name;
			fp->hdrsz = mp->hsize;		/* zero on bootables */
			mach = mp->mach;
			ret  = mp->hparse(fd, fp, &d);
			seek(fd, mp->hsize, 0);		/* seek to end of header */
			break;
		}
	}
	if(mp->magic == 0)
		werrstr("unknown header type");
	return ret;
}
/*
 * Convert header to canonical form
 */
static void
hswal(long *lp, int n, long (*swap) (long))
{
	while (n--) {
		*lp = (*swap) (*lp);
		lp++;
	}
}
/*
 *	Crack a normal a.out-type header
 */
static int
adotout(int fd, Fhdr *fp, ExecHdr *hp)
{
	long pgsize;

	USED(fd);
	pgsize = mach->pgsize;
	settext(fp, hp->e.exec.entry, pgsize+sizeof(Exec),
			hp->e.exec.text, sizeof(Exec));
	setdata(fp, _round(pgsize+fp->txtsz+sizeof(Exec), pgsize),
		hp->e.exec.data, fp->txtsz+sizeof(Exec), hp->e.exec.bss);
	setsym(fp, hp->e.exec.syms, hp->e.exec.spsz, hp->e.exec.pcsz, fp->datoff+fp->datsz);
	return 1;
}

/*
 *	68020 2.out and 68020 bootable images
 *	386I 8.out and 386I bootable images
 *
 */
static int
common(int fd, Fhdr *fp, ExecHdr *hp)
{
	long kbase;

	adotout(fd, fp, hp);
	kbase = mach->kbase;
	if ((fp->entry & kbase) == kbase) {		/* Boot image */
		switch(fp->type) {
		case F68020:
			fp->type = F68020B;
			fp->name = "68020 plan 9 boot image";
			fp->hdrsz = 0;		/* header stripped */
			break;
		case FI386:
			fp->type = FI386B;
			fp->txtaddr = sizeof(Exec);
			fp->name = "386 plan 9 boot image";
			fp->hdrsz = 0;		/* header stripped */
			fp->dataddr = fp->txtaddr+fp->txtsz;
			break;
		case FARM:
			fp->txtaddr = kbase+0x8000+sizeof(Exec);
			fp->name = "ARM plan 9 boot image";
			fp->hdrsz = 0;		/* header stripped */
			fp->dataddr = fp->txtaddr+fp->txtsz;
			return 1;
		default:
			break;
		}
		fp->txtaddr |= kbase;
		fp->entry |= kbase;
		fp->dataddr |= kbase;
	}
	else if (fp->type == FARM && (fp->entry == 0x8020 || fp->entry == 0x8080)) {
		fp->txtaddr = fp->entry;
		fp->name = "ARM Inferno boot image";
		fp->hdrsz = 0;		/* header stripped */
		fp->dataddr = fp->txtaddr+fp->txtsz;
	}
	else if (fp->type == FPOWER && fp->entry == 0x3020) {
		fp->txtaddr = fp->entry;
		fp->name = "Power Inferno boot image";
		fp->hdrsz = 0;		/* header stripped */
		fp->dataddr = fp->txtaddr+fp->txtsz;
	}
	return 1;
}

/*
 *	mips bootable image.
 */
static int
mipsboot(int fd, Fhdr *fp, ExecHdr *hp)
{
	USED(fd);
	switch(hp->e.mipsexec.amagic) {
	default:
	case 0407:	/* some kind of mips */
		fp->type = FMIPSB;
		settext(fp, hp->e.mipsexec.mentry, hp->e.mipsexec.text_start, hp->e.mipsexec.tsize,
					sizeof(struct mipsexec)+4);
		setdata(fp, hp->e.mipsexec.data_start, hp->e.mipsexec.dsize,
				fp->txtoff+hp->e.mipsexec.tsize, hp->e.mipsexec.bsize);
		break;
	case 0413:	/* some kind of mips */
		fp->type = FMIPSB;
		settext(fp, hp->e.mipsexec.mentry, hp->e.mipsexec.text_start, hp->e.mipsexec.tsize, 0);
		setdata(fp, hp->e.mipsexec.data_start, hp->e.mipsexec.dsize, hp->e.mipsexec.tsize,
					hp->e.mipsexec.bsize);
		break;
	}
	setsym(fp, hp->e.mipsexec.nsyms, 0, hp->e.mipsexec.u0.mpcsize, hp->e.mipsexec.symptr);
	fp->hdrsz = 0;		/* header stripped */
	return 1;
}

/*
 *	mips4k bootable image.
 */
static int
mips4kboot(int fd, Fhdr *fp, ExecHdr *hp)
{
	USED(fd);
	switch(hp->e.mipsexec.amagic) {
	default:
	case 0407:	/* some kind of mips */
		fp->type = FMIPSB;
		settext(fp, hp->e.mipsexec.mentry, hp->e.mipsexec.text_start, hp->e.mipsexec.tsize,
					sizeof(struct mips4kexec));
		setdata(fp, hp->e.mipsexec.data_start, hp->e.mipsexec.dsize,
				fp->txtoff+hp->e.mipsexec.tsize, hp->e.mipsexec.bsize);
		break;
	case 0413:	/* some kind of mips */
		fp->type = FMIPSB;
		settext(fp, hp->e.mipsexec.mentry, hp->e.mipsexec.text_start, hp->e.mipsexec.tsize, 0);
		setdata(fp, hp->e.mipsexec.data_start, hp->e.mipsexec.dsize, hp->e.mipsexec.tsize,
					hp->e.mipsexec.bsize);
		break;
	}
	setsym(fp, hp->e.mipsexec.nsyms, 0, hp->e.mipsexec.u0.mpcsize, hp->e.mipsexec.symptr);
	fp->hdrsz = 0;		/* header stripped */
	return 1;
}

/*
 *	sparc bootable image
 */
static int
sparcboot(int fd, Fhdr *fp, ExecHdr *hp)
{
	USED(fd);
	fp->type = FSPARCB;
	settext(fp, hp->e.sparcexec.sentry, hp->e.sparcexec.sentry, hp->e.sparcexec.stext,
					sizeof(struct sparcexec));
	setdata(fp, hp->e.sparcexec.sentry+hp->e.sparcexec.stext, hp->e.sparcexec.sdata,
					fp->txtoff+hp->e.sparcexec.stext, hp->e.sparcexec.sbss);
	setsym(fp, hp->e.sparcexec.ssyms, 0, hp->e.sparcexec.sdrsize, fp->datoff+hp->e.sparcexec.sdata);
	fp->hdrsz = 0;		/* header stripped */
	return 1;
}

/*
 *	next bootable image
 */
static int
nextboot(int fd, Fhdr *fp, ExecHdr *hp)
{
	USED(fd);
	fp->type = FNEXTB;
	settext(fp, hp->e.nextexec.textc.vmaddr, hp->e.nextexec.textc.vmaddr,
					hp->e.nextexec.texts.size, hp->e.nextexec.texts.offset);
	setdata(fp, hp->e.nextexec.datac.vmaddr, hp->e.nextexec.datas.size,
				hp->e.nextexec.datas.offset, hp->e.nextexec.bsss.size);
	setsym(fp, hp->e.nextexec.symc.nsyms, hp->e.nextexec.symc.spoff, hp->e.nextexec.symc.pcoff,
					hp->e.nextexec.symc.symoff);
	fp->hdrsz = 0;		/* header stripped */
	return 1;
}

static Shdr*
elfsectbyname(int fd, Ehdr *hp, Shdr *sp, char *name)
{
	int i, offset, n;
	char s[64];

	offset = sp[hp->shstrndx].offset;
	for(i = 1; i < hp->shnum; i++) {
		seek(fd, offset+sp[i].name, 0);
		n = read(fd, s, sizeof(s)-1);
		if(n < 0)
			continue;
		s[n] = 0;
		if(strcmp(s, name) == 0)
			return &sp[i]; 
	}
	return 0;
}
/*
 *	Decode an Irix 5.x ELF header
 */
static int
elfdotout(int fd, Fhdr *fp, ExecHdr *hp)
{

	Ehdr *ep;
	Shdr *es, *txt, *init, *s;
	long addr, size, offset, bsize;

	ep = &hp->e.ehdr;
	fp->magic = ELF_MAG;
	fp->hdrsz = (ep->ehsize+ep->phnum*ep->phentsize+16)&~15;

	if(ep->shnum <= 0) {
		werrstr("no ELF header sections");
		return 0;
	}
	es = malloc(sizeof(Shdr)*ep->shnum);
	if(es == 0)
		return 0;

	seek(fd, ep->shoff, 0);
	if(read(fd, es, sizeof(Shdr)*ep->shnum) < 0){
		free(es);
		return 0;
	}

	txt = elfsectbyname(fd, ep, es, ".text");
	init = elfsectbyname(fd, ep, es, ".init");
	if(txt == 0 || init == 0 || init != txt+1)
		goto bad;
	if(txt->addr+txt->size != init->addr)
		goto bad;
	settext(fp, ep->elfentry, txt->addr, txt->size+init->size, txt->offset);

	addr = 0;
	offset = 0;
	size = 0;
	s = elfsectbyname(fd, ep, es, ".data");
	if(s) {
		addr = s->addr;
		size = s->size;
		offset = s->offset;
	}

	s = elfsectbyname(fd, ep, es, ".rodata");
	if(s) {
		if(addr){
			if(addr+size != s->addr)
				goto bad;
		} else {
			addr = s->addr;
			offset = s->offset;
		}
		size += s->size;
	}

	s = elfsectbyname(fd, ep, es, ".got");
	if(s) {
		if(addr){
			if(addr+size != s->addr)
				goto bad;
		} else {
			addr = s->addr;
			offset = s->offset;
		}
		size += s->size;
	}

	bsize = 0;
	s = elfsectbyname(fd, ep, es, ".bss");
	if(s) {
		if(addr){
			if(addr+size != s->addr)
				goto bad;
		} else {
			addr = s->addr;
			offset = s->offset;
		}
		bsize = s->size;
	}

	if(addr == 0)
		goto bad;

	setdata(fp, addr, size, offset, bsize);
	fp->name = "IRIX Elf a.out executable";
	free(es);
	return 1;
bad:
	free(es);
	werrstr("ELF sections scrambled");
	return 0;
}

/*
 * (Free|Net)BSD ARM header.
 */
static int
armdotout(int fd, Fhdr *fp, ExecHdr *hp)
{
	long kbase;

	USED(fd);
	settext(fp, hp->e.exec.entry, sizeof(Exec), hp->e.exec.text, sizeof(Exec));
	setdata(fp, fp->txtsz, hp->e.exec.data, fp->txtsz, hp->e.exec.bss);
	setsym(fp, hp->e.exec.syms, hp->e.exec.spsz, hp->e.exec.pcsz, fp->datoff+fp->datsz);

	kbase = 0xF0000000;
	if ((fp->entry & kbase) == kbase) {		/* Boot image */
		fp->txtaddr = kbase+sizeof(Exec);
		fp->name = "ARM *BSD boot image";
		fp->hdrsz = 0;		/* header stripped */
		fp->dataddr = kbase+fp->txtsz;
	}
	return 1;
}

static void
settext(Fhdr *fp, long e, long a, long s, long off)
{
	fp->txtaddr = a;
	fp->entry = e;
	fp->txtsz = s;
	fp->txtoff = off;
}
static void
setdata(Fhdr *fp, long a, long s, long off, long bss)
{
	fp->dataddr = a;
	fp->datsz = s;
	fp->datoff = off;
	fp->bsssz = bss;
}
static void
setsym(Fhdr *fp, long sy, long sppc, long lnpc, long symoff)
{
	fp->symsz = sy;
	fp->symoff = symoff;
	fp->sppcsz = sppc;
	fp->sppcoff = fp->symoff+fp->symsz;
	fp->lnpcsz = lnpc;
	fp->lnpcoff = fp->sppcoff+fp->sppcsz;
}


static long
_round(long a, long b)
{
	long w;

	w = (a/b)*b;
	if (a!=w)
		w += b;
	return(w);
}
