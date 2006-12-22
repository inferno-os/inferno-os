#
# gif2bit -
#
# A simple command line utility for converting GIF images to
# inferno bitmaps.
#
# Craig Newell, Jan. 1999	CraigN@cheque.uq.edu.au
#
implement gif2bit;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display: import draw;
include "string.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "imagefile.m";

mod_name := "gif2bit";

gif2bit : module
{
	init: fn(ctx: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->print("usage: %s <GIF file>\n", mod_name);
	exit;
}	

init(ctx: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;

	# check arguments
	if (argv == nil) 
		usage();
	mod_name = hd argv;
	argv = tl argv;
	if (argv == nil)
		usage();
	s := hd argv;
	if (len s && s[0] == '-')
		usage();

	# load the modules	
	str := load String String->PATH;
	draw = load Draw Draw->PATH;
	bufio = load Bufio Bufio->PATH;
	remap := load Imageremap Imageremap->PATH;
	imgfile := load RImagefile RImagefile->READGIFPATH;
	imgfile->init(bufio);

	# open the display
	display: ref Draw->Display;
	if (ctx == nil) {
		display = Display.allocate(nil);
	} else {
		display = ctx.display;
	}

	# process all the files 
	while (argv != nil) {
	
		# get the filenames		
		gif_name := hd argv;
		argv = tl argv;
		(base_name, nil) := str->splitstrl(gif_name, ".gif");
		bit_name := base_name + ".bit";

		i := bufio->open(gif_name, Bufio->OREAD);
		if (i == nil) {
			sys->print("%s: unable to open <%s>\n", mod_name, gif_name);
			continue;
		}
		(raw_img, errstr) := imgfile->read(i);
		if (errstr != nil) {
			sys->print("%s: %s\n", mod_name, errstr);
			continue;
		}
		i.close();

		(img, errstr1) := remap->remap(raw_img, display, 0);
		if (errstr1 != nil) {
			sys->print("%s: %s\n", mod_name, errstr1);
			continue;
		}
	
		ofd := sys->create(bit_name, Sys->OWRITE, 8r644);
		if (ofd == nil) {
			sys->print("%s: unable to create <%s>\n", mod_name, bit_name);
			continue;
		}
		display.writeimage(ofd, img);
		ofd = nil;	
	}
}
