#include <u.h>
#include <libc.h>
#include <draw.h>
#include <memdraw.h>
#include <pool.h>

static int invert = 0;

void
main(int argc, char **argv)
{
	Memimage *im, *om;
	char *s;
	ulong ofmt;

	ofmt = 0;
	ARGBEGIN{
	case 'i':
		invert = 1;
		break;
	case 'c':
		s = ARGF();
		if(s==nil)
			break;
		ofmt = strtochan(s);
		if(ofmt == 0){
			fprint(2, "cvbit: bad chan: %s\n", s);
			exits("chan");
		}
		break;
	}ARGEND

	memimageinit();
	im = readmemimage(0);
	if(im == nil){
		fprint(2, "cvbit: can't read image: %r\n");
		exits("read");
	}
	if(ofmt){
		om = allocmemimage(im->r, ofmt);
		if(om == nil){
			fprint(2, "cvbit: can't allocate new image: %r\n");
			exits("alloc");
		}
		memimagedraw(om, om->r, im, im->r.min, nil, ZP, S);
	}else
		om = im;
	if(invert){
		uchar *buf;
		int bpl, y, x;

		bpl = bytesperline(om->r, om->depth);
		buf = malloc(bpl);
		for(y=om->r.min.y; y<om->r.max.y; y++){
			if(unloadmemimage(om, Rpt(Pt(om->r.min.x,y), Pt(om->r.max.x,y+1)), buf, bpl) != bpl){
				fprint(2, "cvbit: can't unload image line\n");
				exits("unload");
			}
			for(x=0; x<bpl; x++)
				buf[x] ^= 0xFF;
			if(loadmemimage(om, Rpt(Pt(om->r.min.x,y), Pt(om->r.max.x,y+1)), buf, bpl) != bpl){
				fprint(2, "cvbit: can't load image line\n");
				exits("load");
			}
		}
	}
	if(writememimage(1, om) < 0){
		fprint(2, "cvbit: can't write image: %r\n");
		exits("write");
	}
	exits(nil);
}

char*
poolname(Pool *p)
{
	USED(p);
	return "none";
}

void
poolsetcompact(Pool *p, void (*f)(void*, void*))
{
	USED(p);
	USED(f);
}
