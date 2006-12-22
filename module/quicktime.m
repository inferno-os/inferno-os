#
# Apple QuickTime File Format
#
QuickTime: module
{
	PATH:	con "/dis/lib/quicktime.dis";

	DEFBUF:		con 8192;

	AtomHDR:	con 8;

	Tkhdr: adt
	{
		version:	int;
		creation:	int;
		modtime:	int;
		trackid:	int;
		timescale:	int;
		duration:	int;
		timeoff:	int;
		priority:	int;
		layer:		int;
		altgrp:		int;
		volume:		int;
		matrix:		array of int;
		width:		int;
		height:		int;
	};

	MvhdrSIZE:	con 100;
	Mvhdr: adt
	{
		version:	int;
		create:		int;
		modtime:	int;
		timescale:	int;
		duration:	int;
		rate:		int;
		vol:		int;
		r1:		int;
		r2:		int;
		matrix:		array of int;
		r3:		int;
		r4:		int;
		pvtime:		int;
		posttime:	int;
		seltime:	int;
		seldurat:	int;
		curtime:	int;
		nxttkid:	int;
	};

	# QuickTime descriptor
	QD: adt
	{
		fd:	ref sys->FD;		# descriptor of QuickTime file
		buf:	array of byte;		# buffer
		nbyte:	int;			# bytes remaining
		ptr:	int;			# buffer pointer

		mvhdr:	ref Mvhdr;		# movie header desctiptor

		readn:		fn(r: self ref QD, b: array of byte, l: int): int;
		skip:		fn(r: self ref QD, size: int): int;
		skipatom:	fn(r: self ref QD, size: int): int;
		atomhdr:	fn(r: self ref QD): (string, int);
		mvhd:		fn(r: self ref QD, l: int): string;
		trak:		fn(r: self ref QD, l: int): string;
	};

	init:	fn();
	open:	fn(file: string): (ref QD, string);
};
