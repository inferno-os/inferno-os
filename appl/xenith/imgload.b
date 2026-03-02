implement Imgload;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Image, Rect, Point: import draw;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "imagefile.m";
	imageremap: Imageremap;
	readpng: RImagefile;

include "filter.m";
	inflate: Filter;

include "crc.m";
	crc: Crc;
	CRCstate: import Crc;

include "imgload.m";

# Subsampling PNG decoder state
SPng: adt {
	width, height: int;          # Original dimensions
	dstwidth, dstheight: int;    # Subsampled dimensions
	subsample: int;              # Subsample factor
	depth: int;
	colortype: int;
	nchans: int;
	alpha: int;
	filterbpp: int;
	rowsize: int;
	rowbytessofar: int;
	thisrow: array of byte;
	lastrow: array of byte;
	srcrow: int;                 # Current source row in current phase
	dstrow: int;                 # Current destination row
	done: int;
	error: string;
	# Interlacing support
	interlaced: int;             # 0=progressive, 1=Adam7
	phase: int;                  # Current interlace phase (1-7)
	phaserow: int;               # Row start for current phase
	phaserowstep: int;           # Row step for current phase
	phasecol: int;               # Column start for current phase
	phasecolstep: int;           # Column step for current phase
	phasecols: int;              # Columns in current phase
	phaserows: int;              # Rows in current phase
	phaserowsprocessed: int;     # Rows processed in current phase
	# Output buffer for interlaced - stores full image
	imgbuf: array of byte;       # Full image buffer for interlaced
};

display: ref Display;

# Maximum image size: 16 megapixels (e.g., 4000x4000)
# For larger images, increase heap: emu -pheap=128000000 ...
MAXPIXELS: con 16 * 1024 * 1024;

# Maximum for interlaced images (must fit imgbuf in heap)
# 8 million pixels × 3 bytes = 24MB intermediate buffer
MAXPIXELS_INTERLACED: con 8 * 1024 * 1024;

# Maximum edge dimension
MAXDIM: con 8192;

init(d: ref Display)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	bufio = load Bufio Bufio->PATH;
	imageremap = load Imageremap Imageremap->PATH;
	if(imageremap != nil)
		imageremap->init(d);
	crc = load Crc Crc->PATH;
	inflate = load Filter Filter->INFLATEPATH;
	if(inflate != nil)
		inflate->init();
	display = d;
}

# Calculate subsample factor to fit image within limits
# Returns 1 for no subsampling, 2 for half, etc.
calcsubsample(width, height: int): int
{
	pixels := width * height;
	if(pixels <= MAXPIXELS)
		return 1;

	# Find smallest integer factor that brings us under limit
	for(factor := 2; factor <= 16; factor++){
		newpixels := (width / factor) * (height / factor);
		if(newpixels <= MAXPIXELS)
			return factor;
	}
	return 16;  # Maximum subsample
}

readimage(path: string): (ref Image, string)
{
	if(display == nil)
		return (nil, "imgload not initialized");

	# Try native Inferno image format first
	im := display.open(path);
	if(im != nil)
		return (im, nil);

	# Open file to detect format
	fd := bufio->open(path, Sys->OREAD);
	if(fd == nil)
		return (nil, sys->sprint("can't open %s: %r", path));

	# Read magic bytes
	buf := array[8] of byte;
	n := fd.read(buf, 8);
	if(n < 2){
		fd.close();
		return (nil, "file too small");
	}

	# Reset to beginning
	fd.seek(big 0, Bufio->SEEKSTART);

	# PNG magic: 137 80 78 71 13 10 26 10
	if(n >= 8 && ispng(buf))
		return loadpng(fd, path);

	# PPM P6 magic: "P6"
	if(buf[0] == byte 'P' && buf[1] == byte '6')
		return loadppm(fd, path);

	# PPM P3 (ASCII) magic: "P3"
	if(buf[0] == byte 'P' && buf[1] == byte '3')
		return loadppm(fd, path);

	fd.close();
	return (nil, "unrecognized image format");
}

# Load image from raw bytes (for async loading where file was read in background)
readimagedata(data: array of byte, hint: string): (ref Image, string)
{
	if(display == nil)
		return (nil, "imgload not initialized");

	if(data == nil || len data < 8)
		return (nil, "image data too small");

	# Create Iobuf from memory
	fd := bufio->aopen(data);
	if(fd == nil)
		return (nil, "can't create buffer from image data");

	# Read magic bytes
	buf := array[8] of byte;
	n := fd.read(buf, 8);
	if(n < 2){
		fd.close();
		return (nil, "image data too small");
	}

	# Reset to beginning
	fd.seek(big 0, Bufio->SEEKSTART);

	# PNG magic: 137 80 78 71 13 10 26 10
	if(n >= 8 && ispng(buf))
		return loadpng(fd, hint);

	# PPM P6 magic: "P6"
	if(buf[0] == byte 'P' && buf[1] == byte '6')
		return loadppm(fd, hint);

	# PPM P3 (ASCII) magic: "P3"
	if(buf[0] == byte 'P' && buf[1] == byte '3')
		return loadppm(fd, hint);

	fd.close();
	return (nil, "unrecognized image format");
}

