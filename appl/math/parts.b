implement Partitions;

include "sys.m";
	sys : Sys;
include "draw.m";
include "keyring.m";
	keyring: Keyring;
	IPint: import keyring;

#
# the number p(n) of partitions of n 
# based upon the formula :-
# p(n) = p(n-1)+p(n-2)-p(n-5)-p(n-7)+p(n-12)+p(n-15)-p(n-22)-p(n-26)+.....
# where p[0] = 1 and p[m] = 0 for m < 0
#

aflag := 0;
cflag := 0;

Partitions: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	keyring = load Keyring Keyring->PATH;
	argv = tl argv;
	while(argv != nil){
		s := hd argv;
		if(s != nil && s[0] == '-'){
			for(i := 1; i < len s; i++){
				case s[i]{
					'a' => aflag = 1;
					'c' => cflag = 1;
				}
			}
		}
		else
			parts(int s);
		argv = tl argv;
	}
}

parts(m : int)
{
	if (aflag)
		sys->print("n	p(n)\n");
	if (m <= 0) {
		p := 0;
		if (m == 0)
			p = 1;
		if (aflag)
			sys->print("%d	%d\n", m, p);
		else
			sys->print("p[%d] = %d\n", m, p);
		return;
	}
	p := array[m+1] of ref IPint;
	if (p == nil)
		return;
	p[0] = IPint.inttoip(1);
	for (i := 1; i <= m; i++) {
		k := i;
		s := 1;
		n := IPint.inttoip(0);
		for (j := 1; ; j++) {
			k -= 2*j-1;
			if (k < 0)
				break;
			if (s == 1)
				n = n.add(p[k]);
			else
				n = n.sub(p[k]);
			k -= j;
			if (k < 0)
				break;
			if (s == 1)
				n = n.add(p[k]);
			else
				n = n.sub(p[k]);
			s = -s;
		}
		if (aflag)
			sys->print("%d	%s\n", i, n.iptostr(10));
		p[i] = n;
	}
	if (!aflag)
		sys->print("p[%d] = %s\n", m, p[m].iptostr(10));
	if (cflag)
		check(m, p);
}

#
# given p[0]..p[m], search for congruences of the form
# p[ni+j] = r mod i
#
check(m : int, p : array of ref IPint)
{
	one := IPint.inttoip(1);
	for (i := 2; i < m/3; i++) {
		ip := IPint.inttoip(i);
		for (j := 0; j < i; j++) {
			k := j;
			r := p[k].expmod(one, ip).iptoint();
			s := 1;
			for (;;) {
				k += i;
				if (k > m)
					break;
				if (p[k].expmod(one, ip).iptoint() != r) {
					r = -1;
					break;
				}
				s++;
			}
			if (r >= 0)
				if (j == 0)
					sys->print("p(%dm) = %d mod %d ?\n", i, r, i);
				else
					sys->print("p(%dm+%d) = %d mod %d ?\n", i, j, r, i);
		}
	}
}
