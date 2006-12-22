implement MakeRGBVMap;

include "sys.m";
include "draw.m";

draw: Draw;
sys: Sys;

Display: import draw;

MakeRGBVMap: module
{
	init:	fn(ctxt: ref Draw->Context, nil: list of string);
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	if (draw == nil) {
		sys->print("could not load %s: %r\n", Draw->PATH);
		exit;
	}
	d := ctxt.display;
	sys->print("rgbvmap := array[3*256] of {\n");
	for (i := 0; i < 256; i++) {
		(r, g, b) := d.cmap2rgb(i);
		sys->print("\tbyte\t%d,byte\t%d,byte\t%d,\n", r, g, b);
	}
	sys->print("};\n");
}
