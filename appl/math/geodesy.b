implement Geodesy;

include "sys.m";
	sys: Sys;
include "math.m";
	maths: Math;
	Pi: import Math;
	sin, cos, tan, asin, acos, atan, atan2, sqrt, fabs: import maths;
include "math/geodesy.m";

Approx: con 0;

Epsilon: con 0.000001;
Mperft: con 0.3048;
Earthrad: con 10800.0/Pi*6076.115*Mperft;	# in feet (about 4000 miles) : now metres
Δt: con 16.0;	# now-1989

# lalo0: con "53:57:45N 01:04:55W";
# os0: con "SE6022552235";

# ellipsoids
Airy1830, Airy1830m, Int1924, GRS80: con iota;

Ngrid: con 100000;	# in metres

Vector: adt{
	x, y, z: real;
};

Latlong: adt{
	la: real;	# -Pi to Pi
	lo: real;	# -Pi to Pi
	x: real;
	y: real;
};

Ellipsoid: adt{
	name: string;
	a: real;
	b: real;
};

Datum: adt{
	name: string;
	e: int;
	# X, Y, Z axes etc
};

Mercator: adt{
	name: string;
	F0: real;
	φ0λ0: string;
	E0: real;
	N0: real;
	e: int;
};

Helmert: adt{
	tx, ty, tz: real;	# metres
	s: real;		# ppm
	rx, ry, rz: real;	# secs
};

Format: adt{
	dat: int;	# datum
	cdat: int;	# converting datum
	prj: int;		# projection
	tmp: ref Mercator;	# actual projection
	orig: Lalo;	# origin of above projection
	zone: int;	# UTM zone
};

# ellipsoids
ells := array[] of {
		Airy1830 => Ellipsoid("Airy1830", 6377563.396, 6356256.910),
		Airy1830m => Ellipsoid("Airy1830 modified", 6377340.189, 6356034.447),
		Int1924 => Ellipsoid("International 1924", 6378388.000, 6356911.946),
		GRS80 => Ellipsoid("GRS80", 6378137.000, 6356752.3141),
	};

# datums
dats := array[] of {
		OSGB36 => Datum("OSGB36", Airy1830),
		Ireland65 => Datum("Ireland65", Airy1830m),
		ED50 => Datum("ED50", Int1924),
		WGS84 => Datum("WGS84", GRS80),
		ITRS2000 => Datum("ITRS2000", GRS80),
		ETRS89 => Datum("ETRS89", GRS80),
	};

# transverse Mercator projections
tmps := array[] of {
		Natgrid => Mercator("National Grid", 0.9996012717, "49:00:00N 02:00:00W", real(4*Ngrid), real(-Ngrid), Airy1830),
		IrishNatgrid => Mercator("Irish National Grid", 1.000035, "53:30:00N 08:00:00W", real(2*Ngrid), real(5*Ngrid/2), Airy1830m),
		UTMEur => Mercator("UTM Europe", 0.9996, nil, real(5*Ngrid), real(0), Int1924),
		UTM => Mercator("UTM", 0.9996, nil, real(5*Ngrid), real(0), GRS80),
	};

# Helmert tranformations
HT_WGS84_OSGB36: con Helmert(-446.448, 125.157, -542.060, 20.4894, -0.1502, -0.2470, -0.8421);
HT_ITRS2000_ETRS89: con Helmert(0.054, 0.051, -0.048, 0.0, 0.000081*Δt, 0.00049*Δt, -0.000792*Δt);

# Helmert matrices
HM_WGS84_OSGB36, HM_OSGB36_WGS84, HM_ITRS2000_ETRS89, HM_ETRS89_ITRS2000, HM_ETRS89_OSGB36, HM_OSGB36_ETRS89, HM_IDENTITY: array of array of real;

fmt: ref Format;

# latlong: ref Latlong;

