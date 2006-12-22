implement Mimeimage;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect, Image: import draw;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;
include "imagefile.m";
	imageremap: Imageremap;
include "mimeimage.m";

display: ref Draw->Display;

imagemodules := array[] of {
	("gif", RImagefile->READGIFPATH),
	("jpeg", RImagefile->READJPGPATH),
	("jpg", RImagefile->READJPGPATH),
	("xbm", RImagefile->READXBMPATH),		# not actually a mime type.
	("pic", RImagefile->READPICPATH),
	("png", RImagefile->READPNGPATH),
};

badmodule(p: string)
{
	sys->fprint(sys->fildes(2), "mimeimage: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init(displ: ref Draw->Display)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	if (draw == nil)
		badmodule(Draw->PATH);
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil)
		badmodule(Bufio->PATH);
	imageremap = load Imageremap Imageremap->PATH;
	if (imageremap == nil)
		badmodule(Imageremap->PATH);
	str = load String String->PATH;
	if (str == nil)
		badmodule(String->PATH);

	display = displ;
}

imagesize(mediatype, file: string): (Draw->Point, string)
{
	(img, e) := image(mediatype, file);
	if (img == nil)
		return ((0, 0), e);
	return ((img.r.dx(), img.r.dy()), nil);
}

image(mediatype, file: string): (ref Draw->Image, string)
{
	if (mediatype == nil) {
		for (i := len file - 1; i >= 0; i--)
			if (file[i] == '.')
				break;
		if (i >= 0)
			mediatype = str->tolower(file[i + 1:]);
	}
	# special case for native image type
	if (mediatype == "bit") {
		img := draw->display.open(file);
		err: string;
		if (img == nil)
			err = sys->sprint("%r");
		return (img, err);
	}
	iob := bufio->open(file, Sys->OREAD);
	if (iob == nil)
		return (nil, sys->sprint("%r"));
	for (i := 0; i < len imagemodules; i++)
		if (imagemodules[i].t0 == mediatype)
			break;
	if (i == len imagemodules)
		return (nil, "unrecognised image type");

	# XXX should probably cache the image modules, but do we really want to
	# pay the price?
	mod := load RImagefile imagemodules[i].t1;
	if (mod == nil)
		return (nil, sys->sprint("cannot load %s: %r", imagemodules[i].t1));
	mod->init(bufio);
	(raw, e) := mod->read(iob);
	if (raw == nil)
		return (nil, e);
	return imageremap->remap(raw, display, 1);
}
