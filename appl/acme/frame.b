implement Framem;

include "common.m";

sys : Sys;
drawm : Draw;
acme : Acme;
gui : Gui;
graph : Graph;
utils : Utils;
textm : Textm;

sprint : import sys;
Point, Rect, Font, Image, Pointer : import drawm;
draw, berror, charwidth, strwidth : import graph;
black, white : import gui;

SLOP : con 25;

noglyphs := array[4] of { 16rFFFD, 16r80, '?', ' ' };

frame : ref Frame;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	drawm = mods.draw;
	acme = mods.acme;
	gui = mods.gui;
	graph = mods.graph;
	utils = mods.utils;
	textm = mods.textm;

	frame = newframe();
}

nullframe : Frame;

newframe() : ref Frame
{
	f := ref nullframe;
	f.cols = array[NCOL] of ref Draw->Image;
	return f;
}

frdump(f : ref Frame)
{
	utils->debug(sprint("nchars=%d\n", f.nchars));
	for (i := 0; i < f.nbox; i++) {
		utils->debug(sprint("box %d : ", i));
		fb := f.box[i];
		if (fb.nrune >= 0)
			utils->debug(sprint("%d %d %s\n", fb.nrune, len fb.ptr, fb.ptr));
		else
			utils->debug(sprint("%d\n", fb.nrune));
	}
}

# debugcheck(f : ref Frame, n : int)
# {
# 	if (f.nchars != xfrstrlen(f, 0)) {
#		utils->debug(sprint("%d : bad frame nchars\n", n));
#		frdump(f);
#		berror("");
#	}
# }
		
xfraddbox(f : ref Frame, bn : int, n : int)		# add n boxes after bn, shift the rest up,
									#  * box[bn+n]==box[bn]
{
	i : int;

	if(bn > f.nbox)
		berror("xfraddbox");
	# bn = f.nbox has same effect as bn = f.nbox-1
	if(f.nbox+n > f.nalloc)
		xfrgrowbox(f, n+SLOP);
	for (i=f.nbox; --i > bn; ) {
		t := f.box[i+n];
		f.box[i+n] = f.box[i];
		f.box[i] = t;
	}
	if (bn < f.nbox)
		*f.box[bn+n] = *f.box[bn];
	f.nbox+=n;
}

xfrclosebox(f : ref Frame, n0 : int, n1 : int)	# inclusive
{
	i: int;

	if(n0>=f.nbox || n1>=f.nbox || n1<n0)
		berror("xfrclosebox");
	n1++;
	for(i=n1; i<f.nbox; i++) {
		t := f.box[i-(n1-n0)];
		f.box[i-(n1-n0)] = f.box[i];
		f.box[i] = t;
	}
	f.nbox -= n1-n0;
}

xfrdelbox(f : ref Frame, n0 : int, n1 : int)		# inclusive
{
	if(n0>=f.nbox || n1>=f.nbox || n1<n0)
		berror("xfrdelbox");
	xfrfreebox(f, n0, n1);
	xfrclosebox(f, n0, n1);
}

xfrfreebox(f : ref Frame, n0 : int, n1 : int)		# inclusive
{
	i : int;

	if(n1<n0)
		return;
	if(n0>=f.nbox || n1>=f.nbox)
		berror("xfrfreebox");
	n1++;
	for(i=n0; i<n1; i++)
		if(f.box[i].nrune >= 0) {
			f.box[i].nrune = 0;
			f.box[i].ptr = nil;
		}
}

nilfrbox : Frbox;

xfrgrowbox(f : ref Frame, delta : int)
{
	ofb := f.box;
	f.box = array[f.nalloc+delta] of ref Frbox;
	if(f.box == nil)
		berror("xfrgrowbox");
	f.box[0:] = ofb[0:f.nalloc];
	for (i := 0; i < delta; i++)
		f.box[i+f.nalloc] = ref nilfrbox;
	f.nalloc += delta;
	ofb = nil;
}

dupbox(f : ref Frame, bn : int)
{
	if(f.box[bn].nrune < 0)
		berror("dupbox");
	xfraddbox(f, bn, 1);
	if(f.box[bn].nrune >= 0) {
		f.box[bn+1].nrune = f.box[bn].nrune;
		f.box[bn+1].ptr = f.box[bn].ptr;
	}
}

truncatebox(f : ref Frame, b : ref Frbox, n : int)	# drop last n chars; no allocation done
{
	if(b.nrune<0 || b.nrune<n)
		berror("truncatebox");
	b.nrune -= n;
	b.ptr = b.ptr[0:b.nrune];
	b.wid = strwidth(f.font, b.ptr);
}

