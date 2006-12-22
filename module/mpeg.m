#
# This module has a primitive interface to the
# mpeg device driver
#
Mpeg: module
{
	PATH:		con "/dis/lib/mpeg.dis";

	play:		fn(d: ref Draw->Display, w: ref Image, dopaint: int,
			r: Draw->Rect, file: string, notify: chan of string): string;
	ctl:		fn(msg: string): int;
	keycolor:	fn(d: ref Draw->Display): ref Draw->Image;	
};
