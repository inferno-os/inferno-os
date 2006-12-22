implement Buildstrokes;

#
# this Limbo code is derived from C code that had the following
# copyright notice, which i reproduce as requested
#
# li_strokesnizer.c
#
#	Copyright 2000 Compaq Computer Corporation.
#	Copying or modifying this code for any purpose is permitted,
#	provided that this copyright notice is preserved in its entirety
#	in all copies or modifications.
#	COMPAQ COMPUTER CORPORATION MAKES NO WARRANTIES, EXPRESSED OR
#	IMPLIED, AS TO THE USEFULNESS OR CORRECTNESS OF THIS CODE OR
#
#
# Adapted from cmu_strokesnizer.c by Jay Kistler.
#
# Where is the CMU copyright???? Gotta track it down - Jim Gettys
#
# Credit to Dean Rubine, Jim Kempf, and Ari Rapkin.
#

include "sys.m";
	sys: Sys;

include "strokes.m";
	strokes: Strokes;
	Classifier, Penpoint, Stroke, Region: import strokes;
	Rconvex, Rconcave, Rplain, Rpseudo: import Strokes;

lidebug: con 0;
stderr: ref Sys->FD;

init(r: Strokes)
{
	sys = load Sys Sys->PATH;
	if(lidebug)
		stderr = sys->fildes(2);
	strokes = r;
}

#
#  Implementation of the Li/Yeung recognition algorithm
#

#  Pre-processing and canonicalization parameters
CANONICAL_X: con 108;
CANONICAL_Y: con 128;
NCANONICAL: con 50;


#
# calculate canonical forms
#

canonical_example(nclasses: int, cnames: array of string, examples: array of list of ref Stroke): (string, array of ref Stroke, array of ref Stroke)
{
	canonex := array[nclasses] of ref Stroke;
	dompts := array[nclasses] of ref Stroke;

	#  make canonical examples for each class.
	for(i := 0; i < nclasses; i++){
		if(lidebug)
			sys->fprint(stderr, "canonical_example: class %s\n", cnames[i]);

		#  Make a copy of the examples.
		pts: list of ref Stroke = nil;
		nex := 0;
		for(exl := examples[i]; exl != nil; exl = tl exl){
			t := hd exl;
			pts = t.copy() :: pts;
			nex++;
		}

		#  Canonicalize each example, and derive the max x and y ranges.
		maxxrange := 0;
		maxyrange := 0;
		for(exl = pts; exl != nil; exl = tl exl){
			e := hd exl;
			ce := canonical_stroke(e);
			if(ce == nil){
				if(lidebug)
					sys->fprint(stderr, "example discarded: can't make canonical form\n");
				continue;	# try the next one
			}
			*e = *ce;
			if(e.xrange > maxxrange)
				maxxrange = e.xrange;
			if(e.yrange > maxyrange)
				maxyrange = e.yrange;
		}

		#  Normalise max ranges.
		(maxxrange, maxyrange) = normalise(maxxrange, maxyrange, CANONICAL_X, CANONICAL_Y);

		#  Re-scale each example to max ranges.
		for(exl = pts; exl != nil; exl = tl exl){
			t := hd exl;
			scalex, scaley: int;
			if(t.xrange == 0)
				scalex = 100;
			else
				scalex = (100*maxxrange + t.xrange/2) / t.xrange;
			if(t.yrange == 0)
				scaley = 100;
			else
				scaley = (100*maxyrange + t.yrange/2) / t.yrange;
			t.translate(0, 0, scalex, scaley);
		}

		#  Average the examples; leave average in first example.
		avg := hd pts;				#  careful, aliasing
		for(k := 0; k < NCANONICAL; k++){
			xsum := 0;
			ysum := 0;
			for(exl = pts; exl != nil; exl = tl exl){
				t := hd exl;
				xsum += t.pts[k].x;
				ysum += t.pts[k].y;
			}
			avg.pts[k].x = (xsum + nex/2) / nex;
			avg.pts[k].y = (ysum + nex/2) / nex;
		}

		#  rescale averaged stroke
		avg.scaleup();

		#  Re-compute the x and y ranges and center the stroke.
		avg.center();

		canonex[i] = avg;	# now it's the canonical representation

		if(lidebug){
			sys->fprint(stderr, "%s, avgpts = %d\n", cnames[i], avg.npts);
			for(j := 0; j < avg.npts; j++){
				p := avg.pts[j];
				sys->fprint(stderr, "  (%d %d)\n", p.x, p.y);
			}
		}

		dompts[i] = avg.interpolate().dominant();	# dominant points of canonical representation
	}

	return (nil, canonex, dompts);
}

