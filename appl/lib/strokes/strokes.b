implement Strokes;

#
# this Limbo code is derived from C code that had the following
# copyright notice, which i reproduce as requested
#
# li_recognizer.c
#
#	Copyright 2000 Compaq Computer Corporation.
#	Copying or modifying this code for any purpose is permitted,
#	provided that this copyright notice is preserved in its entirety
#	in all copies or modifications.
#	COMPAQ COMPUTER CORPORATION MAKES NO WARRANTIES, EXPRESSED OR
#	IMPLIED, AS TO THE USEFULNESS OR CORRECTNESS OF THIS CODE OR
#
#
# Adapted from cmu_recognizer.c by Jay Kistler.
#
# Where is the CMU copyright???? Gotta track it down - Jim Gettys
#
# Credit to Dean Rubine, Jim Kempf, and Ari Rapkin.
#
#
# the copyright notice really did end in the middle of the sentence
#

#
# Limbo version for Inferno by forsyth@vitanuova.com, Vita Nuova, September 2001
#

#
# the code is reasonably close to the algorithms described in
#	``On-line Handwritten Alphanumeric Character Recognition Using Dominant Stroke in Strokes'',
#	Xiaolin Li and Dit-Yan Yueng, Department of Computer Science,
#	Hong Kong University of Science and Technology, Hong Kong  (23 August 1996)
#

include "sys.m";
	sys: Sys;

include "strokes.m";

MAXINT: con 16r7FFFFFFF;

# Dynamic programming parameters
DP_BAND: con 3;
SIM_THLD: con 60;	# x100
#DIST_THLD: con 3200;	# x100
DIST_THLD: con 3300;	# x100

#  Low-pass filter parameters -- empirically derived
LP_FILTER_WIDTH: con 6;
LP_FILTER_ITERS: con 8;
LP_FILTER_THLD: con 250;	# x100
LP_FILTER_MIN: con 5;

#  Pseudo-extrema parameters -- empirically derived
PE_AL_THLD: con 1500;	# x100
PE_ATCR_THLD: con 135;	# x100

#  Pre-processing and canonicalization parameters
CANONICAL_X: con 108;
CANONICAL_Y: con 128;
DIST_SQ_THRESHOLD: con 3*3;

#  direction-code table; indexed by dx, dy
dctbl := array[] of {array[] of {1, 0, 7}, array[] of {2, MAXINT, 6}, array[] of {3, 4, 5}};

#  low-pass filter weights
lpfwts := array[2 * LP_FILTER_WIDTH + 1] of int;
lpfconst := -1;

lidebug: con 0;
stderr: ref Sys->FD;

#		x := 0.04 * (i * i);
#		wtvals[i] = floor(100.0 * exp(x));
wtvals := array[] of {100, 104, 117, 143, 189, 271, 422};

init()
{
	sys = load Sys Sys->PATH;
	if(lidebug)
		stderr = sys->fildes(2);
	for(i := LP_FILTER_WIDTH; i >= 0; i--){
		wt := wtvals[i];
		lpfwts[LP_FILTER_WIDTH - i] = wt;
		lpfwts[LP_FILTER_WIDTH + i] = wt;
	}
	lpfconst = 0;
	for(i = 0; i < (2 * LP_FILTER_WIDTH + 1); i++)
		lpfconst += lpfwts[i];
}

Stroke.new(n: int): ref Stroke
{
	return ref Stroke(n, array[n] of Penpoint, 0, 0);
}

Stroke.trim(ps: self ref Stroke, n: int)
{
	ps.npts = n;
	ps.pts = ps.pts[0:n];
}

Stroke.copy(ps: self ref Stroke): ref Stroke
{
	n := ps.npts;
	a := array[n] of Penpoint;
	a[0:] = ps.pts[0:n];
	return ref Stroke(n, a, ps.xrange, ps.yrange);
}

