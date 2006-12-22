implement WmPolyhedra;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect, Pointer, Image, Screen, Display: import draw;
include "tk.m";
	tk: Tk;
	Toplevel: import tk;
include "tkclient.m";
	tkclient: Tkclient;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "math.m";
	math: Math;
	sin, cos, tan, sqrt: import math;
include "rand.m";
	rand: Rand;
include "daytime.m";
	daytime: Daytime;
include "math/polyhedra.m";
	polyhedra: Polyhedra;
	Polyhedron: import Polyhedra;
	scanpolyhedra, getpolyhedron: import polyhedra;
include "math/polyfill.m";
	polyfill: Polyfill;
	initzbuf, clearzbuf, fillpoly: import polyfill;
include "smenu.m";
	smenu: Smenu;
	Scrollmenu: import smenu;

WmPolyhedra : module
{
	init : fn(nil : ref Draw->Context, argv : list of string);
};

WIDTH, HEIGHT: con 400;

mainwin: ref Toplevel;
Disp, black, white, opaque: ref Image;
Dispr: Rect;
pinit := 40;

init(ctxt : ref Draw->Context, argv : list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	bufio = load Bufio Bufio->PATH;
	math = load Math Math->PATH;
	rand = load Rand Rand->PATH;
	daytime = load Daytime Daytime->PATH;
	polyhedra = load Polyhedra Polyhedra->PATH;
	polyfill = load Polyfill Polyfill->PATH;
	smenu = load Smenu Smenu->PATH;
	rand->init(daytime->now());
	daytime = nil;
	polyfill->init();
	√2 = sqrt(2.0);
	√3 = sqrt(3.0);
	cursor := "";

	tkclient->init();
	if(ctxt == nil){
		ctxt = tkclient->makedrawcontext();
		# sys->fprint(sys->fildes(2), "wm not running\n");
		# exit;
	}
	argv = tl argv;
	while(argv != nil){
		case hd argv{
			"-p" =>
				argv = tl argv;
				if(argv != nil)
					pinit = int hd argv;
			"-r" =>
				pinit = -1;
			"-c" =>
				argv = tl argv;
				if(argv != nil)
					cursor = hd argv;
		}
		if(argv != nil)
			argv = tl argv;
	}
	(win, wmcmd) := tkclient->toplevel(ctxt, "", "Polyhedra", Tkclient->Resize | Tkclient->Hide);
	mainwin = win;
	sys->pctl(Sys->NEWPGRP, nil);
	cmdch := chan of string;
	tk->namechan(win, cmdch, "cmd");
	for(i := 0; i < len win_config; i++)
		cmd(win, win_config[i]);
	if(cursor != nil)
		cmd(win, "cursor -bitmap " + cursor);
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd"::"ptr"::nil);
	fittoscreen(win);
	pid := -1;
	sync := chan of int;
	chanθ := chan of real;
	geo := newgeom();
	setimage(win, geo);
	cmd(win, "update");
	display := win.image.display;
	white = display.color(Draw->White);
	black = display.color(Draw->Black);
	opaque = display.opaque;
	shade = array[NSHADES] of ref Image;
	for(i = 0; i < NSHADES; i++){
		# v := (255*i)/(NSHADES-1);		# NSHADES=17
		v := (192*i)/(NSHADES-1)+32;		# NSHADES=13
		# v := (128*i)/(NSHADES-1)+64;	# NSHADES=9
		shade[i] = display.rgb(v, v, v);
		# shade[i] = rgba(display, v, v, v, 16r7f);
	}
	(geo.npolyhedra, geo.polyhedra, geo.b) = scanpolyhedra("/lib/polyhedra.all");
	if(geo.npolyhedra == 0){
		sys->fprint(sys->fildes(2), "cannot open polyhedra database\n");
		exit;
	}
	yieldc := chan of int;
	# spawn yieldproc(yieldc);
	# ypid := <- yieldc;
	initgeom(geo);
	sm := array[2] of ref Scrollmenu;
	sm[0] = scrollmenu(win, ".f.menu", geo.polyhedra, geo.npolyhedra, 0);
	sm[1] = scrollmenu(win, ".f.menud", geo.polyhedra, geo.npolyhedra, 1);
	# createmenu(win, geo.polyhedra);
	spawn drawpolyhedron(geo, sync, chanθ, yieldc);
	pid = <- sync;
	newproc := 0;

	for(;;){
		alt{
		c := <-win.ctxt.kbd =>
			tk->keyboard(win, c);
		c := <-win.ctxt.ptr =>
			tk->pointer(win, *c);
		c := <-win.ctxt.ctl or
		c = <-win.wreq =>
			tkclient->wmctl(win, c);
		c := <- wmcmd =>
			case c{
			"exit" =>
				exits(pid, sm);
			* =>
				sync <-= 0;
				tkclient->wmctl(win, c);
				if(c[0] == '!'){
					if(setimage(win, geo) <= 0)
						exits(pid, sm);
				}
				sync <-= 1;
			}
		c := <- cmdch =>
			(nil, toks) := sys->tokenize(c, " ");
			case hd toks{
			"prev" =>
				geo.curpolyhedron = geo.curpolyhedron.prv;
				getpoly(geo, -1);
				newproc = 1;
			"next" =>
				geo.curpolyhedron = geo.curpolyhedron.nxt;
				getpoly(geo, 1);
				newproc = 1;
			"dual" =>
				geo.dual = !geo.dual;
				newproc = 1;
			"edges" =>
				edges = !edges;
			"faces" =>
				faces = !faces;
			"clear" =>
				clear = !clear;
			"slow" =>
				if(geo.θ > ε){
					if(geo.θ < 2.)
						chanθ <-= geo.θ/2.;
					else
						chanθ <-= geo.θ-1.;
				}
			"fast" =>
				if(geo.θ < 45.){
					if(geo.θ < 1.)
						chanθ <-= 2.*geo.θ;
					else
						chanθ <-= geo.θ+1.;
				}
			"axis" =>
				setaxis(geo);
				initmatrix(geo);
				newproc = 1;
			"menu" =>
				x := int cmd(win, ".p cget actx");
				y := int cmd(win, ".p cget acty");
				w := int cmd(win, ".p cget -actwidth");
				h := int cmd(win, ".p cget -actheight");
				sm[geo.dual].post(x+w/8, y+h/8, cmdch, "");
				# cmd(win, ".f.menu post " + x + " " + y);
			* =>
				i = int hd toks;
				fp := geo.polyhedra;
				for(p := fp; p != nil; p = p.nxt){
					if(p.indx == i){
						geo.curpolyhedron = p;
						getpoly(geo, 1);
						newproc = 1;
						break;
					}
					if(p.nxt == fp)
						break;
				}
			}
		}
		if(newproc){
			sync <-= 0;	# stop it first
			kill(pid);
			spawn drawpolyhedron(geo, sync, chanθ, yieldc);
			pid = <- sync;
			newproc = 0;
		}
	}
}

