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
	readjpg: RImagefile;

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