#
# return the bounding box of a set of points
# (note: unlike Draw->Rectangle, the region is closed)
#
Stroke.bbox(ps: self ref Stroke): (int, int, int, int)
{
	minx := maxx := ps.pts[0].x;
	miny := maxy := ps.pts[0].y;
	for(i := 1; i < ps.npts; i++){
		pt := ps.pts[i];
		if(pt.x < minx)
			minx = pt.x;
		if(pt.x > maxx)
			maxx = pt.x;
		if(pt.y < miny)
			miny = pt.y;
		if(pt.y > maxy)
			maxy = pt.y;
	}
	return (minx, miny, maxx, maxy);	# warning: closed interval
}

Stroke.center(ps: self ref Stroke)
{
	(minx, miny, maxx, maxy) := ps.bbox();
	ps.xrange = maxx-minx;
	ps.yrange = maxy-miny;
	avgxoff := -((CANONICAL_X - ps.xrange + 1) / 2);
	avgyoff := -((CANONICAL_Y - ps.yrange + 1) / 2);
	ps.translate(avgxoff, avgyoff, 100, 100);
}

Stroke.scaleup(ps: self ref Stroke): int
{
	(minx, miny, maxx, maxy) := ps.bbox();
	xrange := maxx - minx;
	yrange := maxy - miny;
	scale: int;
	if(((100 * xrange + CANONICAL_X / 2) / CANONICAL_X) >
			 ((100 * yrange + CANONICAL_Y / 2) / CANONICAL_Y))
		scale = (100 * CANONICAL_X + xrange / 2) / xrange;
	else
		scale = (100 * CANONICAL_Y + yrange / 2) / yrange;
	ps.translate(minx, miny, scale, scale);
	return scale;
}

#  scalex and scaley are x 100.
#  Note that this does NOT update points.xrange and points.yrange!
Stroke.translate(ps: self ref Stroke, minx: int, miny: int, scalex: int, scaley: int)
{
	for(i := 0; i < ps.npts; i++){
		ps.pts[i].x = ((ps.pts[i].x - minx) * scalex + 50) / 100;
		ps.pts[i].y = ((ps.pts[i].y - miny) * scaley + 50) / 100;
	}
}

TAP_PATHLEN: con 10*100;		# x100

Classifier.match(rec: self ref Classifier, stroke: ref Stroke): (int, string)
{
	if(stroke.npts < 1)
		return (-1, nil);

	#  Check for tap.

	#  First thing is to filter out ``close points.''
	stroke = stroke.filter();

	#  Unfortunately, we don't have the actual time that each point
	#  was recorded (i.e., dt is invalid).  Hence, we have to use a
	#  heuristic based on total distance and the number of points.
	if(stroke.npts == 1 || stroke.length() < TAP_PATHLEN)
		return (-1, "tap");

	preprocess_stroke(stroke);

	#  Compute its dominant points.
	dompts := stroke.interpolate().dominant();
	best_dist := MAXDIST;
	best_i := -1;
	best_name: string;

	#  Score input stroke against every class in classifier.
	for(i := 0; i < len rec.cnames; i++){
		name := rec.cnames[i];
		(sim, dist) := score_stroke(dompts, rec.dompts[i]);
		if(dist < MAXDIST)
			sys->fprint(stderr, " (%s, %d, %d)", name, sim, dist);
		if(dist < DIST_THLD){
			if(lidebug)
				sys->fprint(stderr, " (%s, %d, %d)", name, sim, dist);
			#  Is it the best so far?
			if(dist < best_dist){
				best_dist = dist;
				best_i = i;
				best_name = name;
			}
		}
	}

	if(lidebug)
		sys->fprint(stderr, "\n");
	return (best_i, best_name);
}

preprocess_stroke(s: ref Stroke)
{
	#  Filter out points that are too close.
	#  We did this earlier, when we checked for a tap.

#	s = s.filter();


#     assert(s.npts > 0);

	#  Scale up to avoid conversion errors.
	s.scaleup();

	#  Center the stroke.
	s.center();

	if(lidebug){
		(minx, miny, maxx, maxy) := s.bbox();
		sys->fprint(stderr, "After pre-processing:  [ %d %d %d %d]\n",
				minx, miny, maxx, maxy);
		printpoints(stderr, s, "\n");
	}
}

