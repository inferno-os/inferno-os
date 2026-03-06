implement ImgloadTest;

#
# Image loading tests
#
# Tests:
# - PNG magic detection
# - JPEG magic detection
# - PPM magic detection
# - Unknown format rejection
# - readpng module loads and decodes a minimal PNG
# - readjpg module loads and decodes a minimal JPEG
# - imageremap module loads
# - Format-specific error messages
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "imagefile.m";
	imageremap: Imageremap;
	readpng: RImagefile;
	readjpg: RImagefile;

include "testing.m";
	testing: Testing;
	T: import testing;

ImgloadTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/imgload_test.b";

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

# --- Magic byte detection tests ---

# Test PNG magic detection (137 80 78 71 13 10 26 10)
testPngMagic(t: ref T)
{
	pngmagic := array[] of {byte 137, byte 80, byte 78, byte 71,
	                         byte 13, byte 10, byte 26, byte 10};
	t.assert(ispng(pngmagic), "valid PNG magic should be detected");

	# Invalid magic
	notpng := array[] of {byte 0, byte 0, byte 0, byte 0,
	                       byte 0, byte 0, byte 0, byte 0};
	t.assert(!ispng(notpng), "zeroes should not match PNG magic");

	# JPEG bytes should not match PNG
	jpgbytes := array[] of {byte 16rFF, byte 16rD8, byte 16rFF, byte 16rE0,
	                         byte 0, byte 0, byte 0, byte 0};
	t.assert(!ispng(jpgbytes), "JPEG magic should not match PNG");
}

# Test JPEG magic detection (FF D8 FF)
testJpegMagic(t: ref T)
{
	# JFIF JPEG
	jfif := array[] of {byte 16rFF, byte 16rD8, byte 16rFF, byte 16rE0};
	t.assert(isjpeg(jfif), "JFIF JPEG magic should be detected");

	# EXIF JPEG
	exif := array[] of {byte 16rFF, byte 16rD8, byte 16rFF, byte 16rE1};
	t.assert(isjpeg(exif), "EXIF JPEG magic should be detected");

	# Raw JPEG (just SOI + marker)
	rawjpg := array[] of {byte 16rFF, byte 16rD8, byte 16rFF, byte 16rDB};
	t.assert(isjpeg(rawjpg), "raw JPEG magic should be detected");

	# Not JPEG
	notjpg := array[] of {byte 16rFF, byte 16rD9, byte 16rFF, byte 16rE0};
	t.assert(!isjpeg(notjpg), "FF D9 should not match JPEG magic");

	# PNG should not match JPEG
	pngbytes := array[] of {byte 137, byte 80, byte 78, byte 71};
	t.assert(!isjpeg(pngbytes), "PNG magic should not match JPEG");
}

# Test PPM magic detection
testPpmMagic(t: ref T)
{
	p6 := array[] of {byte 'P', byte '6'};
	t.assert(isppm(p6), "P6 magic should be detected as PPM");

	p3 := array[] of {byte 'P', byte '3'};
	t.assert(isppm(p3), "P3 magic should be detected as PPM");

	# P5 is PGM, not PPM we handle, but it's worth noting
	notp := array[] of {byte 'X', byte '6'};
	t.assert(!isppm(notp), "X6 should not match PPM magic");
}

# Test format dispatch logic
testFormatDispatch(t: ref T)
{
	# PNG data should be identified as PNG
	pngdata := array[8] of byte;
	pngmagic := array[] of {byte 137, byte 80, byte 78, byte 71,
	                         byte 13, byte 10, byte 26, byte 10};
	pngdata[0:] = pngmagic;
	t.assertseq(detectformat(pngdata), "png", "PNG data should be detected");

	# JPEG data should be identified as JPEG
	jpgdata := array[8] of byte;
	jpgdata[0] = byte 16rFF;
	jpgdata[1] = byte 16rD8;
	jpgdata[2] = byte 16rFF;
	jpgdata[3] = byte 16rE0;
	t.assertseq(detectformat(jpgdata), "jpeg", "JPEG data should be detected");

	# PPM data should be identified as PPM
	ppmdata := array[8] of byte;
	ppmdata[0] = byte 'P';
	ppmdata[1] = byte '6';
	t.assertseq(detectformat(ppmdata), "ppm", "PPM P6 data should be detected");

	# Unknown data
	unkdata := array[] of {byte 'X', byte 'Y', byte 'Z', byte 0,
	                        byte 0, byte 0, byte 0, byte 0};
	t.assertseq(detectformat(unkdata), "unknown", "random bytes should be unknown");
}

