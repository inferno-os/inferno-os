Pngload: module {
	PATH: con "/dis/xenith/pngload.dis";

	init: fn(d: ref Draw->Display);

	# Load PNG from an open Iobuf. Closes fd on return.
	loadpng: fn(fd: ref Bufio->Iobuf, path: string): (ref Draw->Image, string);

	# Progressive PNG loading with progress updates. Closes fd on return.
	loadpngprogressive: fn(fd: ref Bufio->Iobuf, path: string,
	                       progress: chan of ref Imgload->ImgProgress): (ref Draw->Image, string);
};
