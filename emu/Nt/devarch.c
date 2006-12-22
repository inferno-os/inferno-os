/*
 *  platform-specific interface
 */

#define Unknown win_Unknown
#define UNICODE
#include	<windows.h>
#include <winbase.h>
#include	<winsock.h>
#undef Unknown
#include	"dat.h"
#include	"fns.h"
#include	"error.h"


enum{
	Qdir,
	Qarchctl,
	Qcputype,
	Qregquery,
	Qhostmem
};

static
Dirtab archtab[]={
	".",		{Qdir, 0, QTDIR},	0,	0555,
	"archctl",	{Qarchctl, 0},	0,	0444,
	"cputype",	{Qcputype},	0,	0444,
	"regquery",	{Qregquery}, 0,	0666,
	"hostmem",	{Qhostmem},	0,	0444,
};

typedef struct Value Value;
struct Value {
	int	type;
	int	size;
	union {
		ulong	w;
		vlong	q;
		Rune	utf[1];	/* more allocated as required */
		char	data[1];
	};
};

typedef struct Regroot Regroot;
struct Regroot {
	char*	name;
	HKEY	root;
};

static Regroot roots[] = {
	{"HKEY_CLASSES_ROOT", HKEY_CLASSES_ROOT},
	{"HKEY_CURRENT_CONFIG", HKEY_CURRENT_CONFIG},
	{"HKEY_CURRENT_USER", HKEY_CURRENT_USER},
	{"HKEY_LOCAL_MACHINE", HKEY_LOCAL_MACHINE},
	{"HKEY_PERFORMANCE_DATA", HKEY_PERFORMANCE_DATA},
	{"HKEY_USERS", HKEY_USERS},
};

static struct {
	ulong	mhz;
	int ncpu;
	char	cpu[64];
} arch;

static	QLock	reglock;

extern wchar_t	*widen(char*);
static	Value*	getregistry(HKEY, Rune*, Rune*);
static int nprocs(void);