#
# return the dominant points of Stroke s, assuming s has been through interpolation
#
Stroke.dominant(s: self ref Stroke): ref Stroke
{
	regions := s.regions();

	#  Dominant points are: start, end, extrema of non plain regions, and midpoints of the preceding.
	nonplain := 0;
	for(r := regions; r != nil; r = r.next)
		if(r.rtype != Rplain)
			nonplain++;
	dom := Stroke.new(1 + 2*nonplain + 2);

	#  Pick out dominant points.

	#  start point
	dp := 0;
	previx := 0;
	dom.pts[dp++] = s.pts[previx];
	currix: int;

	cas := s.contourangles(regions);
	for(r = regions; r != nil; r = r.next)
		if(r.rtype != Rplain){
			max_v := 0;
			min_v := MAXINT;
			max_ix := -1;
			min_ix := -1;

			for(i := r.start; i <= r.end; i++){
				v := cas[i];
				if(v > max_v){
					max_v = v; max_ix = i;
				}
				if(v < min_v){
					min_v = v; min_ix = i;
				}
				if(lidebug > 1)
					sys->fprint(stderr, "  %d\n", v);
			}
			if(r.rtype == Rconvex)
				currix = max_ix;
			else
				currix = min_ix;

			dom.pts[dp++] = s.pts[(previx+currix)/2];	# midpoint
			dom.pts[dp++] = s.pts[currix];	# extreme

			previx = currix;
		}

	#  last midpoint, and end point
	lastp := s.npts - 1;
	dom.pts[dp++] = s.pts[(previx+lastp)/2];
	dom.pts[dp++] = s.pts[lastp];
	dom.trim(dp);

	#  Compute chain-code.
	compute_chain_code(dom);

	return dom;
}

Stroke.contourangles(s: self ref Stroke, regions: ref Region): array of int
{
	V := array[s.npts] of int;
	V[0] = 18000;
	for(r := regions; r != nil; r = r.next){
		for(i := r.start; i <= r.end; i++){
			if(r.rtype == Rplain){
				V[i] = 18000;
			}else{
				#  For now, simply choose the mid-point.
				ismidpt := i == (r.start + r.end)/2;
				if(ismidpt ^ (r.rtype!=Rconvex))
					V[i] = 18000;
				else
					V[i] = 0;
			}
		}
	}
	V[s.npts - 1] = 18000;
	return V;
}

Stroke.interpolate(s: self ref Stroke): ref Stroke
{
	#  Compute an upper-bound on the number of interpolated points
	maxpts := s.npts;
	for(i := 0; i < s.npts - 1; i++){
		a := s.pts[i];
		b := s.pts[i+1];
		maxpts += abs(a.x - b.x) + abs(a.y - b.y);
	}

	#  Allocate an array of the maximum size
	newpts := Stroke.new(maxpts);

	#  Interpolate each of the segments.
	j := 0;
	for(i = 0; i < s.npts - 1; i++){
		j = bresline(s.pts[i], s.pts[i+1], newpts, j);
		j--;	#  end point gets recorded as start point of next segment!
	}

	#  Add-in last point and trim
	newpts.pts[j++] = s.pts[s.npts - 1];
	newpts.trim(j);

	if(lidebug){
		sys->fprint(stderr, "After interpolation:\n");
		printpoints(stderr, newpts, "\n");
	}

	#  Compute the chain code for P (the list of points).
	compute_unit_chain_code(newpts);

	return newpts;
}

#  This implementation is due to an anonymous page on the net
bresline(startpt: Penpoint, endpt: Penpoint, newpts: ref Stroke, j: int): int
{
	x0 := startpt.x;
	x1 := endpt.x;
	y0 := startpt.y;
	y1 := endpt.y;

	stepx := 1;
	dx := x1-x0;
	if(dx < 0){
		dx = -dx;
		stepx = -1;
	}
	dx <<= 1;
	stepy := 1;
	dy := y1-y0;
	if(dy < 0){
		dy = -dy;
		stepy = -1;
	}
	dy <<= 1;
	newpts.pts[j++] = (x0, y0, 0);
	if(dx >= dy){
		e := dy - (dx>>1);
		while(x0 != x1){
			if(e >= 0){
				y0 += stepy;
				e -= dx;
			}
			x0 += stepx;
			e += dy;
			newpts.pts[j++] = (x0, y0, 0);
		}
	}else{
		e := dx - (dy>>1);
		while(y0 != y1){
			if(e >= 0){
				x0 += stepx;
				e -= dy;
			}
			y0 += stepy;
			e += dx;
			newpts.pts[j++] = (x0, y0, 0);
		}
	}
	return j;
}

