implement Powers;

include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
include "lock.m";
	lockm: Lock;
	Semaphore: import lockm;

Powers: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

MAXNODES: con (1<<20)/4;

verbose: int;

# Doing
# 	powers -p 3
# gives
# 	[2] 1729 = 1**3 + 12**3 = 9**3 + 10**3
# 	[2] 4104 = 2**3 + 16**3 = 9**3 + 15**3

# ie 1729 can be written in two ways as the sum of 2 cubes as can 4104.

# The options are

# -p	the power to use - default 2
# -n	the number of powers summed - default 2
# -f	the minimum number of ways found before reporting it - default 2
# -l	the least number to consider - default 0
# -m	the greatest number to consider - default 8192

# Thus
# 	pow -p 4 -n 3 -f 3 -l 0 -m 1000000
# gives
# 	[3] 811538 = 12**4 + 17**4 + 29**4 = 7**4 + 21**4 + 28**4 = 4**4 + 23**4 + 27**4

# ie fourth powers, 3 in each sum, minimum of 3 representations, numbers from 0-1000000.

# [2] 25
# [3] 325
# [4] 1105
# [5] 4225
# [6] 5525
# [7] 203125
# [8] 27625
# [9] 71825
# [10] 138125
# [11] 2640625
# [12] 160225
# [13] 17850625
# [14] 1221025
# [15] 1795625
# [16] 801125
# [18] 2082925
# [20] 4005625
# [23] 30525625
# [24] 5928325
# [32] 29641625

# [24] 5928325 = 63**2 + 2434**2 = 94**2 + 2433**2 = 207**2 + 2426**2 = 294**2 + 2417**2 = 310**2 + 2415**2 = 465**2 + 2390**2 = 490**2 + 2385**2 = 591**2 + 2362**2 = 690**2 + 2335**2 = 742**2 + 2319**2 = 849**2 + 2282**2 = 878**2 + 2271**2 = 959**2 + 2238**2 = 1039**2 + 2202**2 = 1062**2 + 2191**2 = 1201**2 + 2118**2 = 1215**2 + 2110**2 = 1290**2 + 2065**2 = 1410**2 + 1985**2 = 1454**2 + 1953**2 = 1535**2 + 1890**2 = 1614**2 + 1823**2 = 1633**2 + 1806**2 = 1697**2 + 1746**2

# [32] 29641625 = 67**2 + 5444**2 = 124**2 + 5443**2 = 284**2 + 5437**2 = 320**2 + 5435**2 = 515**2 + 5420**2 = 584**2 + 5413**2 = 835**2 + 5380**2 = 955**2 + 5360**2 = 1180**2 + 5315**2 = 1405**2 + 5260**2 = 1460**2 + 5245**2 = 1648**2 + 5189**2 = 1795**2 + 5140**2 = 1829**2 + 5128**2 = 1979**2 + 5072**2 = 2012**2 + 5059**2 = 2032**2 + 5051**2 = 2245**2 + 4960**2 = 2308**2 + 4931**2 = 2452**2 + 4861**2 = 2560**2 + 4805**2 = 2621**2 + 4772**2 = 2840**2 + 4645**2 = 3005**2 + 4540**2 = 3035**2 + 4520**2 = 3320**2 + 4315**2 = 3365**2 + 4280**2 = 3517**2 + 4156**2 = 3544**2 + 4133**2 = 3664**2 + 4027**2 = 3715**2 + 3980**2 = 3803**2 + 3896**2

# [2] 1729 = 1**3 + 12**3 = 9**3 + 10**3
# [2] 4104 = 2**3 + 16**3 = 9**3 + 15**3
# [3] 87539319 = 167**3 + 436**3 = 228**3 + 423**3 = 255**3 + 414**3

