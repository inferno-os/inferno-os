#define Unknown win_Unknown
#include	<windows.h>
#undef Unknown
#include	"dat.h"
#include	"fns.h"
#include	"error.h"

#include	"keyboard.h"
#include	"cursor.h"
#include	"ieplugin.h"

/*
 * image channel descriptors - copied from draw.h as it clashes with windows.h on many things
 */
enum {
	CRed = 0,
	CGreen,
	CBlue,
	CGrey,
	CAlpha,
	CMap,
	CIgnore,
	NChan,
};

#define __DC(type, nbits)	((((type)&15)<<4)|((nbits)&15))
#define CHAN1(a,b)	__DC(a,b)
#define CHAN2(a,b,c,d)	(CHAN1((a),(b))<<8|__DC((c),(d)))
#define CHAN3(a,b,c,d,e,f)	(CHAN2((a),(b),(c),(d))<<8|__DC((e),(f)))
#define CHAN4(a,b,c,d,e,f,g,h)	(CHAN3((a),(b),(c),(d),(e),(f))<<8|__DC((g),(h)))

#define NBITS(c) ((c)&15)
#define TYPE(c) (((c)>>4)&15)

enum {
	GREY1	= CHAN1(CGrey, 1),
	GREY2	= CHAN1(CGrey, 2),
	GREY4	= CHAN1(CGrey, 4),
	GREY8	= CHAN1(CGrey, 8),
	CMAP8	= CHAN1(CMap, 8),
	RGB15	= CHAN4(CIgnore, 1, CRed, 5, CGreen, 5, CBlue, 5),
	RGB16	= CHAN3(CRed, 5, CGreen, 6, CBlue, 5),
	RGB24	= CHAN3(CRed, 8, CGreen, 8, CBlue, 8),
	RGBA32	= CHAN4(CRed, 8, CGreen, 8, CBlue, 8, CAlpha, 8),
	ARGB32	= CHAN4(CAlpha, 8, CRed, 8, CGreen, 8, CBlue, 8),	/* stupid VGAs */
	XRGB32  = CHAN4(CIgnore, 8, CRed, 8, CGreen, 8, CBlue, 8),
};

extern ulong displaychan;

extern void drawend(void);

extern	int	chantodepth(ulong);
extern	int	main(int argc, char **argv);
static	void	dprint(char*, ...);
static	DWORD WINAPI	winproc(LPVOID);

static	HINSTANCE	inst;
static	HINSTANCE	previnst;
static	int		attached;
static	ulong	*data;

extern	DWORD	PlatformId;
char*	gkscanid = "emu_win32vk";

extern int cflag;
Plugin *plugin = NULL;

DWORD WINAPI
pluginproc(LPVOID p)
{
	int x, y, b;

	for (;;) {
		WaitForSingleObject(plugin->dopop, INFINITE);
		switch (POP.op) {
		case Pgfxkey:
			if(gkbdq != nil)
				gkbdputc(gkbdq, POP.u.key);
			break;
		case Pmouse:
			x = POP.u.m.x;
			y = POP.u.m.y;
			b = POP.u.m.b;
			mousetrack(b, x, y, 0);
			break;
		}
		SetEvent(plugin->popdone);
	}
}

int WINAPI
WinMain(HINSTANCE winst, HINSTANCE wprevinst, LPSTR cmdline, int wcmdshow)
{
	HANDLE sharedmem;
	uint pid = _getpid();
	char iname[16];
	inst = winst;
	previnst = wprevinst;
	sprint(iname, "%uX", pid);
	sharedmem = OpenFileMapping(FILE_MAP_WRITE, FALSE, iname);
	if (sharedmem != NULL)
		plugin = MapViewOfFile(sharedmem, FILE_MAP_WRITE, 0, 0, 0);
	if (plugin != NULL) {
		DWORD tid;
		int i;
		Xsize = plugin->Xsize;
		Ysize = plugin->Ysize;
		displaychan = plugin->cdesc;
		cflag = plugin->cflag;
		for (i = 0; i < PI_NCLOSE; i++)
			CloseHandle(plugin->closehandles[i]);
		CreateThread(0, 0, pluginproc, 0, 0, &tid);
	
		/* cmdline passed into WinMain does not contain name of executable.
		 * The globals __argc and __argv to include this info - like UNIX
		 */
		main(__argc, __argv);
		UnmapViewOfFile(plugin);
		plugin = NULL;
	}
	if (sharedmem != NULL)
		CloseHandle(sharedmem);
	return 0;
}

static Lock ioplock;

void
newiop()
{
	lock(&ioplock);
}

int
sendiop()
{
	int val;
	SetEvent(plugin->doiop);
	WaitForSingleObject(plugin->iopdone, INFINITE);
	val = plugin->iop.val;
	unlock(&ioplock);
	return val;
}

void
dprint(char *fmt, ...)
{
	va_list arg;
	char buf[128];

	va_start(arg, fmt);
	vseprint(buf, buf+sizeof(buf), fmt, (LPSTR)arg);
	va_end(arg);
	OutputDebugString("inferno: ");
	OutputDebugString(buf);
}

uchar*
attachscreen(IRectangle *r, ulong *chan, int *d, int *width, int *softscreen)
{
	int k;

	if (!attached) {
		newiop();
		IOP.op = Iattachscr;
		if (sendiop() != 0)
			return nil;
		data = plugin->screen;
		attached = 1;
	}
	r->min.x = 0;
	r->min.y = 0;
	r->max.x = Xsize;
	r->max.y = Ysize;

	if(displaychan == 0)
		displaychan = CMAP8;
	*chan = displaychan;

	k = chantodepth(displaychan);
	*d = k;
	*width = (Xsize/4)*(k/8);
	*softscreen = 1;
	return (uchar*)data;
}

void
flushmemscreen(IRectangle r)
{
	if(r.max.x<=r.min.x || r.max.y<=r.min.y)
		return;
	newiop();
	IOP.op = Iflushscr;
	IOP.u.r = r;
	sendiop();
}

void
setpointer(int x, int y)
{
	USED(x); USED(y);
	// TODO
}

void
drawcursor(Drawcursor* c)
{
	USED(c);
	// TODO
}

char*
clipread(void)
{
	return nil;
}

int
clipwrite(char *p)
{
	USED(p);
	return -1;
}
