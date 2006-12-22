implement Pause;
#
# init program to do nothing but pause
#

include "sys.m";
include "draw.m";

Pause: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	<-chan of int;
}