init(d: int, t: int, z: int)
{
	sys = load Sys Sys->PATH;
	maths = load Math Math->PATH;

	helmertinit();
	format(d, t, z);
	# (nil, (la, lo)) := str2lalo(lalo0);
	# (nil, (E, N)) := os2en(os0);
	# latlong = ref Latlong(la, lo, real E, real N);
}

format(d: int, t: int, z: int)
{
	if(fmt == nil)
		fmt = ref Format(WGS84, 0, Natgrid, nil, (0.0, 0.0), 30);
	if(d >= 0 && d <= ETRS89)
		fmt.dat = d;
	if(t >= 0 && t <= UTM)
		fmt.prj = t;
	if(z >= 1 && z <= 60)
		fmt.zone = z;
	fmt.cdat = fmt.dat;
	fmt.tmp = ref Mercator(tmps[fmt.prj]);
	if(fmt.tmp.φ0λ0 == nil)
		fmt.orig = utmlaloz(fmt.zone);
	else
		(nil, fmt.orig) = str2lalo(fmt.tmp.φ0λ0);
	e := fmt.tmp.e;
	if(e != dats[fmt.dat].e){
		for(i := 0; i <= ETRS89; i++)
			if(e == dats[i].e){
				fmt.cdat = i;
				break;
			}
	}
}

str2en(s: string): (int, Eano)
{
	s = trim(s, " \t\n\r");
	if(s == nil)
		return (0, (0.0, 0.0));
	os := s[0] >= 'A' && s[0] <= 'Z' || strchrs(s, "NSEW:") < 0;
	en: Eano;
	if(os){
		(ok, p) := os2en(s);
		if(!ok)
			return (0, (0.0, 0.0));	
		en = p;
	}
	else{
		(ok, lalo) := str2lalo(s);
		if(!ok)
			return (0, (0.0, 0.0));
		en = lalo2en(lalo);
	}
	return (1, en);
}

str2ll(s: string, pos: int, neg: int): (int, real)
{
	(n, ls) := sys->tokenize(s, ": \t");
	if(n < 1 || n > 3)
		return (0, 0.0);
	t := hd ls; ls = tl ls;
	v := real t;
	if(ls != nil){
		t = hd ls; ls = tl ls;
		v += (real t)/60.0;
	}
	if(ls != nil){
		t = hd ls; ls = tl ls;
		v += (real t)/3600.0;
	}
	c := t[len t-1];
	if(c == pos)
		;
	else if(c == neg)
		v = -v;
	else
		return (0, 0.0);
	return (1, norm(deg2rad(v)));
}

str2lalo(s: string): (int, Lalo)
{
	s = trim(s, " \t\n\r");
	p := strchr(s, 'N');
	if(p < 0)
		p = strchr(s, 'S');
	if(p < 0)
		return (0, (0.0, 0.0));
	(ok1, la) := str2ll(s[0: p+1], 'N', 'S');
	(ok2, lo) := str2ll(s[p+1: ], 'E', 'W');
	if(!ok1 || !ok2 || la < -Pi/2.0 || la > Pi/2.0)
		return (0, (0.0, 0.0));
	return (1, (la, lo));
}

ll2str(ll: int, dir: string): string
{
	d := ll/360000;
	ll -= 360000*d;
	m := ll/6000;
	ll -= 6000*m;
	s := ll/100;
	ll -= 100*s;
	return d2(d) + ":" + d2(m) + ":" + d2(s) + "." + d2(ll) + dir;
}

lalo2str(lalo: Lalo): string
{
	la := int(360000.0*rad2deg(lalo.la));
	lo := int(360000.0*rad2deg(lalo.lo));
	lad := "N";
	lod := "E";
	if(la < 0){
		lad = "S";
		la = -la;
	}
	if(lo < 0){
		lod = "W";
		lo = -lo;
	}
	return ll2str(la, lad) + " " + ll2str(lo, lod);
}