chopbox(f : ref Frame, b : ref Frbox, n : int)	# drop first n chars; no allocation done
{
	if(b.nrune<0 || b.nrune<n)
		berror("chopbox");
	b.nrune -= n;
	b.ptr = b.ptr[n:];
	b.wid = strwidth(f.font, b.ptr);
}

xfrsplitbox(f : ref Frame, bn : int, n : int)
{
	dupbox(f, bn);
	truncatebox(f, f.box[bn], f.box[bn].nrune-n);
	chopbox(f, f.box[bn+1], n);
}

xfrmergebox(f : ref Frame, bn : int)		# merge bn and bn+1
{
	b0 := f.box[bn];
	b1 := f.box[bn+1];
	b0.ptr += b1.ptr;
	b0.wid += b1.wid;
	b0.nrune += b1.nrune;
	xfrdelbox(f, bn+1, bn+1);
}

xfrfindbox(f : ref Frame, bn : int, p : int, q : int) : int	# find box containing q and put q on a box boundary
{
	nrune : int;

	for( ; bn < f.nbox; bn++) {
		nrune = 1;
		b := f.box[bn];
# if (b.nrune >= 0 && len b.ptr != b.nrune) {
#	frdump(f);
#	berror(sprint("findbox %d %d %d\n", bn, p, q));
# }
		if(b.nrune >= 0)
			nrune = b.nrune;
		if(p+nrune > q)
			break; 
		p += nrune;
	}
	if(p != q)
		xfrsplitbox(f, bn++, q-p);
	return bn;
}

frdelete(f : ref Frame, p0 : int, p1 : int) : int
{
	pt0, pt1, ppt0 : Point;
	n0, n1, n, s : int;
	r : Rect;
	nn0 : int;
	col : ref Image;

	if(p0 >= f.nchars || p0 == p1 || f.b == nil)
		return 0;
	if(p1 > f.nchars)
		p1 = f.nchars;
	n0 = xfrfindbox(f, 0, 0, p0);
	if(n0 == f.nbox)
		berror("off end in frdelete");
	n1 = xfrfindbox(f, n0, p0, p1);
	pt0 = xfrptofcharnb(f, p0, n0);
	pt1 = frptofchar(f, p1);
	if(f.p0 == f.p1)
		frtick(f, frptofchar(f, f.p0), 0);
	nn0 = n0;
	ppt0 = pt0;
	xfrfreebox(f, n0, n1-1);
	f.modified = 1;

	#
	# Invariants:
	#  pt0 points to beginning, pt1 points to end
	#  n0 is box containing beginning of stuff being deleted
	#  n1, b are box containing beginning of stuff to be kept after deletion
	# cn1 is char position of n1
	# f.p0 and f.p1 are not adjusted until after all deletion is done
	#  region between pt0 and pt1 is clear
	#
	cn1 := p1;
	while(pt1.x!=pt0.x && n1<f.nbox){
		b := f.box[n1];
		pt0 = xfrcklinewrap0(f, pt0, b);
		pt1 = xfrcklinewrap(f, pt1, b);
		n = xfrcanfit(f, pt0, b);
		if(n==0)
			berror("xfrcanfit==0");
		r.min = pt0;
		r.max = pt0;
		r.max.y += f.font.height;
		if(b.nrune > 0){
			if(n != b.nrune){
				xfrsplitbox(f, n1, n);
				b = f.box[n1];
			}
			r.max.x += b.wid;
			draw(f.b, r, f.b, nil, pt1);
			cn1 += b.nrune;
		}
		else{
			r.max.x += xfrnewwid0(f, pt0, b);
			if(r.max.x > f.r.max.x)
				r.max.x = f.r.max.x;
			col = f.cols[BACK];
			if(f.p0<=cn1 && cn1<f.p1)
				col = f.cols[HIGH];
			draw(f.b, r, col, nil, pt0);
			cn1++;
		}
		pt1 = xfradvance(f, pt1, b);
		pt0.x += xfrnewwid(f, pt0, b);
		*f.box[n0++] = *f.box[n1++];
	}
	if(n1==f.nbox && pt0.x!=pt1.x)	# deleting last thing in window; must clean up
		frselectpaint(f, pt0, pt1, f.cols[BACK]);
	if(pt1.y != pt0.y){
		pt2 : Point;

		pt2 = xfrptofcharptb(f, 32767, pt1, n1);
		if(pt2.y > f.r.max.y)
			berror("frptofchar in frdelete");
		if(n1 < f.nbox){
			q0, q1, q2 : int;

			q0 = pt0.y+f.font.height;
			q1 = pt1.y+f.font.height;
			q2 = pt2.y+f.font.height;
			# rob: before was just q2 = pt1.y+f.font.height;
			# q2 = pt2.y;
			if(q2 > f.r.max.y)
				q2 = f.r.max.y;
			draw(f.b, (pt0, (pt0.x+(f.r.max.x-pt1.x), q0)),
				f.b, nil, pt1);
			draw(f.b, ((f.r.min.x, q0), (f.r.max.x, q0+(q2-q1))),
				f.b, nil, (f.r.min.x, q1));
			frselectpaint(f, (pt2.x, pt2.y-(pt1.y-pt0.y)), pt2, f.cols[BACK]);
		}else
			frselectpaint(f, pt0, pt2, f.cols[BACK]);
	}
	xfrclosebox(f, n0, n1-1);
	if(nn0>0 && f.box[nn0-1].nrune>=0 && ppt0.x-f.box[nn0-1].wid>=f.r.min.x){
		--nn0;
		ppt0.x -= f.box[nn0].wid;
	}
	s = n0;
	if(n0 < f.nbox-1)
		s++;
	xfrclean(f, ppt0, nn0, s);
	if(f.p1 > p1)
		f.p1 -= p1-p0;
	else if(f.p1 > p0)
		f.p1 = p0;
	if(f.p0 > p1)
		f.p0 -= p1-p0;
	else if(f.p0 > p0)
		f.p0 = p0;
	f.nchars -= p1-p0;
	if(f.p0 == f.p1)
		frtick(f, frptofchar(f, f.p0), 1);
	pt0 = frptofchar(f, f.nchars);
	n = f.nlines;
	f.nlines = (pt0.y-f.r.min.y)/f.font.height+(pt0.x>f.r.min.x);
	return n - f.nlines;
}

