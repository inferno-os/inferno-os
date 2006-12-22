#
# Microsoft Resource Interchange File Format
# with AVI support
#
Riff: module
{
	PATH:	con "/dis/lib/riff.dis";

	DEFBUF:		con 8192;

	BI_RGB:		con 0;
	BI_RLE8:	con 1;
	BI_RLE4:	con 2;
	BI_BITFEILD:	con 3;

	RGB: adt
	{
		r:	int;
		g:	int;
		b:	int;
	};

	Binfosize:	con 10*4;
	Bitmapinfo: adt		# Windows bitmap info structure
	{
		width:		int;		# width in pixels
		height:		int;		# height in pixels
		planes:		int;		# planes of output device (must be 1)
		bitcount:	int;		# bits per pixel
		compression:	int;		# coding BI_RGB... or IV32 for indeo
		sizeimage:	int;		# size in bytes of image
		xpelpermeter:	int;		# resolution in pixels per meter
		ypelpermeter:	int;
		clrused:	int;		# colors used
		clrimportant:	int;		# how fixed is the map

		cmap:		array of RGB;	# color map
	};

	AVImainhdr:	con 14*4;
	AVIhdr: adt
	{
		usecperframe:	int;
		bytesec:	int;
		flag:		int;
		frames:		int;
		initframes:	int;
		streams:	int;
		bufsize:	int;
		width:		int;
		height:		int;
	};

	AVIstreamhdr:	con 2*4 + 10*4;
	AVIstream: adt
	{
		# Stream Header information
		stype:		string;
		handler:	string;
		flags:		int;
		priority:	int;
		initframes:	int;
		scale:		int;
		rate:		int;
		start:		int;
		length:		int;
		bufsize:	int;
		quality:	int;
		samplesz:	int;

		# Stream Format information (decoder specific)
		fmt:		array of byte;
		binfo:		ref Bitmapinfo;

		fmt2binfo:	fn(a: self ref AVIstream): string;
	};

	# Riff descriptor
	RD: adt
	{
		fd:	ref sys->FD;		# descriptor of RIFF file
		buf:	array of byte;		# buffer
		nbyte:	int;			# bytes remaining
		ptr:	int;			# buffer pointer

		gethdr:		fn(r: self ref RD): (string, int);
		readn:		fn(r: self ref RD, b: array of byte, l: int): int;
		check4:		fn(r: self ref RD, code: string): string;
		avihdr:		fn(r: self ref RD): (ref AVIhdr, string);
		streaminfo:	fn(r: self ref RD): (ref AVIstream, string);
		skip:		fn(r: self ref RD, size: int): int;
	};

	init:	fn();
	open:	fn(file: string): (ref RD, string);
};