en2os(p: Eano): string
{
	E := trunc(p.e);
	N := trunc(p.n);
	es := E/Ngrid;
	ns := N/Ngrid;
	e := E-Ngrid*es;
	n := N-Ngrid*ns;
	d1 := 5*(4-ns/5)+es/5+'A'-3;
	d2 := 5*(4-ns%5)+es%5+'A';
	# now account for 'I' missing
	if(d1 >= 'I')
		d1++;
	if(d2 >= 'I')
		d2++;
	return sys->sprint("%c%c%5.5d%5.5d", d1, d2, e, n);
}

os2en(s: string): (int, Eano)
{
	s = trim(s, " \t\n\r");
	if((m := len s) != 4 && m != 6 && m != 8 && m != 10 && m != 12)
		return (0, (0.0, 0.0));
	m = m/2-1;
	u := Ngrid/10**m;
	d1 := s[0];
	d2 := s[1];
	if(d1 < 'A' || d2 < 'A' || d1 > 'Z' || d2 > 'Z'){
		# error(sys->sprint("bad os reference %s", s));
		e := u*int s[0: 1+m];
		n := u*int s[1+m: 2+2*m];
		return (1, (real e, real n));
	}
	e := u*int s[2: 2+m];
	n := u*int s[2+m: 2+2*m];
	if(d1 >= 'I')
		d1--;
	if(d2 >= 'I')
		d2--;
	d1 -= 'A'-3;
	d2 -= 'A';
	es := 5*(d1%5)+d2%5;
	ns := 5*(4-d1/5)+4-d2/5;
	return (1, (real(Ngrid*es+e), real(Ngrid*ns+n)));
}

utmlalo(lalo: Lalo): Lalo
{
	(nil, zn) := utmzone(lalo);
	return utmlaloz(zn);
}

utmlaloz(zn: int): Lalo
{
	return (0.0, deg2rad(real(6*zn-183)));
}

utmzone(lalo: Lalo): (int, int)
{
	(la, lo) := lalo;
	la = rad2deg(la);
	lo = rad2deg(lo);
	zlo := trunc(lo+180.0)/6+1;
	if(la < -80.0)
		zla := 'B';
	else if(la >= 84.0)
		zla = 'Y';
	else if(la >= 72.0)
		zla = 'X';
	else{
		zla = trunc(la+80.0)/8+'C';
		if(zla >= 'I')
			zla++;
		if(zla >= 'O')
			zla++;
	}
	return (zla, zlo);
}

helmertinit()
{
	(HM_WGS84_OSGB36, HM_OSGB36_WGS84) = helminit(HT_WGS84_OSGB36);
	(HM_ITRS2000_ETRS89, HM_ETRS89_ITRS2000) = helminit(HT_ITRS2000_ETRS89);
	HM_ETRS89_OSGB36 = mulmm(HM_WGS84_OSGB36, HM_ETRS89_ITRS2000);
	HM_OSGB36_ETRS89 = mulmm(HM_ITRS2000_ETRS89, HM_OSGB36_WGS84);
	HM_IDENTITY = m := matrix(3, 4);
	m[0][0] = m[1][1] = m[2][2] = 1.0;
	# mprint(HM_WGS84_OSGB36);
	# mprint(HM_OSGB36_WGS84);
}

helminit(h: Helmert): (array of array of real, array of array of real)
{
	m := matrix(3, 4);

	s := 1.0+h.s/1000000.0;
	rx := sec2rad(h.rx);
	ry := sec2rad(h.ry);
	rz := sec2rad(h.rz);

	m[0][0] = s;
	m[0][1] = -rz;
	m[0][2] = ry;
	m[0][3] = h.tx;
	m[1][0] = rz;
	m[1][1] = s;
	m[1][2] = -rx;
	m[1][3] = h.ty;
	m[2][0] = -ry;
	m[2][1] = rx;
	m[2][2] = s;
	m[2][3] = h.tz;

	return (m, inv(m));
}

