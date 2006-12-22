implement GR;

include "sys.m";
	sys: Sys;
	print, sprint: import sys;
include "math.m";
	math: Math;
	ceil, fabs, floor, Infinity, log10, pow10, sqrt: import math;
include "draw.m";
	screen: ref Draw->Screen;
include "tk.m";
	tk: Tk;
	Toplevel: import tk;
include "tkclient.m";
	tkclient: Tkclient;
include "gr.m";

gr_cfg := array[] of {
	"frame .fc",
	"frame .fc.b",
	"label .fc.b.xy -text {0 0} -anchor e",
	"pack .fc.b.xy -fill x",
	"pack .fc.b -fill both -expand 1",
	"canvas .fc.c -relief sunken -bd 2 -width 600 -height 480 -bg white"+
		" -font /fonts/lucidasans/unicode.8.font",
	"pack .fc.c -fill both -expand 1",
	"pack .Wm_t -fill x",
	"pack .fc -fill both -expand 1",
	"pack propagate . 0",
	"bind .fc.c <ButtonPress-1> {send grcmd down1,%x,%y}",
};

TkCmd(t: ref Toplevel, arg: string): string
{
	rv := tk->cmd(t,arg);
	if(rv!=nil && rv[0]=='!')
		print("tk->cmd(%s): %s\n",arg,rv);
	return rv;
}


open(ctxt: ref Draw->Context, title: string): ref Plot
{
	if(sys==nil){
		sys = load Sys Sys->PATH;
		math = load Math Math->PATH;
		tk = load Tk Tk->PATH;
		tkclient = load Tkclient Tkclient->PATH;
		tkclient->init();
	}
	textsize := 8.;	# textsize is in points, if no user transform
	(t, tb) := tkclient->toplevel(ctxt, "", title, Tkclient->Appl);
	cc := chan of string;
	tk->namechan(t, cc, "grcmd");
	p := ref Plot(nil, Infinity,-Infinity,Infinity,-Infinity, textsize, t, tb, cc);
	for (i:=0; i<len gr_cfg; i++)
		tk->cmd(p.t,gr_cfg[i]);
	tkclient->onscreen(p.t, nil);
	tkclient->startinput(p.t, "kbd"::"ptr"::nil);
	return p;
}

Plot.bye(p: self ref Plot)
{
	cmdloop: for(;;) alt {
	s := <-p.t.ctxt.kbd =>
		tk->keyboard(p.t, s);
	s := <-p.t.ctxt.ptr =>
		tk->pointer(p.t, *s);
	s := <-p.t.ctxt.ctl or
	s = <-p.t.wreq or
	s = <-p.titlechan =>
		if(s == "exit")
			break cmdloop;
		tkclient->wmctl(p.t, s);
		case s{
		"size" =>
			canvw := int TkCmd(p.t, ".fc.c cget -width");
			canvh := int TkCmd(p.t, ".fc.c cget -height");
			TkCmd(p.t,".fc.b.xy configure -text {"+sprint("%d %d",canvw,canvh)+"}");
		}
	press := <-p.canvaschan =>
		(nil,cmds) := sys->tokenize(press,",");
		if(cmds==nil) continue;
		case hd cmds {
		"down1" =>
			xpos := real(hd tl cmds);
			ypos := real(hd tl tl cmds);
			x := (xpos-bx)/ax;
			y := -(ypos-tky+by)/ay;
			TkCmd(p.t,".fc.b.xy configure -text {"+sprint("%.3g %.3g",x,y)+"}");
		}
	}
	TkCmd(p.t,"destroy .;update");
	p.t = nil;
}

Plot.equalxy(p: self ref Plot)
{
	r := 0.;
	if( r < p.xmax - p.xmin ) r = p.xmax - p.xmin;
	if( r < p.ymax - p.ymin ) r = p.ymax - p.ymin;
	m := (p.xmax + p.xmin)/2.;
	p.xmax = m + r/2.;
	p.xmin = m - r/2.;
	m = (p.ymax + p.ymin)/2.;
	p.ymax = m + r/2.;
	p.ymin = m - r/2.;
}

Plot.graph(p: self ref Plot, x, y: array of real)
{
	n := len x;
	op := OP(GR->GRAPH, n, array[n] of real, array[n] of real, nil);
	while(n--){
		t := x[n];
		op.x[n] = t;
		if(t < p.xmin) 
			p.xmin = t;
		if(t > p.xmax) 
			p.xmax = t;
		t = y[n];
		op.y[n] = t;
		if(t < p.ymin) 
			p.ymin = t;
		if(t > p.ymax) 
			p.ymax = t;
	}
	p.op = op :: p.op;
}

