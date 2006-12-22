#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "../port/error.h"

#include <draw.h>
#include <memdraw.h>
#include <memlayer.h>

enum {
	Width		= 160,
	Height		= 25,

	Attr		= 7,		/* white on black */
};

#define CGASCREENBASE	((uchar*)KADDR(0xB8000))

static int cgapos;
static int screeninitdone;
static Lock cgascreenlock;
void (*vgascreenputc)(char*);

static uchar
cgaregr(int index)
{
	outb(0x3D4, index);
	return inb(0x3D4+1) & 0xFF;
}

static void
cgaregw(int index, int data)
{
	outb(0x3D4, index);
	outb(0x3D4+1, data);
}

static void
movecursor(void)
{
	cgaregw(0x0E, (cgapos/2>>8) & 0xFF);
	cgaregw(0x0F, cgapos/2 & 0xFF);
	CGASCREENBASE[cgapos+1] = Attr;
}

static void
cgascreenputc(int c)
{
	int i;

	if(c == '\n'){
		cgapos = cgapos/Width;
		cgapos = (cgapos+1)*Width;
	}
	else if(c == '\t'){
		i = 8 - ((cgapos/2)&7);
		while(i-->0)
			cgascreenputc(' ');
	}
	else if(c == '\b'){
		if(cgapos >= 2)
			cgapos -= 2;
		cgascreenputc(' ');
		cgapos -= 2;
	}
	else{
		CGASCREENBASE[cgapos++] = c;
		CGASCREENBASE[cgapos++] = Attr;
	}
	if(cgapos >= Width*Height){
		memmove(CGASCREENBASE, &CGASCREENBASE[Width], Width*(Height-1));
		memset(&CGASCREENBASE[Width*(Height-1)], 0, Width);
		cgapos = Width*(Height-1);
	}
	movecursor();
}

void
screeninit(void)
{
	memimageinit();
	cgapos = cgaregr(0x0E)<<8;
	cgapos |= cgaregr(0x0F);
	cgapos *= 2;
	screeninitdone = 1;
}

void
cgascreenputs(char* s, int n)
{
	int i;
	Rune r;
	char buf[4];

	if(!islo()){
		if(!canlock(&cgascreenlock))
			return;
	}
	else
		lock(&cgascreenlock);

	if(vgascreenputc == nil){
		while(n-- > 0)
			cgascreenputc(*s++);
		unlock(&cgascreenlock);
		return;
	}

	while(n > 0) {
		i = chartorune(&r, s);
		if(i == 0){
			s++;
			--n;
			continue;
		}
		memmove(buf, s, i);
		buf[i] = 0;
		n -= i;
		s += i;
		vgascreenputc(buf);
	}

	unlock(&cgascreenlock);
}

void
cursorenable(void)
{
}

void
cursordisable(void)
{
}

typedef struct Drawcursor Drawcursor;



void
cursorupdate(Rectangle r)
{
	USED(r);
}

void
drawcursor(Drawcursor *c)
{
	USED(c);
}

uchar*
attachscreen(Rectangle *r, ulong *chan, int* d, int *width, int *softscreen)
{
	static Rectangle screenr = {0, 0, 0, 0};
	static uchar *bdata;
	if (bdata == nil)
		if ((bdata = malloc(1)) == nil)
			return nil;
	*r = screenr;
	*chan = RGB24;
	*d = chantodepth(RGB24);
	*width = 0;
	*softscreen = 0;
	return bdata;
}

void
flushmemscreen(Rectangle r)
{
	USED(r);
}

void
blankscreen(int i)
{
	USED(i);
}

void
getcolor(ulong p, ulong *pr, ulong *pg, ulong *pb)
{
	USED(p);
	USED(pr);
	USED(pg);
	USED(pb);

}

int
setcolor(ulong p, ulong r, ulong g, ulong b)
{
	USED(p);
	USED(r);
	USED(g);
	USED(b);
	return ~0;
}

void (*screenputs)(char*, int) = cgascreenputs;
