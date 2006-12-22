implement Btos;

include "sys.m";
include "convcs.m";

sys : Sys;
codepage : string;

init(arg : string) : string
{
	sys = load Sys Sys->PATH;
	if (arg == nil)
		return "codepage path required";
	fd := sys->open(arg, Sys->OREAD);
	if (fd == nil)
		return sys->sprint("%s: %r", arg);

	buf := array[Sys->UTFmax * 256] of byte;
	nread := 0;
	for (;nread < len buf;) {
		toread := len buf - nread;
		n := sys->read(fd, buf[nread:], toread);
		if (n <= 0)
			break;
		nread += n;
	}
	codepage = string buf[0:nread];
	if (len codepage != 256) {
		codepage = nil;
		return sys->sprint("%s: bad codepage", arg);
	}
	return nil;
}

btos(nil : Convcs->State, b : array of byte, n : int) : (Convcs->State, string, int)
{
	s := "";
	if (n == -1 || n > len b)
		# consume all available characters
		n = len b;

	for (i := 0; i < n; i++)
		s[len s] = codepage[int b[i]];
	return (nil, s, n);
}