normalise(x, y: int, xrange, yrange: int): (int, int)
{
	if((100*x + xrange/2)/xrange > (100*y + yrange/2)/yrange){
		y = (y*xrange + x/2)/x;
		x = xrange;
	}else{
		x = (x*yrange + y/2)/y;
		y = yrange;
	}
	return (x, y);
}

canonical_stroke(points: ref Stroke): ref Stroke
{
	points = points.filter();
	if(points.npts < 2)
		return nil;

	#  Scale up to avoid conversion errors.
	points.scaleup();

	#  Compute an equivalent stroke with equi-distant points
	points = compute_equipoints(points);
	if(points == nil)
		return nil;

	#  Re-translate the points to the origin.
	(minx, miny, maxx, maxy) := points.bbox();
	points.translate(minx, miny, 100, 100);

	#  Store the x and y ranges in the point list.
	points.xrange = maxx - minx;
	points.yrange = maxy - miny;

	if(lidebug){
		sys->fprint(stderr, "Canonical stroke:   %d, %d, %d, %d\n", minx, miny, maxx, maxy);
		for(i := 0; i < points.npts; i++){
			p := points.pts[i];
			sys->fprint(stderr, "      (%d %d)\n", p.x, p.y);
		}
	}

	return points;
}

compute_equipoints(points: ref Stroke): ref Stroke
{
	pathlen := points.length();
	equidist := (pathlen + (NCANONICAL-1)/2) / (NCANONICAL-1);
	equipoints := array[NCANONICAL] of Penpoint;
	if(lidebug)
		sys->fprint(stderr, "compute_equipoints:  npts = %d, pathlen = %d, equidist = %d\n",
				points.npts, pathlen, equidist);

	#  First original point is an equipoint.
	equipoints[0] = points.pts[0];
	nequipoints := 1;
	dist_since_last_eqpt := 0;

	for(i := 1; i < points.npts; i++){
		dx1 := points.pts[i].x - points.pts[i-1].x;
		dy1 := points.pts[i].y - points.pts[i-1].y;
		endx := points.pts[i-1].x*100;
		endy := points.pts[i-1].y*100;
		remaining_seglen := strokes->sqrt(100*100 * (dx1*dx1 + dy1*dy1));
		dist_to_next_eqpt := equidist - dist_since_last_eqpt;
		while(remaining_seglen >= dist_to_next_eqpt){
			if(dx1 == 0){
				#  x-coordinate stays the same
				if(dy1 >= 0)
					endy += dist_to_next_eqpt;
				else
					endy -= dist_to_next_eqpt;
			}else{
				slope := (100*dy1 + dx1/2) / dx1;
				tmp := strokes->sqrt(100*100 + slope*slope);
				dx := (100*dist_to_next_eqpt + tmp/2) / tmp;
				dy := (slope*dx + 50)/100;
				if(dy < 0)
					dy = -dy;
				if(dx1 >= 0)
					endx += dx;
				else
					endx -= dx;
				if(dy1 >= 0)
					endy += dy;
				else
					endy -= dy;
			}
			equipoints[nequipoints].x = (endx + 50) / 100;
			equipoints[nequipoints].y = (endy + 50) / 100;
			nequipoints++;
			#assert(nequipoints <= NCANONICAL);
			dist_since_last_eqpt = 0;
			remaining_seglen -= dist_to_next_eqpt;
			dist_to_next_eqpt = equidist;
		}
		dist_since_last_eqpt += remaining_seglen;
	}

	#  Take care of last equipoint.
	if(nequipoints == NCANONICAL-1){
		#  Make last original point the last equipoint.
		equipoints[nequipoints++] = points.pts[points.npts - 1];
	}
	if(nequipoints != NCANONICAL){	# fell short
		if(lidebug)
			sys->fprint(stderr,"compute_equipoints: nequipoints = %d\n", nequipoints);
		# 	assert(false);
		return nil;
	}
	return ref Stroke(NCANONICAL, equipoints, 0, 0);
}