setimage(win: ref Toplevel, geo: ref Geom): int
{
	panelw := int tk->cmd(win, ".p cget -actwidth");
	panelh := int tk->cmd(win, ".p cget -actheight");
	if(panelw < 3)
		panelw = 3;
	if(panelh < 3)
		panelh = 3;
	Dispr = Rect((0,0), (panelw, panelh));
	Disp = win.image.display.newimage(Dispr, win.image.chans, 0, Draw->Black);
	if(Disp == nil){
		sys->fprint(sys->fildes(2), "not enough image memory\n");
		return 0;
	}
	tk->putimage(win, ".p", Disp, nil);
	if(Dispr.dx() > Dispr.dy())
		h := Dispr.dy();
	else
		h = Dispr.dx();
	rr: Rect = ((0, 0), (h, h));
	corner := ((Dispr.min.x+Dispr.max.x-rr.max.x)/2, (Dispr.min.y+Dispr.max.y-rr.max.y)/2);
	geo.r = (rr.min.add(corner), rr.max.add(corner));
	geo.h = h;
	geo.sx = real ((3*h)/8);
	geo.sy = - real ((3*h)/8);
	geo.tx = h/2+geo.r.min.x;
	geo.ty = h/2+geo.r.min.y;
	geo.zstate = initzbuf(geo.r);
	return 1;
}

# yieldcpu(c: chan of int)
# {
# 	c <-= 1;
# 	<-c;
# }

# yieldproc(c: chan of int)
# {
# 	c <-= sys->pctl(0, nil);
# 	for (;;) {
# 		<-c;
# 		c <-= 1;
# 	}
# }

