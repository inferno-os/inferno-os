Mimeimage: module {
	PATH: con "/dis/ebook/mimeimage.dis";
	init: fn(displ: ref Draw->Display);
	image: fn(mediatype, file: string): (ref Draw->Image, string);
	imagesize: fn(mediatype, file: string): (Draw->Point, string);
};

