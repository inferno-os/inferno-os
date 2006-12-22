#include "u.h"
#include "lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

#include "dosfs.h"

typedef struct Type Type;
typedef struct Medium Medium;
typedef struct Mode Mode;

enum {
	Dany		= -1,
	Nmedia		= 16,

	/* DS1 switch options */
	Sflashfs		= 1<<0,	/* take local fs from flash */
	Snotflash		= 1<<1,	/* don't boot from flash */
};

enum {					/* type */
	Tflash,
	Tuart,
	Tether,
	Thard,

	Tany		= -1,
};

enum {					/* flag and name */
	Fnone		= 0x00,

	Fdos		= 0x01,
	Ndos		= 0x00,
	Fboot		= 0x02,
	Nboot		= 0x01,
	Fbootp		= 0x04,
	Nbootp		= 0x02,
	Fflash		= 0x08,
	Fuart		= 0x10,
	NName		= 0x03,

	Fany		= Fbootp|Fboot|Fdos|Fflash|Fuart,

	Fini		= 0x10,
	Fprobe		= 0x80,
};

enum {					/* mode */
	Mauto		= 0x00,
	Mlocal		= 0x01,
	Manual		= 0x02,
	NMode		= 0x03,
};

typedef struct Type {
	int	type;
	char	*cname;
	int	flag;
	int	(*init)(void);
	long	(*read)(int, void*, long);
	long	(*seek)(int, long);
	Partition* (*setpart)(int, char*);
	char*	name[NName];

	int	mask;
	Medium*	media;
} Type;

typedef struct Medium {
	Type*	type;
	int	flag;
	Partition* partition;
	Dos;

	Medium*	next;
} Medium;

typedef struct Mode {
	char*	name;
	int	mode;
} Mode;

static Type types[] = {
	{	Tflash, "flash",
		Fflash,
		flashinit, 0, 0, 0,
		{ 0, "F", 0, }
	},
/*
	{	Tuart, "uart",
		Fuart|Fboot,
		uartinit, uartread, uartseek, setuartpart,
		{ 0, "u", 0, }
	},
*/
	{	Tether, "ether",
		Fbootp,
		etherinit, 0, 0, 0,
		{ 0, 0, "e", },
	},
	{	Thard, "ata",
		Fini|Fboot|Fdos,
		0, 0, 0, 0,		/* not used now, will be later with PCMCIA */
		{ "hd", "h", 0, },
	},
	{-1},
};

static Medium media[Nmedia];
static Medium *curmedium = media;

static Mode modes[NMode+1] = {
	[Mauto]		{ "auto",   Mauto,  },
	[Mlocal]	{ "local",  Mlocal, },
	[Manual]	{ "manual", Manual, },
};

static char *inis[] = {
	"inferno/inferno.ini",
	"inferno.ini",
	"plan9/plan9.ini",
	"plan9.ini",
	0,
};
char **ini;
int	predawn;

static int
parse(char *line, int *type, int *flag, int *dev, char *file)
{
	Type *tp;
	char buf[2*NAMELEN], *v[4], *p;
	int i;

	strcpy(buf, line);
	switch(getcfields(buf, v, 4, "!")){

	case 3:
		break;

	case 2:
		v[2] = "";
		break;

	default:
		return 0;
	}

	*flag = 0;
	for(tp = types; tp->cname; tp++){
		for(i = 0; i < NName; i++){

			if(tp->name[i] == 0 || strcmp(v[0], tp->name[i]))
				continue;
			*type = tp->type;
			*flag |= 1<<i;

			if((*dev = strtoul(v[1], &p, 0)) == 0 && p == v[1])
				return 0;
		
			strcpy(file, v[2]);
		
			return 1;
		}
	}

	return 0;

}