π: con Math->Pi;
√2, √3: real;
∞: con 1<<30;
ε: con 0.001;

Axis: adt{
	λ, μ, ν: int;
};

Vector: adt{
	x, y, z: real;
};
	
Geom: adt{
	h: int;					# length, breadth of r below
	r: Rect;					# area on screen to update
	sx, sy: real;				# x, y scale
	tx, ty: int;					# x, y translation
	θ: real;					# angle of rotation
	TM: array of array of real;		# rotation matrix
	axis: Axis;					# direction cosines of rotation
	view: Vector;
	light: Vector;
	npolyhedra: int;
	polyhedra: ref Polyhedron;
	curpolyhedron: ref Polyhedron;
	b: ref Iobuf;				# of polyhedra file
	dual: int;
	zstate: ref Polyfill->Zstate;
};

NSHADES: con 13;	# odd
shade: array of ref Image;

clear, faces: int = 1;
edges: int = 0;

setview(geo: ref Geom)
{
	geo.view = (0.0, 0.0, 1.0);
	geo.light = (0.0, -1.0, 0.0);
}

map(v: Vector, geo: ref Geom): Point
{
	return (int (geo.sx*v.x)+geo.tx, int (geo.sy*v.y)+geo.ty);
}

minus(v1: Vector): Vector
{
	return (-v1.x, -v1.y, -v1.z);
}

add(v1, v2: Vector): Vector
{
	return (v1.x+v2.x, v1.y+v2.y, v1.z+v2.z);
}

sub(v1, v2: Vector): Vector
{
	return (v1.x-v2.x, v1.y-v2.y, v1.z-v2.z);
}

mul(v1: Vector, l: real): Vector
{
	return (l*v1.x, l*v1.y, l*v1.z);
}

div(v1: Vector, l: real): Vector
{
	return (v1.x/l, v1.y/l, v1.z/l);
}

normalize(v1: Vector): Vector
{
	return div(v1, sqrt(dot(v1, v1)));
}

dot(v1, v2: Vector): real
{
	return v1.x*v2.x + v1.y*v2.y + v1.z*v2.z;
}

cross(v1, v2: Vector): Vector
{
	return (v1.y*v2.z-v2.y*v1.z, v1.z*v2.x-v2.z*v1.x, v1.x*v2.y-v2.x*v1.y);
}

drawpolyhedron(geo: ref Geom, sync: chan of int, chanθ: chan of real, yieldc: chan of int)
{
	s: string;

	sync <-= sys->pctl(0, nil);
	p := geo.curpolyhedron;
	if(!geo.dual || p.anti){
		s = p.name;
		s += " (" + string p.indx + ")";
		puts(s);
		drawpolyhedron0(p.V, p.F, p.concave, p.allf || p.anti, p.v, p.f, p.fv, p.inc, geo, sync, chanθ, yieldc);
	}
	else{
		s = p.dname;
		s += " (" + string p.indx + ")";
		puts(s);
		drawpolyhedron0(p.F, p.V, p.concave, p.anti, p.f, p.v, p.vf, 0.0, geo, sync, chanθ, yieldc);
	}
}