# [2] 635318657 = 59**4 + 158**4 = 133**4 + 134**4
# [2] 3262811042 = 7**4 + 239**4 = 157**4 + 227**4
# [2] 8657437697 = 193**4 + 292**4 = 256**4 + 257**4
# [2] 68899596497 = 271**4 + 502**4 = 298**4 + 497**4
# [2] 86409838577 = 103**4 + 542**4 = 359**4 + 514**4
# [2] 160961094577 = 222**4 + 631**4 = 503**4 + 558**4
# [2] 2094447251857 = 76**4 + 1203**4 = 653**4 + 1176**4
# [2] 4231525221377 = 878**4 + 1381**4 = 997**4 + 1342**4
# [2] 26033514998417 = 1324**4 + 2189**4 = 1784**4 + 1997**4
# [2] 37860330087137 = 1042**4 + 2461**4 = 2026**4 + 2141**4
# [2] 61206381799697 = 248**4 + 2797**4 = 2131**4 + 2524**4
# [2] 76773963505537 = 1034**4 + 2949**4 = 1797**4 + 2854**4
# [2] 109737827061041 = 1577**4 + 3190**4 = 2345**4 + 2986**4
# [2] 155974778565937 = 1623**4 + 3494**4 = 2338**4 + 3351**4
# [2] 156700232476402 = 661**4 + 3537**4 = 2767**4 + 3147**4
# [2] 621194785437217 = 2694**4 + 4883**4 = 3966**4 + 4397**4
# [2] 652057426144337 = 604**4 + 5053**4 = 1283**4 + 5048**4
# [2] 680914892583617 = 3364**4 + 4849**4 = 4288**4 + 4303**4
# [2] 1438141494155441 = 2027**4 + 6140**4 = 4840**4 + 5461**4
# [2] 1919423464573697 = 274**4 + 6619**4 = 5093**4 + 5942**4
# [2] 2089568089060657 = 498**4 + 6761**4 = 5222**4 + 6057**4
# [2] 2105144161376801 = 2707**4 + 6730**4 = 3070**4 + 6701**4
# [2] 3263864585622562 = 1259**4 + 7557**4 = 4661**4 + 7269**4
# [2] 4063780581008977 = 5181**4 + 7604**4 = 6336**4 + 7037**4
# [2] 6315669699408737 = 1657**4 + 8912**4 = 7432**4 + 7559**4
# [2] 6884827518602786 = 635**4 + 9109**4 = 3391**4 + 9065**4
# [2] 7191538859126257 = 4903**4 + 9018**4 = 6842**4 + 8409**4
# [2] 7331928977565937 = 1104**4 + 9253**4 = 5403**4 + 8972**4
# [2] 7362748995747617 = 5098**4 + 9043**4 = 6742**4 + 8531**4
# [2] 7446891977980337 = 1142**4 + 9289**4 = 4946**4 + 9097**4
# [2] 7532132844821777 = 173**4 + 9316**4 = 4408**4 + 9197**4
# [2] 7985644522300177 = 6262**4 + 8961**4 = 7234**4 + 8511**4

# 5, 6, 7, 8, 9, 10, 11 none

Btree: adt{
	sum: big;
	left: cyclic ref Btree;
	right: cyclic ref Btree;
};

Dtree: adt{
	sum: big;
	freq: int;
	lst: list of array of int;
	left: cyclic ref Dtree;
	right: cyclic ref Dtree;
};

nCr(n: int, r: int): int
{
	if(r > n-r)
		r = n-r;

	# f := g := 1;
	# for(i := 0; i < r; i++){
	# 	f *= n-i;
	# 	g *= i+1;
	# }
	# return f/g;

	num := array[r] of int;
	den := array[r] of int;
	for(i := 0; i < r; i++){
		num[i] = n-i;
		den[i] = i+1;
	}
	for(i = 0; i < r; i++){
		for(j := 0; den[i] != 1; j++){
			if(num[j] == 1)
				continue;
			k := hcf(num[j], den[i]);
			if(k != 1){
				num[j] /= k;
				den[i] /= k;
			}
		}
	}
	f := 1;
	for(i = 0; i < r; i++)
		f *= num[i];
	return f;
}

