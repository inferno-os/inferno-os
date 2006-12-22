implement Libc0;

include "libc0.m";

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

strlen(s: array of byte): int
{
	l := len s;
	for(i := 0; i < l; i++)
		if(s[i] == byte 0)
			break;
	return i;
}

strcpy(s1: array of byte, s2: array of byte): array of byte
{
	l := strlen(s2)+1;
	if(l == len s2)
		s1[0: ] = s2;
	else
		s1[0: ] = s2[0: l];
	return s1;
}

strncpy(s1: array of byte, s2: array of byte, n: int): array of byte
{
	l := strlen(s2);
	if(l >= n)
		s1[0: ] = s2[0: n];
	else{
		s1[0: ] = s2;
		for(i := l; i < n; i++)
			s1[i] = byte '\0';
	}
	return s1;
}

strcat(s1: array of byte, s2: array of byte): array of byte
{
	l := strlen(s2)+1;
	m := strlen(s1);
	if(l == len s2)
		s1[m: ] = s2;
	else
		s1[m: ] = s2[0: l];
	return s1;
}

strncat(s1: array of byte, s2: array of byte, n: int): array of byte
{
	l := strlen(s2);
	if(l >= n){
		m := strlen(s1);
		s1[m: ] = s2[0: n];
		s1[m+n] = byte '\0';
	}
	else
		strcat(s1, s2);
	return s1;
}
	
strdup(s: array of byte): array of byte
{
	l := strlen(s)+1;
	t := array[l] of byte;
	if(l == len s)
		t[0: ] = s;
	else
		t[0: ] = s[0: l];
	return t;
}

strcmp(s1: array of byte, s2: array of byte): int
{
	l1 := strlen(s1);
	l2 := strlen(s2);
	for(i := 0; i < l1 && i < l2; i++)
		if(s1[i] != s2[i])
			return int s1[i]-int s2[i];
	return l1-l2;
}

strncmp(s1: array of byte, s2: array of byte, n: int): int
{
	l1 := strlen(s1);
	l2 := strlen(s2);
	for(i := 0; i < l1 && i < l2 && i < n; i++)
		if(s1[i] != s2[i])
			return int s1[i]-int s2[i];
	return l1-l2;
}

strchr(s: array of byte, n: int): array of byte
{
	l := strlen(s);
	for(i := 0; i < l; i++)
		if(s[i] == byte n)
			return s[i: ];
	return nil;
}

strrchr(s: array of byte, n: int): array of byte
{
	l := strlen(s);
	for(i := l-1; i >= 0; i--)
		if(s[i] == byte n)
			return s[i: ];
	return nil;
}

ls2aab(argl: list of string): array of array of byte
{
	l := len argl;
	ls := argl;
	a := array[l+1] of array of byte;
	for(i := 0; i < l; i++){
		a[i] = array of byte (hd ls + "\0");
		ls = tl ls;
	}
	a[l] = nil;
	return a;
}

s2ab(s: string): array of byte
{
	return array of byte (s + "\0");
}

ab2s(a: array of byte): string
{
	return string a[0: strlen(a)];
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
