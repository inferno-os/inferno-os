implement Sets;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sets.m";

init()
{
	sys = load Sys Sys->PATH;
}

BPW: con 32;
SHIFT: con 5;
MASK: con 31;

# Set adt contains:
#	a - array holding membership of set s for n (0 ≤ n < len a * BPW).
#		∀ n: 0≤n<(len a*BPW), (s.a[n >> SHIFT] & (1 << (n & MASK)) != 0) iff s ∋ n
#	m - "most significant bits", extrapolate membership for n >= len a * BPW.
#		m is 0 if members are excluded by default,
#		or ~0 if members are included by default.

swapops := array[16] of {
	byte 2r0000, byte 2r0001, byte 2r0100, byte 2r0101,
	byte 2r0010, byte 2r0011, byte 2r0110, byte 2r0111,
	byte 2r1000, byte 2r1001, byte 2r1100, byte 2r1101,
	byte 2r1010, byte 2r1011, byte 2r1110, byte 2r1111,
};

Set.X(s1: self Set, o: int, s2: Set): Set
{
	if (len s1.a > len s2.a) {
		(s1, s2) = (s2, s1);
		o = int swapops[o & 2r1111];
	}
	r := Set(0, array[len s2.a] of int);
	for (i := 0; i < len s1.a; i++)
		r.a[i] = op(o, s1.a[i], s2.a[i]);
	for (; i < len s2.a; i++)
		r.a[i] = op(o, s1.m, s2.a[i]);
	r.m = op(o, s1.m, s2.m);
	return r;
}

Set.invert(s: self Set): Set
{
	r := Set(~s.m, array[len s.a] of int);
	for (i := 0; i < len s.a; i++)
		r.a[i] = ~s.a[i];
	return r;
}

# copy s, ensuring that the copy is big enough to hold n.
copy(s: Set, n: int): Set
{
	if (n >= 0) {
		req := (n >> SHIFT) + 1;
		if (req > len s.a) {
			a := array[req] of int;
			a[0:] = s.a;
			for (i := len s.a; i < len a; i++)
				a[i] = s.m;
			return (s.m, a);
		}
	}
	a: array of int;
	if (len s.a > 0) {
		a = array[len s.a] of int;
		a[0:] = s.a;
	}
	return (s.m, a);
}

Set.add(s: self Set, n: int): Set
{
	d := n >> SHIFT;
	if (s.m && d >= len s.a)
		return s;
	r := copy(s, n);
	r.a[d] |= 1<< (n & MASK);
	return r;
}

Set.addlist(s: self Set, ns: list of int): Set
{
	r: Set;
	if (s.m == 0) {
		max := -1;
		for (l := ns; l != nil; l = tl l)
			if (hd l > max)
				max = hd l;
		r = copy(s, max);
	} else
		r = copy(s, -1);
	for (; ns != nil; ns = tl ns) {
		n := hd ns;
		d := n >> SHIFT;
		if (d < len r.a)
			r.a[d] |= 1 << (n & MASK);
	}
	return r;
}


Set.del(s: self Set, n: int): Set
{
	d := n >> SHIFT;
	if (!s.m && d >= len s.a)
		return s;
	r := copy(s, n);
	r.a[d] &= ~(1 << (n & MASK));
	return r;
}

Set.holds(s: self Set, n: int): int
{
	d := n >> SHIFT;
	if (d >= len s.a)
		return s.m;
	return s.a[d] & (1 << (n & MASK));
}

Set.limit(s: self Set): int
{
	for (i := len s.a - 1; i >= 0; i--)
		if (s.a[i] != s.m)
			return (i<<SHIFT) + topbit(s.m ^ s.a[i]);
	return 0;
}

Set.eq(s1: self Set, s2: Set): int
{
	if (len s1.a > len s2.a)
		(s1, s2) = (s2, s1);
	for (i := 0; i < len s1.a; i++)
		if (s1.a[i] != s2.a[i])
			return 0;
	for (; i < len s2.a; i++)
		if (s1.m != s2.a[i])
			return 0;
	return s1.m == s2.m;
}

Set.isempty(s: self Set): int
{
	return Set(0, nil).eq(s);
}

Set.msb(s: self Set): int
{
	return s.m != 0;
}

Set.bytes(s: self Set, n: int): array of byte
{
	m := (s.limit() >> 3) + 1;
	if(m > n)
		n = m;
	d := array[n] of byte;
	# XXX this could proably be made substantially faster by unrolling the
	# loop a little.
	for(i := 0; i < len d; i++){
		j := i >> 2;
		if(j >= len s.a)
			d[i] = byte s.m;
		else
			d[i] = byte (s.a[j] >> ((i & 3) << 3));
	}
	return d;
}