nHr(n: int, r: int): int
{
	if(n == 0)
		return 0;
	return nCr(n+r-1, r);
}

nSr(n: int, i: int, j: int): int
{
	return nHr(j, n)-nHr(i, n);
	# s := 0;
	# for(k := i; k < j; k++)
	# 	s += nHr(k+1, n-1);
	# return s;
}

nSrmax(n: int, i: int, m: int): int
{
	s := 0;
	for(k := i; ; k++){
		s += nHr(k+1, n-1);
		if(s > m)
			break;
	}
	if(k == i)
		return i+1;
	return k;
}

kth(c: array of int, n: int, i: int, j: int, k: int)
{
	l, u: int;

	m := nSr(n, i, j);
	if(k < 0)
		k = 0;
	if(k >= m)
		k = m-1;
	p := 0;
	for(q := 0; q < n; q++){
		if(q == 0){
			l = i;
			u = j-1;
		}
		else{
			l = 0;
			u = c[q-1];
		}
		for(x := l; x <= u; x++){
			m = nHr(x+1, n-q-1);
			p += m;
			if(p > k){
				p -= m;
				break;
			}
		}
		c[q] = x;
	}	
}

pos(c: array of int, n: int): int
{
	p := 0;
	for(q := 0; q < n; q++)
		p += nSr(n-q, 0, c[q]);
	return p;
}

min(c: array of int, n: int, p: int): big
{
	s := big(0);
	for(i := 0; i < n; i++)
		s += big(c[i])**p;
	m := s;
	for(i = n-1; i > 0; i--){
		s -= big(c[i])**p;
		s -= big(c[i-1])**p;
		c[i]--;
		c[i-1]++;
		s += big(c[i-1])**p;
		if(s < m)
			m = s;
	}
	c[0]--;
	c[n-1]++;
	# m--;
	return m;
}

hcf(a, b: int): int
{
	if(b == 0)
		return a;
	for(;;){
		if(a == 0)
			break;
		if(a < b)
			(a, b) = (b, a);
		a %= b;
		# a -= (a/b)*b;
	}
	return b;
}

gcd(l: list of array of int): int
{
	g := (hd l)[0];
	for(; l != nil; l = tl l){
		d := hd l;
		n := len d;
		for(i := 0; i < n; i++)
			g = hcf(d[i], g);
	}
	return g;
}

adddup(s: big, root: ref Dtree): int
{
	n, p, lp: ref Dtree;
	
	p = root;
	while(p != nil){
		if(s == p.sum)
			return ++p.freq;
		lp = p;
		if(s < p.sum)
			p = p.left;
		else
			p = p.right;
	}
	n = ref Dtree(s, 2, nil, nil, nil);
	if(s < lp.sum)
		lp.left = n;
	else
		lp.right = n;
	return n.freq;
}

cp(c: array of int): array of int
{
	n := len c;
	m := 0;
	for(i := 0; i < n; i++)
		if(c[i] != 0)
			m++;
	nc := array[m] of int;
	nc[0: ] = c[0: m];
	return nc;
}

finddup(s: big, c: array of int, root: ref Dtree, f: int)
{
	p: ref Dtree;
	
	p = root;
	while(p != nil){
		if(s == p.sum){
			if(p.freq >= f)
				p.lst = cp(c) :: p.lst;
			return;
		}
		if(s < p.sum)
			p = p.left;
		else
			p = p.right;
	}
}

