implement Ether;

include "sys.m";
	sys: Sys;

include "ether.m";

init()
{
	sys = load Sys Sys->PATH;
}

parse(s: string): array of byte
{
	a := array[Eaddrlen] of byte;
	for(i := 0; i < len a; i++){
		n: int;
		(n, s) = hex(s);
		if(n < 0){
			sys->werrstr("invalid ether address");
			return nil;
		}
		a[i] = byte n;
		if(s != nil && s[0] == ':')
			s = s[1:];
	}
	return a;
}

hex(s: string): (int, string)
{
	n := 0;
	for(i := 0; i < len s && i < 2; i++){
		if((c := s[i]) >= '0' && c <= '9')
			c -= '0';
		else if(c >= 'a' && c <= 'f')
			c += 10 - 'a';
		else if(c >= 'A' && c <= 'F')
			c += 10 - 'A';
		else if(c == ':')
			break;
		else
			return (-1, s);
		n = (n<<4) | c;
	}
	if(i == 0)
		return (-1, s);
	return (n, s[i:]);
}

text(a: array of byte): string
{
	if(len a < Eaddrlen)
		return "<invalid>";
	return sys->sprint("%.2ux%.2ux%.2ux%.2ux%.2ux%.2ux",
		int a[0], int a[1], int a[2], int a[3], int a[4], int a[5]);
}

addressof(dev: string): array of byte
{
	if(dev != nil && dev[0] != '/')
		dev = "/net/"+dev;
	fd := sys->open(dev+"/addr", Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[64] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	if(n > 0 && buf[n-1] == byte '\n')
		n--;
	return parse(string buf[0:n]);
}

eqaddr(a: array of byte, b: array of byte): int
{
	if(len a != len b)
		return 0;
	for(i := 0; i < len a; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
}
