Devpointer: module
{
	PATH:	con	"/dis/lib/devpointer.dis";

	Size:		con 1+4*12;	# 'm' plus 4 12-byte decimal integers
	# merge events that have the same button state.
	Ptrqueue: adt {
		last: ref Draw->Pointer;
		h, t: list of ref Draw->Pointer;
		put:			fn(q: self ref Ptrqueue, s: ref Draw->Pointer);
		get:			fn(q: self ref Ptrqueue): ref Draw->Pointer;
		peek:		fn(q: self ref Ptrqueue): ref Draw->Pointer;
		nonempty:	fn(q: self ref Ptrqueue): int;
	};

	init:		fn();
	reader:	fn(file: string, posn: chan of ref Draw->Pointer, pid: chan of (int, string));
	bytes2ptr:	fn(b: array of byte): ref Draw->Pointer;
	ptr2bytes:	fn(p: ref Draw->Pointer): array of byte;
	srv:	fn(c: chan of ref Draw->Pointer, f: ref Sys->FileIO);
};