Plot.text(p: self ref Plot, justify: int, s: string, x, y: real)
{
	op := OP(GR->TEXT, justify, array[1] of real, array[1] of real, s);
	op.x[0] = x;
	op.y[0] = y;
	p.op = op :: p.op;
}

Plot.pen(p: self ref Plot, nib: int)
{
	p.op = OP(GR->PEN, nib, nil, nil, nil) :: p.op;
}


#---------------------------------------------------------
# The rest of this file is concerned with sending the "display list"
# to Tk.  The only interesting parts of the problem are picking axes
# and drawing dashed lines properly.

ax, bx, ay, by: real;			# transform user to pixels
tky: con 630.;				# Tk_y = tky - y
nseg: int;				# how many segments in current stroke path
pendown: int;				# is pen currently drawing?
xoff := array[] of{"w","","e"};	# LJUST, CENTER, RJUST
yoff := array[] of{"n","","s","s"};	# HIGH, MED, BASE, LOW
linewidth: real;
toplevel: ref Toplevel;			# p.t
tkcmd: string;

mv(x, y: real)
{
	tkcmd = sprint(".fc.c create line %.1f %.1f", ax*x+bx, tky-(ay*y+by));
}

stroke()
{
	if(pendown){
		tkcmd += " -width 3";   # -capstyle round -joinstyle round
		TkCmd(toplevel,tkcmd);
		tkcmd = nil;
		pendown = 0;
		nseg = 0;
	}
}

vec(x, y: real)
{
	tkcmd += sprint(" %.1f %.1f", ax*x+bx, tky-(ay*y+by));
	pendown = 1;
	nseg++;
	if(nseg>1000){
		stroke();
		mv(x,y);
	}
}

circle(u, v, radius: real)
{
	x := ax*u+bx;
	y := tky-(ay*v+by);
	r := radius*(ax+ay)/2.;
	tkcmd = sprint(".fc.c create oval %.1f %.1f %.1f %.1f -width 3",
		x-r, y-r, x+r, y+r);
	TkCmd(toplevel,tkcmd);
	tkcmd = nil;
}

text(s: string, x, y: real, xoff, yoff: string)
{
	# rot = rotation in degrees.  90 is used for y-axis
	# x,y are in PostScript coordinate system, not user
	anchor := yoff + xoff;
	if(anchor!="")
		anchor = "-anchor " + anchor + " ";
	tkcmd = sprint(".fc.c create text %.1f %.1f %s-text '%s",
		ax*x+bx,
		tky-(ay*y+by), anchor, s);
	TkCmd(toplevel,tkcmd);
	tkcmd = nil;
}

datarange(xmin, xmax, margin: real): (real,real)
{
	r := 1.e-30;
	if( r < 0.001*fabs(xmin) ) 
		r = 0.001*fabs(xmin);
	if( r < 0.001*fabs(xmax) ) 
		r = 0.001*fabs(xmax);
	if( r < xmax-xmin ) 
		r = xmax-xmin;
	r *= 1.+2.*margin;
	x0 :=(xmin+xmax)/2. - r/2.;
	return ( x0, x0 + r);
}

dashed(ndash: int, x, y: array of real)
{
	cx, cy: real;	# current position
	d: real;	# length undone in p[i],p[i+1]
	t: real;	# length undone in current dash
	n := len x;
	if(n!=len y || n<=0)
		return;

	# choose precise dashlen
	s := 0.;
	for(i := 0; i < n - 1; i += 1){
		u := x[i+1] - x[i];
		v := y[i+1] - y[i];
		s += sqrt(u*u + v*v);
	}
	i = int floor(real ndash * s);
	if(i < 2) 
		i = 2;
	dashlen := s / real(2 * i - 1);

	t = dashlen;
	ink := 1;
	mv(x[0], y[0]);
	cx = x[0];
	cy = y[0];
	for(i = 0; i < n - 1; i += 1){
		u := x[i+1] - x[i];
		v := y[i+1] - y[i];
		d = sqrt(u * u + v * v);
		if(d > 0.){
			u /= d;
			v /= d;
			while(t <= d){
				cx += t * u;
				cy += t * v;
				if(ink){
					vec(cx, cy);
					stroke();
				}else{
					mv(cx, cy);
				}
				d -= t;
				t = dashlen;
				ink = 1 - ink;
			}
			cx = x[i+1];
			cy = y[i+1];
			if(ink){
				vec(cx, cy);
			}else{
				mv(cx, cy);
			}
			t -= d;
		}
	}
	stroke();
}