drawpolyhedron0(V, F, concave, allf: int, v, f: array of Vector, fv: array of array of int, inc: real, geo: ref Geom, sync: chan of int, chanθ: chan of real, yieldc: chan of int)
{
	norm : array of array of Vector;
	newn, oldn : array of Vector;

	yieldc = nil;	# not used now
	θ := geo.θ;
	totθ := 0.;
	if(θ != 0.)
		n := int ((360.+θ/2.)/θ);
	else
		n = ∞;
	p := n;
	t := 0;
	vec := array[2] of array of Vector;
	vec[0] = array[V] of Vector;
	vec[1] = array[V] of Vector;
	if(concave){
		norm = array[2] of array of Vector;
		norm[0] = array[F] of Vector;
		norm[1] = array[F] of Vector;
	}
	Disp.draw(geo.r, black, opaque, (0, 0));
	reveal(geo.r);
	for(i := 0; ; i = (i+1)%p){
		alt{
			<- sync =>
				<- sync;
			θ = <- chanθ =>
				geo.θ = θ;
				initmatrix(geo);
				if(θ != 0.){
					n = int ((360.+θ/2.)/θ);
					p = int ((360.-totθ+θ/2.)/θ);
				}
				else
					n = p = ∞;
				if(p == 0)
					i = 0;
				else
					i = 1;
			* =>
				# yieldcpu(yieldc);
				sys->sleep(0);
		}
		if(concave)
			clearzbuf(geo.zstate);
		new := vec[t];
		old := vec[!t];
		if(concave){
			newn = norm[t];
			oldn = norm[!t];
		}
		t = !t;
		if(i == 0){
			for(j := 0; j < V; j++)
				new[j] = v[j];
			if(concave){
				for(j = 0; j < F; j++)
					newn[j] = f[j];
			}
			setview(geo);
			totθ = 0.;
			p = n;
		}
		else{
			for(j := 0; j < V; j++)
				new[j] = mulm(geo.TM, old[j]);
			if(concave){
				for(j = 0; j < F; j++)
					newn[j] = mulm(geo.TM, oldn[j]);
			}
			else{
				geo.view = mulmi(geo.TM, geo.view);
				geo.light = mulmi(geo.TM, geo.light);
			}
			totθ += θ;
		}
		if(clear)
			Disp.draw(geo.r, black, opaque, (0, 0));
		for(j := 0; j < F; j++){
			if(concave){
				if(allf || dot(geo.view, newn[j]) < 0.0)
					polyfilla(fv[j], new, newn[j], dot(geo.light, newn[j]), geo, concave, inc);
			}
			else{
				 if(dot(geo.view, f[j]) < 0.0)
					polyfilla(fv[j], new, f[j], dot(geo.light, f[j]), geo, concave, 0.0);
			}
		}
		reveal(geo.r);
	}	
}

ZSCALE: con real (1<<20);
LIMIT: con real (1<<11);

polyfilla(fv: array of int, v: array of Vector, f: Vector, ill: real, geo: ref Geom, concave: int, inc: real)
{
	dc, dx, dy: int;

	d := 0.0;
	n := fv[0];
	ap := array[n+1] of Point;
	for(j := 0; j < n; j++){
		vtx := v[fv[j+1]];
		# vtx = add(vtx, mul(f, 0.1));	# interesting effects with -/larger factors
		ap[j] = map(vtx, geo);
		d += dot(f, vtx);
	}
	ap[n] = ap[0];
	d /= real n;
	if(concave){
		if(fv[n+1] != 1)
			d += inc;
		if(f.z > -ε && f.z < ε)
			return;
		α := geo.sx;
		β := real geo.tx;
		γ := geo.sy;
		δ := real geo.ty;
		c := f.z;
		a := -f.x/(c*α);
		if(a <= -LIMIT || a >= LIMIT)
			return;
		b := -f.y/(c*γ);
		if(b <= -LIMIT || b >= LIMIT)
			return;
		d = d/c-β*a-δ*b;
		if(d <= -LIMIT || d >= LIMIT)
			return;
		dx = int (a*ZSCALE);
		dy = int (b*ZSCALE);
		dc = int (d*ZSCALE);
	}
	edge := white;
	face := shade[int ((real ((NSHADES-1)/2))*(1.0-ill))];
	if(concave){
		if(!faces)
			face = black;
		if(!edges)
			edge = nil;
		fillpoly(Disp, ap, ~0, face, (0, 0), geo.zstate, dc, dx, dy);
	}
	else{
		if(faces)
			Disp.fillpoly(ap, ~0, face, (0, 0));
		if(edges)
			Disp.poly(ap, Draw->Endsquare, Draw->Endsquare, 0, edge, (0, 0));
	}
}

getpoly(geo: ref Geom, dir: int)
{
	p := geo.curpolyhedron;
	if(0){
		while(p.anti){
			if(dir > 0)
				p = p.nxt;
			else
				p = p.prv;
		}
	}
	geo.curpolyhedron = p;
	getpolyhedron(p, geo.b);
}
	
degtorad(α: real): real
{
	return α*π/180.0;
}

initmatrix(geo: ref Geom)
{
	TM := geo.TM;
	φ := degtorad(geo.θ);
	sinθ := sin(φ);
	cosθ := cos(φ);
	(l, m, n) := normalize((real geo.axis.λ, real geo.axis.μ, real geo.axis.ν));
	f := 1.0-cosθ;
	TM[1][1] = (1.0-l*l)*cosθ + l*l;
	TM[1][2] = l*m*f-n*sinθ;
	TM[1][3] = l*n*f+m*sinθ;
	TM[2][1] = l*m*f+n*sinθ;
	TM[2][2] = (1.0-m*m)*cosθ + m*m;
	TM[2][3] = m*n*f-l*sinθ;
	TM[3][1] = l*n*f-m*sinθ;
	TM[3][2] = m*n*f+l*sinθ;
	TM[3][3] = (1.0-n*n)*cosθ + n*n;
}

