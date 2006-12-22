implement Stob;

include "sys.m";
include "convcs.m";

sys : Sys;

init(nil : string) : string
{
	sys = load Sys Sys->PATH;
	return nil;
}

stob(nil : Convcs->State, str : string) : (Convcs->State, array of byte)
{
	b := array [len str] of byte;
	for (i := 0; i < len str; i++) {
		ch := str[i];
		if (ch > 255)
			ch = '?';
		b[i] = byte ch;
	}
	return (nil, b);
}