printdup(p: ref Dtree, pow: int, ix: int)
{
	if(p == nil)
		return;
	printdup(p.left, pow, ix);
	if((l := p.lst) != nil){
		if(gcd(l) == 1){
			min1 := min2 := 16r7fffffff;
			for(; l != nil; l = tl l){
				n := len hd l;
				if(n < min1){
					min2 = min1;
					min1 = n;
				}
				else if(n < min2)
					min2 = n;
			}
			i := min1+min2-pow;
			if(i <= ix){
				sys->print("[%d, %d] %bd", i, p.freq, p.sum);
				for(l = p.lst; l != nil; l = tl l){
					d := hd l;
					n := len d;
					sys->print(" = ");
					for(j := n-1; j >= 0; j--){
						sys->print("%d**%d", d[j], pow);
						if(j > 0)
							sys->print(" + ");
					}
				}
				sys->print("\n");
				if(i < 0){
					sys->print("****************\n");
					exit;
				}
			}
		}
	}
	printdup(p.right, pow, ix);
}

addsum(s: big, root: ref Btree, root1: ref Dtree): int
{
	n, p, lp: ref Btree;
	
	p = root;
	while(p != nil){
		if(s == p.sum)
			return adddup(s, root1);
		lp = p;
		if(s < p.sum)
			p = p.left;
		else
			p = p.right;
	}
	n = ref Btree(s, nil, nil);
	if(s < lp.sum)
		lp.left = n;
	else
		lp.right = n;
	return 1;
}

oiroot(x: big, p: int): int
{
	for(i := 0; ; i++){
		n := big(i)**p;
		if(n > x)
			break;
	}
	return i-1;
}

iroot(x: big, p: int): int
{
	m: big;

	if(x == big(0) || x == big(1))
		return int x;
	v := x;
	n := 0;
	for(i := 32; i > 0; i >>= 1){
		m = ((big(1)<<i)-big(1))<<i;
		if((v&m) != big(0)){
			n += i;
			v >>= i;
		}
	}
	a := big(1) << (n/p);
	b := a<<1;
	while(a < b){
		m = (a+b+big(1))/big(2);
		y := m**p;
		if(y > x)
			b = m-big(1);
		else if(y < x)
			a = m;
		else
			a = b = m;
	}
	if(a**p <= x && (a+big(1))**p > x)
		;
	else{
		sys->print("fatal: %bd %d -> %bd\n", x, p, a);
		exit;
	}
	return int a;
}

initval(c: array of int, n: int, p: int, v: int): big
{
	for(i := 0; i < n; i++)
		c[i] = 0;
	c[0] = v;
	return big(v)**p;
}

nxtval(c: array of int, n: int, p: int, s: big): big
{
	for(k := n-1; k >= 0; k--){
		s -= big(c[k])**p;
		c[k]++;
		if(k == 0){
			s += big(c[k])**p;
			break;
		}
		else{
			if(c[k] <= c[k-1]){
				s += big(c[k])**p;
				break;
			}
			c[k] = 0;
		}
	}
	return s;
}

powers(p: int, n: int, f: int, ix: int, lim0: big, lim: big, ch: chan of int, lock: ref Semaphore)
{
	root := ref Btree(big(-1), nil, nil);
	root1 := ref Dtree(big(-1), 0, nil, nil, nil);

	min := max := lim0;

	c := array[n] of int;

	for(;;){
		imin := iroot((min+big(n-1))/big(n), p);
		imax := nSrmax(n, imin, MAXNODES);
		max = big(imax)**p - big(1);
		while(max <= min){	# could do better
			imax++;
			max = big(imax)**p - big(1);
		}
		if(max > lim){
			max = lim;
			imax = iroot(max, p)+1;
		}

		if(verbose)
			sys->print("searching in %d-%d(%bd-%bd)\n", imin, imax, min, max);

		m := mm := 0;
		maxf := 0;
		s := initval(c, n, p, imin);
		for(;;){
			mm++;
			if(s >= min && s < max){
				fr := addsum(s, root, root1);
				if(fr > maxf)
					maxf = fr;
				m++;
			}
			s = nxtval(c, n, p, s);
			if(c[0] == imax)
				break;
		}

		root.left = root.right = nil;

		if(maxf >= f){
			if(verbose)
				sys->print("finding duplicates\n");

			s = initval(c, n, p, imin);
			for(;;){
				if(s >= min && s < max)
					finddup(s, c, root1, f);
				s = nxtval(c, n, p, s);
				if(c[0] == imax)
					break;
			}

			if(lock != nil)
				lock.obtain();
			printdup(root1, p, ix);
			if(lock != nil)
				lock.release();

			root1.left = root1.right = nil;
		}

		if(verbose)
			sys->print("%d(%d) nodes searched\n", m, mm);

		if(mm != nSr(n, imin, imax)){
			sys->print("**fatal**\n");
			exit;
		}

		min = max;
		if(min >= lim)
			break;
	}
	if(ch != nil)
		ch <-= 0;
}