ispng(buf: array of byte): int
{
	pngmagic := array[] of {byte 137, byte 80, byte 78, byte 71,
	                        byte 13, byte 10, byte 26, byte 10};
	for(i := 0; i < len pngmagic; i++)
		if(buf[i] != pngmagic[i])
			return 0;
	return 1;
}

# Read PNG dimensions from IHDR chunk without decoding
# PNG structure: 8-byte signature, then IHDR chunk
# IHDR: 4 bytes length, 4 bytes "IHDR", 4 bytes width, 4 bytes height (big-endian)
pngdimensions(fd: ref Iobuf): (int, int, string)
{
	# Read first 24 bytes: signature(8) + length(4) + type(4) + width(4) + height(4)
	hdr := array[24] of byte;
	n := fd.read(hdr, 24);
	if(n < 24)
		return (0, 0, "can't read PNG header");

	# Verify IHDR chunk type at bytes 12-15
	if(hdr[12] != byte 'I' || hdr[13] != byte 'H' ||
	   hdr[14] != byte 'D' || hdr[15] != byte 'R')
		return (0, 0, "invalid PNG: missing IHDR");

	# Width at bytes 16-19 (big-endian)
	width := (int hdr[16] << 24) | (int hdr[17] << 16) |
	         (int hdr[18] << 8)  | int hdr[19];

	# Height at bytes 20-23 (big-endian)
	height := (int hdr[20] << 24) | (int hdr[21] << 16) |
	          (int hdr[22] << 8)  | int hdr[23];

	return (width, height, nil);
}

loadpng(fd: ref Iobuf, path: string): (ref Image, string)
{
	# Check dimensions BEFORE loading
	(width, height, dimerr) := pngdimensions(fd);
	if(dimerr != nil){
		fd.close();
		return (nil, dimerr);
	}

	if(width <= 0 || height <= 0){
		fd.close();
		return (nil, sys->sprint("invalid PNG dimensions: %dx%d", width, height));
	}

	# Calculate subsample factor
	subsample := calcsubsample(width, height);

	# Seek back to beginning for decode
	fd.seek(big 0, Bufio->SEEKSTART);

	# For small images, use system reader (fast, handles all PNG variants)
	if(subsample == 1){
		if(readpng == nil){
			readpng = load RImagefile RImagefile->READPNGPATH;
			if(readpng == nil){
				fd.close();
				return (nil, "can't load PNG reader");
			}
			readpng->init(bufio);
		}

		(raw, err) := readpng->read(fd);
		fd.close();
		if(raw == nil){
			if(err != nil && len err > 0)
				return (nil, "PNG: " + err);
			return (nil, "PNG decode failed");
		}

		if(imageremap == nil)
			return (nil, "imageremap not available");

		(im, err2) := imageremap->remap(raw, display, 1);
		if(im == nil){
			if(err2 != nil && len err2 > 0)
				return (nil, "PNG remap: " + err2);
			return (nil, "PNG conversion failed");
		}
		return (im, nil);
	}

	# Large images: use streaming decoder with subsampling
	return loadpngsubsample(fd, width, height, subsample);
}