mulm(TM: array of array of real, v: Vector): Vector
{
	x := v.x;
	y := v.y;
	z := v.z;
	v.x = TM[1][1]*x + TM[1][2]*y + TM[1][3]*z;
	v.y = TM[2][1]*x + TM[2][2]*y + TM[2][3]*z;
	v.z = TM[3][1]*x + TM[3][2]*y + TM[3][3]*z;
	return v;
}

mulmi(TM: array of array of real, v: Vector): Vector
{
	x := v.x;
	y := v.y;
	z := v.z;
	v.x = TM[1][1]*x + TM[2][1]*y + TM[3][1]*z;
	v.y = TM[1][2]*x + TM[2][2]*y + TM[3][2]*z;
	v.z = TM[1][3]*x + TM[2][3]*y + TM[3][3]*z;
	return v;
}

reveal(r: Rect)
{
	cmd := sys->sprint(".p dirty %d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
	tk->cmd(mainwin, cmd);
	tk->cmd(mainwin, "update");
}

newgeom(): ref Geom
{
	geo := ref Geom;
	TM := array[4] of array of real;
	for(i := 0; i < 4; i++)
		TM[i] = array[4] of real;
	geo.θ = 10.;
	geo.TM = TM;
	geo.axis = (1, 1, 1);
	geo.view = (1., 1., 1.);
	geo.light = (1., 1., 1.);
	geo.dual = 0;
	return geo;
}

setaxis(geo: ref Geom)
{
	oaxis := geo.axis;
	# while(geo.axis == Axis (0, 0, 0) || geo.axis = oaxis) not allowed
	while((geo.axis.λ == 0 && geo.axis.μ == 0 && geo.axis.ν == 0) || (geo.axis.λ == oaxis.λ && geo.axis.μ == oaxis.μ && geo.axis.ν == oaxis.ν))
		geo.axis = (rand->rand(5) - 2, rand->rand(5) - 2, rand->rand(5) - 2);
}

initgeom(geo: ref Geom)
{
	if(pinit < 0)
		pn := rand->rand(geo.npolyhedra);
	else
		pn = pinit;
	for(p := geo.polyhedra; --pn >= 0; p = p.nxt)
		;
	geo.curpolyhedron = p;
	getpoly(geo, 1);
	setaxis(geo);
  	geo.θ = real (rand->rand(5)+1);
	geo.dual = 0;
  	initmatrix(geo);
	setview(geo);
  	Disp.draw(geo.r, black, opaque, (0, 0));
	reveal(geo.r);
}

kill(pid: int): int
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil)
		return -1;
	if(sys->write(fd, array of byte "kill", 4) != 4)
		return -1;
	return 0;
}

exits(pid: int, sm: array of ref Scrollmenu)
{
	if(pid != -1)
		kill(pid);
	# kill(ypid);
	sm[0].destroy();
	sm[1].destroy();
	exit;
}

cmd(top: ref Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "polyhedra: tk error on '%s': %s\n", s, e);
	return e;
}

puts(s: string)
{
	cmd(mainwin, ".f1.txt configure -text {" + s + "}");
	cmd(mainwin, "update");
}

MENUMAX: con 10;

scrollmenu(top: ref Tk->Toplevel, mname: string, p: ref Polyhedron, n: int, dual: int): ref Scrollmenu
{
	labs := array[n] of string;
	i := 0;
	for(q := p; q != nil && i < n; q = q.nxt){
		if(dual)
			name := q.dname;
		else
			name = q.name;
		labs[i++] = string q.indx + " " + name;
	}
	sm := Scrollmenu.new(top, mname, labs, MENUMAX, (n-MENUMAX)/2);
	cmd(top, mname + " configure -borderwidth 3");
	return sm;
}

