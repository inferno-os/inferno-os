implement WImagefile;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Chans, Display, Image, Rect: import draw;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "imagefile.m";

Nhash: con 4001;

Entry: adt
{
	index: int;
	prefix: int;
	exten: int;
	next:	cyclic ref Entry;
};

IO: adt
{
	fd:	ref Iobuf;
	buf:	array of byte;
	i:	int;
	nbits:	int;	 # bits in right side of shift register
	sreg:	int;	# shift register
};

tbl: array of ref Entry;

colormap: array of array of byte;
log2 := array[] of {1 => 0, 2 => 1, 4 => 2, 8 => 3, * => -1};

init(iomod: Bufio)
{
	if(sys == nil){
		sys = load Sys Sys->PATH;
		draw = load Draw Draw->PATH;
	}
	bufio = iomod;
}

writeimage(fd: ref Iobuf, image: ref Image): string
{
	case image.chans.desc {
	(Draw->GREY1).desc or (Draw->GREY2).desc or
	(Draw->GREY4).desc or (Draw->GREY8).desc or
	(Draw->CMAP8).desc =>
		if(image.depth > 8 || (image.depth&(image.depth-1)) != 0)
			return "inconsistent depth";
	* =>
		return "unsupported channel type";
	}

	inittbl();

	writeheader(fd, image);
	writedescriptor(fd, image);

	err := writedata(fd, image);
	if(err != nil)
		return err;

	writetrailer(fd);
	fd.flush();
	return err;
}

inittbl()
{
	tbl = array[4096] of ref Entry;
	for(i:=0; i<len tbl; i++)
		tbl[i] = ref Entry(i, -1, i, nil);
}

# Write header, logical screen descriptor, and color map
writeheader(fd: ref Iobuf, image: ref Image): string
{
	# Header
	fd.puts("GIF89a");

	# Logical Screen Descriptor
	put2(fd, image.r.dx());
	put2(fd, image.r.dy());
	# color table present, 4 bits per color (for RGBV best case), size of color map
	fd.putb(byte ((1<<7)|(3<<4)|(image.depth-1)));
	fd.putb(byte 0);	# white background (doesn't matter anyway)
	fd.putb(byte 0);	# pixel aspect ratio - unused

	# Global Color Table
	getcolormap(image);
	ldepth := log2[image.depth];
	if(image.chans.eq(Draw->GREY8))
		ldepth = 4;
	fd.write(colormap[ldepth], len colormap[ldepth]);
	return nil;
}

# Write image descriptor
writedescriptor(fd: ref Iobuf, image: ref Image)
{
	# Image Separator
	fd.putb(byte 16r2C);

	# Left, top, width, height
	put2(fd, 0);
	put2(fd, 0);
	put2(fd, image.r.dx());
	put2(fd, image.r.dy());
	# no special processing
	fd.putb(byte 0);
}

# Write data
writedata(fd: ref Iobuf, image: ref Image): string
{
	# LZW Minimum code size
	if(image.depth == 1)
		fd.putb(byte 2);

	else
		fd.putb(byte image.depth);

	# Encode and emit the data
	err := encode(fd, image);
	if(err != nil)
		return err;

	# Block Terminator
	fd.putb(byte 0);
	return nil;
}

# Write data
writetrailer(fd: ref Iobuf)
{
	fd.putb(byte 16r3B);
}

# Write little-endian 16-bit integer
put2(fd: ref Iobuf, i: int)
{
	fd.putb(byte i);
	fd.putb(byte (i>>8));
}

# Get color map for all ldepths, in format suitable for writing out
getcolormap(image: ref Draw->Image)
{
	if(colormap != nil)
		return;
	colormap = array[5] of array of byte;
	display := image.display;
	colormap[4] = array[3*256] of byte;
	colormap[3] = array[3*256] of byte;
	colormap[2] = array[3*16] of byte;
	colormap[1] = array[3*4] of byte;
	colormap[0] = array[3*2] of byte;
	c := colormap[4];
	for(i:=0; i<256; i++){
		c[3*i+0] = byte i;
		c[3*i+1] = byte i;
		c[3*i+2] = byte i;
	}
	c = colormap[3];
	for(i=0; i<256; i++){
		(r, g, b) := display.cmap2rgb(i);
		c[3*i+0] = byte r;
		c[3*i+1] = byte g;
		c[3*i+2] = byte b;
	}
	c = colormap[2];
	for(i=0; i<16; i++){
		col := (i<<4)|i;
		(r, g, b) := display.cmap2rgb(col);
		c[3*i+0] = byte r;
		c[3*i+1] = byte g;
		c[3*i+2] = byte b;
	}
	c = colormap[1];
	for(i=0; i<4; i++){
		col := (i<<6)|(i<<4)|(i<<2)|i;
		(r, g, b) := display.cmap2rgb(col);
		c[3*i+0] = byte r;
		c[3*i+1] = byte g;
		c[3*i+2] = byte b;
	}
	c = colormap[0];
	for(i=0; i<2; i++){
		if(i == 0)
			col := 0;
		else
			col = 16rFF;
		(r, g, b) := display.cmap2rgb(col);
		c[3*i+0] = byte r;
		c[3*i+1] = byte g;
		c[3*i+2] = byte b;
	}
}

