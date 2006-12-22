#
#	MPEG ISO 11172 IO module.
#
Mpegio: module
{
	PATH:	con "/dis/mpeg/mpegio.dis";

	MBSZ:	con Sys->ATOMICIO;

	PICTURE_SC:	con 16r100;
	SLICE1_SC:	con 16r101;
	SLICEN_SC:	con 16r1AF;
	USER_SC:		con 16r1B2;
	SEQUENCE_SC:	con 16r1B3;
	EXTENSION_SC:	con 16r1B5;
	SEQUENCE_EC:	con 16r1B7;
	GROUP_SC:	con 16r1B8;
	STREAM_EC:	con 16r1B9;
	PACK_SC:		con 16r1BA;
	SYSHD_SC:	con 16r1BB;
	STREAM_BASE:	con 16r1BC;
	PRIVSTREAM2:	con 16r1BF;
	AUDIO_STR0:	con 16r1C0;
	VIDEO_STR0:	con 16r1E0;

	MEXCEPT:		con "mpeg: ";
	X_FORMAT:	con "fmt error";
	X_READ:		con "read error";
	X_WRITE:		con "write error";
	X_EOF:		con "premature eof";

	UNDEF:		con 100;

	CONSTRAINED, CLOSED, BROKEN:	con 1 << iota;
	FPFV, FPBV, GSTART:	con 1 << iota;

	IPIC:		con 1;
	PPIC:		con 2;
	BPIC:		con 3;
	DPIC:		con 4;

	ptypes:	con "0IPBD";

	MB_Q, MB_MF, MB_MB, MB_P, MB_I:	con 1 << iota;

	Stream: adt
	{
		id:		byte;
		scale:	byte;
		bound:	int;
		fd:		ref Sys->FD;
	};

	Picture: adt
	{
		seek:		int;
		eos:		int;
		temporal:	int;
		ptype:	int;
		vbvdelay:	int;
		flags:		int;
		forwfc:	int;
		backfc:	int;
		slices:	array of ref Slice;
		addr:		int;
	};

	Slice: adt
	{
		blocks:	array of ref MacroBlock;
	};

	MacroBlock: adt
	{
		flags:		int;
		qscale:	int;
		mhfc, mhfr, mvfc, mvfr: int;
		mhbc, mhbr, mvbc, mvbr: int;
		pcode:	int;
		rls:		array of array of Pair;
		addr:		int;
	};

	YCbCr: adt
	{
		Y, Cb, Cr: array of byte;
	};

	Pair:		type (int, int);
	Triple:	type (int, int, int);

	Mpegi: adt
	{
		fd:		ref Sys->FD;
		name:	string;
		error:	string;
		looked:	int;
		value:	int;
		# info
		width:	int;
		height:	int;
		aspect:	int;
		frames:	int;
		rate:		int;
		vbv:		int;
		flags:		int;
		intra:		array of int;
		nintra:	array of int;
		smpte:	int;
		# real buffer
		seek:		int;
		index:	int;
		size:		int;
		buff:		array of byte;
		# stream buffer
		sid:		int;	# stream id
		slim:		int;	# stream limit <= size
		sresid:	int;	# stream residual (-1 entire file)
		sbits:		int;	# bits remaining
		svalue:	int;	# current value

		packt0:	int;
		packt1:	int;
		packmr:	int;
		syssz:	int;
		boundmr:	int;
		syspar:	int;
		nstream:	int;
		streams:	array of Stream;
		log:		ref Sys->FD;

		startsys:	fn(m: self ref Mpegi);
		packhdr:	fn(m: self ref Mpegi);
		syshdr:	fn(m: self ref Mpegi);
		packetcp:	fn(m: self ref Mpegi): int;
		getfd:	fn(m: self ref Mpegi, c: int): ref Sys->FD;
		stamps:	fn(m: self ref Mpegi): int;

		streaminit:	fn(m: self ref Mpegi, c: int);
		inittables:	fn();
		sseek:	fn(m: self ref Mpegi);
		seqhdr:	fn(m: self ref Mpegi);
		grphdr:	fn(m: self ref Mpegi);
		getquant:	fn(m: self ref Mpegi): array of int;
		getpicture:	fn(m: self ref Mpegi, detail: int): ref Picture;
		picture:	fn(m: self ref Mpegi, detail: int): ref Picture;
		detail:	fn(m: self ref Mpegi, p: ref Picture);
		skipdetail:	fn(m: self ref Mpegi);
		slice:		fn(m: self ref Mpegi, p: ref Picture): ref Slice;

		cpn:		fn(m: self ref Mpegi, fd: ref Sys->FD, n: int);
		fill:		fn(m: self ref Mpegi);
		tell:		fn(m: self ref Mpegi): int;
		skipn:	fn(m: self ref Mpegi, n: int);
		getb:		fn(m: self ref Mpegi): int;
		getw:		fn(m: self ref Mpegi): int;
		get22:	fn(m: self ref Mpegi, s: string): int;
		getsc:	fn(m: self ref Mpegi): int;
		nextsc:	fn(m: self ref Mpegi): int;
		peeksc:	fn(m: self ref Mpegi): int;
		xnextsc:	fn(m: self ref Mpegi, code: int);

		sfill:		fn(m: self ref Mpegi);
		sgetb:	fn(m: self ref Mpegi): int;
		sgetn:	fn(m: self ref Mpegi, n: int): int;
		sdiffn:	fn(m: self ref Mpegi, n: int): int;
		sdct:		fn(m: self ref Mpegi, a: array of Triple, s: string): Pair;
		speekn:	fn(m: self ref Mpegi, n: int): int;
		smarker:	fn(m: self ref Mpegi);
		sgetsc:	fn(m: self ref Mpegi): int;
		snextsc:	fn(m: self ref Mpegi): int;
		speeksc:	fn(m: self ref Mpegi): int;
		sseeksc:	fn(m: self ref Mpegi);
		svlc:		fn(m: self ref Mpegi, a: array of Pair, n: int, s: string): int;

		fmterr:	fn(m: self ref Mpegi, s: string);
	};

	init:		fn();
	prepare:	fn(fd: ref Sys->FD, name: string): ref Mpegi;
	raisex:		fn(s: string);
};