trans(f: int, t: int): array of array of real
{
	case(f){
	WGS84 =>
		case(t){
		WGS84 =>
			return HM_IDENTITY;
		OSGB36 =>
			return HM_WGS84_OSGB36;
		ITRS2000 =>
			return HM_IDENTITY;
		ETRS89 =>
			return HM_ITRS2000_ETRS89;
		}
	OSGB36 =>
		case(t){
		WGS84 =>
			return HM_OSGB36_WGS84;
		OSGB36 =>
			return HM_IDENTITY;
		ITRS2000 =>
			return HM_OSGB36_WGS84;
		ETRS89 =>
			return HM_OSGB36_ETRS89;
		}
	ITRS2000 =>
		case(t){
		WGS84 =>
			return HM_IDENTITY;
		OSGB36 =>
			return HM_WGS84_OSGB36;
		ITRS2000 =>
			return HM_IDENTITY;
		ETRS89 =>
			return HM_ITRS2000_ETRS89;
		}
	ETRS89 =>
		case(t){
		WGS84 =>
			return HM_ETRS89_ITRS2000;
		OSGB36 =>
			return HM_ETRS89_OSGB36;
		ITRS2000 =>
			return HM_ETRS89_ITRS2000;
		ETRS89 =>
			return HM_IDENTITY;
		}
	}
	return HM_IDENTITY;	# Ireland65, ED50 not done
}

datum2datum(lalo: Lalo, f: int, t: int): Lalo
{
	if(f == t)
		return lalo;
	(la, lo) := lalo;
	v := laloh2xyz(la, lo, 0.0, dats[f].e);
	v = mulmv(trans(f, t), v);
	(la, lo, nil) = xyz2laloh(v, dats[t].e);
	return (la, lo);
}

laloh2xyz(φ: real, λ: real, H: real, e: int): Vector
{
	a := ells[e].a;
	b := ells[e].b;
	e2 := 1.0-(b/a)**2;

	s := sin(φ);
	c := cos(φ);

	ν := a/sqrt(1.0-e2*s*s);
	x := (ν+H)*c*cos(λ);
	y := (ν+H)*c*sin(λ);
	z := ((1.0-e2)*ν+H)*s;

	return (x, y, z);
}

xyz2laloh(v: Vector, e: int): (real, real, real)
{
	x := v.x;
	y := v.y;
	z := v.z;

	a := ells[e].a;
	b := ells[e].b;
	e2 := 1.0-(b/a)**2;

	λ := atan2(y, x);

	p := sqrt(x*x+y*y);
	φ := φ1 := atan(z/(p*(1.0-e2)));
	ν := 0.0;
	do{
		φ = φ1;
		s := sin(φ);
		ν = a/sqrt(1.0-e2*s*s);
		φ1 = atan((z+e2*ν*s)/p);
	}while(!small(fabs(φ-φ1)));

	φ = φ1;
	H := p/cos(φ)-ν;

	return (φ, λ, H);
}

