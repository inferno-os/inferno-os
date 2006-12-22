implement Btos;

include "sys.m";
include "convcs.m";

sys : Sys;

init(nil : string) : string
{
	sys = load Sys Sys->PATH;
	return nil;
}

btos(nil : Convcs->State, b : array of byte, n : int) : (Convcs->State, string, int)
{
	nbytes := 0;
	str := "";

	if (n == -1) {
		# gather as much as possible
		nbytes = sys->utfbytes(b, len b);
		if (nbytes > 0)
			str = string b[:nbytes];
	} else {
		for (; nbytes < len b && len str < n;) {
			(ch, l, s) := sys->byte2char(b, nbytes);
			if (l > 0) {
				str[len str] = ch;
				nbytes += l;
			} else
				break;
		}
	}
	return (nil, str, nbytes);
}
