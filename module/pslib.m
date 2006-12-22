Pslib : module 
{
	PATH:		con "/dis/lib/pslib.dis";

	init:	fn(bufio: Bufio);
	writeimage: fn(ioutb: ref Bufio->Iobuf, im: ref Draw->Image, dpi: int);
};