xfrredraw(f : ref Frame, pt : Point)
{
	nb : int;

	for(nb = 0; nb < f.nbox; nb++) {
		b := f.box[nb];
		pt = xfrcklinewrap(f, pt, b);
		if(b.nrune >= 0)
			graph->stringx(f.b, pt, f.font, b.ptr, f.cols[TEXT]);
		pt.x += b.wid;
	}
}

frdrawsel(f : ref Frame, pt : Point, p0 : int, p1 : int, issel : int)
{
	back, text : ref Image;

	if(f.ticked)
		frtick(f, frptofchar(f, f.p0), 0);
	if(p0 == p1){
		frtick(f, pt, issel);
		return;
	}
	if(issel){
		back = f.cols[HIGH];
		text = f.cols[HTEXT];
	}else{
		back = f.cols[BACK];
		text = f.cols[TEXT];
	}
	frdrawsel0(f, pt, p0, p1, back, text);
}

frdrawsel0(f : ref Frame, pt : Point, p0 : int, p1 : int, back : ref Image, text : ref Image)
{
	b : ref Frbox;
	nb, nr, w, x, trim : int;
	qt : Point;
	p : int;
	ptr : string;

	p = 0;
	trim = 0;
	for(nb=0; nb<f.nbox && p<p1; nb++){
		b = f.box[nb];
		nr = b.nrune;
		if(nr < 0)
			nr = 1;
		if(p+nr <= p0){
			p += nr;
			continue;
		}
		if(p >= p0){
			qt = pt;
			pt = xfrcklinewrap(f, pt, b);
			if(pt.y > qt.y)
				draw(f.b, (qt, (f.r.max.x, pt.y)), back, nil, qt);
		}
		ptr = b.ptr;
		if(p < p0){		# beginning of region: advance into box
			ptr = ptr[p0-p:];
			nr -= (p0-p);
			p = p0;
		}
		trim = 0;
		if(p+nr > p1){	# end of region: trim box
			nr -= (p+nr)-p1;
			trim = 1;
		}
		if(b.nrune<0 || nr==b.nrune)
			w = b.wid;
		else
			w = strwidth(f.font, ptr[0:nr]);
		x = pt.x+w;
		if(x > f.r.max.x)
			x = f.r.max.x;
		draw(f.b, (pt, (x, pt.y+f.font.height)), back, nil, pt);
		if(b.nrune >= 0)
			graph->stringx(f.b, pt, f.font, ptr[0:nr], text);
		pt.x += w;
		p += nr;
	}
	# if this is end of last plain text box on wrapped line, fill to end of line
	if(p1>p0 &&  nb>0 && nb<f.nbox && f.box[nb-1].nrune>0 && !trim){
		qt = pt;
		pt = xfrcklinewrap(f, pt, f.box[nb]);
		if(pt.y > qt.y)
			draw(f.b, (qt, (f.r.max.x, pt.y)), back, nil, qt);
	}
}

frtick(f : ref Frame, pt : Point, ticked : int)
{
	r : Rect;

	if(f.ticked==ticked || f.tick==nil || !pt.in(f.r))
		return;
	pt.x--;	# looks best just left of where requested
	r = (pt, (pt.x+FRTICKW, pt.y+f.font.height));
	if(ticked){
		draw(f.tickback, f.tickback.r, f.b, nil, pt);
		draw(f.b, r, f.tick, nil, (0, 0));
	}else
		draw(f.b, r, f.tickback, nil, (0, 0));
	f.ticked = ticked;
}

