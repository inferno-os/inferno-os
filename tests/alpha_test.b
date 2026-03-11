implement AlphaTest;

#
# Regression tests for RGBA32 pre-multiplied alpha in imageremap.b.
#
# Background: PNG images store straight (un-premultiplied) alpha. Inferno's
# alphacalc11 Porter-Duff SoverD with a nil mask computes:
#   fd  = 255 - A
#   dst = MUL(255, src_R) + MUL(fd, dst_R)
# This is only correct when src_R is already pre-multiplied (src_R = R*A/255).
#
# Bug (commit 2810bb20): imageremap.b stored straight alpha and lucifer.b used
# logoimg-as-mask, making alphacalc11 compute fd=255-A^2/255 — causing
# semi-transparent edge pixels to render as near-background colour ("christmas tree").
#
# Fix (commit 1dbdddda): pre-multiply R,G,B by A in imageremap.b CRGBA path;
# revert lucifer.b draw call to use nil mask.
#
# Tests verify:
#   1. Opaque pixel (A=255): pre-mult is identity, values unchanged
#   2. Transparent pixel (A=0): pre-mult zeroes all RGB channels
#   3. Semi-transparent pixel: stored as R*A/255, G*A/255, B*A/255
#   4. Half-transparent blue over red background composites correctly
#      (correct R≈127; buggy implementation with mask=src gives R≈191)
#
# Run: emu -g200x100 -r. /dis/tests/alpha_test.dis
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Image, Rect, Point: import draw;

include "bufio.m";

include "imagefile.m";
	remap: Imageremap;

include "testing.m";
	testing: Testing;
	T: import testing;

AlphaTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/alpha_test.b";

passed  := 0;
failed  := 0;
skipped := 0;

display: ref Display;

