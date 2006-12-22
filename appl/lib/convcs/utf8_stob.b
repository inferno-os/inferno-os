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
	return (nil, array of byte str);
}