compute_chain_code(pts: ref Stroke)
{
	for(i := 0; i < pts.npts - 1; i++){
		dx := pts.pts[i+1].x - pts.pts[i].x;
		dy := pts.pts[i+1].y - pts.pts[i].y;
		pts.pts[i].chaincode = (12 - quadr(likeatan(dy, dx))) % 8;
	}
}

compute_unit_chain_code(pts: ref Stroke)
{
	for(i := 0; i < pts.npts - 1; i++){
		dx := pts.pts[i+1].x - pts.pts[i].x;
		dy := pts.pts[i+1].y - pts.pts[i].y;
		pts.pts[i].chaincode = dctbl[dx+1][dy+1];
	}
}

Stroke.regions(pts: self ref Stroke): ref Region
{
	#  Allocate a 2 x pts.npts array for use in computing the (filtered) Angle set, A_n.
	R := array[] of {0 to LP_FILTER_ITERS+1 => array[pts.npts] of int};
	curr := R[0];

	#  Compute the Angle set, A, in the first element of array R.
	#  Values in R are in degrees, x 100.
	curr[0] = 18000;		#  a_0
	for(i := 1; i < pts.npts - 1; i++){
		d_i := pts.pts[i].chaincode;
		d_iminusone := pts.pts[i-1].chaincode;
		if(d_iminusone < d_i)
			d_iminusone += 8;
		a_i := (d_iminusone - d_i) % 8;
		#  convert to degrees, x 100
		curr[i] = ((12 - a_i) % 8) * 45 * 100;
	}
	curr[pts.npts-1] = 18000;	#  a_L-1

	#  Perform a number of filtering iterations.
	next := R[1];
	for(j := 0; j < LP_FILTER_ITERS; ){
		for(i = 0; i < pts.npts; i++){
			next[i] = 0;
			for(k := i - LP_FILTER_WIDTH; k <= i + LP_FILTER_WIDTH; k++){
				oldval: int;
				if(k < 0 || k >= pts.npts)
					oldval = 18000;
				else
					oldval = curr[k];
				next[i] += oldval * lpfwts[k - (i	- LP_FILTER_WIDTH)];	#  overflow?
			}
			next[i] /= lpfconst;
		}
		j++;
		curr = R[j];
		next = R[j+1];
	}

	#  Do final thresholding around PI.
	#  curr and next are set-up correctly at end of previous loop!
	for(i = 0; i < pts.npts; i++)
		if(abs(curr[i] - 18000) < LP_FILTER_THLD)
			next[i] = 18000;
		else
			next[i] = curr[i];
	curr = next;

	#  Debugging.
	if(lidebug > 1){
		for(i = 0; i < pts.npts; i++){
			p := pts.pts[i];
			sys->fprint(stderr, "%3d:  (%d %d)  %ud  ",
				i, p.x, p.y, p.chaincode);
			for(j = 0; j < 2 + LP_FILTER_ITERS; j++)
				sys->fprint(stderr, "%d  ", R[j][i]);
			sys->fprint(stderr, "\n");
		}
	}

	#  Do the region segmentation.
	r := regions := ref Region(regiontype(curr[0]), 0, 0, nil);
	for(i = 1; i < pts.npts; i++){
		t := regiontype(curr[i]);
		if(t != r.rtype){
			r.end = i-1;
			if(lidebug > 1)
				sys->fprint(stderr, "  (%d, %d) %d\n", r.start, r.end, r.rtype);
			r.next = ref Region(t, i, 0, nil);
			r = r.next;
		}
	}
	r.end = i-1;
	if(lidebug > 1)
		sys->fprint(stderr, "  (%d, %d), %d\n", r.start, r.end, r.rtype);

	#  Filter out convex/concave regions that are too short.
	for(r = regions; r != nil; r = r.next)
		if(r.rtype == Rplain){
			while((nr := r.next) != nil && (nr.end - nr.start) < LP_FILTER_MIN){
				#  nr must not be plain, and it must be followed by a plain
				#  assert(nr.rtype != Rplain);
				#  assert(nr.next != nil && (nr.next).rtype == Rplain);
				if(nr.next == nil){
					sys->fprint(stderr, "recog: nr.next==nil\n");	# can't happen
					break;
				}
				r.next = nr.next.next;
				r.end = nr.next.end;
			}
		}

	#  Add-in pseudo-extremes.
	for(r = regions; r != nil; r = r.next)
		if(r.rtype == Rplain){
			arclen := pts.pathlen(r.start, r.end);
			dx := pts.pts[r.end].x - pts.pts[r.start].x;
			dy := pts.pts[r.end].y - pts.pts[r.start].y;
			chordlen := sqrt(100*100 * (dx*dx + dy*dy));
			atcr := 0;
			if(chordlen)
				atcr = (100*arclen + chordlen/2) / chordlen;

			if(lidebug)
				sys->fprint(stderr, "%d, %d, %d\n", arclen, chordlen, atcr);

			#  Split region if necessary.
			if(arclen >= PE_AL_THLD && atcr >= PE_ATCR_THLD){
				mid := (r.start + r.end)/2;
				end := r.end;
				r.end = mid - 1;
				r = r.next = ref Region(Rpseudo, mid, mid,
					ref Region(Rplain, mid+1, end, r.next));
			}
		}

	return regions;
}