lalo2en(lalo: Lalo): Eano
{
	(φ, λ) := lalo;
	if(fmt.cdat != fmt.dat)
		(φ, λ) = datum2datum(lalo, fmt.dat, fmt.cdat);

	s := sin(φ);
	c := cos(φ);
	t2 := tan(φ)**2;

	(nil, F0, φ0λ0, E0, N0, e) := *fmt.tmp;
	a := ells[e].a;
	b := ells[e].b;
	e2 := 1.0-(b/a)**2;

	if(φ0λ0 == nil)	# UTM
		(φ0, λ0) := utmlalo((φ, λ));	# don't use fmt.zone here
	else
		(φ0, λ0) = fmt.orig;

	n := (a-b)/(a+b);
	ν := a*F0/sqrt(1.0-e2*s*s);
	ρ := ν*(1.0-e2)/(1.0-e2*s*s);
	η2 := ν/ρ-1.0;

	φ1 := φ-φ0;
	φ2 := φ+φ0;
	M := b*F0*((1.0+n*(1.0+1.25*n*(1.0+n)))*φ1 - (3.0*n*(1.0+n*(1.0+0.875*n)))*sin(φ1)*cos(φ2) + 1.875*n*n*(1.0+n)*sin(2.0*φ1)*cos(2.0*φ2) - 35.0/24.0*n**3*sin(3.0*φ1)*cos(3.0*φ2));

	I := M+N0;
	II := ν*s*c/2.0;
	III := ν*s*c**3*(5.0-t2+9.0*η2)/24.0;
	IIIA := ν*s*c**5*(61.0+t2*(t2-58.0))/720.0;
	IV := ν*c;
	V := ν*c**3*(ν/ρ-t2)/6.0;
	VI := ν*c**5*(5.0+14.0*η2+t2*(t2-18.0-58.0*η2))/120.0;

	λ -= λ0;
	λ2 := λ*λ;
	N := I+λ2*(II+λ2*(III+IIIA*λ2));
	E := E0+λ*(IV+λ2*(V+VI*λ2));

	# if(E < 0.0 || E >= real(7*Ngrid))
	# 	E = 0.0;
	# if(N < 0.0 || N >= real(13*Ngrid))
	# 	N = 0.0;
	return (E, N);
}

en2lalo(en: Eano): Lalo
{
	E := en.e;
	N := en.n;

	(nil, F0, nil, E0, N0, e) := *fmt.tmp;
	a := ells[e].a;
	b := ells[e].b;
	e2 := 1.0-(b/a)**2;

	(φ0, λ0) := fmt.orig;

	n := (a-b)/(a+b);

	M0 := 1.0+n*(1.0+1.25*n*(1.0+n));
	M1 := 3.0*n*(1.0+n*(1.0+0.875*n));
	M2 := 1.875*n*n*(1.0+n);
	M3 := 35.0/24.0*n**3;

	N -= N0;
	M := 0.0;
	φ := φold := φ0;
	do{
		φ = (N-M)/(a*F0)+φold;
		φ1 := φ-φ0;
		φ2 := φ+φ0;
		M = b*F0*(M0*φ1 - M1*sin(φ1)*cos(φ2) + M2*sin(2.0*φ1)*cos(2.0*φ2) - M3*sin(3.0*φ1)*cos(3.0*φ2));
		φold = φ;
	}while(fabs(N-M) >= 0.01);

	s := sin(φ);
	c := cos(φ);
	t := tan(φ);
	t2 := t*t;

	ν := a*F0/sqrt(1.0-e2*s*s);
	ρ := ν*(1.0-e2)/(1.0-e2*s*s);
	η2 := ν/ρ-1.0;

	VII := t/(2.0*ρ*ν);
	VIII := VII*(5.0+η2+3.0*t2*(1.0-3.0*η2))/(12.0*ν*ν);
	IX := VII*(61.0+45.0*t2*(2.0+t2))/(360.0*ν**4);
	X := 1.0/(ν*c);
	XI := X*(ν/ρ+2.0*t2)/(6.0*ν*ν);
	XII := X*(5.0+4.0*t2*(7.0+6.0*t2))/(120.0*ν**4);
	XIIA := X*(61.0+2.0*t2*(331.0+60.0*t2*(11.0+6.0*t2)))/(5040.0*ν**6);

	E -= E0;
	E2 := E*E;
	φ = φ-E2*(VII-E2*(VIII-E2*IX));
	λ := λ0+E*(X-E2*(XI-E2*(XII-E2*XIIA)));

	if(fmt.cdat != fmt.dat)
		(φ, λ) = datum2datum((φ, λ), fmt.cdat, fmt.dat);
	return (φ, λ);
}

mulmm(m1: array of array of real, m2: array of array of real): array of array of real
{
	m := matrix(3, 4);
	mul3x3(m, m1, m2);
	for(i := 0; i < 3; i++){
		sum := 0.0;
		for(k := 0; k < 3; k++)
			sum += m1[i][k]*m2[k][3];
		m[i][3] = sum+m1[i][3];
	}
	return m;
}