labfmt(x:real): string
{
	lab := sprint("%.6g",x);
	if(len lab>2){
		if(lab[0]=='0' && lab[1]=='.')
			lab = lab[1:];
		else if(lab[0]=='-' && len lab>3 && lab[1]=='0' && lab[2]=='.')
			lab = "-"+lab[2:];
	}
	return lab;
}

Plot.paint(p: self ref Plot, xlabel, xunit, ylabel, yunit: string)
{
	oplist: list of OP;

	# tunable parameters for dimensions of graph (fraction of box side)
	margin: con 0.075;		# separation of data from box boundary
	ticksize := 0.02;
	sep := ticksize;		# separation of text from box boundary

	# derived coordinates of various feature points...
	x0, x1, y0, y1: real;		# box corners, in original coord
	# radius := 0.2*p.textsize;	# radius for circle marker
	radius := 0.8*p.textsize;	# radius for circle marker

	Pen := SOLID;
	width := SOLID;
	linewidth = 2.;
	nseg = 0;
	pendown = 0;

	if(xunit=="") xunit = nil;
	if(yunit=="") yunit = nil;

	(x0,x1) = datarange(p.xmin,p.xmax,margin);
	ax = (400.-2.*p.textsize)/((x1-x0)*(1.+2.*sep));
	bx = 506.-ax*x1;
	(y0,y1) = datarange(p.ymin,p.ymax,margin);
	ay = (400.-2.*p.textsize)/((y1-y0)*(1.+2.*sep));
	by = 596.-ay*y1;
	# PostScript version
	# magic numbers here come from BoundingBox: 106 196 506 596
	# (x0,x1) = datarange(p.xmin,p.xmax,margin);
	# ax = (400.-2.*p.textsize)/((x1-x0)*(1.+2.*sep));
	# bx = 506.-ax*x1;
	# (y0,y1) = datarange(p.ymin,p.ymax,margin);
	# ay = (400.-2.*p.textsize)/((y1-y0)*(1.+2.*sep));
	# by = 596.-ay*y1;

	# convert from fraction of box to PostScript units
	ticksize *= ax*(x1-x0);
	sep *= ax*(x1-x0);

	# revert to original drawing order
	log := p.op;
	oplist = nil;
	while(log!=nil){
		oplist = hd log :: oplist;
		log = tl log;
	}
	p.op = oplist;

	toplevel = p.t;
	#------------send display list to Tk-----------------
	while(oplist!=nil){
		op := hd oplist;
		n := op.n;
		case op.code{
		GRAPH =>
			if(Pen == DASHED){
				dashed(17, op.x, op.y);
			}else if(Pen == DOTTED){
				dashed(85, op.x, op.y);
			}else{
				for(i:=0; i<n; i++){
					xx := op.x[i];
					yy := op.y[i];
					if(Pen == CIRCLE){
						circle(xx, yy, radius/(ax+ay));
					}else if(Pen == CROSS){
						mv(xx-radius/ax, yy);
						vec(xx+radius/ax, yy);
						stroke();
						mv(xx, yy-radius/ay);
						vec(xx, yy+radius/ay);
						stroke();
					}else if(Pen == INVIS){
					}else{
						if(i==0){
							mv(xx, yy);
						}else{
							vec(xx, yy);
						}
					}
				}
				stroke();
			}
		TEXT =>
			angle := 0.;
			if(op.n&UP) angle = 90.;
			text(op.t,op.x[0],op.y[0],xoff[n&7],yoff[(n>>3)&7]);
		PEN =>
			Pen = n;
			if( Pen==SOLID && width!=SOLID ){
				linewidth = 2.;
				width=SOLID;
			}else if( Pen==REFERENCE && width!=REFERENCE ){
				linewidth = 0.8;
				width=REFERENCE;
			}
		}
		oplist = tl oplist;
	}

	#--------------------now add axes-----------------------
	mv(x0,y0);
	vec(x1,y0);
	vec(x1,y1);
	vec(x0,y1);
	vec(x0,y0);
	stroke();

	# x ticks
	(lab1,labn,labinc,k,u,s) := mytic(x0,x1);
	for (i := lab1; i <= labn; i += labinc){
		r := real i*s*u;
		mv(r,y0);
		vec(r,y0+ticksize/ay);
		stroke();
		mv(r,y1);
		vec(r,y1-ticksize/ay);
		stroke();
		text(labfmt(real i*s),r,y0-sep/ay,"","n");
	}
	yy := y0-(2.*sep+p.textsize)/ay;
	labelstr := "";
	if(xlabel!=nil)
		labelstr = xlabel;
	if(k!=0||xunit!=nil)
		labelstr += " /";
	if(k!=0)
		labelstr += " ₁₀"+ string k;
	if(xunit!=nil)
		labelstr += " " + xunit;
	text(labelstr,(x0+x1)/2.,yy,"","n");

	# y ticks
	(lab1,labn,labinc,k,u,s) = mytic(y0,y1);
	for (i = lab1; i <= labn; i += labinc){
		r := real i*s*u;
		mv(x0,r);
		vec(x0+ticksize/ax,r);
		stroke();
		mv(x1,r);
		vec(x1-ticksize/ax,r);
		stroke();
		text(labfmt(real i*s),x0-sep/ax,r,"e","");
	}
	xx := x0-(4.*sep+p.textsize)/ax;
	labelstr = "";
	if(ylabel!=nil)
		labelstr = ylabel;
	if(k!=0||yunit!=nil)
		labelstr += " /";
	if(k!=0)
		labelstr += " ₁₀"+ string k;
	if(yunit!=nil)
		labelstr += " " + yunit;
	text(labelstr,xx,(y0+y1)/2.,"e","");

	TkCmd(p.t, "update");
}



