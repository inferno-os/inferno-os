Bufio: module
{
	PATH:		con "/dis/lib/bufio.dis";

	SEEKSTART:	con Sys->SEEKSTART;
	SEEKRELA:	con Sys->SEEKRELA;
	SEEKEND:	con Sys->SEEKEND;

	OREAD:		con Sys->OREAD;
	OWRITE:		con Sys->OWRITE;
	ORDWR:		con Sys->ORDWR;

	EOF:		con -1;
	ERROR:		con -2;

	Iobuf: adt {
		seek:		fn(b: self ref Iobuf, n: big, where: int): big;
		offset:		fn(b: self ref Iobuf): big;

		read:		fn(b: self ref Iobuf, a: array of byte, n: int): int;
		write:		fn(b: self ref Iobuf, a: array of byte, n: int): int;

		getb:		fn(b: self ref Iobuf): int;
		getc:		fn(b: self ref Iobuf): int;
		gets:		fn(b: self ref Iobuf, sep: int): string;
		gett:		fn(b: self ref Iobuf, sep: string): string;

		ungetb:		fn(b: self ref Iobuf): int;
		ungetc:		fn(b: self ref Iobuf): int;

		putb:		fn(b: self ref Iobuf, b: byte): int;
		putc:		fn(b: self ref Iobuf, c: int): int;
		puts:		fn(b: self ref Iobuf, s: string): int;

		flush:		fn(b: self ref Iobuf): int;
		close:		fn(b: self ref Iobuf);

		setfill:	fn(b: self ref Iobuf, f: BufioFill);

		# Internal variables
		fd:		ref Sys->FD;	# the file
		buffer:		array of byte;	# the buffer
		index:		int;		# read/write pointer in buffer
		size:		int;		# characters remaining/written
		dirty:		int;		# needs flushing
		bufpos:		big;		# position in file of buf[0]
		filpos:		big;		# current file pointer
		lastop:		int;		# OREAD or OWRITE
		mode:		int;		# mode of open
	};

	open:		fn(name: string, mode: int): ref Iobuf;
	create:		fn(name: string, mode, perm: int): ref Iobuf;
	fopen:		fn(fd: ref Sys->FD, mode: int): ref Iobuf;
	sopen:		fn(input: string): ref Iobuf;
	aopen:		fn(input: array of byte): ref Iobuf;
};

BufioFill: module
{
	fill:	fn(b: ref Bufio->Iobuf): int;
};

ChanFill: module
{
	PATH:	con "/dis/lib/chanfill.dis";

	init:	fn(data: array of byte, fid: int, wc: Sys->Rwrite, r: ref Sys->FileIO, b: Bufio): ref Bufio->Iobuf;
	fill:	fn(b: ref Bufio->Iobuf): int;
};