# --- Module loading tests ---

# Test that readpng module can be loaded
testReadpngLoads(t: ref T)
{
	if(readpng == nil){
		readpng = load RImagefile RImagefile->READPNGPATH;
		if(readpng == nil){
			t.fatal("cannot load readpng module from " + RImagefile->READPNGPATH);
			return;
		}
		readpng->init(bufio);
	}
	t.log("readpng module loaded successfully");
}

# Test that readjpg module can be loaded
testReadjpgLoads(t: ref T)
{
	if(readjpg == nil){
		readjpg = load RImagefile RImagefile->READJPGPATH;
		if(readjpg == nil){
			t.fatal("cannot load readjpg module from " + RImagefile->READJPGPATH);
			return;
		}
		readjpg->init(bufio);
	}
	t.log("readjpg module loaded successfully");
}

# Test that imageremap module loads
testImageremapLoads(t: ref T)
{
	if(imageremap == nil){
		imageremap = load Imageremap Imageremap->PATH;
		if(imageremap == nil){
			t.fatal("cannot load imageremap module");
			return;
		}
		# Note: imageremap->init() requires a Display, skip in headless
	}
	t.log("imageremap module loaded successfully");
}

# --- PNG decode tests ---

# Test decoding a minimal valid 1x1 red PNG (8-bit RGB, no interlace)
testDecodePng1x1(t: ref T)
{
	if(readpng == nil){
		readpng = load RImagefile RImagefile->READPNGPATH;
		if(readpng == nil){
			t.skip("readpng not available");
			return;
		}
		readpng->init(bufio);
	}

	# Minimal 1x1 red PNG (pre-computed)
	# This is a valid PNG with IHDR, IDAT, IEND
	png := mkpng1x1red();
	fd := bufio->aopen(png);
	if(fd == nil){
		t.fatal("cannot create bufio from PNG data");
		return;
	}

	(raw, err) := readpng->read(fd);
	fd.close();

	if(raw == nil){
		t.fatal(sys->sprint("readpng->read failed: %s", err));
		return;
	}

	t.asserteq(raw.r.max.x, 1, "PNG width should be 1");
	t.asserteq(raw.r.max.y, 1, "PNG height should be 1");
	t.asserteq(raw.nchans, 3, "PNG should have 3 channels (RGB)");
	t.assert(raw.chans != nil, "PNG chans should not be nil");
	t.asserteq(len raw.chans, 3, "PNG should have 3 channel arrays");

	# Check pixel data: red = (255, 0, 0) in R, G, B channels
	if(len raw.chans[0] > 0 && len raw.chans[1] > 0 && len raw.chans[2] > 0){
		t.asserteq(int raw.chans[0][0], 255, "red channel should be 255");
		t.asserteq(int raw.chans[1][0], 0, "green channel should be 0");
		t.asserteq(int raw.chans[2][0], 0, "blue channel should be 0");
	}
	t.log("1x1 red PNG decoded successfully");
}

# Test readpng rejects invalid data gracefully
testPngInvalidData(t: ref T)
{
	if(readpng == nil){
		readpng = load RImagefile RImagefile->READPNGPATH;
		if(readpng == nil){
			t.skip("readpng not available");
			return;
		}
		readpng->init(bufio);
	}

	# Feed garbage bytes
	garbage := array[64] of { * => byte 16rAA };
	fd := bufio->aopen(garbage);
	if(fd == nil){
		t.fatal("cannot create bufio from garbage data");
		return;
	}

	(raw, err) := readpng->read(fd);
	fd.close();

	t.assert(raw == nil || err != nil, "readpng should fail on garbage data");
	t.log(sys->sprint("readpng rejected garbage: %s", err));
}

