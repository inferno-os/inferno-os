implement Mersenne;

include "sys.m";
	sys : Sys;
include "draw.m";
include "ipints.m";
	ipints: IPints;
	IPint: import ipints;

# Test primality of Mersenne numbers

Mersenne: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	ipints = load IPints IPints->PATH;
	p := 3;
	if(tl argv != nil)
		p = int hd tl argv;
	if(isprime(p) && (p == 2 || lucas(p)))
		s := "";
	else
		s = "not ";
	sys->print("2^%d-1 is %sprime\n", p, s);
}

# s such that s^2 <= n
sqrt(n: int): int
{
	v := n;
	r := 0;
	for(t := 1<<30; t; t >>= 2){
		if(t+r <= v){
			v -= t+r;
			r = (r>>1)|t;
		}
		else
			r = r>>1;
	}
	return r;
}

isprime(n: int): int
{
	if(n < 2)
		return 0;
	if(n == 2)
		return 1;
	if((n&1) == 0)
		return 0;
	s := sqrt(n);
	for(i := 3; i <= s; i += 2)
		if(n%i == 0)
			return 0;
	return 1;
}

pow(b : ref IPint, n : int): ref IPint
{
	zero := IPint.inttoip(0);
	one := IPint.inttoip(1);
	if((b.cmp(zero) == 0 && n != 0) || b.cmp(one) == 0 || n == 1)
		return b;
	if(n == 0)
		return one;
	c := b;
	b = one;
	while(n){
		while(!(n & 1)){
			n >>= 1;
			c = c.mul(c);
		}
		n--;
		b = c.mul(b);
	}
	return b;
}

lucas(p: int): int
{
	zero := IPint.inttoip(0);
	one := IPint.inttoip(1);
	two := IPint.inttoip(2);
	bigp := pow(two, p).sub(one);
	u := IPint.inttoip(4);
	for(i := 2; i < p; i++){
		u = u.mul(u);
		if(u.cmp(two) <= 0)
			u = two.sub(u);
		else
			u = u.sub(two).expmod(one, bigp);
	}
	return u.cmp(zero) == 0;
}