xfrdraw(f : ref Frame, pt : Point) : Point
{
	nb, n : int;

	for(nb=0; nb < f.nbox; nb++){
		b := f.box[nb];
		pt = xfrcklinewrap0(f, pt, b);
		if(pt.y == f.r.max.y){
			f.nchars -= xfrstrlen(f, nb);
			xfrdelbox(f, nb, f.nbox-1);
			break;
		}
		if(b.nrune > 0){
			n = xfrcanfit(f, pt, b);
			if(n == 0)
				berror("draw: xfrcanfit==0");
			if(n != b.nrune){
				xfrsplitbox(f, nb, n);
				b = f.box[nb];
			}
			pt.x += b.wid;
		}else{
			if(b.bc == '\n') {
				pt.x = f.r.min.x;
				pt.y += f.font.height;
			}
			else
				pt.x += xfrnewwid(f, pt, b);
		}
	}
	return pt;
}

xfrstrlen(f : ref Frame, nb : int) : int
{
	n, nrune : int;

	for(n=0; nb<f.nbox; nb++) {
		nrune = f.box[nb].nrune;
		if(nrune < 0)
			nrune = 1;
		n += nrune;
	}
	return n;
}

frinit(f : ref Frame, r : Rect, ft : ref Font, b : ref Image, cols : array of ref Draw->Image)
{
	f.font = ft;
	f.scroll = 0;
	f.maxtab = 8*charwidth(ft, '0');
	f.nbox = 0;
	f.nalloc = 0;
	f.nchars = 0;
	f.nlines = 0;
	f.p0 = 0;
	f.p1 = 0;
	f.box = nil;
	f.lastlinefull = 0;
	if(cols != nil)
		for(i := 0; i < NCOL; i++)
			f.cols[i] = cols[i];
	for (i = 0; i < len noglyphs; i++) {
		if (charwidth(ft, noglyphs[i]) != 0) {
			f.noglyph = noglyphs[i];
			break;
		}
	}
	frsetrects(f, r, b);
	if (f.tick==nil && f.cols[BACK] != nil)
		frinittick(f);
}

frinittick(f : ref Frame)
{
	ft : ref Font;

	ft = f.font;
	f.tick = nil;
	f.tick = graph->balloc(((0, 0), (FRTICKW, ft.height)), (gui->mainwin).chans, Draw->White);
	if(f.tick == nil)
		return;
	f.tickback = graph->balloc(f.tick.r, (gui->mainwin).chans, Draw->White);
	if(f.tickback == nil){
		f.tick = nil;
		return;
	}
	# background color
	draw(f.tick, f.tick.r, f.cols[BACK], nil, (0, 0));
	# vertical line
	draw(f.tick, ((FRTICKW/2, 0), (FRTICKW/2+1, ft.height)), black, nil, (0, 0));
	# box on each end
	# draw(f->tick, Rect(0, 0, FRTICKW, FRTICKW), f->cols[TEXT], nil, ZP);
	# draw(f->tick, Rect(0, ft->height-FRTICKW, FRTICKW, ft->height), f->cols[TEXT], nil, ZP);
}

frsetrects(f : ref Frame, r : Rect, b : ref Image)
{
	f.b = b;
	f.entire = r;
	f.r = r;
	f.r.max.y -= (r.max.y-r.min.y)%f.font.height;
	f.maxlines = (r.max.y-r.min.y)/f.font.height;
}

frclear(f : ref Frame, freeall : int)
{
	if(f.nbox)
		xfrdelbox(f, 0, f.nbox-1);
	for (i := 0; i < f.nalloc; i++)
		f.box[i] = nil;
	if(freeall)
		f.tick = f.tickback = nil;
	f.box = nil;
	f.ticked = 0;
}

DELTA : con 25;
TMPSIZE : con 256;

Plist : adt {
	pt0 : Point;
	pt1 : Point;
};

nalloc : int = 0;
pts : array of Plist;

