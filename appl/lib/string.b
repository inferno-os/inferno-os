implement String;

include "string.m";

splitl(s: string, cl: string): (string, string)
{
	n := len s;
	for(j := 0; j < n; j++) {
		if(in(s[j], cl))
			return (s[0:j], s[j:n]);
	}
	return (s,"");
}

splitr(s: string, cl: string): (string, string)
{
	n := len s;
	for(j := n-1; j >= 0; j--) {
		if(in(s[j], cl))
			return (s[0:j+1], s[j+1:n]);
	}
	return ("",s);
}

drop(s: string, cl: string): string
{
	n := len s;
	for(j := 0; j < n; j++) {
		if(!in(s[j], cl))
			return (s[j:n]);
	}
	return "";
}

take(s: string, cl: string): string
{
	n := len s;
	for(j := 0; j < n; j++) {
		if(!in(s[j], cl))
			return (s[0:j]);
	}
	return s;
}

in(c: int, s: string): int
{
	n := len s;
	if(n == 0)
		return 0;
	ans := 0;
	negate := 0;
	if(s[0] == '^') {
		negate = 1;
		s = s[1:];
		n--;
	}
	for(i := 0; i < n; i++) {
		if(s[i] == '-' && i > 0 && i < n-1)  {
			if(c >= s[i-1] && c <= s[i+1]) {
				ans = 1;
				break;
			}
			i++;
		}
		else
		if(c == s[i]) {
			ans = 1;
			break;
		}
	}
	if(negate)
		ans = !ans;
	return ans;
}

splitstrl(s: string, t: string): (string, string)
{
	n := len s;
	nt := len t;
	if(nt == 0)
		return ("", s);
	c0 := t[0];
    mainloop:
	for(j := 0; j <= n-nt; j++) {
		if(s[j] == c0) {
			for(k := 1; k < nt; k++)
				if(s[j+k] != t[k])
					continue mainloop;
			return(s[0:j], s[j:n]);
		}
	}
	return (s,"");
}

splitstrr(s: string, t: string): (string, string)
{
	n := len s;
	nt := len t;
	if(nt == 0)
		return (s, "");
	c0 := t[0];
    mainloop:
	for(j := n-nt; j >= 0; j--) {
		if(s[j] == c0) {
			for(k := 1; k < nt; k++)
				if(s[j+k] != t[k])
					continue mainloop;
			return(s[0:j+nt], s[j+nt:n]);
		}
	}
	return ("",s);
}

prefix(pre: string, s: string): int
{
	if(len s < len pre)
		return 0;
	for(k := 0; k < len pre; k++)
		if(pre[k] != s[k])
			return 0;
	return 1;
}

tolower(s: string): string
{
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c >= 'A' && c <= 'Z')
			s[i] += 'a' - 'A';
	}
	return s;
}

toupper(s: string): string
{
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c >= 'a' && c <= 'z')
			s[i] += 'A' - 'a';
	}
	return s;
}

startnum(s: string, base: int): (int, int, int)
{
	if(s == nil || base != 0 && (base < 2 || base > 36))
		return (0, 0, 0);

	# skip possible leading white space
	c := ' ';
	for (i := 0; i < len s; i++) {
		c = s[i];
		if(c != ' ' && c != '\t' && c != '\n')
			break;
	}

	# optional sign
	neg := 0;
	if(c == '-' || c == '+') {
		if(c == '-')
			neg = 1;
		i++;
	}

	if(base == 0) {
		# parse possible leading base designator
		start := i;
		base = -1;
		for (; i < start+3 && i < len s; i++) {
			c = s[i];
			if (c == 'r' && i > start) {
				base = int s[start:i];
				i++;
				break;
			} else if (c < '0' || c > '9')
				break;
		}
		if (base == -1) {
			i = start;
			base = 10;
		} else if (base == 0 || base > 36)
			return (0, 0, i);
	}
	if(i >= len s)
		return (0, 0, 0);

	return (base, neg, i);
}

tobig(s: string, base: int): (big, string)
{
	neg, i: int;

	(base, neg, i) = startnum(s, base);
	if(base == 0)
		return (big 0, s);

	# parse number itself.
	# probably this should check for overflow, and max out, as limbo op does?
	start := i;
	n := big 0;
	for (; i < len s; i++) {
		if((d := digit(s[i], base)) < 0)
			break;
		n = n*big base + big d;
	}
	if (i == start)
		return (big 0, s);
	if (neg)
		return (-n, s[i:]);
	return (n, s[i:]);
}

toint(s: string, base: int): (int, string)
{
	neg, i: int;

	(base, neg, i) = startnum(s, base);
	if(base == 0)
		return (0, s);

	# parse number itself.
	# probably this should check for overflow, and max out, as limbo op does?
	start := i;
	n := 0;
	for (; i < len s; i++){
		if((d := digit(s[i], base)) < 0)
			break;
		n = n*base + d;
	}
	if (i == start)
		return (0, s);
	if (neg)
		return (-n, s[i:]);
	return (n, s[i:]);
}

