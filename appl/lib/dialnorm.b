implement Dialnorm;

include "dialnorm.m";

normalize(s: string): string
{
	if(len s == 0)
		return s;
	# Already Inferno dial syntax (tcp!host!port, udp!h!p, etc.)
	for(i := 0; i < len s; i++)
		if(s[i] == '!')
			return s;
	# Find last ':' to support IPv6-style host[::]:port? — we
	# deliberately do not. Inferno's dial syntax for IPv6 is
	# different and a colon-only literal would be ambiguous,
	# so we leave anything containing more than one ':' alone.
	first := -1;
	last := -1;
	for(i = 0; i < len s; i++)
		if(s[i] == ':') {
			if(first < 0)
				first = i;
			last = i;
		}
	if(last < 0 || first != last)
		return s;
	if(last == 0 || last == len s - 1)
		return s;
	host := s[0:last];
	port := s[last+1:];
	for(i = 0; i < len port; i++)
		if(port[i] < '0' || port[i] > '9')
			return s;
	return "tcp!" + host + "!" + port;
}