# --- JPEG decode tests ---

# Test decoding a minimal valid 1x1 JPEG
testDecodeJpeg1x1(t: ref T)
{
	if(readjpg == nil){
		readjpg = load RImagefile RImagefile->READJPGPATH;
		if(readjpg == nil){
			t.skip("readjpg not available");
			return;
		}
		readjpg->init(bufio);
	}

	jpg := mkjpeg1x1();
	fd := bufio->aopen(jpg);
	if(fd == nil){
		t.fatal("cannot create bufio from JPEG data");
		return;
	}

	(raw, err) := readjpg->read(fd);
	fd.close();

	if(raw == nil){
		t.fatal(sys->sprint("readjpg->read failed: %s", err));
		return;
	}

	t.asserteq(raw.r.max.x, 1, "JPEG width should be 1");
	t.asserteq(raw.r.max.y, 1, "JPEG height should be 1");
	t.assert(raw.nchans == 1 || raw.nchans == 3, "JPEG should have 1 or 3 channels");
	t.assert(raw.chans != nil, "JPEG chans should not be nil");
	t.log(sys->sprint("1x1 JPEG decoded: %dx%d, %d chans",
		raw.r.max.x, raw.r.max.y, raw.nchans));
}

# Test readjpg rejects invalid data gracefully
testJpegInvalidData(t: ref T)
{
	if(readjpg == nil){
		readjpg = load RImagefile RImagefile->READJPGPATH;
		if(readjpg == nil){
			t.skip("readjpg not available");
			return;
		}
		readjpg->init(bufio);
	}

	garbage := array[64] of { * => byte 16rBB };
	fd := bufio->aopen(garbage);
	if(fd == nil){
		t.fatal("cannot create bufio from garbage data");
		return;
	}

	(raw, err) := readjpg->read(fd);
	fd.close();

	t.assert(raw == nil || err != nil, "readjpg should fail on garbage data");
	t.log(sys->sprint("readjpg rejected garbage: %s", err));
}

# --- Test data construction ---

# PNG magic bytes helper
ispng(buf: array of byte): int
{
	pngmagic := array[] of {byte 137, byte 80, byte 78, byte 71,
	                         byte 13, byte 10, byte 26, byte 10};
	if(len buf < 8)
		return 0;
	for(i := 0; i < 8; i++)
		if(buf[i] != pngmagic[i])
			return 0;
	return 1;
}

# JPEG magic bytes helper
isjpeg(buf: array of byte): int
{
	if(len buf < 3)
		return 0;
	return buf[0] == byte 16rFF && buf[1] == byte 16rD8 && buf[2] == byte 16rFF;
}

# PPM magic bytes helper
isppm(buf: array of byte): int
{
	if(len buf < 2)
		return 0;
	if(buf[0] != byte 'P')
		return 0;
	return buf[1] == byte '3' || buf[1] == byte '6';
}

# Format detection (mirrors imgload.b dispatch logic)
detectformat(buf: array of byte): string
{
	if(len buf >= 8 && ispng(buf))
		return "png";
	if(len buf >= 3 && isjpeg(buf))
		return "jpeg";
	if(len buf >= 2 && isppm(buf))
		return "ppm";
	return "unknown";
}

# Build a CRC32 table and compute CRC for PNG chunks
crctable: array of int;

initcrc()
{
	crctable = array[256] of int;
	for(n := 0; n < 256; n++){
		c := n;
		for(k := 0; k < 8; k++){
			if(c & 1)
				c = int 16rEDB88320 ^ (c >> 1);
			else
				c = c >> 1;
		}
		crctable[n] = c;
	}
}

pngcrc(data: array of byte): array of byte
{
	if(crctable == nil)
		initcrc();

	c := int 16rFFFFFFFF;
	for(i := 0; i < len data; i++)
		c = crctable[(c ^ int data[i]) & 16rFF] ^ (c >> 8);
	c = c ^ int 16rFFFFFFFF;

	crc := array[4] of byte;
	crc[0] = byte(c >> 24);
	crc[1] = byte(c >> 16);
	crc[2] = byte(c >> 8);
	crc[3] = byte c;
	return crc;
}