bxscan(f : ref Frame, rp : string, l : int, ppt : Point) : (Point, Point)
{
	w, c, nb, delta, nl, nr : int;
	sp : int = 0;

	frame.r = f.r;
	frame.b = f.b;
	frame.font = f.font;
	frame.maxtab = f.maxtab;
	frame.nbox = 0;
	frame.nchars = 0;
	for(i := 0; i < NCOL; i++)
		frame.cols[i] = f.cols[i];
	frame.noglyph = f.noglyph;
	delta = DELTA;
	nl = 0;
	for(nb=0; sp<l && nl <= f.maxlines; nb++){
		if(nb == frame.nalloc){
			xfrgrowbox(frame, delta);
			if(delta < 10000)
				delta *= 2;
		}
		b := frame.box[nb];
		c = rp[sp];
		if(c=='\t' || c=='\n'){
			b.bc = c;
			b.wid = 5000;
			if(c == '\n')
				b.minwid = 0;
			else
				b.minwid = charwidth(frame.font, ' ');
			b.nrune = -1;
			if(c=='\n')
				nl++;
			frame.nchars++;
			sp++;
		}else{
			nr = 0;
			w = 0;
			ssp := sp;
			nul := 0;
			while(sp < l){
				c = rp[sp];
				if(c=='\t' || c=='\n')
					break;
				if(nr+1 >= TMPSIZE)
					break;
				if ((cw := charwidth(frame.font, c)) == 0) {	# used to be only for c == 0
					c = frame.noglyph;
					cw = charwidth(frame.font, c);
					nul = 1;
				}
				w += cw;
				sp++;
				nr++;
			}
			b = frame.box[nb];
			b.ptr = rp[ssp:sp];
			b.wid = w;
			b.nrune = nr;
			frame.nchars += nr;
			if (nul) {
				for (i = 0; i < nr; i++)
					if (charwidth(frame.font, b.ptr[i]) == 0)
						b.ptr[i] = frame.noglyph;
			}
		}
		frame.nbox++;
	}
	ppt = xfrcklinewrap0(f, ppt, frame.box[0]);
	return (xfrdraw(frame, ppt), ppt);
}

chopframe(f : ref Frame, pt : Point, p : int, bn : int)
{
	nb, nrune : int;

	for(nb = bn; ; nb++){
		if(nb >= f.nbox)
			berror("endofframe");
		b := f.box[nb];
		pt = xfrcklinewrap(f, pt, b);
		if(pt.y >= f.r.max.y)
			break;
		nrune = b.nrune;
		if(nrune < 0)
			nrune = 1;
		p += nrune;
		pt = xfradvance(f, pt, b);
	}
	f.nchars = p;
	f.nlines = f.maxlines;
	if (nb < f.nbox)				# BUG
		xfrdelbox(f, nb, f.nbox-1);
}

