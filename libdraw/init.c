#include "lib9.h"
#include "draw.h"
#include "kernel.h"
#include "interp.h"

int	_drawdebug;

enum {
	CHECKLOCKING = 0
};

/*
 * Attach, or possibly reattach, to window.
 * If reattaching, maintain value of screen pointer.
 */
int
gengetwindow(Display *d, char *winname, Image **winp, Screen **scrp, int ref)
{
	int n, fd;
	char buf[64+1];
	Image *image;

	fd = libopen(winname, OREAD);
	if(fd<0 || (n=libread(fd, buf, sizeof buf-1))<=0){
		*winp = d->image;
		assert(*winp && (*winp)->chan != 0);
		return 1;
	}
	libclose(fd);
	buf[n] = '\0';
	if(*winp != nil){
		_freeimage1(*winp);
		freeimage((*scrp)->image);
		freescreen(*scrp);
		*scrp = nil;
	}
	image = namedimage(d, buf);
	if(image == 0){
		*winp = nil;
		return -1;
	}
	assert(image->chan != 0);

	*scrp = allocscreen(image, d->white, 0);
	if(*scrp == nil){
		*winp = nil;
		return -1;
	}

	*winp = _allocwindow(*winp, *scrp, insetrect(image->r, Borderwidth), ref, DWhite);
	if(*winp == nil)
		return -1;
	assert((*winp)->chan != 0);
	return 1;
}

#define	NINFO	12*12

Display*
initdisplay(char *dev, char *win, void(*error)(Display*, char*))
{
	char buf[128], info[NINFO+1], *t;
	int datafd, ctlfd, reffd;
	Display *disp;
	Image *image;
	Dir *dir;
	void *q;
	ulong chan;

	fmtinstall('P', Pfmt);
	fmtinstall('R', Rfmt);
	if(dev == 0)
		dev = "/dev";
	if(win == 0)
		win = "/dev";
	if(strlen(dev)>sizeof buf-25 || strlen(win)>sizeof buf-25){
		kwerrstr("initdisplay: directory name too long");
		return nil;
	}
	t = strdup(win);
	if(t == nil)
		return nil;

	q = libqlalloc();
	if(q == nil)
		return nil;

	sprint(buf, "%s/draw/new", dev);
	ctlfd = libopen(buf, ORDWR);
	if(ctlfd < 0){
		if(libbind("#i", dev, MBEFORE) < 0){
    Error1:
			libqlfree(q);
			free(t);
			kwerrstr("initdisplay: %s: %r", buf);
			return 0;
		}
		ctlfd = libopen(buf, ORDWR);
	}
	if(ctlfd < 0)
		goto Error1;
	if(libread(ctlfd, info, sizeof info) < NINFO){
    Error2:
		libclose(ctlfd);
		goto Error1;
	}

	if((chan=strtochan(info+2*12)) == 0){
		kwerrstr("bad channel in %s", buf);
		goto Error2;
	}

	sprint(buf, "%s/draw/%d/data", dev, atoi(info+0*12));
	datafd = libopen(buf, ORDWR);
	if(datafd < 0)
		goto Error2;
	sprint(buf, "%s/draw/%d/refresh", dev, atoi(info+0*12));
	reffd = libopen(buf, OREAD);
	if(reffd < 0){
    Error3:
		libclose(datafd);
		goto Error2;
	}
	strcpy(buf, "allocation failed");
	disp = malloc(sizeof(Display));
	if(disp == 0){
    Error4:
		libclose(reffd);
		goto Error3;
	}
	image = malloc(sizeof(Image));
	if(image == 0){
    Error5:
		free(disp);
		goto Error4;
	}
	memset(image, 0, sizeof(Image));
	memset(disp, 0, sizeof(Display));
	image->display = disp;
	image->id = 0;
	image->chan = chan;
	image->depth = chantodepth(chan);
	image->repl = atoi(info+3*12);
	image->r.min.x = atoi(info+4*12);
	image->r.min.y = atoi(info+5*12);
	image->r.max.x = atoi(info+6*12);
	image->r.max.y = atoi(info+7*12);
	image->clipr.min.x = atoi(info+8*12);
	image->clipr.min.y = atoi(info+9*12);
	image->clipr.max.x = atoi(info+10*12);
	image->clipr.max.y = atoi(info+11*12);
	disp->dirno = atoi(info+0*12);
	disp->datachan = libfdtochan(datafd, ORDWR);
	disp->refchan = libfdtochan(reffd, OREAD);
	disp->ctlchan = libfdtochan(ctlfd, ORDWR);
	if(disp->datachan == nil || disp->refchan == nil || disp->ctlchan == nil)
		goto Error4;
	disp->bufsize = Displaybufsize;	/* TO DO: iounit(datafd) */
	if(disp->bufsize <= 0)
		disp->bufsize = Displaybufsize;
	if(disp->bufsize < 512){
		kwerrstr("iounit %d too small", disp->bufsize);
		goto Error5;
	}
	/* TO DO: allocate buffer */

	libclose(datafd);
	libclose(reffd);
	disp->image = image;
	disp->bufp = disp->buf;
	disp->error = error;
	disp->chan = image->chan;
	disp->depth = image->depth;
	disp->windir = t;
	disp->devdir = strdup(dev);
	disp->qlock = q;
	libqlock(q);
	disp->white = allocimage(disp, Rect(0, 0, 1, 1), GREY1, 1, DWhite);
	disp->black = allocimage(disp, Rect(0, 0, 1, 1), GREY1, 1, DBlack);
	disp->opaque = allocimage(disp, Rect(0, 0, 1, 1), GREY1, 1, DWhite);
	disp->transparent = allocimage(disp, Rect(0, 0, 1, 1), GREY1, 1, DBlack);
	if(disp->white == nil || disp->black == nil || disp->opaque == nil || disp->transparent == nil){
		free(image);
		free(disp->devdir);
		free(disp->white);
		free(disp->black);
		libclose(ctlfd);
		goto Error5;
	}
	if((dir = libdirfstat(ctlfd))!=nil && dir->type=='i'){
		disp->local = 1;
		disp->dataqid = dir->qid.path;
	}
	free(dir);
	libclose(ctlfd);

	if(CHECKLOCKING)
		disp->local = 0;	/* force display locking even for local access */

	assert(disp->chan != 0 && image->chan != 0);
	return disp;
}