run(name: string, testfn: ref fn(t: ref T))
{
	t := testing->newTsrc(name, SRCFILE);
	{
		testfn(t);
	} exception {
	"fail:fatal" =>
		;
	"fail:skip" =>
		;
	"*" =>
		t.failed = 1;
	}

	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

# Build a synthetic 1x1 RGBA raw image with the given channel values.
mkrgbaraw(r, g, b, a: int): ref RImagefile->Rawimage
{
	raw := ref RImagefile->Rawimage;
	raw.r = Rect((0,0),(1,1));
	raw.nchans = 4;
	raw.chandesc = RImagefile->CRGBA;
	raw.chans = array[4] of array of byte;
	raw.chans[0] = array[1] of byte;
	raw.chans[1] = array[1] of byte;
	raw.chans[2] = array[1] of byte;
	raw.chans[3] = array[1] of byte;
	raw.chans[0][0] = byte r;   # R channel
	raw.chans[1][0] = byte g;   # G channel
	raw.chans[2][0] = byte b;   # B channel
	raw.chans[3][0] = byte a;   # A channel
	raw.cmap  = nil;
	raw.transp = 0;
	return raw;
}

# Remap a raw RGBA image and read back the 4 RGBA32 bytes.
# RGBA32 memory layout: byte[0]=A, byte[1]=B, byte[2]=G, byte[3]=R
remapbytes(raw: ref RImagefile->Rawimage): array of byte
{
	(im, err) := remap->remap(raw, display, 0);
	if(im == nil) {
		sys->fprint(sys->fildes(2), "remap failed: %s\n", err);
		return nil;
	}
	buf := array[4] of {byte 0};
	im.readpixels(im.r, buf);
	return buf;
}

# Inferno's integer MUL used by alphacalc11: (a*b+127)/255
mul(a, b: int): int
{
	return (a * b + 127) / 255;
}

# Test 1: fully opaque pixel — A=255, pre-multiply is identity
testOpaqueUnchanged(t: ref T)
{
	# Orange: R=255, G=105, B=52, A=255
	buf := remapbytes(mkrgbaraw(255, 105, 52, 255));
	if(buf == nil) { t.fatal("remap returned nil"); return; }
	# With A=255: R*255/255=R, so all values are unchanged
	t.asserteq(int buf[0], 255, "opaque A=255");
	t.asserteq(int buf[1], 52,  "opaque B=52*255/255=52");
	t.asserteq(int buf[2], 105, "opaque G=105*255/255=105");
	t.asserteq(int buf[3], 255, "opaque R=255*255/255=255");
}

# Test 2: fully transparent pixel — A=0, all RGB must be zeroed
testTransparentZeroed(t: ref T)
{
	# Non-zero RGB values with A=0: pre-multiply zeroes everything
	buf := remapbytes(mkrgbaraw(200, 100, 50, 0));
	if(buf == nil) { t.fatal("remap returned nil"); return; }
	t.asserteq(int buf[0], 0, "transparent A=0");
	t.asserteq(int buf[1], 0, "transparent B=50*0/255=0");
	t.asserteq(int buf[2], 0, "transparent G=100*0/255=0");
	t.asserteq(int buf[3], 0, "transparent R=200*0/255=0");
}

# Test 3: semi-transparent pixel matching logo-halo.png edge data
# Values taken from testlogoremap output: raw R=53, G=158, B=255, A=34
testSemiTransparentPreMult(t: ref T)
{
	buf := remapbytes(mkrgbaraw(53, 158, 255, 34));
	if(buf == nil) { t.fatal("remap returned nil"); return; }
	# Expected (integer division truncates):
	#   B = 255*34/255 = 34
	#   G = 158*34/255 = 5372/255 = 21
	#   R =  53*34/255 = 1802/255 = 7
	wantA := 34;
	wantB := 255 * 34 / 255;    # 34
	wantG := 158 * 34 / 255;    # 21
	wantR :=  53 * 34 / 255;    # 7
	t.asserteq(int buf[0], wantA, "semi-trans A=34 unchanged");
	t.asserteq(int buf[1], wantB, sys->sprint("semi-trans B=255*34/255=%d", wantB));
	t.asserteq(int buf[2], wantG, sys->sprint("semi-trans G=158*34/255=%d", wantG));
	t.asserteq(int buf[3], wantR, sys->sprint("semi-trans R=53*34/255=%d",  wantR));
}

# Test 4: mid-range alpha — A=128, pure blue
testSemiTransparentMid(t: ref T)
{
	# Pure blue at ~50% opacity: R=0, G=0, B=255, A=128
	buf := remapbytes(mkrgbaraw(0, 0, 255, 128));
	if(buf == nil) { t.fatal("remap returned nil"); return; }
	# B = 255*128/255 = 32767/255 = 128; R=G=0
	wantB := 255 * 128 / 255;   # 128
	t.asserteq(int buf[0], 128,   "mid-alpha A=128");
	t.asserteq(int buf[1], wantB, sys->sprint("mid-alpha B=255*128/255=%d", wantB));
	t.asserteq(int buf[2], 0,     "mid-alpha G=0");
	t.asserteq(int buf[3], 0,     "mid-alpha R=0");
}

# Test 5: full compositing pipeline — half-transparent blue over red background.
#
# Correct result (pre-mult + nil mask):
#   fd  = 255 - MUL(128, 255) = 255 - 128 = 127
#   R   = MUL(255,   0) + MUL(127, 255) = 0 + 127 = 127
#   G   = MUL(255,   0) + MUL(127,   0) = 0
#   B   = MUL(255, 128) + MUL(127,   0) = 128
#
# Bug (mask=src, straight alpha):
#   fd  = 255 - MUL(128, 128) = 255 - 64 = 191
#   R   = MUL(128,   0) + MUL(191, 255) = 0 + 191 = 191  ← too much red
#
testCompositingCorrect(t: ref T)
{
	# Source: pure blue, half-transparent
	raw := mkrgbaraw(0, 0, 255, 128);
	(rgba, err) := remap->remap(raw, display, 0);
	if(rgba == nil) { t.fatal("remap failed: " + err); return; }

	# Background: XRGB32 filled with red (R=255, G=0, B=0)
	# XRGB32 memory layout: [B, G, R, X]
	xrgb := display.newimage(Rect((0,0),(1,1)), Draw->XRGB32, 0, Draw->Black);
	if(xrgb == nil) { t.fatal("cannot create XRGB32 image"); return; }
	bg := array[4] of {byte 0};
	bg[0] = byte 0;    # B=0
	bg[1] = byte 0;    # G=0
	bg[2] = byte 255;  # R=255
	bg[3] = byte 0;    # X=0
	xrgb.writepixels(xrgb.r, bg);

	# Composite RGBA32 over XRGB32 using nil mask (correct Porter-Duff SoverD)
	xrgb.draw(xrgb.r, rgba, nil, (0,0));

	res := array[4] of {byte 0};
	xrgb.readpixels(xrgb.r, res);

	wantR := mul(255, 0) + mul(127, 255);   # = 0 + 127 = 127
	wantG := 0;
	wantB := mul(255, 128) + mul(127, 0);   # = 128 + 0 = 128

	# XRGB32 readpixels memory: [B, G, R, X]
	gotB := int res[0];
	gotG := int res[1];
	gotR := int res[2];

	t.asserteq(gotB, wantB, sys->sprint("composite B: got %d want %d", gotB, wantB));
	t.asserteq(gotG, wantG, sys->sprint("composite G: got %d want %d", gotG, wantG));
	# Key regression check: red channel must be ~127, not ~191 (the bug value)
	t.asserteq(gotR, wantR, sys->sprint("composite R (bug gives 191): got %d want %d", gotR, wantR));
}

init(nil: ref Draw->Context, args: list of string)
{
	sys     = load Sys Sys->PATH;
	draw    = load Draw Draw->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	remap = load Imageremap Imageremap->PATH;
	if(remap == nil) {
		sys->fprint(sys->fildes(2), "cannot load imageremap: %r\n");
		raise "fail:cannot load imageremap";
	}

	display = draw->Display.allocate(nil);
	if(display == nil) {
		sys->fprint(sys->fildes(2), "cannot open display: %r\n");
		raise "fail:no display";
	}

	remap->init(display);

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	run("OpaqueUnchanged",       testOpaqueUnchanged);
	run("TransparentZeroed",     testTransparentZeroed);
	run("SemiTransparentPreMult", testSemiTransparentPreMult);
	run("SemiTransparentMid",    testSemiTransparentMid);
	run("CompositingCorrect",    testCompositingCorrect);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