frinsert(f : ref Frame, rp : string, l : int, p0 : int)
{
	pt0, pt1, ppt0, ppt1, pt : Point;
	s, n, n0, nn0, y : int;
	r : Rect;
	npts : int;
	col : ref Image;

	if(p0 > f.nchars || l == 0 || f.b == nil)
		return;
	n0 = xfrfindbox(f, 0, 0, p0);
	cn0 := p0;
	nn0 = n0;
	pt0 = xfrptofcharnb(f, p0, n0);
	ppt0 = pt0;
	(pt1, ppt0) = bxscan(f, rp, l, ppt0);
	ppt1 = pt1;
	if(n0 < f.nbox){
		b := f.box[n0];
		pt0 = xfrcklinewrap(f, pt0, b);	# for frdrawsel()
		ppt1 = xfrcklinewrap0(f, ppt1, b);
	}
	f.modified = 1;
	#
	# ppt0 and ppt1 are start and end of insertion as they will appear when
	# insertion is complete. pt0 is current location of insertion position
	# (p0); pt1 is terminal point (without line wrap) of insertion.
	#
	if(f.p0 == f.p1)
		frtick(f, frptofchar(f, f.p0), 0);
	
	#
	# Find point where old and new x's line up
	# Invariants:
	#	pt0 is where the next box (b, n0) is now
	#	pt1 is where it will be after then insertion
	# If pt1 goes off the rectangle, we can toss everything from there on
	#

	for(npts=0; pt1.x!= pt0.x && pt1.y!=f.r.max.y && n0<f.nbox; npts++){
		b := f.box[n0];
		pt0 = xfrcklinewrap(f, pt0, b);
		pt1 = xfrcklinewrap0(f, pt1, b);
		if(b.nrune > 0){
			n = xfrcanfit(f, pt1, b);
			if(n == 0)
				berror("xfrcanfit==0");
			if(n != b.nrune){
				xfrsplitbox(f, n0, n);
				b = f.box[n0];
			}
		}
		if(npts == nalloc){
			opts := pts;
			pts = array[npts+DELTA] of Plist;
			pts[0:] = opts[0:npts];
			for (k := 0; k < DELTA; k++)
				pts[k+npts].pt0 = pts[k+npts].pt1 = (0, 0);
			opts = nil;
			nalloc += DELTA;
			b = f.box[n0];
		}
		pts[npts].pt0 = pt0;
		pts[npts].pt1 = pt1;
		# has a text box overflowed off the frame?
		if(pt1.y == f.r.max.y)
			break;
		pt0 = xfradvance(f, pt0, b);
		pt1.x += xfrnewwid(f, pt1, b);
		n0++;
		nrune := b.nrune;
		if(nrune < 0)
			nrune = 1;
		cn0 += nrune;
	}
	if(pt1.y > f.r.max.y)
		berror("frinsert pt1 too far");
	if(pt1.y==f.r.max.y && n0<f.nbox){
		f.nchars -= xfrstrlen(f, n0);
		xfrdelbox(f, n0, f.nbox-1);
	}
	if(n0 == f.nbox)
		f.nlines = (pt1.y-f.r.min.y)/f.font.height+(pt1.x>f.r.min.x);
	else if(pt1.y!=pt0.y){
		q0, q1 : int;

		y = f.r.max.y;
		q0 = pt0.y+f.font.height;
		q1 = pt1.y+f.font.height;
		f.nlines += (q1-q0)/f.font.height;
		if(f.nlines > f.maxlines)
			chopframe(f, ppt1, p0, nn0);
		if(pt1.y < y){
			r = f.r;
			r.min.y = q1;
			r.max.y = y;
			if(q1 < y)
				draw(f.b, r, f.b, nil, (f.r.min.x, q0));
			r.min = pt1;
			r.max.x = pt1.x+(f.r.max.x-pt0.x);
			r.max.y = q1;
			draw(f.b, r, f.b, nil, pt0);
		}
	}
	#
	# Move the old stuff down to make room.  The loop will move the stuff
	# between the insertion and the point where the x's lined up.
	# The draws above moved everything down after the point they lined up.
	#
	y = 0;
	if(pt1.y == f.r.max.y)
		y = pt1.y;
	for(j := n0-1; --npts >= 0; --j){
		pt = pts[npts].pt1;
		b := f.box[j];
		if(b.nrune > 0){
			r.min = pt;
			r.max = r.min;
			r.max.x += b.wid;
			r.max.y += f.font.height;
			draw(f.b, r, f.b, nil, pts[npts].pt0);
			if(pt.y < y){	# clear bit hanging off right
				r.min = pt;
				r.max = pt;
				r.min.x += b.wid;
				r.max.x = f.r.max.x;
				r.max.y += f.font.height;
				if(f.p0<=cn0 && cn0<f.p1)	# b+1 is inside selection
					col = f.cols[HIGH];
				else
					col = f.cols[BACK];
				draw(f.b, r, col, nil, r.min);
			}
			y = pt.y;
			cn0 -= b.nrune;
		}else{
			r.min = pt;
			r.max = pt;
			r.max.x += b.wid;
			r.max.y += f.font.height;
			if(r.max.x >= f.r.max.x)
				r.max.x = f.r.max.x;
			cn0--;
			if(f.p0<=cn0 && cn0<f.p1)	# b is inside selection
				col = f.cols[HIGH];
			else
				col = f.cols[BACK];
			draw(f.b, r, col, nil, r.min);
			y = 0;
			if(pt.x == f.r.min.x)
				y = pt.y;
		}
	}
	# insertion can extend the selection, so the condition here is different 
	if(f.p0<p0 && p0<=f.p1)
		col = f.cols[HIGH];
	else
		col = f.cols[BACK];
	frselectpaint(f, ppt0, ppt1, col);
	xfrredraw(frame, ppt0);
	xfraddbox(f, nn0, frame.nbox);
	for(n=0; n<frame.nbox; n++)
		*f.box[nn0+n] = *frame.box[n];
	if(nn0>0 && f.box[nn0-1].nrune>=0 && ppt0.x-f.box[nn0-1].wid>=f.r.min.x){
		--nn0;
		ppt0.x -= f.box[nn0].wid;
	}
	n0 += frame.nbox;
	s = n0;
	if(n0 < f.nbox-1)
		s++;
	xfrclean(f, ppt0, nn0, s);
	f.nchars += frame.nchars;
	if(f.p0 >= p0)
		f.p0 += frame.nchars;
	if(f.p0 > f.nchars)
		f.p0 = f.nchars;
	if(f.p1 >= p0)
		f.p1 += frame.nchars;
	if(f.p1 > f.nchars)
		f.p1 = f.nchars;
	if(f.p0 == f.p1)
		frtick(f, frptofchar(f, f.p0), 1);
}

xfrptofcharptb(f : ref Frame, p : int, pt : Point, bn : int) : Point
{
	s : int;
	l : int;
	r : int;

	for( ; bn < f.nbox; bn++){
		b := f.box[bn];
		pt = xfrcklinewrap(f, pt, b);
		l = b.nrune;
		if(l < 0)
			l = 1;
		if(p < l){
			if(b.nrune > 0)
				for(s = 0; p > 0; s++){
					r = b.ptr[s];
					pt.x += charwidth(f.font, r);
					if(r==0 || pt.x>f.r.max.x)
						berror("frptofchar");
					p--;
				}
			break;
		}
		p -= l;
		pt = xfradvance(f, pt, b);
	}
	return pt;
}

