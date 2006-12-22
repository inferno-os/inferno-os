#
# bit2gif -
#
# A simple command line utility for converting inferno bitmaps
# to gif images.
#
# Craig Newell, Jan. 1999	CraigN@cheque.uq.edu.au
#
implement bit2gif;

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

bit2gif : module
{
	init: fn(ctx: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->print("usage: bit2gif <inferno bitmap>\n");
	exit;
}	

init(ctx: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;

	# check arguments
	if (argv == nil) 
		usage();
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
	imgfile := load WImagefile WImagefile->WRITEGIFPATH;
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
		bit_name := hd argv;
		(gif_name, nil) := str->splitstrl(bit_name, ".bit");
		gif_name = gif_name + ".gif";

		# load inferno bitmap
		img := display.open(bit_name);
		if (img == nil) {
			sys->print("bit2gif: unable to read <%s>\n", bit_name);
		} else {
			# save as gif
			o := bufio->create(gif_name, Bufio->OWRITE, 8r644);
			if (o != nil) {
				imgfile->writeimage(o, img);
				o.close();
			}
		}

		# next argument
		argv = tl argv;
	}
}