digit(c: int, base: int): int
{
	if ('0' <= c && c <= '0' + base - 1)
		return c-'0';
	else if ('a' <= c && c < 'a' + base - 10)
		return (c - 'a' + 10);
	else if ('A' <= c && c  < 'A' + base - 10)
		return (c - 'A' + 10);
	else
		return -1;	
}

rpow(x: real, n: int): real
{
	inv := 0;
	if(n < 0){
		n = -n;
		inv = 1;
	}
	r := 1.0;
	for(;;){
		if(n&1)
			r *= x;
		if((n >>= 1) == 0)
			break;
		x *= x;
	}
	if(inv)
		r = 1.0/r;
	return r;
}

match(p: string, s: string, i: int): int
{
	if(i+len p > len s)
		return 0;
	for(j := 0; j < len p; j++){
		c := s[i++];
		if(c >= 'A' && c <= 'Z')
			c += 'a'-'A';
		if(p[j] != c)
			return 0;
	}
	return 1;
}

toreal(s: string, base: int): (real, string)
{
	neg, i: int;

	(base, neg, i) = startnum(s, base);
	if(base == 0)
		return (0.0, s);

	c := s[i];
	if((c == 'i' || c == 'I') && match("infinity", s, i))
		return (real s, s[i+8:]);
	if((c == 'n' || c == 'N') && match("nan", s, i))
		return (real s, s[i+3:]);

	if(digit(c, base) < 0)
		return (0.0, s);

	num := 0.0;
	for(; i < len s && (d := digit(s[i], base)) >= 0; i++)
		num = num*real base + real d;
	dig := 0;	# digits in fraction
	if(i < len s && s[i] == '.'){
		i++;
		for(; i < len s && (d = digit(s[i], base)) >= 0; i++){
			num = num*real base + real d;
			dig++;
		}
	}
	exp := 0;
	eneg := 0;
	if(i < len s && ((c = s[i]) == 'e' || c == 'E')){
		start := i;	# might still be badly formed
		i++;
		if(i < len s && ((c = s[i]) == '-' || c == '+')){
			i++;
			if(c == '-'){
				dig = -dig;
				eneg = 1;
			}
		}
		if(i < len s && s[i] >= '0' && s[i] <= '9'){	# exponents are always decimal
			for(; i < len s && (d = digit(s[i], 10)) >= 0; i++)
				exp = exp*base + d;
		}else
			i = start;
	}
	if(base == 10)
		return (real s[0: i], s[i:]);	# conversion can be more accurate
	exp -= dig;
	if(exp < 0){
		exp = -exp;
		eneg = !eneg;
	}
	if(exp < 0 || exp > 19999)
		exp = 19999;	# huge but otherwise arbitrary limit
	dem := rpow(real base, exp);
	if(eneg)
		num /= dem;
	else
		num *= dem;
	if(neg)
		return  (-num,s[i:]);
	return (num, s[i:]);
}

append(s: string, l: list of string): list of string
{
	t:	list of string;

	# Reverse l, prepend s, and reverse result.
	while (l != nil) {
		t = hd l :: t;
		l = tl l;
	}
	t = s :: t;
	do {
		l = hd t :: l;
		t = tl t;
	} while (t != nil);
	return l;
}

quoted(argv: list of string): string
{
	return quotedc(argv, nil);
}

quotedc(argv: list of string, cl: string): string
{
	s := "";
	while(argv != nil){
		arg := hd argv;
		for(i := 0; i < len arg; i++){
			c := arg[i];
			if(c == ' ' || c == '\t' || c == '\n' || c == '\'' || in(c, cl))
				break;
		}
		if(i < len arg || arg == nil){
			s += "'" + arg[0:i];
			for(; i < len arg; i++){
				if (arg[i] == '\'')
					s[len s] = '\'';
				s[len s] = arg[i];
			}
			s[len s] = '\'';
		}else
			s += arg;
		if(tl argv != nil)
			s[len s] = ' ';
		argv = tl argv;
	}
	return s;
}

unquoted(s: string): list of string
{
	args: list of string;
	word: string;
	inquote := 0;
	for(j := len s; j > 0;){
		c := s[j-1];
		if(c == ' ' || c == '\t' || c == '\n'){
			j--;
			continue;
		}
		for(i := j-1; i >= 0 && ((c = s[i]) != ' ' && c != '\t' && c != '\n' || inquote); i--){	# collect word
			if(c == '\''){
				word = s[i+1:j] + word;
				j = i;
				if(!inquote || i == 0 || s[i-1] != '\'')
					inquote = !inquote;
				else
					i--;
			}
		}
		args = (s[i+1:j]+word) :: args;
		word = nil;
		j = i;
	}
	# if quotes were unbalanced, balance them and try again.
	if(inquote)
		return unquoted(s + "'");
	return args;
}