frptofchar(f : ref Frame, p : int) : Point
{
	return xfrptofcharptb(f, p, f.r.min, 0);
}

xfrptofcharnb(f : ref Frame, p : int, nb : int) : Point	# doesn't do final xfradvance to next line
{
	pt : Point;
	nbox : int;

	nbox = f.nbox;
	f.nbox = nb;
	pt = xfrptofcharptb(f, p, f.r.min, 0);
	f.nbox = nbox;
	return pt;
}

xfrgrid(f : ref Frame, p: Point) : Point
{
	p.y -= f.r.min.y;
	p.y -= p.y%f.font.height;
	p.y += f.r.min.y;
	if(p.x > f.r.max.x)
		p.x = f.r.max.x;
	return p;
}

frcharofpt(f : ref Frame, pt : Point) : int
{
	qt : Point;
	bn, nrune : int;
	s : int;
	p : int;
	r : int;

	pt = xfrgrid(f, pt);
	qt = f.r.min;

	bn=0;
	for(p=0; bn<f.nbox && qt.y<pt.y; bn++){
		b := f.box[bn];
		qt = xfrcklinewrap(f, qt, b);
		if(qt.y >= pt.y)
			break;
		qt = xfradvance(f, qt, b);
		nrune = b.nrune;
		if(nrune < 0)
			nrune = 1;
		p += nrune;
	}

	for(; bn<f.nbox && qt.x<=pt.x; bn++){
		b := f.box[bn];
		qt = xfrcklinewrap(f, qt, b);
		if(qt.y > pt.y)
			break;
		if(qt.x+b.wid > pt.x){
			if(b.nrune < 0)
				qt = xfradvance(f, qt, b);
			else{
				s = 0;
				for(;;){
					r = b.ptr[s++];
					qt.x += charwidth(f.font, r);
					if(qt.x > pt.x)
						break;
					p++;
				}
			}
		}else{
			nrune = b.nrune;
			if(nrune < 0)
				nrune = 1;
			p += nrune;
			qt = xfradvance(f, qt, b);
		}
	}
	return p;
}

region(a, b : int) : int
{
	if(a < b)
		return -1;
	if(a == b)
		return 0;
	return 1;
}

frselect(f : ref Frame, m : ref Pointer)	# when called, button 1 is down
{
	p0, p1, q : int;
	mp, pt0, pt1, qt : Point;
	b, scrled, reg : int;

	mp = m.xy;
	b = m.buttons;

	f.modified = 0;
	frdrawsel(f, frptofchar(f, f.p0), f.p0, f.p1, 0);
	p0 = p1 = frcharofpt(f, mp);
	f.p0 = p0;
	f.p1 = p1;
	pt0 = frptofchar(f, p0);
	pt1 = frptofchar(f, p1);
	frdrawsel(f, pt0, p0, p1, 1);
	do{
		scrled = 0;
		if(f.scroll){
			if(m.xy.y < f.r.min.y){
				textm->framescroll(f, -(f.r.min.y-m.xy.y)/f.font.height-1);
				p0 = f.p1;
				p1 = f.p0;
				scrled = 1;
			}else if(m.xy.y > f.r.max.y){
				textm->framescroll(f, (m.xy.y-f.r.max.y)/f.font.height+1);
				p0 = f.p0;
				p1 = f.p1;
				scrled = 1;
			}
			if(scrled){
				pt0 = frptofchar(f, p0);
				pt1 = frptofchar(f, p1);
				reg = region(p1, p0);
			}
		}
		q = frcharofpt(f, m.xy);
		if(p1 != q){
			if(reg != region(q, p0)){	# crossed starting point; reset
				if(reg > 0)
					frdrawsel(f, pt0, p0, p1, 0);
				else if(reg < 0)
					frdrawsel(f, pt1, p1, p0, 0);
				p1 = p0;
				pt1 = pt0;
				reg = region(q, p0);
				if(reg == 0)
					frdrawsel(f, pt0, p0, p1, 1);
			}
			qt = frptofchar(f, q);
			if(reg > 0){
				if(q > p1)
					frdrawsel(f, pt1, p1, q, 1);
				else if(q < p1)
					frdrawsel(f, qt, q, p1, 0);
			}else if(reg < 0){
				if(q > p1)
					frdrawsel(f, pt1, p1, q, 0);
				else
					frdrawsel(f, qt, q, p1, 1);
			}
			p1 = q;
			pt1 = qt;
		}
		f.modified = 0;
		if(p0 < p1) {
			f.p0 = p0;
			f.p1 = p1;
		}
		else {
			f.p0 = p1;
			f.p1 = p0;
		}
		if(scrled)
			textm->framescroll(f, 0);
		graph->bflush();
		if(!scrled)
			acme->frgetmouse();
	}while(m.buttons == b);
}