regiontype(val: int): int
{
	if(val == 18000)
		return Rplain;
	if(val < 18000)
		return Rconcave;
	return Rconvex;
}

#
# return the similarity of two strokes and,
# if similar, the distance between them;
# if dissimilar, the distance is MAXDIST)
#
score_stroke(a: ref Stroke, b: ref Stroke): (int, int)
{
	sim := compute_similarity(a, b);
	if(sim < SIM_THLD)
		return (sim, MAXDIST);
	return (sim, compute_distance(a, b));
}

compute_similarity(A: ref Stroke, B: ref Stroke): int
{
	#  A is the	longer sequence, length	N.
	#  B is the shorter sequence, length M.
	if(A.npts < B.npts){
		t := A; A = B; B = t;
	}
	N := A.npts;
	M := B.npts;

	#  Allocate and initialize the Gain matrix, G.
	#  The size of G is M x (N + 1).
	#  Note that row 0 is unused.
	#  Similarities are x 10.
	G := array[M] of array of int;
	for(i := 1; i < M; i++){
		G[i] = array[N+1] of int;
		bcode := B.pts[i-1].chaincode;

		G[i][0] = 0;	# source column

		for(j := 1; j < N; j++){
			diff := abs(bcode - A.pts[j-1].chaincode);
			if(diff > 4)
				diff = 8 - diff;	# symmetry
			v := 0;
			if(diff == 0)
				v = 10;
			else if(diff == 1)
				v = 6;
			G[i][j] = v;
		}

		G[i][N] = 0;	# sink column
	}

	#  Do the DP algorithm.
	#  Proceed in column order, from highest column to the lowest.
	#  Within each column, proceed from the highest row to the lowest.
	#  Skip the highest column.
	for(j := N - 1; j >= 0; j--)
		for(i = M - 1; i > 0; i--){
			max := G[i][j + 1];
			if(i < M-1){
				t := G[i + 1][j + 1];
				if(t > max)
					max = t;
			}
			G[i][j] += max;
		}

	return (10*G[1][0] + (N-1)/2) / (N-1);
}

