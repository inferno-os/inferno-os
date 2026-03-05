implement Viewport;

#
# Viewport - Shared pan/scroll/drag logic for content viewers
#
# Pure offset management: no Draw dependency, no rendering,
# no pointer handling.  Callers (Xenith, lucipres) own those.
#

include "viewport.m";

new(): ref View
{
	return ref View(0, 0, 0, 0, 0, 0);
}

setbounds(v: ref View, cw, ch, vw, vh: int)
{
	v.contentw = cw;
	v.contenth = ch;
	v.vieww = vw;
	v.viewh = vh;
	clamp(v);
}

clamp(v: ref View)
{
	mx := maxpanx(v);
	my := maxpany(v);
	if(v.panx < 0) v.panx = 0;
	if(v.panx > mx) v.panx = mx;
	if(v.pany < 0) v.pany = 0;
	if(v.pany > my) v.pany = my;
}

maxpanx(v: ref View): int
{
	d := v.contentw - v.vieww;
	if(d < 0) d = 0;
	return d;
}

maxpany(v: ref View): int
{
	d := v.contenth - v.viewh;
	if(d < 0) d = 0;
	return d;
}

scrolly(v: ref View, dir: int, step: int): int
{
	my := maxpany(v);
	if(dir > 0) {
		# Scroll down
		if(v.pany >= my)
			return 1;	# at bottom boundary
		v.pany += step;
		if(v.pany > my)
			v.pany = my;
	} else {
		# Scroll up
		if(v.pany <= 0)
			return -1;	# at top boundary
		v.pany -= step;
		if(v.pany < 0)
			v.pany = 0;
	}
	return 0;
}

scrollx(v: ref View, dir: int, step: int): int
{
	mx := maxpanx(v);
	if(dir > 0) {
		if(v.panx >= mx)
			return 1;
		v.panx += step;
		if(v.panx > mx)
			v.panx = mx;
	} else {
		if(v.panx <= 0)
			return -1;
		v.panx -= step;
		if(v.panx < 0)
			v.panx = 0;
	}
	return 0;
}

scrollstep(viewh: int): int
{
	# 3 lines of ~20px, or 20% of viewport
	step := viewh / 5;
	if(step < 60) step = 60;
	return step;
}

drag(v: ref View, startpx, startpy, dx, dy: int)
{
	v.panx = startpx + dx;
	v.pany = startpy + dy;
	clamp(v);
}

reset(v: ref View)
{
	v.panx = 0;
	v.pany = 0;
}
