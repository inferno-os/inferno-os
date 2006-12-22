implement Hist0;

include "sys.m";
	sys: Sys;
	print: import sys;
include "math.m";
	math: Math;
	fmin: import math;

include "draw.m";
include "tk.m";
	tk: Tk;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "gr.m";
	gr: GR;
	Plot: import gr;

Hist0: module{
	init:	fn(nil: ref Draw->Context, argv: list of string);
};


plotfile(ctxt: ref Draw->Context, nil: list of string, filename: string){
	p := gr->open(ctxt,filename);
	input := bufio->open(filename,bufio->OREAD);
	if(input==nil){
		print("can't read %s",filename);
		exit;
	}

	n := 0;
	maxn := 100;
	x := array[maxn] of real;
	y := array[maxn] of real;
	while(1){
		xn := input.gett(" \t\n\r");
		if(xn==nil)
			break;
		yn := input.gett(" \t\n\r");
		if(yn==nil){
			print("after reading %d pairs, saw singleton\n",n);
			exit;
		}
		if(n>=maxn){
			maxn *= 2;
			newx := array[maxn] of real;
			newy := array[maxn] of real;
			for(i:=0; i<n; i++){
				newx[i] = x[i];
				newy[i] = y[i];
			}
			x = newx;
			y = newy;
		}
		x[n] = real xn;
		y[n] = real yn;
		n++;
	}
	if(n==0){
		print("empty input\n");
		exit;
	}

	for(i:=0; i<n; i++){
		h := 0.2;
		if(i==0) h *= x[i+1]-x[i];
		else if(i==n-1) h *= x[i]-x[i-1];
		else h *= fmin(x[i+1]-x[i],x[i]-x[i-1]);
		barx := array[] of{x[i]-h,x[i]-h,x[i]+h,x[i]+h,x[i]-h};
		bary := array[] of{0.,y[i],y[i],0.,0.};
		p.graph(barx,bary);
	}
	p.paint("",nil,"",nil);
	p.bye();
}

init(ctxt: ref Draw->Context, argv: list of string){
	sys = load Sys Sys->PATH;
	math = load Math Math->PATH;
	tk = load Tk Tk->PATH;
	bufio = load Bufio Bufio->PATH;
	if((gr = load GR GR->PATH) == nil){
		sys->print("%s: Can't load gr\n",hd argv);
		exit;
	}

	tkargs := "";
	argv = tl argv;
	if(argv != nil) {
		tkargs = hd argv;
		argv = tl argv;
	}
	if(argv!=nil)
		plotfile(ctxt,argv,hd argv);
}