mulmv(m: array of array of real, v: Vector): Vector
{
	x := v.x;
	y := v.y;
	z := v.z;
	v.x = m[0][0]*x + m[0][1]*y + m[0][2]*z + m[0][3];
	v.y = m[1][0]*x + m[1][1]*y + m[1][2]*z + m[1][3];
	v.z = m[2][0]*x + m[2][1]*y + m[2][2]*z + m[2][3];
	return v;
}

inv(m: array of array of real): array of array of real
{
	n := matrix(3, 4);
	inv3x3(m, n);
	(n[0][3], n[1][3], n[2][3]) = mulmv(n, (-m[0][3], -m[1][3], -m[2][3]));
	return n;
}

mul3x3(m: array of array of real, m1: array of array of real, m2: array of array of real)
{
	for(i := 0; i < 3; i++){
		for(j := 0; j < 3; j++){
			sum := 0.0;
			for(k := 0; k < 3; k++)
				sum += m1[i][k]*m2[k][j];
			m[i][j] = sum;
		}
	}
}

inv3x3(m: array of array of real, n: array of array of real)
{
	t00 := m[0][0];
	t01 := m[0][1];
	t02 := m[0][2];
	t10 := m[1][0];
	t11 := m[1][1];
	t12 := m[1][2];
	t20 := m[2][0];
	t21 := m[2][1];
	t22 := m[2][2];

	n[0][0] = t11*t22-t12*t21;
	n[1][0] = t12*t20-t10*t22;
	n[2][0] = t10*t21-t11*t20;
	n[0][1] = t02*t21-t01*t22;
	n[1][1] = t00*t22-t02*t20;
	n[2][1] = t01*t20-t00*t21;
	n[0][2] = t01*t12-t02*t11;
	n[1][2] = t02*t10-t00*t12;
	n[2][2] = t00*t11-t01*t10;

	d := t00*n[0][0]+t01*n[1][0]+t02*n[2][0];
	for(i := 0; i < 3; i++)
		for(j := 0; j < 3; j++)
			n[i][j] /= d;
}

matrix(rows: int, cols: int): array of array of real
{
	m := array[rows] of array of real;
	for(i := 0; i < rows; i++)
		m[i] = array[cols] of { * => 0.0 };
	return m;
}

vprint(v: Vector)
{
	sys->print("	%f	%f	%f\n", v.x, v.y, v.z);
}

mprint(m: array of array of real)
{
	for(i := 0; i < len m; i++){
		for(j := 0; j < len m[i]; j++)
			sys->print("	%f", m[i][j]);
		sys->print("\n");
	}
}

# lalo2xy(la: real, lo: real, lalo: ref Latlong): Eano
# {
# 	x, y: real;
# 
# 	la0 := lalo.la;
# 	lo0 := lalo.lo;
# 	if(Approx){
# 		x = Earthrad*cos(la0)*(lo-lo0)+lalo.x;
# 		y = Earthrad*(la-la0)+lalo.y;
# 	}
# 	else{
# 		x = Earthrad*cos(la)*sin(lo-lo0)+lalo.x;
# 		y = Earthrad*(sin(la)*cos(la0)-sin(la0)*cos(la)*cos(lo-lo0))+lalo.y;
# 	}
# 	return (x, y);
# }

# lalo2xyz(la: real, lo: real, lalo: ref Latlong): (int, int, int)
# {
# 	z: real;
# 
# 	la0 := lalo.la;
#     	lo0 := lalo.lo;
# 	(x, y) := lalo2xy(la, lo, lalo);
# 	if(Approx)
# 		z = Earthrad;
# 	else
# 		z = Earthrad*(sin(la)*sin(la0)+cos(la)*cos(la0)*cos(lo-lo0));
# 	return (x, y, int z);
# }