# Put n bits of c into output at io.buf[i];
output(io: ref IO, c, n: int)
{
	if(c < 0){
		if(io.nbits != 0)
			io.buf[io.i++] = byte io.sreg;
		io.fd.putb(byte io.i);
		io.fd.write(io.buf, io.i);
		io.nbits = 0;
		return;
	}

	if(io.nbits+n >= 31){
		sys->print("panic: WriteGIF sr overflow\n");
		exit;
	}
	io.sreg |= c<<io.nbits;
	io.nbits += n;

	while(io.nbits >= 8){
		io.buf[io.i++] = byte io.sreg;
		io.sreg >>= 8;
		io.nbits -= 8;
	}

	if(io.i >= 255){
		io.fd.putb(byte 255);
		io.fd.write(io.buf, 255);
		io.buf[0:] = io.buf[255:io.i];
		io.i -= 255;
	}
}

# LZW encoder
encode(fd: ref Iobuf, image: ref Image): string
{
	c, h, csize, prefix: int;
	e, oe: ref Entry;

	first := 1;
	ld := log2[image.depth];
	# ldepth 0 must generate codesize 2 with values 0 and 1 (see the spec.)
	ld0 := ld;
	if(ld0 == 0)
		ld0 = 1;
	codesize := (1<<ld0);
	CTM := 1<<codesize;
	EOD := CTM+1;

	io := ref IO (fd, array[300] of byte, 0, 0, 0);
	sreg := 0;
	nbits := 0;
	bitsperpixel := 1<<ld;
	pm := (1<<bitsperpixel)-1;

	# Read image data into memory
	# potentially one extra byte on each end of each scan line
	data := array[image.r.dy()*(2+(image.r.dx()>>(3-log2[image.depth])))] of byte;
	ndata := image.readpixels(image.r, data);
	if(ndata < 0)
		return sys->sprint("WriteGIF: readpixels: %r");
	datai := 0;
	x := image.r.min.x;

Init:
	for(;;){
		csize = codesize+1;
		nentry := EOD+1;
		maxentry := (1<<csize);
		hash := array[Nhash] of ref Entry;
		for(i := 0; i<nentry; i++){
			e = tbl[i];
			h = (e.prefix<<24) | (e.exten<<8);
			h %= Nhash;
			if(h < 0)
				h += Nhash;
			e.next = hash[h];
			hash[h] = e;
		}
		prefix = -1;
		if(first)
			output(io, CTM, csize);
		first = 0;

		# Scan over pixels.  Because of partially filled bytes on ends of scan lines,
		# which must be ignored in the data stream passed to GIF, this is more
		# complex than we'd like
	Next:
		for(;;){
			if(ld != 3){
				# beginning of scan line is difficult; prime the shift register
				if(x == image.r.min.x){
					if(datai == ndata)
						break;
					sreg = int data[datai++];
					nbits = 8-((x&(7>>ld))<<ld);
				}
				x++;
				if(x == image.r.max.x)
					x = image.r.min.x;
			}
			if(nbits == 0){
				if(datai == ndata)
					break;
				sreg = int data[datai++];
				nbits = 8;
			}
			nbits -= bitsperpixel;
			c = sreg>>nbits & pm;
			h = prefix<<24 | c<<8;
			h %= Nhash;
			if(h < 0)
				h += Nhash;
			oe = nil;
			for(e = hash[h]; e!=nil; e=e.next){
				if(e.prefix == prefix && e.exten == c){
					if(oe != nil){
						oe.next = e.next;
						e.next = hash[h];
						hash[h] = e;
					}
					prefix = e.index;
					continue Next;
				}
				oe = e;
			}

			output(io, prefix, csize);
			early:=0; # peculiar tiff feature here for reference
			if(nentry == maxentry-early){
				if(csize == 12){
					nbits += codesize;	# unget pixel
					x--;
					output(io, CTM, csize);
					continue Init;
				}
				csize++;
				maxentry = (1<<csize);
			}

			e = tbl[nentry];
			e.prefix = prefix;
			e.exten = c;
			e.next = hash[h];
			hash[h] = e;

			prefix = c;
			nentry++;
		}
		break Init;
	}
	output(io, prefix, csize);
	output(io, EOD, csize);
	output(io, -1, csize);
	return nil;
}
