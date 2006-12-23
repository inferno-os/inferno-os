implement Sets;
include "sys.m";
	sys: Sys;
include "sets32.m";

init()
{
	sys = load Sys Sys->PATH;
}

set(): Set
{
	return Set(0);
}

BITS: con 32;
MSB: con 1 << (BITS - 1);

Set.X(s1: self Set, o: int, s2: Set): Set
{
	return Set(op(o, s1.s, s2.s));
}

Set.invert(s: self Set): Set
{
	return Set(~s.s);
}

Set.add(s: self Set, n: int): Set
{
	return Set(s.s | (1 << n));
}

Set.del(s: self Set, n: int): Set
{
	return Set(s.s & ~(1 << n));
}

Set.addlist(s: self Set, ns: list of int): Set
{
	for (; ns != nil; ns = tl ns)
		s.s |= (1 << hd ns);
	return s;
}

Set.holds(s: self Set, n: int): int
{
	return s.s & (1 << n);
}

Set.str(s: self Set): string
{
	msb := s.s >> (BITS - 1);

	# discard all top bits that are the same as msb
	t := 16rf << (BITS - 4);
	sig := 8;
	while (t != 0) {
		if ((msb & t) != (s.s & t))
			break;
		sig--;
		t = (t >> 4) & 16r0fffffff;		# logical shift right
	}
	str: string;
	if (sig > 0) {
		top := ~MSB & s.s;
		if (sig < 8)		# shifting left by 32 bits is undefined.
			top &= (1 << (sig << 2)) - 1;
		str = sys->sprint("%.*ux", sig, top);
	}
	return str + ":" + string (msb & 1);
}

Set.bytes(s: self Set, n: int): array of byte
{
	m := (s.limit() >> 3) + 1;
	if(m > n)
		n = m;
	d := array[n] of byte;
	case len d {
	1 =>
		d[0] = byte s.s;
	2 =>
		d[0] = byte s.s;
		d[1] = byte (s.s >> 8);
	3 =>
		d[0] = byte s.s;
		d[1] = byte (s.s >> 8);
		d[2] = byte (s.s >> 16);
	4 =>
		d[0] = byte s.s;
		d[1] = byte (s.s >> 8);
		d[2] = byte (s.s >> 16);
		d[3] = byte (s.s >> 24);
	* =>
		d[0] = byte s.s;
		d[1] = byte (s.s >> 8);
		d[2] = byte (s.s >> 16);
		d[3] = byte (s.s >> 24);
		msb := byte (s.s >> (BITS - 1));		# sign extension
		for(i := 4; i < len d; i++)
			d[i] = msb;
	}
	return d;
}
		
bytes2set(d: array of byte): Set
{
	if(len d == 0)
		return Set(0);
	msb := ~(int (d[len d - 1] >> 7) - 1);
	v: int;
	case len d {
	1 =>
		v = int d[0] | (msb & int 16rffffff00);
	2 =>
		v = int d[0] | (int d[1] << 8) | (msb & int 16rffff0000);
	3 =>
		v = int d[0] | (int d[1] << 8) | (int d[2] << 16) | (msb & int 16rff000000);
	* or		# XXX could raise (or return) an error for len d > 4
	4 =>
		v = int d[0] | (int d[1] << 8) | (int d[2] << 16) | (int d[3] << 24);
	}
	return Set(v);
}


Set.debugstr(s: self Set): string
{
	return sys->sprint("%ux", s.s);
}

Set.eq(s1: self Set, s2: Set): int
{
	return s1.s == s2.s;
}

Set.isempty(s: self Set): int
{
	return s.s == 0;
}

Set.msb(s: self Set): int
{
	return (s.s & MSB) != 0;
}

Set.limit(s: self Set): int
{
	m := s.s >> (BITS - 1);	# sign extension
	return topbit(s.s ^ m);
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


str2set(str: string): Set
{
	n := len str;
	if (n < 2 || str[n - 2] != ':')
		return Set(0);
	c := str[n - 1];
	if (c != '0' && c != '1')
		return Set(0);
	n -= 2;
	msb := ~(c - '1');
	# XXX should we give some sort of error if there
	# are more bits than we can hold?
	return Set((hex2int(str[0:n], msb) & ~MSB) | (msb & MSB));
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
	2r1101 => return ~a | b;
	2r1110 => return a | b;
	2r1111 => return ~0;
	}
	return 0;
}