Mpegd: module
{
	PATH:	con "/dis/mpeg/decode.dis";
	PATH4:	con "/dis/mpeg/decode4.dis";

	init:		fn(m: ref Mpegio->Mpegi);
	Idecode:	fn(p: ref Mpegio->Picture): ref Mpegio->YCbCr;
	Pdecode:	fn(p: ref Mpegio->Picture): ref Mpegio->YCbCr;
	Bdecode:	fn(p: ref Mpegio->Picture): ref Mpegio->YCbCr;
	Bdecode2:	fn(p: ref Mpegio->Picture, f0, f1: ref Mpegio->YCbCr): ref Mpegio->YCbCr;
};

IDCT: module
{
	FPATH:	con "/dis/mpeg/fltidct.dis";		# based on rob's jpeg
	RPATH:	con "/dis/mpeg/refidct.dis";	# reference (full idct)
	SPATH:	con "/dis/mpeg/scidct.dis";	# scaled integer implementation
	XPATH:	con "/dis/mpeg/fixidct.dis";	# nasty fixed point
	PATH:	con SPATH;

	init:		fn();
	idct:		fn(block: array of int);
};

Remap: module
{
	PATH:	con "/dis/mpeg/remap.dis";
	PATH1:	con "/dis/mpeg/remap1.dis";
	PATH2:	con "/dis/mpeg/remap2.dis";
	PATH4:	con "/dis/mpeg/remap4.dis";
	PATH24:	con "/dis/mpeg/remap24.dis";

	init:		fn(m: ref Mpegio->Mpegi);
	remap:	fn(p: ref Mpegio->YCbCr): array of byte;
};