compute_distance(A: ref Stroke, B: ref Stroke): int
{
	#  A is the	longer sequence, length	N.
	#  B is the shorter sequence, length M.
	if(A.npts < B.npts){
		t := A; A = B; B = t;
	}
	N := A.npts;
	M := B.npts;

	#  Construct the helper vectors, BE and TE, which say for each column
	#  what are the ``bottom'' and ``top'' rows of interest.
	BE := array[N+1] of int;
	TE := array[N+1] of int;

	for(j := 1; j <= N; j++){
		bot := j + (M - DP_BAND);
		if(bot > M) bot = M;
		BE[j] = bot;

		top := j - (N - DP_BAND);
		if(top < 1) top = 1;
		TE[j] = top;
	}

	#  Allocate and initialize the Cost matrix, C.
	#  The size of C is (M + 1) x (N + 1).
	#  Note that row and column 0 are unused.
	#  Costs are x 100.
	C := array[M+1] of array of int;
	for(i := 1; i <= M; i++){
		C[i] = array[N+1] of int;
		bx := B.pts[i-1].x;
		by := B.pts[i-1].y;

		for(j = 1; j <= N; j++){
			ax := A.pts[j-1].x;
			ay := A.pts[j-1].y;
			dx := bx - ax;
			dy := by - ay;
			dist := sqrt(10000 * (dx * dx + dy * dy));

			C[i][j] = dist;
		}
	}

	#  Do the DP algorithm.
	#  Proceed in column order, from highest column to the lowest.
	#  Within each column, proceed from the highest row to the lowest.
	for(j = N; j > 0; j--)
		for(i = M; i > 0; i--){
			min := MAXDIST;
			if(i > BE[j] || i < TE[j] || (j == N && i == M))
				continue;
			if(j < N){
				if(i >= TE[j+1]){
					tmp := C[i][j+1];
					if(tmp < min)
						min = tmp;
				}
				if(i < M){
					tmp := C[i+1][j+1];
					if(tmp < min)
						min = tmp;
				}
			}
			if(i < BE[j]){
				tmp := C[i+1][j];
				if(tmp < min)
					min = tmp;
			}
			C[i][j] += min;
		}
	return (C[1][1] + N / 2) / N;	# dist
}

#  Result is x 100.
Stroke.length(s: self ref Stroke): int
{
	return s.pathlen(0, s.npts-1);
}

#  Result is x 100.
Stroke.pathlen(s: self ref Stroke, first: int, last: int): int
{
	l := 0;
	for(i := first + 1; i <= last; i++){
		dx := s.pts[i].x - s.pts[i-1].x;
		dy := s.pts[i].y - s.pts[i-1].y;
		l += sqrt(100*100 * (dx*dx + dy*dy));
	}
	return l;
}

#  Note that this does NOT update points.xrange and points.yrange!
Stroke.filter(s: self ref Stroke): ref Stroke
{
	pts := array[s.npts] of Penpoint;
	pts[0] = s.pts[0];
	npts := 1;
	for(i := 1; i < s.npts; i++){
		j := npts - 1;
		dx := s.pts[i].x - pts[j].x;
		dy := s.pts[i].y - pts[j].y;
		magsq := dx * dx + dy * dy;
		if(magsq >= DIST_SQ_THRESHOLD){
			pts[npts] = s.pts[i];
			npts++;
		}
	}
	return ref Stroke(npts, pts[0:npts], 0, 0);
}

abs(a: int): int
{
	if(a < 0)
		return -a;
	return a;
}

#  Code from Joseph Hall (jnhall@sat.mot.com).
sqrt(n: int): int
{
	nn := n;
	k0 := 2;
	for(i := n; i > 0; i >>= 2)
		k0 <<= 1;
	nn <<= 2;
	k1: int;
	for(;;){
		k1 = (nn / k0 + k0) >> 1;
		if(((k0 ^ k1) & ~1) == 0)
			break;
		k0 = k1;
	}
	return (k1 + 1) >> 1;
}

#  Helper routines from Mark Hayter.
likeatan(tantop: int, tanbot: int): int
{
	#  Use tan(theta)=top/bot -. order for t
	#  t in range 0..16r40000

	if(tantop == 0 && tantop == 0)
		return 0;
	t := (tantop << 16) / (abs(tantop) + abs(tanbot));
	if(tanbot < 0)
		t = 16r20000 - t;
	else if(tantop < 0)
		t = 16r40000 + t;
	return t;
}

quadr(t: int): int
{
	return (8 - (((t + 16r4000) >> 15) & 7)) & 7;
}

printpoints(fd: ref Sys->FD, pts: ref Stroke, sep: string)
{
	for(j := 0; j < pts.npts; j++){
		p := pts.pts[j];
		sys->fprint(fd, "  (%d %d) %ud%s", p.x, p.y, pts.pts[j].chaincode, sep);
	}
}