# Subsampling PNG decoder - reads full rows but only stores subsampled output
loadpngsubsample(fd: ref Iobuf, width, height, subsample: int): (ref Image, string)
{
	if(crc == nil || inflate == nil){
		fd.close();
		return (nil, "PNG subsample: missing crc or inflate module");
	}

	# Skip PNG signature (8 bytes)
	sig := array[8] of byte;
	if(fd.read(sig, 8) != 8){
		fd.close();
		return (nil, "can't read PNG signature");
	}

	# Read IHDR chunk
	crcstate := crc->init(0, int 16rffffffff);

	chunklen := png_getint(fd, nil);
	if(chunklen != 13){
		fd.close();
		return (nil, "invalid IHDR size");
	}

	chunktype := array[4] of byte;
	if(fd.read(chunktype, 4) != 4){
		fd.close();
		return (nil, "can't read chunk type");
	}
	crc->crc(crcstate, chunktype, 4);

	if(string chunktype != "IHDR"){
		fd.close();
		return (nil, "expected IHDR chunk");
	}

	# Read IHDR data (we already know width/height from pngdimensions)
	ihdrdata := array[13] of byte;
	if(fd.read(ihdrdata, 13) != 13){
		fd.close();
		return (nil, "can't read IHDR data");
	}
	crc->crc(crcstate, ihdrdata, 13);

	depth := int ihdrdata[8];
	colortype := int ihdrdata[9];
	# compression := int ihdrdata[10];  # must be 0
	# filter := int ihdrdata[11];       # must be 0
	interlace := int ihdrdata[12];

	# Skip CRC
	fd.read(array[4] of byte, 4);

	# Determine channels and bytes per pixel
	nchans := 1;
	alpha := 0;
	case colortype {
	0 =>  # Grayscale
		nchans = 1;
	2 =>  # RGB
		nchans = 3;
	3 =>  # Indexed
		nchans = 1;
	4 =>  # Grayscale + Alpha
		nchans = 1;
		alpha = 1;
	6 =>  # RGBA
		nchans = 3;
		alpha = 1;
	* =>
		fd.close();
		return (nil, sys->sprint("unsupported color type %d", colortype));
	}

	if(depth != 8){
		fd.close();
		return (nil, sys->sprint("only 8-bit depth supported, got %d", depth));
	}

	srcbpp := nchans + alpha;  # bytes per pixel in source

	# For interlaced images, we need stricter subsampling since imgbuf must fit in memory
	if(interlace != 0){
		pixels := (width / subsample) * (height / subsample);
		while(pixels > MAXPIXELS_INTERLACED && subsample < 32){
			subsample++;
			pixels = (width / subsample) * (height / subsample);
		}
	}

	# Setup subsampling state
	png := ref SPng;
	png.width = width;
	png.height = height;
	png.dstwidth = width / subsample;
	png.dstheight = height / subsample;
	if(png.dstwidth < 1) png.dstwidth = 1;
	if(png.dstheight < 1) png.dstheight = 1;
	png.subsample = subsample;
	png.depth = depth;
	png.colortype = colortype;
	png.nchans = nchans;
	png.alpha = alpha;
	png.filterbpp = srcbpp;
	png.interlaced = interlace;
	png.done = 0;
	png.error = nil;

	png.dstrow = 0;
	png.phaserowsprocessed = 0;

	# Initialize phase for interlaced or non-interlaced
	if(interlace != 0){
		png.phase = 1;
		png_initphase(png);
		# For interlaced, we need full image buffer since rows arrive out of order
		png.imgbuf = array[png.dstwidth * png.dstheight * 3] of { * => byte 0 };
	} else {
		png.phase = 0;
		png.phaserow = 0;
		png.phaserowstep = 1;
		png.phasecol = 0;
		png.phasecolstep = 1;
		png.phasecols = width;
		png.phaserows = height;
		png.rowsize = width * srcbpp + 1;
		png.imgbuf = nil;
	}

	png.rowbytessofar = 0;
	png.thisrow = array[png.rowsize] of byte;
	png.lastrow = array[png.rowsize] of { * => byte 0 };
	png.srcrow = 0;

	# Allocate output image
	dstbpl := png.dstwidth * 3;  # RGB24 output
	im := display.newimage(Rect((0,0), (png.dstwidth, png.dstheight)),
		Draw->RGB24, 0, Draw->Black);
	if(im == nil){
		fd.close();
		return (nil, "can't allocate output image");
	}

	dstrowdata := array[dstbpl] of byte;
	palette: array of byte;

	# Process chunks
	rq: chan of ref Filter->Rq;
	inflateStarted := 0;
	inflateFinished := 0;
	firstIDAT := 1;

	while(png.error == nil && !png.done){
		chunklen = png_getint(fd, nil);
		if(chunklen < 0){
			png.error = "unexpected EOF";
			break;
		}

		if(fd.read(chunktype, 4) != 4){
			png.error = "can't read chunk type";
			break;
		}

		typename := string chunktype;

		case typename {
		"IEND" =>
			png.done = 1;

		"PLTE" =>
			palette = array[chunklen] of byte;
			if(fd.read(palette, chunklen) != chunklen){
				png.error = "can't read PLTE";
				break;
			}
			fd.read(array[4] of byte, 4);  # skip CRC

		"IDAT" =>
			remaining := chunklen;
			if(firstIDAT){
				rq = inflate->start(nil);
				inflateStarted = 1;
				# Skip zlib header (2 bytes)
				fd.read(array[2] of byte, 2);
				remaining -= 2;
				firstIDAT = 0;
			}

			while(remaining > 0 && png.error == nil && !inflateFinished){
				pick m := <-rq {
				Fill =>
					toread := len m.buf;
					if(toread > remaining)
						toread = remaining;
					got := fd.read(m.buf, toread);
					if(got <= 0){
						m.reply <-= -1;
						png.error = "EOF in IDAT";
						break;
					}
					m.reply <-= got;
					remaining -= got;

				Result =>
					m.reply <-= 0;
					png_processdata(png, im, dstrowdata, palette, m.buf);

				Finished =>
					inflateFinished = 1;

				Error =>
					png.error = "inflate error";
				}
			}
			fd.read(array[4] of byte, 4);  # skip CRC

		* =>
			# Skip unknown chunk
			skipbuf := array[1024] of byte;
			while(chunklen > 0){
				toread := 1024;
				if(toread > chunklen)
					toread = chunklen;
				fd.read(skipbuf, toread);
				chunklen -= toread;
			}
			fd.read(array[4] of byte, 4);  # skip CRC
		}
	}

	# Drain inflate — process any remaining Results after all IDAT data fed
	if(inflateStarted && !inflateFinished){
		while(!inflateFinished){
			pick m := <-rq {
			Fill =>
				m.reply <-= -1;
			Result =>
				m.reply <-= 0;
				png_processdata(png, im, dstrowdata, palette, m.buf);
			Finished =>
				inflateFinished = 1;
			Error =>
				inflateFinished = 1;
			}
		}
	}

	fd.close();

	if(png.error != nil)
		return (nil, "PNG: " + png.error);

	# For interlaced images, write the accumulated imgbuf to the image
	if(png.interlaced != 0 && png.imgbuf != nil){
		rowdata := array[png.dstwidth * 3] of byte;
		dstbpl := png.dstwidth * 3;
		for(y := 0; y < png.dstheight; y++){
			rowdata[0:] = png.imgbuf[y*dstbpl:(y+1)*dstbpl];
			rowr := Rect((0, y), (png.dstwidth, y + 1));
			im.writepixels(rowr, rowdata);
		}
	}

	return (im, nil);
}