static int
boot(Medium *mp, int flag, char *file)
{
	Dosfile df;
	char ixdos[128], *p;
	int r;

	uartsetboot(0);
	if(flag & Fbootp){
		sprint(BOOTLINE, "%s!%d", mp->type->name[Nbootp], mp->dev);
		return bootp(mp->dev, file);
	}

	if(flag & Fflash){
		if(mp->flag & Fflash && flashbootable(0))
			flashboot(mp->dev);
	}

	if(flag & Fboot){

		if(mp->flag & Fini){
			(*mp->type->setpart)(mp->dev, "disk");
			plan9ini(mp, nil);
		}
		if(file == 0 || *file == 0)
			file = mp->partition->name;
		(*mp->type->setpart)(mp->dev, file);
		sprint(BOOTLINE, "%s!%d!%s", mp->type->name[Nboot], mp->dev, file);
		r = plan9boot(mp->dev, mp->seek, mp->read);
		uartsetboot(0);
		return r;
	}

	if(flag & Fdos){
		if(mp->type->setpart)
			(*mp->type->setpart)(mp->dev, "disk");
		if(mp->flag & Fini)
			plan9ini(mp, nil);
		if(file == 0 || *file == 0){
			strcpy(ixdos, *ini);
			if(p = strrchr(ixdos, '/'))
				p++;
			else
				p = ixdos;
			strcpy(p, "impc");
			if(dosstat(mp, ixdos, &df) <= 0)
				return -1;
		}
		else
			strcpy(ixdos, file);
		sprint(BOOTLINE, "%s!%d!%s", mp->type->name[Ndos], mp->dev, ixdos);
		return dosboot(mp, ixdos);
	}

	return -1;
}

static Medium*
allocm(Type *tp)
{
	Medium **l;

	if(curmedium >= &media[Nmedia])
		return 0;

	for(l = &tp->media; *l; l = &(*l)->next)
		;
	*l = curmedium++;
	return *l;
}

Medium*
probe(int type, int flag, int dev)
{
	Type *tp;
	int dombr, i, start;
	Medium *mp;
	Dosfile df;
	Partition *pp;

	for(tp = types; tp->cname; tp++){
		if(type != Tany && type != tp->type || tp->init == 0)
			continue;

		if(flag != Fnone){
			for(mp = tp->media; mp; mp = mp->next){
				if((flag & mp->flag) && (dev == Dany || dev == mp->dev))
					return mp;
			}
		}
		if((tp->flag & Fprobe) == 0){
			tp->flag |= Fprobe;
			tp->mask = (*tp->init)();
		}

		for(i = 0; tp->mask; i++){
			if((tp->mask & (1<<i)) == 0)
				continue;
			tp->mask &= ~(1<<i);

			if((mp = allocm(tp)) == 0)
				continue;

			mp->dev = i;
			mp->flag = tp->flag;
			mp->seek = tp->seek;
			mp->read = tp->read;
			mp->type = tp;

			if(mp->flag & Fboot){
				if((mp->partition = (*tp->setpart)(i, "boot")) == 0)
					mp->flag &= ~Fboot;
				if((mp->flag & (Fflash|Fuart)) == 0)
					(*tp->setpart)(i, "disk");
			}

			if(mp->flag & Fdos){
				start = 0;
				dombr = 1;
				if(mp->type->setpart){
					if(pp = (*mp->type->setpart)(i, "dos")){
						if(start = pp->start)
							dombr = 0;
					}
					(*tp->setpart)(i, "disk");
				}
				if(dosinit(mp, start, dombr) < 0)
					mp->flag &= ~(Fini|Fdos);
				else
					print("dos init failed\n");
			}

			if(mp->flag & Fini){
				mp->flag &= ~Fini;
				for(ini = inis; *ini; ini++){
					if(dosstat(mp, *ini, &df) <= 0)
						continue;
					mp->flag |= Fini;
					break;
				}
			}

			if((flag & mp->flag) && (dev == Dany || dev == i))
				return mp;
		}
	}

	return 0;
}