/*
 * Call with d unlocked.
 * Note that disp->defaultfont and defaultsubfont are not freed here.
 */
void
closedisplay(Display *disp)
{
	int fd;
	char buf[128];

	if(disp == nil)
		return;
	libqlock(disp->qlock);
	if(disp->oldlabel[0]){
		snprint(buf, sizeof buf, "%s/label", disp->windir);
		fd = libopen(buf, OWRITE);
		if(fd >= 0){
			libwrite(fd, disp->oldlabel, strlen(disp->oldlabel));
			libclose(fd);
		}
	}

	free(disp->devdir);
	free(disp->windir);
	freeimage(disp->white);
	freeimage(disp->black);
	freeimage(disp->opaque);
	freeimage(disp->transparent);
	free(disp->image);
	libchanclose(disp->datachan);
	libchanclose(disp->refchan);
	libchanclose(disp->ctlchan);
	/* should cause refresh slave to shut down */
	libqunlock(disp->qlock);
	libqlfree(disp->qlock);
	free(disp);
}

int
lockdisplay(Display *disp)
{
	if(disp->local)
		return 0;
	if(libqlowner(disp->qlock) != currun()){
		libqlock(disp->qlock);
		return 1;
	}
	return 0;
}

void
unlockdisplay(Display *disp)
{
	if(disp->local)
		return;
	libqunlock(disp->qlock);
}

/* use static buffer to avoid stack bloat */
int
_drawprint(int fd, char *fmt, ...)
{
	int n;
	va_list arg;
	char buf[128];
//	static QLock l;

//	qlock(&l);
	va_start(arg, fmt);
	vseprint(buf, buf+sizeof buf, fmt, arg);
	va_end(arg);
	n = libwrite(fd, buf, strlen(buf));
//	qunlock(&l);
	return n;
}

#ifdef YYY
void
drawerror(Display *d, char *s)
{
	char err[ERRMAX];

	if(d->error)
		d->error(d, s);
	else{
		err[0] = 0;
		errstr(err, sizeof err);
		_drawprint(2, "draw: %s: %s\n", s, err);
		exits(s);
	}
}

static
int
doflush(Display *d)
{
	int n;

	n = d->bufp-d->buf;
	if(n <= 0)
		return 1;

	if(kchanio(d->datachan, d->buf, n, OWRITE) != n){
		if(_drawdebug)
			_drawprint(2, "flushimage fail: d=%p: %r\n", d); /**/
		d->bufp = d->buf;	/* might as well; chance of continuing */
		return -1;
	}
	d->bufp = d->buf;
	return 1;
}

int
flushimage(Display *d, int visible)
{
	if(visible)
		*d->bufp++ = 'v';	/* one byte always reserved for this */
	return doflush(d);
}

uchar*
bufimage(Display *d, int n)
{
	uchar *p;

	if(n<0 || n>Displaybufsize){
		kwerrstr("bad count in bufimage");
		return 0;
	}
	if(d->bufp+n > d->buf+Displaybufsize)
		if(doflush(d) < 0)
			return 0;
	p = d->bufp;
	d->bufp += n;
	return p;
}

#endif