# Build a minimal 1x1 red PNG (8-bit RGB, no interlace)
mkpng1x1red(): array of byte
{
	# PNG signature
	sig := array[] of {byte 137, byte 80, byte 78, byte 71,
	                    byte 13, byte 10, byte 26, byte 10};

	# IHDR: 1x1, 8-bit, RGB (colortype 2), no interlace
	ihdrdata := array[] of {
		byte 0, byte 0, byte 0, byte 1,  # width = 1
		byte 0, byte 0, byte 0, byte 1,  # height = 1
		byte 8,                            # bit depth = 8
		byte 2,                            # color type = 2 (RGB)
		byte 0,                            # compression = 0
		byte 0,                            # filter = 0
		byte 0                             # interlace = 0
	};
	ihdrtypedata := array[4 + len ihdrdata] of byte;
	ihdrtypedata[0:] = array[] of {byte 'I', byte 'H', byte 'D', byte 'R'};
	ihdrtypedata[4:] = ihdrdata;
	ihdrcrc := pngcrc(ihdrtypedata);

	# IDAT: zlib header + deflate block with row data
	# Row data: filter=0, R=255, G=0, B=0
	# zlib: 78 01 = CMF=78 (deflate, window 7), FLG=01 (no dict, FCHECK=1)
	# deflate final block, no compression:
	#   01 = BFINAL=1, BTYPE=00 (no compression)
	#   04 00 FB FF = LEN=4, NLEN=~4
	#   00 FF 00 00 = filter(0), R(255), G(0), B(0)
	# adler32 of uncompressed: s1=256, s2=512 => 00 02 01 00
	idatpayload := array[] of {
		byte 16r78, byte 16r01,             # zlib header
		byte 16r01,                          # BFINAL=1, BTYPE=00
		byte 16r04, byte 16r00,             # LEN=4
		byte 16rFB, byte 16rFF,             # NLEN=~4
		byte 16r00,                          # filter byte = None
		byte 16rFF, byte 16r00, byte 16r00, # R=255, G=0, B=0
		byte 16r00, byte 16r02, byte 16r01, byte 16r00  # adler32
	};
	idattypedata := array[4 + len idatpayload] of byte;
	idattypedata[0:] = array[] of {byte 'I', byte 'D', byte 'A', byte 'T'};
	idattypedata[4:] = idatpayload;
	idatcrc := pngcrc(idattypedata);

	# IEND
	iendtypedata := array[] of {byte 'I', byte 'E', byte 'N', byte 'D'};
	iendcrc := pngcrc(iendtypedata);

	# Assemble full PNG
	total := len sig
		+ 4 + 4 + len ihdrdata + 4      # IHDR chunk
		+ 4 + 4 + len idatpayload + 4   # IDAT chunk
		+ 4 + 4 + 0 + 4;                # IEND chunk

	png := array[total] of byte;
	off := 0;

	# Signature
	png[off:] = sig;
	off += len sig;

	# IHDR
	putbe32(png, off, len ihdrdata); off += 4;
	png[off:] = ihdrtypedata;
	off += len ihdrtypedata;
	png[off:] = ihdrcrc; off += 4;

	# IDAT
	putbe32(png, off, len idatpayload); off += 4;
	png[off:] = idattypedata;
	off += len idattypedata;
	png[off:] = idatcrc; off += 4;

	# IEND
	putbe32(png, off, 0); off += 4;
	png[off:] = iendtypedata;
	off += len iendtypedata;
	png[off:] = iendcrc; off += 4;

	return png;
}