# Process decompressed PNG data with subsampling
png_processdata(png: ref SPng, im: ref Image, dstrow, palette: array of byte, buf: array of byte)
{
	if(png.error != nil)
		return;

	i := 0;
	while(i < len buf){
		# For interlaced images, check if we're done with all phases
		if(png.interlaced != 0 && png.phase > 7)
			return;

		# For non-interlaced, check if we're past the image
		if(png.interlaced == 0 && png.srcrow >= png.height)
			return;

		# Skip empty phases in interlaced mode
		if(png.interlaced != 0 && png.phaserows == 0){
			png.phase++;
			if(png.phase <= 7)
				png_initphase(png);
			continue;
		}

		# Accumulate bytes into current row
		tocopy := png.rowsize - png.rowbytessofar;
		if(tocopy > len buf - i)
			tocopy = len buf - i;

		png.thisrow[png.rowbytessofar:] = buf[i:i+tocopy];
		i += tocopy;
		png.rowbytessofar += tocopy;

		if(png.rowbytessofar >= png.rowsize){
			# Complete row - apply filter
			png_applyfilter(png);

			# Output or store the row
			if(png.interlaced != 0){
				# Interlaced: store in imgbuf at correct position
				png_outputrow_interlaced(png, palette);
			} else {
				# Non-interlaced: check if we should output this row (subsample)
				if(png.srcrow % png.subsample == 0 && png.dstrow < png.dstheight){
					png_outputrow(png, im, dstrow, palette);
					png.dstrow++;
				}
			}

			# Swap rows for filter
			tmp := png.lastrow;
			png.lastrow = png.thisrow;
			png.thisrow = tmp;

			png.srcrow++;
			png.phaserowsprocessed++;
			png.rowbytessofar = 0;

			# For interlaced, check if phase is complete
			if(png.interlaced != 0 && png.phaserowsprocessed >= png.phaserows){
				png.phase++;
				if(png.phase <= 7)
					png_initphase(png);
			}
		}
	}
}

# Apply PNG filter to current row
png_applyfilter(png: ref SPng)
{
	filter := int png.thisrow[0];
	bpp := png.filterbpp;

	case filter {
	0 =>  # None
		;
	1 =>  # Sub
		for(x := bpp + 1; x < png.rowsize; x++)
			png.thisrow[x] += png.thisrow[x - bpp];
	2 =>  # Up
		for(x := 1; x < png.rowsize; x++)
			png.thisrow[x] += png.lastrow[x];
	3 =>  # Average
		for(x := 1; x < png.rowsize; x++){
			a := 0;
			if(x > bpp)
				a = int png.thisrow[x - bpp];
			a += int png.lastrow[x];
			png.thisrow[x] += byte(a / 2);
		}
	4 =>  # Paeth
		for(x := 1; x < png.rowsize; x++){
			a, b, c: int;
			if(x > bpp)
				a = int png.thisrow[x - bpp];
			else
				a = 0;
			b = int png.lastrow[x];
			if(x > bpp)
				c = int png.lastrow[x - bpp];
			else
				c = 0;
			p := a + b - c;
			pa := p - a; if(pa < 0) pa = -pa;
			pb := p - b; if(pb < 0) pb = -pb;
			pc := p - c; if(pc < 0) pc = -pc;
			if(pa <= pb && pa <= pc)
				png.thisrow[x] += byte a;
			else if(pb <= pc)
				png.thisrow[x] += byte b;
			else
				png.thisrow[x] += byte c;
		}
	}
}

# Output a subsampled row to the image (non-interlaced)
png_outputrow(png: ref SPng, im: ref Image, dstrow, palette: array of byte)
{
	srcdata := png.thisrow[1:];  # Skip filter byte
	subsample := png.subsample;
	bpp := png.nchans + png.alpha;

	for(dstx := 0; dstx < png.dstwidth; dstx++){
		srcx := dstx * subsample;
		srcoff := srcx * bpp;
		dstoff := dstx * 3;

		case png.colortype {
		0 or 4 =>  # Grayscale (with or without alpha)
			v := srcdata[srcoff];
			dstrow[dstoff] = v;
			dstrow[dstoff+1] = v;
			dstrow[dstoff+2] = v;
		2 or 6 =>  # RGB (with or without alpha)
			# RGB24 byte order: B=byte[0], G=byte[1], R=byte[2]
			dstrow[dstoff] = srcdata[srcoff+2];
			dstrow[dstoff+1] = srcdata[srcoff+1];
			dstrow[dstoff+2] = srcdata[srcoff];
		3 =>  # Indexed
			idx := int srcdata[srcoff];
			if(palette != nil && idx*3+2 < len palette){
				# Palette stores RGB; RGB24 needs BGR
				dstrow[dstoff] = palette[idx*3+2];
				dstrow[dstoff+1] = palette[idx*3+1];
				dstrow[dstoff+2] = palette[idx*3];
			}
		}
	}

	# Write row to image
	rowr := Rect((0, png.dstrow), (png.dstwidth, png.dstrow + 1));
	im.writepixels(rowr, dstrow);
}

