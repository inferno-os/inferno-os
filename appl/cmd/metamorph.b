implement metamorph;

include "sys.m";
include "draw.m";
include "bufio.m";
include "string.m";
include "imagefile.m";

sys:	Sys;
bufio:	Bufio;
str:	String;
draw:	Draw;

FD:	import sys;
Display: import draw;

stderr:	ref FD;

metamorph: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	if (bufio == nil) {
		sys->fprint(stderr, "could not load %s: %r\n", Bufio->PATH);
		exit;
	}
	draw = load Draw Draw->PATH;
	if (draw == nil) {
		sys->fprint(stderr, "could not load %s: %r\n", Draw->PATH);
		exit;
	}
	ri := load RImagefile RImagefile->READGIFPATH;
	if (ri == nil) {
		sys->fprint(stderr, "could not load %s: %r\n", RImagefile->READGIFPATH);
		exit;
	}
	ir := load Imageremap Imageremap->PATH;
	if (ir == nil) {
		sys->fprint(stderr, "could not load %s: %r\n", Imageremap->PATH);
		exit;
	}

	if (len args < 2) {
		sys->fprint(stderr, "Metamorph Usage:\n		metamorph <# of slides>\n\n");
		return;
		}

	infile	:string;


 	(numslides, nil) := str->toint((hd (tl args)), 10);

	for (count := 1;count <=numslides; count++) {

		ri->init(bufio);
		
		if ( count < 10 )
			infile= sys->sprint("img00%d.GIF",count);
		if (( count >= 10 ) && ( count < 100))
			infile= sys->sprint("img0%d.GIF",count);
		if (count >= 100)
			infile= sys->sprint("img%d.GIF",count);

		outfile := sys->sprint("img%d.bit",count);
		
		inf := bufio->open(infile, Bufio->OREAD);
		sys->print ("Reading %s\n",infile);
		if (inf == nil) {
			sys->fprint(stderr, "could not fopen(0): %r\n");
			exit;
		}
		(gif, s) := ri->read(inf);
		if (gif == nil) {
			sys->fprint(stderr, "bad GIF: %s\n", s);
			exit;
		}
		(im, e) := ir->remap(gif, ctxt.display, 1);
		if (im == nil) {
			sys->fprint(stderr, "bad remap: %s\n", e);
			exit;
		}
		sys->print("Writing %s\n",outfile);
		outf := sys->create(outfile, sys->OWRITE,438);
		ctxt.display.writeimage(outf, im);
		outf = nil;
	}
}
