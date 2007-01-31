implement Stob;

include "sys.m";
	sys: Sys;
include "convcs.m";

bigendian := 1;
header := 1;

init(arg : string) : string
{
	sys = load Sys Sys->PATH;
	case arg {
	"le" =>
		bigendian = 0;
		header = 0;
	"be" =>
		header = 0;
	}
	return nil;
}

stob(state : Convcs->State, s : string) : (Convcs->State, array of byte)
{
	if(state == nil){
		if(header)
			s = sys->sprint("%c", 16rfeff) + s;
		state = "doneheader";
	}

	b := array[len s * 2] of byte;
	j := 0;
	if(bigendian){
		for(i := 0; i < len s; i++){
			c := s[i];
			b[j++] = byte (c >> 8);
			b[j++] = byte c;
		}
	}else{
		for(i := 0; i < len s; i++){
			c := s[i];
			b[j++] = byte c;
			b[j++] = byte (c >> 8);
		}
	}
	return (state, b);
}