# Output a row from interlaced PNG to imgbuf with subsampling
# Pixels go to specific positions based on phase parameters
png_outputrow_interlaced(png: ref SPng, palette: array of byte)
{
	srcdata := png.thisrow[1:];  # Skip filter byte
	bpp := png.nchans + png.alpha;
	subsample := png.subsample;
	dstbpl := png.dstwidth * 3;

	# Calculate the actual source row in original image coordinates
	# srcrow is the row within this phase, phaserow is the starting row
	actualsrcy := png.phaserow + png.srcrow * png.phaserowstep;

	# Check if this row contributes to subsampled output
	if(actualsrcy % subsample != 0)
		return;

	dsty := actualsrcy / subsample;
	if(dsty >= png.dstheight)
		return;

	# Calculate starting phasex that maps to a subsampled destination
	# We need: (phasecol + phasex * phasecolstep) % subsample == 0
	# Iterate through destination pixels and find corresponding source pixels
	colstep := png.phasecolstep;
	colstart := png.phasecol;

	for(dstx := 0; dstx < png.dstwidth; dstx++){
		# Destination pixel corresponds to source column dstx * subsample
		srcx := dstx * subsample;

		# Check if this source column is provided by this phase
		# Phase provides columns: colstart, colstart+colstep, colstart+2*colstep, ...
		if(srcx < colstart)
			continue;
		diff := srcx - colstart;
		if(diff % colstep != 0)
			continue;

		phasex := diff / colstep;
		if(phasex >= png.phasecols)
			continue;

		# Source pixel offset in row data
		srcoff := phasex * bpp;
		# Destination offset in imgbuf
		dstoff := dsty * dstbpl + dstx * 3;

		if(dstoff + 2 >= len png.imgbuf || srcoff + bpp - 1 >= len srcdata)
			continue;

		case png.colortype {
		0 or 4 =>  # Grayscale (with or without alpha)
			v := srcdata[srcoff];
			png.imgbuf[dstoff] = v;
			png.imgbuf[dstoff+1] = v;
			png.imgbuf[dstoff+2] = v;
		2 or 6 =>  # RGB (with or without alpha)
			# RGB24 byte order: B=byte[0], G=byte[1], R=byte[2]
			png.imgbuf[dstoff] = srcdata[srcoff+2];
			png.imgbuf[dstoff+1] = srcdata[srcoff+1];
			png.imgbuf[dstoff+2] = srcdata[srcoff];
		3 =>  # Indexed
			idx := int srcdata[srcoff];
			if(palette != nil && idx*3+2 < len palette){
				# Palette stores RGB; RGB24 needs BGR
				png.imgbuf[dstoff] = palette[idx*3+2];
				png.imgbuf[dstoff+1] = palette[idx*3+1];
				png.imgbuf[dstoff+2] = palette[idx*3];
			}
		}
	}
}

# Read big-endian 32-bit integer from PNG
png_getint(fd: ref Iobuf, crcstate: ref CRCstate): int
{
	buf := array[4] of byte;
	if(fd.read(buf, 4) != 4)
		return -1;
	if(crcstate != nil)
		crc->crc(crcstate, buf, 4);
	return (int buf[0] << 24) | (int buf[1] << 16) | (int buf[2] << 8) | int buf[3];
}

# Adam7 interlace parameters:
# Phase: row_start, row_step, col_start, col_step
# 1: 0, 8, 0, 8  (1/64 of pixels)
# 2: 0, 8, 4, 8  (1/64 of pixels)
# 3: 4, 8, 0, 4  (1/32 of pixels)
# 4: 0, 4, 2, 4  (1/16 of pixels)
# 5: 2, 4, 0, 2  (1/8 of pixels)
# 6: 0, 2, 1, 2  (1/4 of pixels)
# 7: 1, 2, 0, 1  (1/2 of pixels)

# Initialize phase parameters for Adam7 interlacing
png_initphase(png: ref SPng)
{
	# Adam7 parameters: (row_start, row_step, col_start, col_step)
	params := array[8] of { * => (0, 1, 0, 1) };
	params[1] = (0, 8, 0, 8);
	params[2] = (0, 8, 4, 8);
	params[3] = (4, 8, 0, 4);
	params[4] = (0, 4, 2, 4);
	params[5] = (2, 4, 0, 2);
	params[6] = (0, 2, 1, 2);
	params[7] = (1, 2, 0, 1);

	if(png.phase < 1 || png.phase > 7){
		png.error = "invalid interlace phase";
		return;
	}

	(png.phaserow, png.phaserowstep, png.phasecol, png.phasecolstep) = params[png.phase];

	# Calculate columns and rows in this phase
	png.phasecols = (png.width - png.phasecol + png.phasecolstep - 1) / png.phasecolstep;
	png.phaserows = (png.height - png.phaserow + png.phaserowstep - 1) / png.phaserowstep;

	if(png.phasecols < 0) png.phasecols = 0;
	if(png.phaserows < 0) png.phaserows = 0;

	# Calculate row size for this phase (filter byte + pixel data)
	srcbpp := png.nchans + png.alpha;
	if(png.phasecols > 0)
		png.rowsize = png.phasecols * srcbpp + 1;
	else
		png.rowsize = 1;  # Just filter byte for empty phases

	# Reallocate row buffers for this phase
	png.thisrow = array[png.rowsize] of byte;
	png.lastrow = array[png.rowsize] of { * => byte 0 };
	png.rowbytessofar = 0;
	png.srcrow = 0;
	png.phaserowsprocessed = 0;
}