# xy2lalo(p: Eano, lalo: ref Latlong): (real, real)
# {
# 	la, lo: real;
# 
# 	x := p.e;
# 	y := p.n;
# 	la0 := lalo.la;
# 	lo0 := lalo.lo;
# 	if(Approx){
# 		la = la0 + (y-lalo.y)/Earthrad;
# 		lo = lo0 + (x-lalo.x)/(Earthrad*cos(la0));
# 	}
# 	else{
# 		a, b, c, d, bestd, r, r1, r2, lat, lon, tmp: real;
# 		i, n: int;
# 
# 		bestd = -1.0;
# 		la = lo = 0.0;
# 		a = (x-lalo.x)/Earthrad;
# 		b = (y-lalo.y)/Earthrad;
# 		(n, r1, r2) = quad(1.0, -2.0*b*cos(la0), (a*a-1.0)*sin(la0)*sin(la0)+b*b);
# 		if(n == 0)
# 			return (la, lo);
# 		while(--n >= 0){
# 			if(n == 1)
# 				r = r2;
# 			else
# 				r = r1;
# 			if(fabs(r) <= 1.0){
# 				lat = asin(r);
# 				c = cos(lat);
# 				if(small(c))
# 					tmp = 0.0;	# lat = +90, -90, lon = lo0
# 				else
# 					tmp = a/c;
# 				if(fabs(tmp) <= 1.0){
# 					for(i = 0; i < 2; i++){
# 						if(i == 0)
# 							lon = norm(asin(tmp)+lo0);
# 						else
# 							lon = norm(Pi-asin(tmp)+lo0);
# 						(X, Y, Z) := lalo2xyz(lat, lon, lalo);
# 						# eliminate non-roots by d, root on other side of earth by Z
# 						d = (real X-x)**2+(real Y-y)**2;
# 						if(Z >= 0 && (bestd < 0.0 || d < bestd)){
# 							bestd = d;
# 							la = lat;
# 							lo = lon;
# 						}
# 					}
# 				}
# 			}
# 		}
# 	}
# 	return (la, lo);
# }

# quad(a: real, b: real, c: real): (int, real, real)
# {
# 	r1, r2: real;
# 
# 	D := b*b-4.0*a*c;
# 	if(small(a)){
# 		if(small(b))
# 			return (0, r1, r2);
# 		r1 = r2 = -c/b;
# 		return (1, r1, r2);
# 	}
# 	if(D < 0.0)
# 		return (0, r1, r2);
# 	D = sqrt(D);
# 	r1 = (-b+D)/(2.0*a);
# 	r2 = (-b-D)/(2.0*a);
# 	if(small(D))
# 		return (1, r1, r2);
# 	else
# 		return (2, r1, r2);
# }

d2(v: int): string
{
	s := string v;
	if(v < 10)
		s = "0" + s;
	return s;
}

trim(s: string, t: string): string
{
	while(s != nil && strchr(t, s[0]) >= 0)
		s = s[1: ];
	while(s != nil && strchr(t, s[len s-1]) >= 0)
		s = s[0: len s-1];
	return s;
}

strchrs(s: string, t: string): int
{
	for(i := 0; i < len t; i++){
		p := strchr(s, t[i]);
		if(p >= 0)
			return p;
	}
	return -1;
}

strchr(s: string, c: int): int
{
	for(i := 0; i < len s; i++)
		if(s[i] == c)
			return i;
	return -1;
}

deg2rad(d: real): real
{
	return d*Pi/180.0;
}

rad2deg(r: real): real
{
	return r*180.0/Pi;
}

sec2rad(s: real): real
{
	return deg2rad(s/3600.0);
}

norm(r: real): real
{
	while(r > Pi)
		r -= 2.0*Pi;
	while(r < -Pi)
		r += 2.0*Pi;
	return r;
}

small(r: real): int
{
	return r > -Epsilon && r < Epsilon;
}

trunc(r: real): int
{
	# down : assumes r >= 0
	i := int r;
	if(real i > r)
		i--;
	return i;
}

abs(x: int): int
{
	if(x < 0)
		return -x;
	return x;
}