# automatic tic choice                      Eric Grosse  9 Dec 84
# Input: low and high endpoints of expanded data range
# Output: lab1, labn, labinc, k, u, s   where the tics are
#   (lab1*s, (lab1+labinc)*s, ..., labn*s) * 10^k
# and u = 10^k.  k is metric, i.e. k=0 mod 3.

max3(a, b, c: real): real
{
	if(a<b) a=b;
	if(a<c) a=c;
	return(a);
}

my_mod(i, n: int): int
{
	while(i< 0) i+=n;
	while(i>=n) i-=n;
	return(i);
}

mytic(l, h: real): (int,int,int,int,real,real)
{
	lab1, labn, labinc, k, nlab, j, ndig, t1, tn: int;
	u, s: real;
	eps := .0001;
	k = int floor( log10((h-l)/(3.+eps)) );
	u = pow10(k);
	t1 = int ceil(l/u-eps);
	tn = int floor(h/u+eps);
	lab1 = t1;
	labn = tn;
	labinc = 1;
	nlab = labn - lab1 + 1;
	if( nlab>5 ){
		lab1 = t1 + my_mod(-t1,2);
		labn = tn - my_mod( tn,2);
		labinc = 2;
		nlab = (labn-lab1)/labinc + 1;
		if( nlab>5 ){
			lab1 = t1 + my_mod(-t1,5);
			labn = tn - my_mod( tn,5);
			labinc = 5;
			nlab = (labn-lab1)/labinc + 1;
			if( nlab>5 ){
				u *= 10.; 
				k++;
				lab1 = int ceil(l/u-eps);
				labn = int floor(h/u+eps);
				nlab = labn - lab1 + 1;
				labinc = 1;
			} else if( nlab<3 ){
				lab1 = t1 + my_mod(-t1,4);
				labn = tn - my_mod( tn,4);
				labinc = 4;
				nlab = (labn-lab1)/labinc + 1;
			}
		}
	}
	ndig = int(1.+floor(log10(max3(fabs(real lab1),fabs(real labn),1.e-30))));
	if( ((k<=0)&&(k>=-ndig))   # no zeros have to be added
	    || ((k<0)&&(k>=-3))
	    || ((k>0)&&(ndig+k<=4)) ){   # even with zeros, label is small
		s = u;
		k = 0;
		u = 1.;
	}else if(k>0){
		s = 1.;
		j = ndig;
		while(k%3!=0){ 
			k--; 
			u/=10.; 
			s*=10.; 
			j++; 
		}
		if(j-3>0){ 
			k+=3; 
			u*=1000.; 
			s/=1000.; 
		}
	}else{ # k<0
		s = 1.;
		j = ndig;
		while(k%3!=0){ 
			k++; 
			u*=10.; 
			s/=10.; 
			j--; 
		}
		if(j<0){ 
			k-=3; 
			u/=1000.; 
			s*=1000.; 
		}
	}
	return (lab1, labn, labinc, k, u, s);
}