loadppm(fd: ref Iobuf, path: string): (ref Image, string)
{
	# Read PPM header: P6\n<width> <height>\n<maxval>\n<data>
	# Or P3 for ASCII RGB

	magic := fd.gets('\n');
	if(magic == nil){
		fd.close();
		return (nil, "can't read PPM magic");
	}

	# Trim newline
	if(len magic > 0 && magic[len magic - 1] == '\n')
		magic = magic[:len magic - 1];

	binary := (magic == "P6");

	# Skip comments, read dimensions
	line: string;
	for(;;){
		line = fd.gets('\n');
		if(line == nil){
			fd.close();
			return (nil, "unexpected EOF in PPM header");
		}
		if(len line > 0 && line[0] != '#')
			break;
	}

	# Parse width height
	(n, toks) := sys->tokenize(line, " \t\n");
	if(n < 2){
		fd.close();
		return (nil, "bad PPM dimensions");
	}
	srcwidth := int hd toks;
	srcheight := int hd tl toks;

	if(srcwidth <= 0 || srcheight <= 0){
		fd.close();
		return (nil, "invalid PPM dimensions");
	}

	# Read maxval
	line = fd.gets('\n');
	if(line == nil){
		fd.close();
		return (nil, "can't read PPM maxval");
	}
	maxval := int line;
	if(maxval <= 0 || maxval > 255){
		fd.close();
		return (nil, "unsupported PPM maxval");
	}

	# Calculate subsample factor for large images
	subsample := calcsubsample(srcwidth, srcheight);
	dstwidth := srcwidth / subsample;
	dstheight := srcheight / subsample;
	if(dstwidth < 1) dstwidth = 1;
	if(dstheight < 1) dstheight = 1;

	# Create output image - use RGB24 format
	r := Rect((0, 0), (dstwidth, dstheight));
	im := display.newimage(r, Draw->RGB24, 0, Draw->Black);
	if(im == nil){
		fd.close();
		return (nil, "can't allocate image");
	}

	# Read pixel data with subsampling
	srcbpl := srcwidth * 3;  # Source bytes per line
	dstbpl := dstwidth * 3;  # Dest bytes per line
	srcrowdata := array[srcbpl] of byte;
	dstrowdata := array[dstbpl] of byte;

	dsty := 0;
	for(srcy := 0; srcy < srcheight; srcy++){
		if(binary){
			# Binary mode: read full source row
			nread := 0;
			while(nread < srcbpl){
				got := fd.read(srcrowdata[nread:], srcbpl - nread);
				if(got <= 0){
					fd.close();
					return (nil, "short read in PPM data");
				}
				nread += got;
			}
		} else {
			# ASCII mode: read space-separated values for full row
			for(x := 0; x < srcbpl; x++){
				s := "";
				c: int;
				while((c = fd.getb()) != Bufio->EOF){
					if(c != ' ' && c != '\t' && c != '\n' && c != '\r')
						break;
				}
				if(c == Bufio->EOF){
					fd.close();
					return (nil, "unexpected EOF in PPM data");
				}
				s[0] = c;
				while((c = fd.getb()) != Bufio->EOF && c >= '0' && c <= '9')
					s[len s] = c;
				srcrowdata[x] = byte int s;
			}
		}

		# Only process rows we're keeping (subsample vertically)
		if(srcy % subsample == 0 && dsty < dstheight){
			# Subsample horizontally: copy every Nth pixel
			for(dstx := 0; dstx < dstwidth; dstx++){
				srcx := dstx * subsample;
				# PPM stores RGB; RGB24 needs BGR
				dstrowdata[dstx*3 + 0] = srcrowdata[srcx*3 + 2];
				dstrowdata[dstx*3 + 1] = srcrowdata[srcx*3 + 1];
				dstrowdata[dstx*3 + 2] = srcrowdata[srcx*3 + 0];
			}

			# Write subsampled row to image
			rowr := Rect((0, dsty), (dstwidth, dsty + 1));
			im.writepixels(rowr, dstrowdata);
			dsty++;
		}
	}

	fd.close();
	return (im, nil);
}