static void
archinit(void)
{
	Value *v;
	char *p;

	v = getregistry(HKEY_LOCAL_MACHINE, L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", L"ProcessorNameString");
	if(v != nil){
		snprint(arch.cpu, sizeof(arch.cpu), "%S", v->utf);
		if((p = strrchr(arch.cpu, ' ')) != nil)
			for(; p >= arch.cpu && *p == ' '; p--)
				*p = '\0';
		free(v);
	}else{
		v = getregistry(HKEY_LOCAL_MACHINE, L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", L"VendorIdentifier");
		if(v != nil){
			snprint(arch.cpu, sizeof(arch.cpu), "%S", v->utf);
			free(v);
		}else
			snprint(arch.cpu, sizeof(arch.cpu), "unknown");
	}
	v = getregistry(HKEY_LOCAL_MACHINE, L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", L"~MHz");
	if(v != nil){
		arch.mhz = v->w;
		free(v);
	}
	arch.ncpu = nprocs();
}

static int
nprocs(void)
{
	int n;
	char *p;
	Rune *r;
	Value *v;
	n = 0;
	for(;;){
		p = smprint("HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\%d", n);
		if(waserror()){
			free(p);
			nexterror();
		}
		r = widen(p);
		free(p);
		v = getregistry(HKEY_LOCAL_MACHINE, r, L"~MHz");
		free(r);
		if(v == nil)
			break;
		free(v);
		n++;
	}
	return n;
}

static Chan*
archattach(char* spec)
{
	return devattach('a', spec);
}

static Walkqid*
archwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, archtab, nelem(archtab), devgen);
}

static int
archstat(Chan* c, uchar *db, int n)
{
	return devstat(c, db, n, archtab, nelem(archtab), devgen);
}

static Chan*
archopen(Chan* c, int omode)
{
	return devopen(c, omode, archtab, nelem(archtab), devgen);
}

static void
archclose(Chan* c)
{
	if((ulong)c->qid.path == Qregquery && c->aux != nil)
		free(c->aux);
}

static long
archread(Chan* c, void* a, long n, vlong offset)
{
	char *p;
	Value *v;
	int i, l;
	MEMORYSTATUS mem;

	switch((ulong)c->qid.path){
	case Qdir:
		return devdirread(c, a, n, archtab, nelem(archtab), devgen);
	case Qarchctl:
	case Qcputype:
		l = 0;
		if((ulong)c->qid.path == Qcputype)
			l = 4;
		p = smalloc(READSTR);
		if(waserror()){
			free(p);
			nexterror();
		}
		snprint(p, READSTR, "cpu %q %lud %d\n", arch.cpu, arch.mhz, arch.ncpu);
		n = readstr(offset, a, n, p+l);
		poperror();
		free(p);
		break;
	case Qregquery:
		v = c->aux;
		if(v == nil)
			return 0;
		p = smalloc(READSTR);
		if(waserror()){
			free(p);
			nexterror();
		}
		switch(v->type){
		case REG_NONE:
			n = readstr(offset, a, n, "nil");
			break;
		case REG_DWORD:
			snprint(p, READSTR, "int %ld", v->w);
			n = readstr(offset, a, n, p);
			break;
#ifdef REG_QWORD
		case REG_QWORD:
			snprint(p, READSTR, "int %lld", v->q);
			n = readstr(offset, a, n, p);
			break;
#endif
		case REG_SZ:
		case REG_EXPAND_SZ:
			if(v->utf[0])
				snprint(p, READSTR, "str %Q", v->utf);
			n = readstr(offset, a, n, p);
			break;
		case REG_MULTI_SZ:
			l = snprint(p, READSTR, "str");
			for(i=0;;){
				l += snprint(p+l, READSTR-l, " %Q", v->utf+i);
				while(v->utf[i++] != 0){
					/* skip */
				}
				if(v->utf[i] == 0)
					break;	/* final terminator */
			}
			n = readstr(offset, a, n, p);
			break;
		case REG_BINARY:
			l = n;
			n = readstr(offset, a, l, "bin");
			if(n >= 3){
				offset -= 3;
				if(offset+l > v->size)
					l = v->size - offset;
				memmove((char*)a+n, v->data+offset, l);
				n += l;
			}
			break;
		default:
			error("unknown registry type");
			n=0;
			break;
		}
		poperror();
		free(p);
		c->aux = nil;
		free(v);
		break;
	case Qhostmem:
		mem.dwLength = sizeof(mem);
		GlobalMemoryStatus(&mem);	/* GlobalMemoryStatusEx isn't on NT */
		p = smalloc(READSTR);
		if(waserror()){
			free(p);
			nexterror();
		}
		snprint(p, READSTR, "load %ld\nphys %lud %lud\nvirt %lud %lud\nswap %lud %lud\n",
			mem.dwMemoryLoad,
			mem.dwAvailPhys, mem.dwTotalPhys, mem.dwAvailVirtual, mem.dwTotalVirtual,
			mem.dwAvailPageFile, mem.dwTotalPageFile);
		n = readstr(offset, a, n, p);
		poperror();
		free(p);
		break;
	default:
		n=0;
		break;
	}
	return n;
}

static long
archwrite(Chan* c, void* a, long n, vlong offset)
{
	Value *v;
	int i;
	Cmdbuf *cb;
	Rune *key, *item;

	if((ulong)c->qid.path != Qregquery)
		error(Eperm);
	USED(offset);
	if(c->aux != nil){
		free(c->aux);
		c->aux = nil;
	}
	cb = parsecmd(a, n);
	if(waserror()){
		free(cb);
		nexterror();
	}
	if(cb->nf < 3)
		error(Ebadctl);
	for(i=0; i<nelem(roots); i++)
		if(strcmp(cb->f[0], roots[i].name) == 0)
			break;
	if(i >= nelem(roots))
		errorf("unknown root: %s", cb->f[0]);
	key = widen(cb->f[1]);
	if(waserror()){
		free(key);
		nexterror();
	}
	item = widen(cb->f[2]);
	if(waserror()){
		free(item);
		nexterror();
	}
	v = getregistry(roots[i].root, key, item);
	if(v == nil)
		error(up->env->errstr);
	c->aux = v;
	poperror();
	free(item);
	poperror();
	free(key);
	poperror();
	free(cb);
	return n;
}

Dev archdevtab = {
	'a',
	"arch",

	archinit,
	archattach,
	archwalk,
	archstat,
	archopen,
	devcreate,
	archclose,
	archread,
	devbread,
	archwrite,
	devbwrite,
	devremove,
	devwstat,
};

static void
regerr(int rc)
{
	Rune err[64];

	FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM,
		0, rc, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
		err, sizeof(err), 0);
	errorf("%S", err);
}

static Value*
getregistry(HKEY root, Rune *keyname, Rune *name)
{
	long res;
	HKEY key;
	DWORD dtype, n;
	void* vp;
	Value *val;

	qlock(&reglock);
	if(waserror()){
		qunlock(&reglock);
		return nil;
	}
	res = RegOpenKey(root, keyname, &key);
	if(res != ERROR_SUCCESS)
		regerr(res);
	if(waserror()){
		RegCloseKey(key);
		nexterror();
	}
	n = 0;
	res = RegQueryValueEx(key, name, NULL, &dtype, NULL, &n);
	if(res != ERROR_SUCCESS)
		regerr(res);
	val = smalloc(sizeof(Value)+n);
	if(waserror()){
		free(val);
		nexterror();
	}
	if(0)
		fprint(2, "%S\\%S: %d %d\n", keyname, name, dtype, n);
	val->type = dtype;
	val->size = n;
	switch(dtype){
	case REG_DWORD:
		vp = &val->w;
		break;
#ifdef REG_QWORD
	case REG_QWORD:
		vp = &val->q;
		break;
#endif
	case REG_SZ:
	case REG_EXPAND_SZ:
	case REG_MULTI_SZ:
		vp = val->utf;
		break;
	case REG_BINARY:
	case REG_NONE:
		vp = val->data;
		break;
	default:
		errorf("unsupported registry type: %d", dtype);
		return nil;	/* for compiler */
	}
	res = RegQueryValueEx(key, name, NULL, NULL, vp, &n);
	if(res != ERROR_SUCCESS)
		regerr(res);
	poperror();
	poperror();
	RegCloseKey(key);
	poperror();
	qunlock(&reglock);
	return val;
}
