implement Polyhedra;

include "sys.m";
	sys: Sys;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "math/polyhedra.m";

scanpolyhedra(f: string): (int, ref Polyhedron, ref Iobuf)
{
	first, last: ref Polyhedron;
	D: int;

	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(bufio == nil)
		bufio = load Bufio Bufio->PATH;
	b := bufio->open(f, Sys->OREAD);
	if(b == nil)
		return (0, nil, nil);
	n := 0;
	for(;;){
		s := getstring(b);
		if(s == nil)
			break;
		n++;
		p := ref Polyhedron;
		if(first == nil)
			first = p;
		else{
			last.nxt = p;
			p.prv = last;
		}
		last = p;
		p.name = s;
		p.dname = getstring(b);
		b.gets('\n');
		(p.allf, p.adj) = scanvc(getstring(b));
		b.gets('\n');
		b.gets('\n');
		b.gets('\n');
		l := getstring(b);
		(p.indx, l) = getint(l);
		(p.V, l) = getint(l);
		(p.E, l) = getint(l);
		(p.F, l) = getint(l);
		(nil, l) = getint(l);
		(D, l) = getint(l);
		(p.anti, l) = getint(l);
		p.concave = D != 1 || p.allf;
		p.offset = b.offset();
		tot := 2*p.V+2*p.F;
		for(i := 0; i < tot; i++)
			b.gets('\n');
		if(p.indx < 58 || p.indx == 59 || p.indx == 66 || p.indx == 67)
			p.inc = 0.1;
		else
			p.inc = 0.0;
		# sys->print("%d:	%d %d %d %d %s\n", p.indx, p.allf, D != 1, p.anti, p.concave, vc);
	}
	first.prv = last;
	last.nxt = first;
	return (n, first, b);
}

getpolyhedra(p: ref Polyhedron, b: ref Iobuf)
{
	q := p;
	do{
		getpolyhedron(q, b);
		q = q.nxt;
	}while(q != p);	
}

getpolyhedron(p: ref Polyhedron, b: ref Iobuf)
{
	if(p.v != nil)
		return;
	b.seek(p.offset, Bufio->SEEKSTART);
	p.v = array[p.V] of Vector;
	for(i := 0; i < p.V; i++)
		p.v[i] = getvector(b);
	p.f = array[p.F] of Vector;
	for(i = 0; i < p.F; i++)
		p.f[i] = getvector(b);
	p.fv = array[p.F] of array of int;
	for(i = 0; i < p.F; i++)
		p.fv[i] = getarray(b, p.adj);
	p.vf = array[p.V] of array of int;
	for(i = 0; i < p.V; i++)
		p.vf[i] = getarray(b, p.adj);
}

getstring(b: ref Iobuf): string
{
	s := b.gets('\n');
	if(s == nil)
		return nil;
	if(s[0] == '#')
		return getstring(b);
	if(s[len s - 1] == '\n')
		return s[0: len s - 1];
	return s;
}

getvector(b: ref Iobuf): Vector
{
	v: Vector;

	s := getstring(b);
	(v.x, s) = getreal(s);
	(v.y, s) = getreal(s);
	(v.z, s) = getreal(s);
	return v;
}

getarray(b: ref Iobuf, adj: int): array of int
{
	n, d: int;

	s := getstring(b);
	(n, s) = getint(s);
	a := array[n+2] of int;
	a[0] = n;
	for(i := 1; i <= n; i++)
		(a[i], s) = getint(s);
	(d, s) = getint(s);
	if(d == 0 || d == n-1 || adj)
		d = 1;
	a[n+1] = d;
	return a;
}

getint(s: string): (int, string)
{
	n := int s;
	for(i := 0; i < len s && s[i] == ' '; i++)
		;
	for( ; i < len s; i++)
		if(s[i] == ' ')
			return (n, s[i+1:]);
	return (n, nil);
}

getreal(s: string): (real, string)
{
	r := real s;
	for(i := 0; i < len s && s[i] == ' '; i++)
		;
	for( ; i < len s; i++)
		if(s[i] == ' ')
			return (r, s[i+1:]);
	return (r, nil);
}

vftab := array[] of { 0, 0, 0, 2, 3, 3, 5, 0, 3, 0, 3 };

scanvc(s: string): (int, int)
{
	af := 0;
	ad := 0;
	fd := ld := 1;
	ln := len s;
	if(ln > 0 && s[0] == '('){
		s = s[1:];
		ln--;
	}
	while(ln > 0 && s[ln-1] != ')'){
		s = s[0: ln-1];
		ln--;
	}
	(m, lst) := sys->tokenize(s, ".");
	for(l := lst ; l != nil; l = tl l){
		(m, lst) = sys->tokenize(hd l, "/");
		if(m == 1)
			(n, d) := (int hd lst, 1);
		else if(m == 2)
			(n, d) = (int hd lst, int hd tl lst);
		else
			sys->print("vc error\n");
		if(d != 1 && d == vftab[n])
			af = 1;
		if(d == n-1)
			d = 1;
		if(l == lst)
			fd = d;
		else if(ld != 1 && d != 1)
			ad = 1;
		ld = d;
	}
	if(ld != 1 && fd != 1)
		ad = 1;
	return (af, ad);
}