# Progressive image decode - sends progress updates during decode
readimagedataprogressive(data: array of byte, hint: string,
                         progress: chan of ref ImgProgress): (ref Image, string)
{
	if(display == nil)
		return (nil, "imgload not initialized");

	if(data == nil || len data < 8)
		return (nil, "image data too small");

	# Create Iobuf from memory
	fd := bufio->aopen(data);
	if(fd == nil)
		return (nil, "can't create buffer from image data");

	# Read magic bytes
	buf := array[8] of byte;
	n := fd.read(buf, 8);
	if(n < 2){
		fd.close();
		return (nil, "image data too small");
	}

	# Reset to beginning
	fd.seek(big 0, Bufio->SEEKSTART);

	# PNG magic: 137 80 78 71 13 10 26 10
	if(n >= 8 && ispng(buf))
		return loadpngprogressive(fd, hint, progress);

	# PPM: fall back to non-progressive (simpler format, usually fast)
	if(buf[0] == byte 'P' && (buf[1] == byte '6' || buf[1] == byte '3'))
		return loadppm(fd, hint);

	fd.close();
	return (nil, "unrecognized image format");
}

# Progressive PNG decoder - sends progress updates during decode
loadpngprogressive(fd: ref Iobuf, path: string, progress: chan of ref ImgProgress): (ref Image, string)
{
	# Check dimensions BEFORE loading
	(width, height, dimerr) := pngdimensions(fd);
	if(dimerr != nil){
		fd.close();
		return (nil, dimerr);
	}

	if(width <= 0 || height <= 0){
		fd.close();
		return (nil, sys->sprint("invalid PNG dimensions: %dx%d", width, height));
	}

	# Calculate subsample factor
	subsample := calcsubsample(width, height);

	# Seek back to beginning for decode
	fd.seek(big 0, Bufio->SEEKSTART);

	# For small images, use standard reader (fast, no progress needed)
	if(subsample == 1){
		if(readpng == nil){
			readpng = load RImagefile RImagefile->READPNGPATH;
			if(readpng == nil){
				fd.close();
				return (nil, "can't load PNG reader");
			}
			readpng->init(bufio);
		}

		(raw, err) := readpng->read(fd);
		fd.close();
		if(raw == nil){
			if(err != nil && len err > 0)
				return (nil, "PNG: " + err);
			return (nil, "PNG decode failed");
		}

		if(imageremap == nil)
			return (nil, "imageremap not available");

		(im, err2) := imageremap->remap(raw, display, 1);
		if(im == nil){
			if(err2 != nil && len err2 > 0)
				return (nil, "PNG remap: " + err2);
			return (nil, "PNG conversion failed");
		}
		return (im, nil);
	}

	# Large image: use subsampling decoder with progress
	return loadpngsubsampleprogressive(fd, width, height, subsample, progress);
}

