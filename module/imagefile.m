RImagefile: module 
{
	READGIFPATH:	con "/dis/lib/readgif.dis";
	READJPGPATH:	con "/dis/lib/readjpg.dis";
	READXBMPATH:	con "/dis/lib/readxbitmap.dis";
	READPICPATH:	con "/dis/lib/readpicfile.dis";
	READPNGPATH:	con "/dis/lib/readpng.dis";

	Rawimage: adt
	{
		r:	Draw->Rect;
		cmap:    array of byte;
		transp:  int;	# transparency flag (only for nchans=1)
		trindex: byte;	# transparency index
		nchans:  int;
		chans:   array of array of byte;
		chandesc:int;

		fields:	int;    # defined by format
	};

	# chandesc
	CRGB:   con 0;  # three channels, no map
	CY:     con 1;  # one channel, luminance
	CRGB1:  con 2;  # one channel, map present

	init:	fn(bufio: Bufio);
	read:	fn(fd: ref Bufio->Iobuf): (ref Rawimage, string);
	readmulti:	fn(fd: ref Bufio->Iobuf): (array of ref Rawimage, string);
};

WImagefile: module 
{
	WRITEGIFPATH:	con "/dis/lib/writegif.dis";

	init:	fn(bufio: Bufio);
#	write:	fn(fd: ref Bufio->Iobuf, ref RImagefile->Rawimage): string;
	writeimage:	fn(fd: ref Bufio->Iobuf, image: ref Draw->Image): string;
};


Imageremap: module
{
	PATH:	con "/dis/lib/imageremap.dis";

	init:	fn(d: ref Draw->Display);
	remap:	fn(i: ref RImagefile->Rawimage, d: ref Draw->Display, errdiff: int): (ref Draw->Image, string);
};
