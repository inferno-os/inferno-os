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
	ns := len s;
	n := len pre;
	if(ns < n)
		return 0;
	for(k := 0; k < n; k++) {
		if(pre[k] != s[k])
			return 0;
	}
	return 1;
}

tolower(s: string): string
{
	r := s;
	for(i := 0; i < len r; i++) {
		c := r[i];
		if(c >= int 'A' && c <= int 'Z')
			r[i] = r[i] + (int 'a' - int 'A');
	}
	return r;
}

toupper(s: string): string
{
	r := s;
	for(i := 0; i < len r; i++) {
		c := r[i];
		if(c >= int 'a' && c <= int 'z')
			r[i] = r[i] - (int 'a' - int 'A');
	}
	return r;
}

tobig(s: string, base: int): (big, string)
{
	if (s == nil || base < 0 || base > 36 || base == 1)
		return (big 0, s);

	# skip possible leading white space
	c: int;
	for (i := 0; i < len s; i++) {
		c = s[i];
		if(c != ' ' && c != '\t' && c != '\n')
			break;
	}

	# skip possible sign character
	neg := 0;
	if (c == '-' || c == '+') {
		if(c == '-')
			neg = 1;
		i++;
	}

	if (base == 0) {
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
			return (big 0, s);
	}

	# parse number itself.
	# perhaps this should check for overflow, and max out, as limbo op does?
	start := i;
	dig := '9';
	if (base < 10)
		dig = '0' + base - 1;
	n := big 0;
	for (; i < len s; i++) {
		c = s[i];
		if ('0' <= c && c <= dig)
			n = (n * big base) + big(c - '0');
		else if ('a' <= c && c < 'a' + base - 10)
			n = (n * big base) + big(c - 'a' + 10);
		else if ('A' <= c && c  < 'A' + base - 10)
			n = (n * big base) + big(c - 'A' + 10);
		else
			break;
	}
	if (i == start)
		return (big 0, s);
	if (neg)
		return (-n, s[i:]);
	return (n, s[i:]);
}

toint(s: string, base: int): (int, string)
{
	if (s == nil || base < 0 || base > 36 || base == 1)
		return (0, s);

	# skip possible leading white space
	c: int;
	for (i := 0; i < len s; i++) {
		c = s[i];
		if(c != ' ' && c != '\t' && c != '\n')
			break;
	}

	# skip possible sign character
	neg := 0;
	if (c == '-' || c == '+') {
		if(c == '-')
			neg = 1;
		i++;
	}

	if (base == 0) {
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
			return (0, s);
	}

	# parse number itself.
	# perhaps this should check for overflow, and max out, as limbo op does?
	start := i;
	dig := '9';
	if (base < 10)
		dig = '0' + base - 1;
	n := 0;
	for (; i < len s; i++) {
		c = s[i];
		if ('0' <= c && c <= dig)
			n = (n * base) + (c - '0');
		else if ('a' <= c && c < 'a' + base - 10)
			n = (n * base) + (c - 'a' + 10);
		else if ('A' <= c && c  < 'A' + base - 10)
			n = (n * base) + (c - 'A' + 10);
		else
			break;
	}
	if (i == start)
		return (0, s);
	if (neg)
		return (-n, s[i:]);
	return (n, s[i:]);
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
