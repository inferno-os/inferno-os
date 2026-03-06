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
	readjpg: RImagefile;

include "filter.m";
	inflate: Filter;

include "crc.m";
	crc: Crc;
	CRCstate: import Crc;

include "imgload.m";

include "pngload.m";
	pngload: Pngload;

display: ref Display;

# Maximum image size for subsampling (shared with pngload)
MAXPIXELS: con 16 * 1024 * 1024;

init(d: ref Display)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	bufio = load Bufio Bufio->PATH;
	imageremap = load Imageremap Imageremap->PATH;
	if(imageremap != nil)
		imageremap->init(d);
	pngload = load Pngload Pngload->PATH;
	if(pngload != nil)
		pngload->init(d);
	display = d;
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

	return dispatch(fd, path);
}

# Load image from raw bytes
readimagedata(data: array of byte, hint: string): (ref Image, string)
{
	if(display == nil)
		return (nil, "imgload not initialized");

	if(data == nil || len data < 8)
		return (nil, "image data too small");

	fd := bufio->aopen(data);
	if(fd == nil)
		return (nil, "can't create buffer from image data");

	return dispatch(fd, hint);
}

# Progressive image decode - sends progress updates during decode
readimagedataprogressive(data: array of byte, hint: string,
                         progress: chan of ref ImgProgress): (ref Image, string)
{
	if(display == nil)
		return (nil, "imgload not initialized");

	if(data == nil || len data < 8)
		return (nil, "image data too small");

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
	if(n >= 8 && ispng(buf)){
		if(pngload == nil){
			fd.close();
			return (nil, "PNG loader not available");
		}
		return pngload->loadpngprogressive(fd, hint, progress);
	}

	# JPEG magic: FF D8 FF
	if(n >= 3 && isjpeg(buf))
		return loadjpeg(fd, hint);

	# PPM: fall back to non-progressive (simpler format, usually fast)
	if(buf[0] == byte 'P' && (buf[1] == byte '6' || buf[1] == byte '3'))
		return loadppm(fd, hint);

	# JPEG magic: FF D8 FF
	if(n >= 3 && int buf[0] == 16rFF && int buf[1] == 16rD8 && int buf[2] == 16rFF)
		return loadjpeg(fd, hint);

	fd.close();
	return (nil, "unrecognized image format");
}

# Format detection and dispatch
dispatch(fd: ref Iobuf, path: string): (ref Image, string)
{
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
	if(n >= 8 && ispng(buf)){
		if(pngload == nil){
			fd.close();
			return (nil, "PNG loader not available");
		}
		return pngload->loadpng(fd, path);
	}

	# JPEG magic: FF D8 FF
	if(n >= 3 && isjpeg(buf))
		return loadjpeg(fd, path);

	# PPM P6 magic: "P6"
	if(buf[0] == byte 'P' && buf[1] == byte '6')
		return loadppm(fd, path);

	# PPM P3 (ASCII) magic: "P3"
	if(buf[0] == byte 'P' && buf[1] == byte '3')
		return loadppm(fd, path);

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

# JPEG magic: FF D8 FF (SOI marker + start of next marker)
isjpeg(buf: array of byte): int
{
	return buf[0] == byte 16rFF && buf[1] == byte 16rD8 && buf[2] == byte 16rFF;
}

# Load JPEG using the system readjpg module
loadjpeg(fd: ref Iobuf, path: string): (ref Image, string)
{
	if(readjpg == nil){
		readjpg = load RImagefile RImagefile->READJPGPATH;
		if(readjpg == nil){
			fd.close();
			return (nil, "can't load JPEG reader");
		}
		readjpg->init(bufio);
	}

	(raw, err) := readjpg->read(fd);
	fd.close();
	if(raw == nil){
		if(err != nil && len err > 0)
			return (nil, "JPEG: " + err);
		return (nil, "JPEG decode failed");
	}

	if(imageremap == nil)
		return (nil, "imageremap not available");

	(im, err2) := imageremap->remap(raw, display, 1);
	if(im == nil){
		if(err2 != nil && len err2 > 0)
			return (nil, "JPEG remap: " + err2);
		return (nil, "JPEG conversion failed");
	}
	return (im, nil);
}

# Calculate subsample factor to fit image within limits
calcsubsample(width, height: int): int
{
	pixels := width * height;
	if(pixels <= MAXPIXELS)
		return 1;

	for(factor := 2; factor <= 16; factor++){
		newpixels := (width / factor) * (height / factor);
		if(newpixels <= MAXPIXELS)
			return factor;
	}
	return 16;
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

# Load a JPEG image using Inferno's readjpg module.
loadjpeg(fd: ref Iobuf, path: string): (ref Image, string)
{
	if(readjpg == nil) {
		readjpg = load RImagefile RImagefile->READJPGPATH;
		if(readjpg == nil)
			return (nil, "can't load JPEG reader");
		readjpg->init(bufio);
	}
	fd.seek(big 0, Bufio->SEEKSTART);
	(raw, err) := readjpg->read(fd);
	fd.close();
	if(raw == nil)
		return (nil, "JPEG read failed: " + err);
	if(imageremap == nil)
		return (nil, "imageremap not available");
	(im, err2) := imageremap->remap(raw, display, 1);
	return (im, err2);
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

	# JPEG: fall back to non-progressive (readjpg doesn't have progressive interface)
	if(n >= 3 && int buf[0] == 16rFF && int buf[1] == 16rD8 && int buf[2] == 16rFF)
		return loadjpeg(fd, hint);

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
