implement Testsets;
include "sys.m";
	sys: Sys;
include "draw.m";
include "rand.m";
include "sets.m";		# "sets.m" or "sets32.m"
	sets: Sets;
	Set, set, A, B: import sets;

BPW: con 32;
SHIFT: con 5;
MASK: con 31;

Testsets: module {
	init: fn(nil: ref Draw->Context, nil: list of string);
};

∅: Set;

Testbig: con 1;

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	sets = load Sets Sets->PATH;
	if (sets == nil) {
		sys->print("cannot load %s: %r\n", Sets->PATH);
		exit;
	}
	rand := load Rand Rand->PATH;
	sets->init();

	∅ = set();
	s := set().addlist(1::2::3::4::nil);
	addit(s);
	sys->print("s %s\n", s.str());
	r := s.invert();
	sys->print("r %s\n", r.str());
	r = r.del(20);
	addit(r);
	sys->print("r del20: %s\n", r.str());
	z := r.X(~A&~B, s);
	addit(z);
	sys->print("z: %s\n", z.str());

	x := set();
	for (i := 0; i < 31; i++)
		if (rand->rand(2))
			x = x.add(i);
	addit(x);
	for(i = 0; i < 31; i++)
		addit(set().add(i));
	if (Testbig) {
		r = r.del(100);
		addit(r);
		sys->print("rz: %s\n", r.str());
		r = r.add(100);
		addit(r);
		sys->print("rz2: %s\n", r.str());
		x = set();
		for (i = 0; i < 200; i++)
			x = x.add(rand->rand(300));
		addit(x);
		for(i = 31; i < 70; i++)
			addit(set().add(i));
	}
	sys->print("empty: %s\n", set().str());
	addit(set());
	sys->print("full: %s\n", set().invert().str());
	test();
	sys->print("done tests\n");
}

ds(d: array of byte): string
{
	s := "";
	for(i := len d - 1; i >= 0; i--)
		s += sys->sprint("%.2x", int d[i]);
	return s;
}

testsets: list of Set;
addit(s: Set)
{
	testsets = s :: testsets;
}

test()
{
	for (t := testsets; t != nil; t = tl t)
		testsets = (hd t).invert() :: testsets;

	for (t = testsets; t != nil; t = tl t)
		testa(hd t);
	for (t = testsets; t != nil; t = tl t) {
		a := hd t;
		for (s := testsets; s != nil; s = tl s) {
			b := hd s;
			testab(a, b);
		}
	}
}

testab(a, b: Set)
{
	{
		check(!a.eq(b) == !b.eq(a), "equality");
		if (superset(a, b) && !a.eq(b))
			check(!superset(b, a), "superset");
	} exception {
	"test failed" =>
		sys->print("%s, %s [%s, %s]\n", a.str(), b.str(), a.debugstr(), b.debugstr());
	}
}

testa(a: Set)
{
	{
		check(sets->str2set(a.str()).eq(a), "string conversion");
		check(a.eq(a), "self equality");
		check(a.eq(a.invert().invert()), "double inversion");
		check(a.X(A&~B, a).eq(∅), "self not intersect");
		check(a.limit() == a.invert().limit(), "invert limit");
		check(a.X(A&~B, set().invert()).limit() == 0, "zero limit");
		check(sets->bytes2set(a.bytes(0)).eq(a), "bytes conversion");
		check(sets->bytes2set(a.bytes(3)).eq(a), "bytes conversion(2)");

		if (a.limit() > 0) {
			if (a.msb())
				check(!a.holds(a.limit() - 1), "hold limit 1");
			else
				check(a.holds(a.limit() - 1), "hold limit 2");
		}
	} exception {
	"test failed" =>
		sys->print("%s [%s]\n", a.str(), a.debugstr());
	}
}

check(ok: int, s: string)
{
	if (!ok) {
		sys->print("test failed: %s; ", s);
		raise "test failed";
	}
}

# return true if a is a superset of b
superset(a, b: Set): int
{
	return a.X(~A&B, b).eq(∅);
}