void
main(void)
{
	Medium *mp;
	int dev, flag, i, mode, tried, type, options;
	char def[2*NAMELEN], file[2*NAMELEN], line[80], *p;
	Type *tp;

	machinit();
	archinit();
	meminit();
	cpminit();
	trapinit();
	consinit();	/* screen and keyboard initially */
	screeninit();
	cpuidprint();
	alarminit();
	clockinit();
	predawn = 0;
	spllo();
	options = archoptionsw();

	mp = 0;
	for(tp = types; tp->cname; tp++){
		if(tp->type == Tether)
			continue;
		if((mp = probe(tp->type, Fini, Dany)) && (mp->flag & Fini)){
			plan9ini(mp, nil);
			break;
		}
	}

	if(mp == 0 || (mp->flag & Fini) == 0)
		plan9ini(nil, flashconfig(0));

	//consinit();	/* establish new console location */

	if((options & Snotflash) == 0 && flashbootable(0)){
		print("Flash boot\n");
		flashboot(0);
	}

	tried = 0;
	mode = Mauto;
	p = getconf("bootfile");
	flag = 0;

	if(p != 0) {
		mode = Manual;
		for(i = 0; i < NMode; i++){
			if(strcmp(p, modes[i].name) == 0){
				mode = modes[i].mode;
				goto done;
			}
		}
		if(parse(p, &type, &flag, &dev, file) == 0) {
			print("Bad bootfile syntax: %s\n", p);
			goto done;
		}
		mp = probe(type, flag, dev);
		if(mp == 0) {
			print("Cannot access device: %s\n", p);
			goto done;
		}
		tried = boot(mp, flag, file);
	}
done:
	if(tried == 0 && mode != Manual){
		flag = Fany;
		if(mode == Mlocal)
			flag &= ~Fbootp;
		if(options & Snotflash)
			flag &= ~Fflash;
		if((mp = probe(Tany, flag, Dany)) != 0)
			boot(mp, flag & mp->flag, 0);
	}

	def[0] = 0;
	probe(Tany, Fnone, Dany);

	flag = 0;
	for(tp = types; tp->cname; tp++){
		for(mp = tp->media; mp; mp = mp->next){
			if(flag == 0){
				flag = 1;
				print("Boot devices:");
			}

			if(mp->flag & Fbootp)
				print(" %s!%d", mp->type->name[Nbootp], mp->dev);
			if(mp->flag & Fdos)
				print(" %s!%d", mp->type->name[Ndos], mp->dev);
			if(mp->flag & (Fflash|Fuart) || mp->flag & Fboot)
				print(" %s!%d", mp->type->name[Nboot], mp->dev);
		}
	}
	if(flag)
		print("\n");

	for(;;){
		if(getstr("boot from", line, sizeof(line), def) >= 0){
			if(parse(line, &type, &flag, &dev, file)){
				if(mp = probe(type, flag, dev))
					boot(mp, flag, file);
			}
		}
		def[0] = 0;
	}
}

void
machinit(void)
{
	memset(m, 0, sizeof(*m));
	m->delayloop = 20000;
	m->cpupvr = getpvr();
	m->iomem = KADDR(INTMEM);
}

int
getcfields(char* lp, char** fields, int n, char* sep)
{
	int i;

	for(i = 0; lp && *lp && i < n; i++){
		while(*lp && strchr(sep, *lp) != 0)
			*lp++ = 0;
		if(*lp == 0)
			break;
		fields[i] = lp;
		while(*lp && strchr(sep, *lp) == 0){
			if(*lp == '\\' && *(lp+1) == '\n')
				*lp++ = ' ';
			lp++;
		}
	}

	return i;
}

static	Map	memv[512];
static	RMap	rammap = {"physical memory"};

void
meminit(void)
{
	ulong e;

	mapinit(&rammap, memv, sizeof(memv));
	e = PADDR(&end);
	mapfree(&rammap, e, 4*1024*1024-e);	/* fixed 4Mbytes is plenty for bootstrap */
}

void*
ialloc(ulong n, int align)
{
	ulong a;
	int s;

	if(align <= 0)
		align = 4;
	s = splhi();
	a = mapalloc(&rammap, 0, n, align);
	splx(s);
	if(a == 0)
		panic("ialloc");
	return memset(KADDR(a), 0, n);
}

void*
malloc(ulong n)
{
	ulong *p;

	n = ((n+sizeof(int)-1)&~(sizeof(int)-1))+2*sizeof(int);
	p = ialloc(n, sizeof(int));
	*p++ = 0xcafebeef;
	*p++ = n;
	return p;
}

void
free(void *ap)
{
	int s;
	ulong *p;

	p = ap;
	if(p){
		if(*(p -= 2) != 0xcafebeef)
			panic("free");
		s = splhi();
		mapfree(&rammap, (ulong)p, p[1]);
		splx(s);
	}
}

void
sched(void)
{
}