createmenu(top: ref Tk->Toplevel, p: ref Polyhedron)
{
	mn := ".f.menu";
	cmd(top, "menu " + mn);
	i := j := 0;
	for(q := p ; q != nil; q = q.nxt){
		cmd(top, mn + " add command -label {" + string q.indx + " " + q.name + "} -command {send cmd " + string q.indx + "}");
		if(q.nxt == p)
			break;
		i++;
		j++;
		if(j == MENUMAX && q.nxt != nil){
			cmd(top, mn + " add cascade -label MORE -menu " + mn + ".menu");
			mn += ".menu";
			cmd(top, "menu " + mn);
			j = 0;
		}
	}
}

fittoscreen(win: ref Tk->Toplevel)
{
	Point: import draw;
	if (win.image == nil || win.image.screen == nil)
		return;
	r := win.image.screen.image.r;
	scrsize := Point((r.max.x - r.min.x), (r.max.y - r.min.y));
	bd := int cmd(win, ". cget -bd");
	winsize := Point(int cmd(win, ". cget -actwidth") + bd * 2, int cmd(win, ". cget -actheight") + bd * 2);
	if (winsize.x > scrsize.x)
		cmd(win, ". configure -width " + string (scrsize.x - bd * 2));
	if (winsize.y > scrsize.y)
		cmd(win, ". configure -height " + string (scrsize.y - bd * 2));
	actr: Rect;
	actr.min = Point(int cmd(win, ". cget -actx"), int cmd(win, ". cget -acty"));
	actr.max = actr.min.add((int cmd(win, ". cget -actwidth") + bd*2,
				int cmd(win, ". cget -actheight") + bd*2));
	(dx, dy) := (actr.dx(), actr.dy());
	if (actr.max.x > r.max.x)
		(actr.min.x, actr.max.x) = (r.max.x - dx, r.max.x);
	if (actr.max.y > r.max.y)
		(actr.min.y, actr.max.y) = (r.max.y - dy, r.max.y);
	if (actr.min.x < r.min.x)
		(actr.min.x, actr.max.x) = (r.min.x, r.min.x + dx);
	if (actr.min.y < r.min.y)
		(actr.min.y, actr.max.y) = (r.min.y, r.min.y + dy);
	cmd(win, ". configure -x " + string actr.min.x + " -y " + string actr.min.y);
}

win_config := array[] of {
	"frame .f",
	"button .f.prev -text {prev} -command {send cmd prev}",
	"button .f.next -text {next} -command {send cmd next}",
	"checkbutton .f.dual -text {dual} -command {send cmd dual} -variable dual",
	".f.dual deselect",
	"pack .f.prev -side left",
	"pack .f.next -side right",
	"pack .f.dual -side top",

	"frame .f0",
	"checkbutton .f0.edges -text {edges} -command {send cmd edges} -variable edges",
	".f0.edges deselect",
	"checkbutton .f0.faces -text {faces} -command {send cmd faces} -variable faces",
	".f0.faces select",
	"checkbutton .f0.clear -text {clear} -command {send cmd clear} -variable clear",
	".f0.clear select",
	"pack .f0.edges -side left",
	"pack .f0.faces -side right",
	"pack .f0.clear -side top",

	"frame .f2",
	"button .f2.slow -text {slow} -command {send cmd slow}",
	"button .f2.fast -text {fast} -command {send cmd fast}",
	"button .f2.axis -text {axis} -command {send cmd axis}",
	"pack .f2.slow -side left",
	"pack .f2.fast -side right",
	"pack .f2.axis -side top",

	"frame .f1",
	"label .f1.txt -text { } -width " + string WIDTH,
	"pack .f1.txt -side top -fill x",

	"frame .f3",
	"button .f3.menu -text {menu} -command {send cmd menu}",
	"pack .f3.menu -side left",

	"frame .pbd -bd 3",
	"panel .p -width " + string WIDTH + " -height " + string HEIGHT,

	"pack .f -side top -fill x",
	"pack .f0 -side top -fill x",
	"pack .f2 -side top -fill x",
	"pack .f1 -side top -fill x",
	"pack .f3 -side top -fill x",
	"pack .p -in .pbd -fill both -expand 1",
	"pack .pbd -side bottom -fill both -expand 1",
	"pack propagate . 0",

};

rgba(d: ref Display, r: int, g: int, b: int, α: int): ref Image
{
	c := draw->setalpha((r<<24)|(g<<16)|(b<<8), α);
	return d.newimage(((0, 0), (1, 1)), d.image.chans, 1, c);
}
