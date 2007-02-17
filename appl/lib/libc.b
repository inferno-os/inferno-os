implement Libc;

include "libc.m";

islx(c: int): int
{
	return c >= 'a' && c <= 'f';
}

isux(c: int): int
{
	return c >= 'A' && c <= 'F';
}

isalnum(c: int): int
{
	return isalpha(c) || isdigit(c);
}

isalpha(c: int): int
{
	return islower(c) || isupper(c);
}

isascii(c: int): int
{
	return (c&~16r7f) == 0;
}

iscntrl(c: int): int
{
	return c == 16r7f || (c&~16r1f) == 0;
}

isdigit(c: int): int
{
	return c >= '0' && c <= '9';
}

isgraph(c: int): int
{
	return c >= '!' && c <= '~';
}

islower(c: int): int
{
	return c >= 'a' && c <= 'z';
}

isprint(c: int): int
{
	return c >= ' ' && c <= '~';
}

ispunct(c: int): int
{
	return isascii(c) && !iscntrl(c) && !isspace(c) && !isalnum(c);
}

isspace(c: int): int
{
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

isupper(c: int): int
{
	return c >= 'A' && c <= 'Z';
}

isxdigit(c: int): int
{
	return isdigit(c) || islx(c) || isux(c);
}

tolower(c: int): int
{
	if(isupper(c))
		return c+'a'-'A';
	return c;
}

toupper(c: int): int
{
	if(islower(c))
		return c+'A'-'a';
	return c;
}

toascii(c: int): int
{
	return c&16r7f;
}

strchr(s: string, n: int): int
{
	l := len s;
	for(i := 0; i < l; i++)
		if(s[i] == n)
			return i;
	return -1;
}

strrchr(s: string, n: int): int
{
	l := len s;
	for(i := l-1; i >= 0; i--)
		if(s[i] == n)
			return i;
	return -1;
}

strncmp(s1: string, s2: string, n: int): int
{
	l1 := len s1;
	l2 := len s2;
	m := n;
	if(m > l1)
		m = l1;
	if(m > l2)
		m = l2;
	for(i := 0; i < m; i++)
		if(s1[i] != s2[i])
			return s1[i]-s2[i];
	if(i == n)
		return 0;
	return l1-l2;
}

abs(n: int): int
{
	if(n < 0)
		return -n;
	return n;
}

min(m: int, n: int): int
{
	if(m < n)
		return m;
	return n;
}

max(m: int, n: int): int
{
	if(m > n)
		return m;
	return n;
}