frselectpaint(f : ref Frame, p0 : Point, p1 : Point, col : ref Image)
{
	n : int;
	q0, q1 : Point;

	q0 = p0;
	q1 = p1;
	q0.y += f.font.height;
	q1.y += f.font.height;
	n = (p1.y-p0.y)/f.font.height;
	if(f.b == nil)
		berror("frselectpaint b==0");
	if(p0.y == f.r.max.y)
		return;
	if(n == 0)
		draw(f.b, (p0, q1), col, nil, (0, 0));
	else{
		if(p0.x >= f.r.max.x)
			p0.x = f.r.max.x-1;
		draw(f.b, ((p0.x, p0.y), (f.r.max.x, q0.y)), col, nil, (0, 0));
		if(n > 1)
			draw(f.b, ((f.r.min.x, q0.y), (f.r.max.x, p1.y)),
				col, nil, (0, 0));
		draw(f.b, ((f.r.min.x, p1.y), (q1.x, q1.y)),
			col, nil, (0, 0));
	}
}

xfrcanfit(f : ref Frame, pt : Point, b : ref Frbox) : int
{
	left, nr : int;
	p : int;
	r : int;

	left = f.r.max.x-pt.x;
	if(b.nrune < 0)
		return b.minwid <= left;
	if(left >= b.wid)
		return b.nrune;
	nr = 0;
	for(p = 0; p < len b.ptr; p++){
		r = b.ptr[p];
		left -= charwidth(f.font, r);
		if(left < 0)
			return nr;
		nr++;
	}
	berror("xfrcanfit can't");
	return 0;
}

xfrcklinewrap(f : ref Frame, p : Point, b : ref Frbox) : Point
{
	wid : int;

	if(b.nrune < 0)
		wid = b.minwid;
	else
		wid = b.wid;

	if(wid > f.r.max.x-p.x){
		p.x = f.r.min.x;
		p.y += f.font.height;
	}
	return p;
}

xfrcklinewrap0(f : ref Frame, p : Point, b : ref Frbox) : Point
{
	if(xfrcanfit(f, p, b) == 0){
		p.x = f.r.min.x;
		p.y += f.font.height;
	}
	return p;
}

xfrcklinewrap1(f : ref Frame, p : Point, wid : int) : Point
{
	if(wid > f.r.max.x-p.x){
		p.x = f.r.min.x;
		p.y += f.font.height;
	}
	return p;
}

xfradvance(f : ref Frame, p : Point, b : ref Frbox) : Point
{
	if(b.nrune<0 && b.bc=='\n'){
		p.x = f.r.min.x;
		p.y += f.font.height;
	}else
		p.x += b.wid;
	return p;
}

xfrnewwid(f : ref Frame, pt : Point, b : ref Frbox) : int
{
	b.wid = xfrnewwid0(f, pt, b);
	return b.wid;
}

xfrnewwid0(f : ref Frame, pt : Point, b : ref Frbox) : int
{
	c, x : int;

	c = f.r.max.x;
	x = pt.x;
	if(b.nrune >= 0 || b.bc != '\t')
		return b.wid;
	if(x+b.minwid > c)
		x = pt.x = f.r.min.x;
	x += f.maxtab;
	x -= (x-f.r.min.x)%f.maxtab;
	if(x-pt.x<b.minwid || x>c)
		x = pt.x+b.minwid;
	return x-pt.x;
}

xfrclean(f : ref Frame, pt : Point, n0 : int, n1 : int)	# look for mergeable boxes
{
	nb, c : int;

	c = f.r.max.x;
	for(nb=n0; nb<n1-1; nb++){
		b0 := f.box[nb];
		b1 := f.box[nb+1];
		pt = xfrcklinewrap(f, pt, b0);
		while(b0.nrune>=0 && nb<n1-1 && b1.nrune>=0 && pt.x+b0.wid+b1.wid<c){
			xfrmergebox(f, nb);
			n1--;
			b0 = f.box[nb];
			b1 = f.box[nb+1];
		}
		pt = xfradvance(f, pt, f.box[nb]);
	}
	for(; nb<f.nbox; nb++){
		b := f.box[nb];
		pt = xfrcklinewrap(f, pt, b);
		pt = xfradvance(f, pt, f.box[nb]);
	}
	f.lastlinefull = 0;
	if(pt.y >= f.r.max.y)
		f.lastlinefull = 1;
}