bytes2set(d: array of byte): Set
{
	if(len d == 0)
		return (0, nil);
	a := array[(len d + 3) >> 2] of int;		# round up
	n := len d >> 2;
	for(i := 0; i < n; i++){
		j := i << 2;
		a[i] = int d[j] + (int d[j+1] << 8) + (int d[j+2] << 16) + (int d[j+3] << 24);
	}
	msb := ~(int (d[len d - 1] >> 7) - 1);
	j := i << 2;
	case len d & 3 {
	0 =>
		;
	1 =>
		a[i] = int d[j] | (msb & int 16rffffff00);
	2 =>
		a[i] = int d[j] | (int d[j+1] << 8) | (msb & int 16rffff0000);
	3 =>
		a[i] = int d[j] | (int d[j+1] << 8) | (int d[j+2] << 16) | (msb & int 16rff000000);
	}
	return (msb, a);
}

Set.str(s: self Set): string
{
	str: string;

	# discard all top bits that are the same as msb.
	sig := 0;
loop:
	for (i := len s.a - 1; i >= 0; i--) {
		t := 16rf << (BPW - 4);
		sig = 8;
		while (t != 0) {
			if ((s.m & t) != (s.a[i] & t))
				break loop;
			sig--;
			t = (t >> 4) & 16r0fffffff;		# logical shift right
		}
	}
	if (i >= 0) {
		top := s.a[i];
		if (sig < 8)		# shifting left by 32 bits is undefined.
			top &= (1 << (sig << 2)) - 1;
		str = sys->sprint("%.*ux", sig, top);
		for (i--; i >= 0; i--)
			str += sys->sprint("%.8ux", s.a[i]);
	}
	return str + ":" + string (s.m & 1);
}

str2set(str: string): Set
{
	n := len str;
	if (n < 2 || str[n - 2] != ':')
		return (0, nil);
	c := str[n - 1];
	if (c != '0' && c != '1')
		return (0, nil);
	msb := ~(c - '1');

	n -= 2;
	if (n == 0)
		return (msb, nil);
	req := ((n * 4 - 1) >> SHIFT) + 1;
	a := array[req] of int;
	d := 0;
	for (i := n; i > 0; ) {
		j := i - 8;
		if (j < 0)
			j = 0;
		a[d++] = hex2int(str[j:i], msb);
		i = j;
	}
	return (msb, a);
}

Set.debugstr(s: self Set): string
{
	str: string;
	for (i := len s.a - 1; i >= 0; i--)
		str += sys->sprint("%ux:", s.a[i]);
	str += sys->sprint(":%ux", s.m);
	return str;
}

set(): Set
{
	return (0, nil);
}

hex2int(s: string, fill: int): int
{
	n := fill;
	for (i := 0; i < len s; i++) {
		c := s[i];
		if (c >= '0' && c <= '9')
			c -= '0';
		else if (c >= 'a' && c <= 'f')
			c -= 'a' - 10;
		else if (c >= 'A' && c <= 'F')
			c -= 'A' - 10;
		else
			c = 0;
		n = (n << 4) | c;
	}
	return n;
}

op(o: int, a, b: int): int
{
	case o &  2r1111 {
	2r0000 => return 0;
	2r0001 => return ~(a | b);
	2r0010 => return a & ~b;
	2r0011 => return ~b;
	2r0100 => return ~a & b;
	2r0101 => return ~a;
	2r0110 => return a ^ b;
	2r0111 => return ~(a & b);
	2r1000 => return a & b;
	2r1001 => return ~(a ^ b);
	2r1010 => return a;
	2r1011 => return a | ~b;
	2r1100 => return b;
	2r1101 => return ~(a | b);
	2r1110 => return a | b;
	2r1111 => return ~0;
	}
	return 0;
}

topbit(v: int): int
{
	if (v == 0)
		return 0;
	(b, n, mask) := (1, 16, int 16rffff0000);
	while (n != 0) {
		if (v & mask) {
			b += n;
			v >>= n;		# could return if v==0 here if we thought it worth it
		}
		n >>= 1;
		mask >>= n;
	}
	return b;
}

nbits(n: int): int
{
	n = ((n >> 1) & 16r55555555) + (n & 16r55555555) ;
	n = ((n >> 2) & 16r33333333) + (n & 16r33333333) ;
	n = ((n >> 4) + n) & 16r0F0F0F0F ;
	n = ((n >> 8) + n) ;
	return ((n >> 16) + n) & 16rFF ;
}