usage()
{
	sys->print("usage: powers -p power -n number -f frequency -i index -l minimum -m maximum -s procs -v\n");
	exit;
}

partition(p: int, n: int, l: big, m: big, s: int): array of big
{
	a := array[s+1] of big;
	a[0] = big(iroot(l, p))**n;
	a[s] = (big(iroot(m, p))+big(1))**n;
	nn := a[s]-a[0];
	q := nn/big(s);
	r := nn-q*big(s);
	t := big(0);
	lb := a[0];
	for(i := 0; i < s; i++){
		ub := lb+q;
		t += r;
		if(t >= big(s)){
			ub++;
			t -= big(s);
		}
		a[i+1] = ub;
		lb = ub;
	}
	if(a[s] != a[0]+nn){
		sys->print("fatal: a[s]\n");
		exit;
	}
	for(i = 0; i < s; i++){
		# sys->print("%bd %bd\n", a[i], a[i]**p);
		a[i] = big(iroot(a[i], n))**p;
	}
	a[0] = l;
	a[s] = m;
	while(a[0] >= a[1]){
		a[1] = a[0];
		a = a[1: ];
		--s;
	}
	while(a[s] <= a[s-1]){
		a[s-1] = a[s];
		a = a[0: s];
		--s;
	}
	return a;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	lockm = load Lock Lock->PATH;

	lockm->init();
	lock := Semaphore.new();

	p := n := f := 2;
	ix := 1<<30;
	l := m := big(0);
	s := 1;

	arg->init(args);
	while((c := arg->opt()) != 0){
		case c {
			'p' =>
				p = int arg->arg();
			'n' =>
				n = int arg->arg();
			'f' =>
				f = int arg->arg();
			'i' =>
				ix = int arg->arg();
			'l' =>
				l = big(arg->arg());
			'm' =>
				m = big(arg->arg())+big(1);
			's' =>
				s = int arg->arg();
			'v' =>
				verbose = 1;
			* =>
				usage();
		}
	}
	if(arg->argv() != nil)
		usage();

	if(p < 2){
		p = 2;
		sys->print("setting p = %d\n", p);
	}
	if(n < 2){
		n = 2;
		sys->print("setting n = %d\n", n);
	}
	if(f < 2){
		f = 2;
		sys->print("setting f = %d\n", f);
	}
	if(l < big(0)){
		l = big(0);
		sys->print("setting l = %bd\n", l);
	}
	if(m <= big(0)){
		m = big((1<<13)+1);
		sys->print("setting m = %bd\n", m-big(1));
	}
	if(l >= m)
		exit;

	if(s <= 1)
		powers(p, n, f, ix, l, m, nil, nil);
	else{
		nproc := 0;
		ch := chan of int;
		a := partition(p, n, l, m, s);
		lb := a[0];
		for(i := 0; i < s; i++){
			ub := a[i+1];
			if(lb < ub){
				nproc++;
				spawn powers(p, n, f, ix, lb, ub, ch, lock);
			}
			lb = ub;
		}
		for( ; nproc != 0; nproc--)
			<- ch;
	}
}