# Build a minimal 1x1 grayscale JPEG (baseline, JFIF)
# This is the smallest valid JFIF JPEG that readjpg can decode
mkjpeg1x1(): array of byte
{
	# Minimal JFIF 1x1 grayscale JPEG
	# Constructed from JPEG spec:
	#   SOI, APP0 (JFIF), DQT, SOF0, DHT (DC), DHT (AC), SOS, data, EOI
	jpg := array[] of {
		# SOI
		byte 16rFF, byte 16rD8,

		# APP0 - JFIF marker
		byte 16rFF, byte 16rE0,
		byte 16r00, byte 16r10,  # length = 16
		byte 'J', byte 'F', byte 'I', byte 'F', byte 0,  # JFIF\0
		byte 16r01, byte 16r01,  # version 1.1
		byte 16r00,              # aspect ratio units = none
		byte 16r00, byte 16r01,  # X density = 1
		byte 16r00, byte 16r01,  # Y density = 1
		byte 16r00, byte 16r00,  # no thumbnail

		# DQT - quantization table (all 1s for simplicity)
		byte 16rFF, byte 16rDB,
		byte 16r00, byte 16r43,  # length = 67
		byte 16r00,              # table 0, 8-bit precision
		# 64 quantization values (all 1 for lossless-ish)
		byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1,
		byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1,
		byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1,
		byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1,
		byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1,
		byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1,
		byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1,
		byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1,

		# SOF0 - Start of Frame (baseline, 1x1, 1 component grayscale)
		byte 16rFF, byte 16rC0,
		byte 16r00, byte 16r0B,  # length = 11
		byte 16r08,              # 8-bit precision
		byte 16r00, byte 16r01,  # height = 1
		byte 16r00, byte 16r01,  # width = 1
		byte 16r01,              # 1 component
		byte 16r01,              # component ID = 1
		byte 16r11,              # H=1, V=1
		byte 16r00,              # quant table 0

		# DHT - DC Huffman table (class 0, table 0)
		# Minimal table: just code for category 0 (DC=0)
		byte 16rFF, byte 16rC4,
		byte 16r00, byte 16r1F,  # length = 31
		byte 16r00,              # DC table, ID 0
		# 16 count bytes: 1 code of length 1, rest 0
		byte 16r00, byte 16r01, byte 16r05, byte 16r01,
		byte 16r01, byte 16r01, byte 16r01, byte 16r01,
		byte 16r01, byte 16r00, byte 16r00, byte 16r00,
		byte 16r00, byte 16r00, byte 16r00, byte 16r00,
		# values
		byte 16r00, byte 16r01, byte 16r02, byte 16r03,
		byte 16r04, byte 16r05, byte 16r06, byte 16r07,
		byte 16r08, byte 16r09, byte 16r0A, byte 16r0B,

		# DHT - AC Huffman table (class 1, table 0)
		byte 16rFF, byte 16rC4,
		byte 16r00, byte 16rB5,  # length = 181
		byte 16r10,              # AC table, ID 0
		# Standard luminance AC table counts
		byte 16r00, byte 16r02, byte 16r01, byte 16r03,
		byte 16r03, byte 16r02, byte 16r04, byte 16r03,
		byte 16r05, byte 16r05, byte 16r04, byte 16r04,
		byte 16r00, byte 16r00, byte 16r01, byte 16r7D,
		# Standard luminance AC table values (162 values)
		byte 16r01, byte 16r02, byte 16r03, byte 16r00,
		byte 16r04, byte 16r11, byte 16r05, byte 16r12,
		byte 16r21, byte 16r31, byte 16r41, byte 16r06,
		byte 16r13, byte 16r51, byte 16r61, byte 16r07,
		byte 16r22, byte 16r71, byte 16r14, byte 16r32,
		byte 16r81, byte 16r91, byte 16rA1, byte 16r08,
		byte 16r23, byte 16r42, byte 16rB1, byte 16rC1,
		byte 16r15, byte 16r52, byte 16rD1, byte 16rF0,
		byte 16r24, byte 16r33, byte 16r62, byte 16r72,
		byte 16r82, byte 16r09, byte 16r0A, byte 16r16,
		byte 16r17, byte 16r18, byte 16r19, byte 16r1A,
		byte 16r25, byte 16r26, byte 16r27, byte 16r28,
		byte 16r29, byte 16r2A, byte 16r34, byte 16r35,
		byte 16r36, byte 16r37, byte 16r38, byte 16r39,
		byte 16r3A, byte 16r43, byte 16r44, byte 16r45,
		byte 16r46, byte 16r47, byte 16r48, byte 16r49,
		byte 16r4A, byte 16r53, byte 16r54, byte 16r55,
		byte 16r56, byte 16r57, byte 16r58, byte 16r59,
		byte 16r5A, byte 16r63, byte 16r64, byte 16r65,
		byte 16r66, byte 16r67, byte 16r68, byte 16r69,
		byte 16r6A, byte 16r73, byte 16r74, byte 16r75,
		byte 16r76, byte 16r77, byte 16r78, byte 16r79,
		byte 16r7A, byte 16r83, byte 16r84, byte 16r85,
		byte 16r86, byte 16r87, byte 16r88, byte 16r89,
		byte 16r8A, byte 16r92, byte 16r93, byte 16r94,
		byte 16r95, byte 16r96, byte 16r97, byte 16r98,
		byte 16r99, byte 16r9A, byte 16rA2, byte 16rA3,
		byte 16rA4, byte 16rA5, byte 16rA6, byte 16rA7,
		byte 16rA8, byte 16rA9, byte 16rAA, byte 16rB2,
		byte 16rB3, byte 16rB4, byte 16rB5, byte 16rB6,
		byte 16rB7, byte 16rB8, byte 16rB9, byte 16rBA,
		byte 16rC2, byte 16rC3, byte 16rC4, byte 16rC5,
		byte 16rC6, byte 16rC7, byte 16rC8, byte 16rC9,
		byte 16rCA, byte 16rD2, byte 16rD3, byte 16rD4,
		byte 16rD5, byte 16rD6, byte 16rD7, byte 16rD8,
		byte 16rD9, byte 16rDA, byte 16rE1, byte 16rE2,
		byte 16rE3, byte 16rE4, byte 16rE5, byte 16rE6,
		byte 16rE7, byte 16rE8, byte 16rE9, byte 16rEA,
		byte 16rF1, byte 16rF2, byte 16rF3, byte 16rF4,
		byte 16rF5, byte 16rF6, byte 16rF7, byte 16rF8,
		byte 16rF9, byte 16rFA,

		# SOS - Start of Scan
		byte 16rFF, byte 16rDA,
		byte 16r00, byte 16r08,  # length = 8
		byte 16r01,              # 1 component
		byte 16r01,              # component 1
		byte 16r00,              # DC table 0, AC table 0
		byte 16r00,              # Ss = 0
		byte 16r3F,              # Se = 63
		byte 16r00,              # Ah=0, Al=0

		# Entropy-coded data: DC=128 (gray), all AC=0
		# DC category 8 (value 128): Huffman code for cat 8 then 8 bits
		# With standard luminance DC table, cat 8 = code 111110 (6 bits)
		# Then value 128 = 10000000 (8 bits)
		# Then EOB (AC): code 1010 (4 bits) from standard AC table
		# Total: 111110 10000000 1010 = 18 bits
		# Padded: 11111010 00000010 10111111 (fill bits)
		byte 16rFA, byte 16r02, byte 16rBF,

		# EOI
		byte 16rFF, byte 16rD9
	};
	return jpg;
}

# Write a big-endian 32-bit int into a byte array
putbe32(buf: array of byte, off, val: int)
{
	buf[off] = byte(val >> 24);
	buf[off+1] = byte(val >> 16);
	buf[off+2] = byte(val >> 8);
	buf[off+3] = byte val;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil){
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	testing->init();

	for(a := args; a != nil; a = tl a){
		if(hd a == "-v")
			testing->verbose(1);
	}

	# Magic byte detection tests
	run("PngMagic", testPngMagic);
	run("JpegMagic", testJpegMagic);
	run("PpmMagic", testPpmMagic);
	run("FormatDispatch", testFormatDispatch);

	# Module loading tests
	run("ReadpngLoads", testReadpngLoads);
	run("ReadjpgLoads", testReadjpgLoads);
	run("ImageremapLoads", testImageremapLoads);

	# PNG decode tests
	run("DecodePng1x1", testDecodePng1x1);
	run("PngInvalidData", testPngInvalidData);

	# JPEG decode tests
	run("DecodeJpeg1x1", testDecodeJpeg1x1);
	run("JpegInvalidData", testJpegInvalidData);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
