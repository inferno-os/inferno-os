# fit a polynomial to a set of points
#	fit -dn [-v]
#		where n is the degree of the polynomial

implement Fit;

include "sys.m";
	sys: Sys;
include "draw.m";
include "math.m";
	maths: Math;
include "bufio.m";
	bufio: Bufio;
include "arg.m";

Fit: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

MAXPTS: con 512;
MAXDEG: con 16;
EPS: con 0.0000005;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	maths = load Math Math->PATH;
	if(maths == nil)
		fatal(sys->sprint("cannot load maths library"));
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		fatal(sys->sprint("cannot load bufio"));
	main(argv);
}

isn(r: real, n: int): int
{
	s := r - real n;
	if(s < 0.0)
		s = -s;
	return s < EPS;
}

fact(n: int): real
{
	f := 1.0;
	for(i := 1; i <= n; i++)
		f *= real i;
	return f;
}

comb(n: int, r: int): real
{
	f := 1.0;
	for(i := 0; i < r; i++)
		f *= real (n-i);
	return f/fact(r);
}

matalloc(n: int): array of array of real
{
	mat := array[n] of array of real;
	for(i := 0; i < n; i++)
		mat[i] = array[n] of real;
	return mat;
}

matsalloc(n: int): array of array of array of real
{
	mats := array[n+1] of array of array of real;
	for(i := 0; i <= n; i++)
		mats[i] = matalloc(i);
	return mats;
}

det(mat: array of array of real, n: int, mats: array of array of array of real): real
{
	# easy cases first
	if(n == 0)
		return 1.0;
	if(n == 1)
		return mat[0][0];
	if(n == 2)
		return mat[0][0]*mat[1][1]-mat[0][1]*mat[1][0];
	d := 0.0;
	s := 1;
	m := mats[n-1];
	for(k := 0; k < n; k++){
		for(i := 0; i < n-1; i++){
			for(j := 0; j < n-1; j++){
				if(j < k)
					m[i][j] = mat[i+1][j];
				else
					m[i][j] = mat[i+1][j+1];
			}
		}
		d += (real s)*mat[0][k]*det(m, n-1, mats);
		s = -s;
	}
	return d;
}

main(argv: list of string)
{
	i, j: int;
	x, y, z: real;
	fb: ref Bufio->Iobuf;

	n := 0;
	p := 1;
	arg := load Arg Arg->PATH;	
	if(arg == nil)
		fatal(sys->sprint("cannot load %s: %r", Arg->PATH));
	arg->init(argv);
	verbose := 0;
	while((o := arg->opt()) != 0)
		case o{
		'd' =>
			p = int arg->arg();
	 	'v' =>
			verbose = 1;
		* =>
			fatal(sys->sprint("bad option %c", o));
		}
	args := arg->argv();
	arg = nil;
	if(args != nil){
		s := hd args;
		fb = bufio->open(s, bufio->OREAD);
		if(fb == nil)
			fatal(sys->sprint("cannot open %s", s));
	}
	else{
		fb = bufio->open("/dev/cons", bufio->OREAD);
		if(fb == nil)
			fatal(sys->sprint("missing data file name"));
	}
	a := array[p+1] of real;
	b := array[p+1] of real;
	sx := array[2*p+1] of real;
	sxy := array[p+1] of real;
	xd := array[MAXPTS] of real;
	yd := array[MAXPTS] of real;
	while(1){
		xs := ss(bufio->fb.gett(" \t\r\n"));
		if(xs == nil)
			break;
		ys := ss(bufio->fb.gett(" \t\r\n"));
		if(ys == nil)
			fatal(sys->sprint("missing value"));
		if(n >= MAXPTS)
			fatal(sys->sprint("too many points"));
		xd[n] = real xs;
		yd[n] = real ys;
		n++;
	}
	if(p < 0)
		fatal(sys->sprint("negative power"));
	if(p > MAXDEG)
		fatal(sys->sprint("power too large"));
	if(n < p+1)
		fatal(sys->sprint("not enough points"));
	# use x-xbar, y-ybar to avoid overflow
	for(i = 0; i <= p; i++)
		sxy[i] = 0.0;
	for(i = 0; i <= 2*p; i++)
		sx[i] = 0.0;
	xbar := ybar := 0.0;
	for(i = 0; i < n; i++){
		xbar += xd[i];
		ybar += yd[i];
	}
	xbar = xbar/(real n);
	ybar = ybar/(real n);
	for(i = 0; i < n; i++){
		x = xd[i]-xbar;
		y = yd[i]-ybar;
		for(j = 0; j <= p; j++)
			sxy[j] += y*x**j;
		for(j = 0; j <= 2*p; j++)
			sx[j] += x**j;
	}
	mats := matsalloc(p+1);
	mat := mats[p+1];
	for(i = 0; i <= p; i++)
		for(j = 0; j <= p; j++)
			mat[i][j] = sx[i+j];
	d := det(mat, p+1, mats);
	if(isn(d, 0))
		fatal(sys->sprint("points not independent"));
	for(j = 0; j <= p; j++){
		for(i = 0; i <= p; i++)
			mat[i][j] = sxy[i];
		a[j] = det(mat, p+1, mats)/d;
		for(i = 0; i <= p; i++)
			mat[i][j] = sx[i+j];
	}
	if(verbose)
		sys->print("\npt	actual x	actual y	predicted y\n");
	e := 0.0;
	for(i = 0; i < n; i++){
		x = xd[i]-xbar;
		y = yd[i]-ybar;
		z = 0.0;
		for(j = 0; j <= p; j++)
			z += a[j]*x**j;
		z += ybar;
		e += (z-yd[i])*(z-yd[i]);
		if(verbose)
			sys->print("%d.	%f	%f	%f\n", i+1, xd[i], yd[i], z);
	}
	if(verbose)
		 sys->print("root mean squared error = %f\n", maths->sqrt(e/(real n)));
	for(i = 0; i <= p; i++)
		b[i] = 0.0;
	b[0] += ybar;
	for(i = 0; i <= p; i++)
		for(j = 0; j <= i; j++)
			b[j] += a[i]*comb(i, j)*(-xbar)**(i-j);
	pr := 0;
	sys->print("y = ");
	for(i = p; i >= 0; i--){
		if(!isn(b[i], 0) || (i == 0 && pr == 0)){
			if(b[i] < 0.0){
				sys->print("-");
				b[i] = -b[i];
			}
			else if(pr)
				sys->print("+");
			pr = 1;
			if(i == 0)
				sys->print("%f", b[i]);
			else{
				if(!isn(b[i], 1))
				 	sys->print("%f*", b[i]);
				 sys->print("x");
				if(i > 1)
		   			sys->print("^%d", i);
 			}
		}
	}
	sys->print("\n");
}

ss(s: string): string
{
	l := len s;
	while(l > 0 && (s[0] == ' ' || s[0] == '\t' || s[0] == '\r' || s[0] == '\n')){
		s = s[1: ];
		l--;
	}
	while(l > 0 && (s[l-1] == ' ' || s[l-1] == '\t' || s[l-1] == '\r' || s[l-1] == '\n')){
		s = s[0: l-1];
		l--;
	}
	return s;
}

fatal(s: string)
{
	sys->fprint(sys->fildes(2), "fit: %s\n", s);
	exit;
}
