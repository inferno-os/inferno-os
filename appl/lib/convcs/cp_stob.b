implement Stob;

include "sys.m";
include "convcs.m";

sys : Sys;
map : array of byte;

ERRCHAR : con 16rFFFD;

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
	codepage := string buf[0:nread];
	if (len codepage != 256) {
		codepage = nil;
		return sys->sprint("%s: bad codepage", arg);
	}
	buf = nil;
	map = array[16r10000] of { * => byte '?' };
	for (i := 0; i < 256; i++)
		map[codepage[i]] = byte i;
	return nil;
}

stob(nil : Convcs->State, str : string) : (Convcs->State, array of byte)
{
	b := array [len str] of byte;
	n := len str;

	for (i := 0; i < n; i++)
		b[i] = map[str[i]];
	return (nil, b);
}