# Progressive subsampling PNG decoder
loadpngsubsampleprogressive(fd: ref Iobuf, width, height, subsample: int,
                            progress: chan of ref ImgProgress): (ref Image, string)
{
	if(crc == nil || inflate == nil){
		fd.close();
		return (nil, "PNG subsample: missing crc or inflate module");
	}

	# Skip PNG signature (8 bytes)
	sig := array[8] of byte;
	if(fd.read(sig, 8) != 8){
		fd.close();
		return (nil, "can't read PNG signature");
	}

	# Read IHDR chunk
	crcstate := crc->init(0, int 16rffffffff);

	chunklen := png_getint(fd, nil);
	if(chunklen != 13){
		fd.close();
		return (nil, "invalid IHDR size");
	}

	chunktype := array[4] of byte;
	if(fd.read(chunktype, 4) != 4){
		fd.close();
		return (nil, "can't read chunk type");
	}
	crc->crc(crcstate, chunktype, 4);

	if(string chunktype != "IHDR"){
		fd.close();
		return (nil, "expected IHDR chunk");
	}

	# Read IHDR data
	ihdrdata := array[13] of byte;
	if(fd.read(ihdrdata, 13) != 13){
		fd.close();
		return (nil, "can't read IHDR data");
	}
	crc->crc(crcstate, ihdrdata, 13);

	depth := int ihdrdata[8];
	colortype := int ihdrdata[9];
	interlace := int ihdrdata[12];

	# Skip CRC
	fd.read(array[4] of byte, 4);

	# Determine channels and bytes per pixel
	nchans := 1;
	alpha := 0;
	case colortype {
	0 =>  nchans = 1;
	2 =>  nchans = 3;
	3 =>  nchans = 1;
	4 =>  nchans = 1; alpha = 1;
	6 =>  nchans = 3; alpha = 1;
	* =>
		fd.close();
		return (nil, sys->sprint("unsupported color type %d", colortype));
	}

	if(depth != 8){
		fd.close();
		return (nil, sys->sprint("only 8-bit depth supported, got %d", depth));
	}

	srcbpp := nchans + alpha;

	# For interlaced images, stricter subsampling
	if(interlace != 0){
		pixels := (width / subsample) * (height / subsample);
		while(pixels > MAXPIXELS_INTERLACED && subsample < 32){
			subsample++;
			pixels = (width / subsample) * (height / subsample);
		}
	}

	# Setup subsampling state
	png := ref SPng;
	png.width = width;
	png.height = height;
	png.dstwidth = width / subsample;
	png.dstheight = height / subsample;
	if(png.dstwidth < 1) png.dstwidth = 1;
	if(png.dstheight < 1) png.dstheight = 1;
	png.subsample = subsample;
	png.depth = depth;
	png.colortype = colortype;
	png.nchans = nchans;
	png.alpha = alpha;
	png.filterbpp = srcbpp;
	png.interlaced = interlace;
	png.done = 0;
	png.error = nil;
	png.dstrow = 0;
	png.phaserowsprocessed = 0;

	if(interlace != 0){
		png.phase = 1;
		png_initphase(png);
		png.imgbuf = array[png.dstwidth * png.dstheight * 3] of { * => byte 0 };
	} else {
		png.phase = 0;
		png.phaserow = 0;
		png.phaserowstep = 1;
		png.phasecol = 0;
		png.phasecolstep = 1;
		png.phasecols = width;
		png.phaserows = height;
		png.rowsize = width * srcbpp + 1;
		png.imgbuf = nil;
	}

	png.rowbytessofar = 0;
	png.thisrow = array[png.rowsize] of byte;
	png.lastrow = array[png.rowsize] of { * => byte 0 };
	png.srcrow = 0;

	# Allocate output image
	dstbpl := png.dstwidth * 3;
	im := display.newimage(Rect((0,0), (png.dstwidth, png.dstheight)),
		Draw->RGB24, 0, Draw->Black);
	if(im == nil){
		fd.close();
		return (nil, "can't allocate output image");
	}

	# Send initial progress (0 rows, image created)
	if(progress != nil){
		alt {
			progress <-= ref ImgProgress(im, 0, png.dstheight) => ;
			* => ;  # Non-blocking
		}
	}

	dstrowdata := array[dstbpl] of byte;
	palette: array of byte;

	# Track rows for progress updates
	lastprogressrow := 0;
	progressinterval := png.dstheight / 10;  # Update ~10 times during decode
	if(progressinterval < 1) progressinterval = 1;

	# Process chunks
	rq: chan of ref Filter->Rq;
	inflateStarted := 0;
	inflateFinished := 0;
	firstIDAT := 1;

	while(png.error == nil && !png.done){
		chunklen = png_getint(fd, nil);
		if(chunklen < 0){
			png.error = "unexpected EOF";
			break;
		}

		if(fd.read(chunktype, 4) != 4){
			png.error = "can't read chunk type";
			break;
		}

		typename := string chunktype;

		case typename {
		"IEND" =>
			png.done = 1;

		"PLTE" =>
			palette = array[chunklen] of byte;
			if(fd.read(palette, chunklen) != chunklen){
				png.error = "can't read PLTE";
				break;
			}
			fd.read(array[4] of byte, 4);

		"IDAT" =>
			remaining := chunklen;
			if(firstIDAT){
				rq = inflate->start(nil);
				inflateStarted = 1;
				fd.read(array[2] of byte, 2);
				remaining -= 2;
				firstIDAT = 0;
			}

			while(remaining > 0 && png.error == nil && !inflateFinished){
				pick m := <-rq {
				Fill =>
					toread := len m.buf;
					if(toread > remaining)
						toread = remaining;
					got := fd.read(m.buf, toread);
					if(got <= 0){
						m.reply <-= -1;
						png.error = "EOF in IDAT";
						break;
					}
					m.reply <-= got;
					remaining -= got;

				Result =>
					m.reply <-= 0;
					png_processdata(png, im, dstrowdata, palette, m.buf);

					# Send progress if enough rows decoded
					if(progress != nil && png.dstrow - lastprogressrow >= progressinterval){
						lastprogressrow = png.dstrow;
						alt {
							progress <-= ref ImgProgress(im, png.dstrow, png.dstheight) => ;
							* => ;  # Non-blocking
						}
					}

				Finished =>
					inflateFinished = 1;

				Error =>
					png.error = "inflate error";
				}
			}
			fd.read(array[4] of byte, 4);

		* =>
			skipbuf := array[1024] of byte;
			while(chunklen > 0){
				toread := 1024;
				if(toread > chunklen)
					toread = chunklen;
				fd.read(skipbuf, toread);
				chunklen -= toread;
			}
			fd.read(array[4] of byte, 4);
		}
	}

	# Drain inflate — process any remaining Results after all IDAT data fed
	if(inflateStarted && !inflateFinished){
		while(!inflateFinished){
			pick m := <-rq {
			Fill =>
				m.reply <-= -1;
			Result =>
				m.reply <-= 0;
				png_processdata(png, im, dstrowdata, palette, m.buf);
			Finished =>
				inflateFinished = 1;
			Error =>
				inflateFinished = 1;
			}
		}
	}

	fd.close();

	if(png.error != nil)
		return (nil, "PNG: " + png.error);

	# For interlaced images, write the accumulated imgbuf
	if(png.interlaced != 0 && png.imgbuf != nil){
		rowdata := array[png.dstwidth * 3] of byte;
		dstbpl := png.dstwidth * 3;
		for(y := 0; y < png.dstheight; y++){
			rowdata[0:] = png.imgbuf[y*dstbpl:(y+1)*dstbpl];
			rowr := Rect((0, y), (png.dstwidth, y + 1));
			im.writepixels(rowr, rowdata);
		}
	}

	return (im, nil);
}
