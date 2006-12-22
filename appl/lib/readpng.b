implement RImagefile;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Point: import Draw;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "imagefile.m";

include "crc.m";
	crc: Crc;
	CRCstate: import Crc;

include "filter.m";
	inflate: Filter;

Chunk: adt {
	size : int;
	typ: string;
	crc_state: ref CRCstate;
};

Png: adt {
	depth: int;
	filterbpp: int;
	colortype: int;
	compressionmethod: int;
	filtermethod: int;
	interlacemethod: int;
	# tRNS
	PLTEsize: int;
	tRNS: array of byte;
	# state for managing unpacking
	alpha: int;
	done: int;
	error: string;
	row, rowstep, colstart, colstep: int;
	phase: int;
	phasecols: int;
	phaserows: int;
	rowsize: int;
	rowbytessofar: int;
	thisrow: array of byte;
	lastrow: array of byte;
};

init(iomod: Bufio)
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(crc == nil)
		crc =  load Crc Crc->PATH;
	if(inflate == nil)
		inflate = load Filter "/dis/lib/inflate.dis";
	inflate->init();
	bufio = iomod;
}

readmulti(fd: ref Iobuf): (array of ref Rawimage, string)
{
	(i, err) := read(fd);
	if(i != nil){
		a := array[1] of { i };
		return (a, err);
	}
	return (nil, err);
}

read(fd: ref Iobuf): (ref Rawimage, string)
{
	chunk := ref Chunk;
	png := ref Png;
	raw := ref Rawimage;

	chunk.crc_state = crc->init(0, int 16rffffffff);
# Check it's a PNG
	if (!get_signature(fd))
		return (nil, "not a PNG");
# Get the IHDR
	if (!get_chunk_header(fd, chunk))
		return (nil, "duff header");
	if (chunk.typ != "IHDR")
		return (nil, "IHDR must come first");
	if (chunk.size != 13)
		return (nil, "IHDR wrong size");
	raw.r.max.x = get_int(fd, chunk.crc_state);
	if (raw.r.max.x <= 0)
		return (nil, "invalid width");
	raw.r.max.y = get_int(fd, chunk.crc_state);
	if (raw.r.max.y <= 0)
		return (nil, "invalid height");
	png.depth = get_byte(fd, chunk.crc_state);
	case png.depth {
	1 or 2 or 4 or 8 or 16 =>
		;
	* =>
		return (nil, "invalid depth");
	}
	png.colortype = get_byte(fd, chunk.crc_state);

	okcombo : int;

	case png.colortype {
	0 =>
		okcombo = 1;
		raw.nchans = 1;
		raw.chandesc = RImagefile->CY;
		png.alpha = 0;
	2  =>
		okcombo = (png.depth == 8 || png.depth == 16);
		raw.nchans = 3;
		raw.chandesc = RImagefile->CRGB;
		png.alpha = 0;
	3 =>
		okcombo = (png.depth != 16);
		raw.nchans = 1;
		raw.chandesc = RImagefile->CRGB1;
		png.alpha = 0;
	4 =>
		okcombo = (png.depth == 8 || png.depth == 16);
		raw.nchans = 1;
		raw.chandesc = RImagefile->CY;
		png.alpha = 1;
	6 =>
		okcombo = (png.depth == 8 || png.depth == 16);
		raw.nchans = 3;
		raw.chandesc = RImagefile->CRGB;
		png.alpha = 1;
	* =>
		return (nil, "invalid colortype");
	}
	if (!okcombo)
		return (nil, "invalid depth/colortype combination");
	png.compressionmethod = get_byte(fd, chunk.crc_state);
	if (png.compressionmethod != 0)
		return (nil, "invalid compression method " + string png.compressionmethod);
	png.filtermethod = get_byte(fd, chunk.crc_state);
	if (png.filtermethod != 0)
		return (nil, "invalid filter method");
	png.interlacemethod = get_byte(fd, chunk.crc_state);
	if (png.interlacemethod != 0 && png.interlacemethod != 1)
		return (nil, "invalid interlace method");
	if(0)
		sys->print("width %d height %d depth %d colortype %d interlace %d\n",
			raw.r.max.x, raw.r.max.y, png.depth, png.colortype, png.interlacemethod);
	if (!get_crc_and_check(fd, chunk))
		return (nil, "invalid CRC");
# Stash some detail in raw
	raw.r.min = Point(0, 0);
	raw.transp = 0;
	raw.chans = array[raw.nchans] of array of byte;
	{
		for (r:= 0; r < raw.nchans; r++)
			raw.chans[r] = array[raw.r.max.x * raw.r.max.y] of byte;
	}
# Get the next chunk
	seenPLTE := 0;
	seenIDAT := 0;
	seenLastIDAT := 0;
	inflateFinished := 0;
	seenIEND := 0;
	seentRNS := 0;
	rq: chan of ref Filter->Rq;

	png.error = nil;
	rq = nil;
	while (png.error == nil) {
		if (!get_chunk_header(fd, chunk)) {
			if (!seenIEND)
				png.error = "duff header";
			break;
		}
		if (seenIEND) {
			png.error = "rubbish at eof";
			break;
		}
		case (chunk.typ) {
		"IEND" =>
			seenIEND = 1;
		"PLTE" =>
			if (seenPLTE) {
				png.error = "too many PLTEs";
				break;
			}
			if (seentRNS) {
				png.error = "tRNS before PLTE";
				break;
			}
			if (seenIDAT) {
				png.error = "PLTE too late";
				break;
			}
			if (chunk.size % 3 || chunk.size < 1 * 3 || chunk.size > 256 * 3) {
				png.error = "PLTE strange size";
				break;
			}
			if (png.colortype == 0 || png.colortype == 4) {
				png.error = "superfluous PLTE";
				break;
			}
			raw.cmap = array[256 * 3] of byte;
			png.PLTEsize = chunk.size / 3;
			if (!get_bytes(fd, chunk.crc_state, raw.cmap, chunk.size)) {
				png.error = "eof in PLTE";
				break;
			}
#			{
#				x: int;
#				sys->print("Palette:\n");
#				for (x = 0; x < chunk.size; x += 3)
#					sys->print("%3d: (%3d, %3d, %3d)\n",
#						x / 3, int raw.cmap[x], int raw.cmap[x + 1], int raw.cmap[x + 2]);
#			}
			seenPLTE = 1;
		"tRNS" =>
			if (seenIDAT) {
				png.error = "tRNS too late";
				break;
			}
			case png.colortype {
			0 =>
				if (chunk.size != 2) {
					png.error = "tRNS wrong size";
					break;
				}
				level := get_ushort(fd, chunk.crc_state);
				if (level < 0) {
					png.error = "eof in tRNS";
					break;
				}
				if (png.depth != 16) {
					raw.transp = 1;
					raw.trindex = byte level;
				}
			2 =>
				# a legitimate coding, but we can't use the information
				if (!skip_bytes(fd, chunk.crc_state, chunk.size))
					png.error = "eof in skipped tRNS chunk";
				break;
			3 =>
				if (!seenPLTE) {
					png.error = "tRNS too early";
					break;
				}
				if (chunk.size > png.PLTEsize) {
					png.error = "tRNS too big";
					break;
				}
				png.tRNS = array[png.PLTEsize] of byte;
				for (x := chunk.size; x < png.PLTEsize; x++)
					png.tRNS[x] = byte 255;
				if (!get_bytes(fd, chunk.crc_state, png.tRNS, chunk.size)) {
					png.error = "eof in tRNS";
					break;
				}
#				{
#					sys->print("tRNS:\n");
#					for (x = 0; x < chunk.size; x++)
#						sys->print("%3d: (%3d)\n", x, int png.tRNS[x]);
#				}
				if (png.error == nil) {
					# analyse the tRNS chunk to see if it contains a single transparent index
					# translucent entries are treated as opaque
					for (x = 0; x < chunk.size; x++)
						if (png.tRNS[x] == byte 0) {
							raw.trindex = byte x;
							if (raw.transp) {
								raw.transp = 0;
								break;
							}
							raw.transp = 1;
						}
#					if (raw.transp)
#						sys->print("selected index %d\n", int raw.trindex);
				}
			4 or 6 =>
				png.error = "tRNS invalid when alpha present";
			}
			seentRNS = 1;
		"IDAT" =>
			if (seenLastIDAT) {
				png.error = "non contiguous IDATs";
				break;
			}
			if (inflateFinished) {
				png.error = "too many IDATs";
				break;
			}
			remaining := 0;
			if (!seenIDAT) {
				# open channel to inflate filter
				if (!processdatainit(png, raw))
					break;
				rq = inflate->start(nil);
				skip_bytes(fd, chunk.crc_state, 2);
				remaining = chunk.size - 2;
			}
			else
				remaining = chunk.size;
			while (remaining && png.error == nil) {
				pick m := <- rq {
				Fill =>
#					sys->print("Fill(%d) remaining %d\n", len m.buf, remaining);
					toget := len m.buf;
					if (toget > remaining)
						toget = remaining;
					if (!get_bytes(fd, chunk.crc_state, m.buf, toget)) {
						m.reply <-= -1;
						png.error = "eof during IDAT";
						break;
					}
					m.reply <-= toget;
					remaining -= toget;
				Result =>
#					sys->print("Result(%d)\n", len m.buf);
					m.reply <-= 0;
					processdata(png, raw, m.buf);
				Info =>
#					sys->print("Info(%s)\n", m.msg);
				Finished =>
					inflateFinished = 1;
#					sys->print("Finished\n");
				Error =>
					return (nil, "inflate error\n");
				}
			}
			seenIDAT = 1;
		* =>
			# skip the blighter
			if (!skip_bytes(fd, chunk.crc_state, chunk.size))
				png.error = "eof in skipped chunk";
		}
		if (png.error != nil)
			break;
		if (!get_crc_and_check(fd, chunk))
			return (nil, "invalid CRC");
		if (chunk.typ != "IDAT" && seenIDAT)
			seenLastIDAT = 1;
	}
	# can only get here if IEND was last chunk, or png.error set
	
	if (png.error == nil && !seenIDAT) {
		png.error = "no IDAT!";
		inflateFinished = 1;
	}
	while (rq != nil && !inflateFinished) {
		pick m := <-rq {
		Fill =>
#			sys->print("Fill(%d)\n", len m.buf);
			png.error = "eof in zlib stream";
			m.reply <-= -1;
			inflateFinished = 1;
		Result =>
#			sys->print("Result(%d)\n", len m.buf);
			if (png.error != nil) {
				m.reply <-= -1;
				inflateFinished = 1;
			}
			else {
				m.reply <-= 0;
				processdata(png, raw, m.buf);
			}
		Info =>
#			sys->print("Info(%s)\n", m.msg);
		Finished =>
#			sys->print("Finished\n");
			inflateFinished = 1;
			break;
		Error =>
			png.error = "inflate error\n";
			inflateFinished = 1;
		}
		
	}
	if (png.error == nil && !png.done)
		png.error = "insufficient data";
	return (raw, png.error);
}

phase2stepping(phase: int): (int, int, int, int)
{
	case phase {
	0 =>
		return (0, 1, 0, 1);
	1 =>
		return (0, 8, 0, 8);
	2 =>
		return (0, 8, 4, 8);
	3 =>
		return (4, 8, 0, 4);
	4 =>
		return (0, 4, 2, 4);
	5 =>
		return (2, 4, 0, 2);
	6 =>
		return (0, 2, 1, 2);
	7 =>
		return (1, 2, 0, 1);
	* =>
		return (-1, -1, -1, -1);
	}
}

processdatainitphase(png: ref Png, raw: ref Rawimage)
{
	(png.row, png.rowstep, png.colstart, png.colstep) = phase2stepping(png.phase);
	if (raw.r.max.x > png.colstart)
		png.phasecols = (raw.r.max.x - png.colstart + png.colstep - 1) / png.colstep;
	else
		png.phasecols = 0;
	if (raw.r.max.y > png.row)
		png.phaserows = (raw.r.max.y - png.row + png.rowstep - 1) / png.rowstep;
	else
		png.phaserows = 0;
	png.rowsize = png.phasecols * (raw.nchans + png.alpha) * png.depth;
	png.rowsize = (png.rowsize + 7) / 8;
	png.rowsize++;		# for the filter byte
	png.rowbytessofar = 0;
	png.thisrow = array[png.rowsize] of byte;
	png.lastrow = array[png.rowsize] of byte;
#	sys->print("init phase %d: r (%d, %d, %d) c (%d, %d, %d) (%d)\n",
#		png.phase, png.row, png.rowstep, png.phaserows,
#		png.colstart, png.colstep, png.phasecols, png.rowsize);
}

processdatainit(png: ref Png, raw: ref Rawimage): int
{
	if (raw.nchans != 1&& raw.nchans != 3) {
		png.error = "only 1 or 3 channels supported";
		return 0;
	}
#	if (png.interlacemethod != 0) {
#		png.error = "only progressive supported";
#		return 0;
#	}
	if (png.colortype == 3 && raw.cmap == nil) {
		png.error = "PLTE chunk missing";
		return 0;
	}
	png.done = 0;
	png.filterbpp = (png.depth * (raw.nchans + png.alpha) + 7) / 8;
	png.phase = png.interlacemethod;

	processdatainitphase(png, raw);

	return 1;
}

upconvert(out: array of byte, outstride: int, in: array of byte, pixels: int, bpp: int)
{
	b: byte;
	bits := pixels * bpp;
	lim := bits / 8;
	mask := byte ((1 << bpp) - 1);
	outx := 0;
	inx := 0;
	for (x := 0; x < lim; x++) {
		b = in[inx];
		for (s := 8 - bpp; s >= 0; s -= bpp) {
			pixel := (b >> s) & mask;
			ucp := pixel;
			for (y := bpp; y < 8; y += bpp)
				ucp |= pixel << y;
			out[outx] = ucp; 
			outx += outstride;
		}
		inx++;
	}
	residue := (bits % 8) / bpp;
	if (residue) {
		b = in[inx];
		for (s := 8 - bpp; s >= 0; s -= bpp) {
			pixel := (b >> s) & mask;
			ucp := pixel;
			for (y := bpp; y < 8; y += bpp)
				ucp |= pixel << y;
			out[outx] = ucp; 
			outx += outstride;
			if (--residue <= 0)
				break;
		}
	}
}

# expand (1 or 2 or 4) bit to 8 bit without scaling (for palletized stuff)

expand(out: array of byte, outstride: int, in: array of byte, pixels: int, bpp: int)
{
	b: byte;
	bits := pixels * bpp;
	lim := bits / 8;
	mask := byte ((1 << bpp) - 1);
	outx := 0;
	inx := 0;
	for (x := 0; x < lim; x++) {
		b = in[inx];
		for (s := 8 - bpp; s >= 0; s -= bpp) {
			out[outx] = (b >> s) & mask;
			outx += outstride;
		}
		inx++;
	}
	residue := (bits % 8) / bpp;
	if (residue) {
		b = in[inx];
		for (s := 8 - bpp; s >= 0; s -= bpp) {
			out[outx] = (b >> s) & mask;
			outx += outstride;
			if (--residue <= 0)
				break;
		}
	}
}

copybytes(out: array of byte, outstride: int, in: array of byte, instride: int, pixels: int)
{
	inx := 0;
	outx := 0;
	for (x := 0; x < pixels; x++) {
		out[outx] = in[inx];
		inx += instride;
		outx += outstride;
	}
}

outputrow(png: ref Png, raw: ref Rawimage, row: array of byte)
{
	offset := png.row * raw.r.max.x;
	case raw.nchans {
	1 =>
		case (png.depth) {
		* =>
			png.error = "depth not supported";
			return;
		1 or 2 or 4 =>
			if (raw.chandesc == RImagefile->CRGB1)
				expand(raw.chans[0][offset + png.colstart:], png.colstep, row, png.phasecols, png.depth);
			else
				upconvert(raw.chans[0][offset + png.colstart:], png.colstep, row, png.phasecols, png.depth);
		8 or 16 =>
			# might have an Alpha channel to ignore!
			stride := (png.alpha + 1) * png.depth / 8;
			copybytes(raw.chans[0][offset + png.colstart:], png.colstep, row, stride, png.phasecols);
		}
	3 =>
		case (png.depth) {
		* =>
			png.error = "depth not supported (2)";
			return;
		8 or 16 =>
			# split rgb into three channels
			bytespc := png.depth / 8;
			stride := (3  + png.alpha) * bytespc;
			copybytes(raw.chans[0][offset + png.colstart:], png.colstep, row, stride, png.phasecols);
			copybytes(raw.chans[1][offset + png.colstart:], png.colstep, row[bytespc:], stride, png.phasecols);
			copybytes(raw.chans[2][offset + png.colstart:], png.colstep, row[bytespc * 2:], stride, png.phasecols);
		}
	}
}

filtersub(png: ref Png)
{
	subx := 1;
	for (x := int png.filterbpp + 1; x < png.rowsize; x++) {
		png.thisrow[x] += png.thisrow[subx];
		subx++;
	}
}

filterup(png: ref Png)
{
	if (png.row == 0)
		return;
	for (x := 1; x < png.rowsize; x++)
		png.thisrow[x] += png.lastrow[x];
}

filteraverage(png: ref Png)
{
	for (x := 1; x < png.rowsize; x++) {
		a: int;
		if (x > png.filterbpp)
			a = int png.thisrow[x - png.filterbpp];
		else
			a = 0;
		if (png.row != 0)
			a += int png.lastrow[x];
		png.thisrow[x] += byte (a / 2);
	}
}

filterpaeth(png: ref Png)
{
	a, b, c: byte;
	p, pa, pb, pc: int;
	for (x := 1; x < png.rowsize; x++) {
		if (x > png.filterbpp)
			a = png.thisrow[x - png.filterbpp];
		else
			a = byte 0;
		if (png.row == 0) {
			b = byte 0;
			c = byte 0;
		} else {
			b = png.lastrow[x];
			if (x > png.filterbpp)
				c = png.lastrow[x - png.filterbpp];
			else
				c = byte 0;
		}
		p = int a + int b - int c;
		pa = p - int a;
		if (pa < 0)
			pa = -pa;
		pb  = p - int b;
		if (pb < 0)
			pb = -pb;
		pc = p - int c;
		if (pc < 0)
			pc = -pc;
		if (pa <= pb && pa <= pc)
			png.thisrow[x] += a;
		else if (pb <= pc)
			png.thisrow[x] += b;
		else
			png.thisrow[x] += c;
	}		
}

phaseendcheck(png: ref Png, raw: ref Rawimage): int
{
	if (png.row >= raw.r.max.y || png.rowsize <= 1) {
		# this phase is over
		if (png.phase == 0) {
			png.done = 1;
		}
		else {
			png.phase++;
			if (png.phase > 7)
				png.done = 1;
			else
				processdatainitphase(png, raw);
		}
		return 1;
	}
	return 0;
}

processdata(png: ref Png, raw: ref Rawimage, buf: array of byte)
{
#sys->print("processdata(%d)\n", len buf);
	if (png.error != nil)
		return;
	i := 0;
	while (i < len buf) {
		if (png.done) {
			png.error = "too much data";
			return;
		}
		if (phaseendcheck(png, raw))
			continue;
		tocopy := (png.rowsize - png.rowbytessofar);
		if (tocopy > (len buf - i))
			tocopy = len buf - i;
		png.thisrow[png.rowbytessofar :] = buf[i : i + tocopy];
		i += tocopy;
		png.rowbytessofar += tocopy;
		if (png.rowbytessofar >= png.rowsize) {
			# a new row has arrived
			# apply filter here
#sys->print("phase %d row %d\n", png.phase, png.row);
			case int png.thisrow[0] {
			0 =>
				;
			1 =>
				filtersub(png);
			2 =>
				filterup(png);
			3 =>
				filteraverage(png);
			4 =>
				filterpaeth(png);
			* =>
#				sys->print("implement filter method %d\n", int png.thisrow[0]);
				png.error = "filter method unsupported";
				return;
			}
			# output row
			if (png.row >= raw.r.max.y) {
				png.error = "too much data";
				return;
			}
			outputrow(png, raw, png.thisrow[1 :]);
			png.row += png.rowstep;
			save := png.lastrow;
			png.lastrow = png.thisrow;
			png.thisrow = save;
			png.rowbytessofar = 0;
		}
	}
	phaseendcheck(png, raw);
}

get_signature(fd: ref Iobuf): int
{
	sig := array[8] of { byte 137, byte 80, byte 78, byte 71, byte 13, byte 10, byte 26, byte 10 };
	x: int;
	for (x = 0; x < 8; x++)
		if (fd.getb() != int sig[x])
			return 0;
	return 1;
}

get_bytes(fd: ref Iobuf, crc_state: ref CRCstate, buf: array of byte, n: int): int
{
	if (buf == nil) {
		fd.seek(big n, bufio->SEEKRELA);
		return 1;
	}
	if (fd.read(buf, n) != n)
		return 0;
	if (crc_state != nil)
		crc->crc(crc_state, buf, n);
	return 1;
}

skip_bytes(fd: ref Iobuf, crc_state: ref CRCstate, n: int): int
{
	buf := array[1024] of byte;
	while (n) {
		thistime: int = 1024;
		if (thistime > n)
			thistime = n;
		if (!get_bytes(fd, crc_state, buf, thistime))
			return 0;
		n -= thistime;
	}
	return 1;
}

get_4(fd: ref Iobuf, crc_state: ref CRCstate, signed: int): (int, int)
{
	buf := array[4] of byte;
	if (!get_bytes(fd, crc_state, buf, 4))
		return (0, 0);
	if (signed && int buf[0] & 16r80)
		return (0, 0);
	r:int  = (int buf[0] << 24) | (int buf[1] << 16) | (int buf[2] << 8) | (int buf[3]);
#	sys->print("got int %d\n", r);
	return (1, r);
}

get_int(fd: ref Iobuf, crc_state: ref CRCstate): int
{
	ok, r: int;
	(ok, r) = get_4(fd, crc_state, 1);
	if (ok)
		return r;
	return -1;
}

get_ushort(fd: ref Iobuf, crc_state: ref CRCstate): int
{
	buf := array[2] of byte;
	if (!get_bytes(fd, crc_state, buf, 2))
		return -1;
	return (int buf[0] << 8) | int buf[1];
}

get_crc_and_check(fd: ref Iobuf, chunk: ref Chunk): int
{
	crc, ok: int;
	(ok, crc) = get_4(fd, nil, 0);
	if (!ok)
		return 0;
#	sys->print("crc: computed %.8ux expected %.8ux\n", chunk.crc_state.crc, crc);
	if (chunk.crc_state.crc != crc)
		return 1;
	return 1;
}

get_byte(fd: ref Iobuf, crc_state: ref CRCstate): int
{
	buf := array[1] of byte;
	if (!get_bytes(fd, crc_state, buf, 1))
		return -1;
#	sys->print("got byte %d\n", int buf[0]);
	return int buf[0];
}

get_type(fd: ref Iobuf, crc_state: ref CRCstate): string
{
	x: int;
	buf := array[4] of byte;
	if (!get_bytes(fd, crc_state, buf, 4))
		return nil;
	for (x = 0; x < 4; x++) {
		c: int;
		c = int buf[x];
		if (c == bufio->EOF || (c < 65 || c > 90 && c < 97) || c > 122)
			return nil;
	}
	return string buf;
}

get_chunk_header(fd: ref Iobuf, chunk: ref Chunk): int
{
	chunk.size = get_int(fd, nil);
	if (chunk.size < 0)
		return 0;
	crc->reset(chunk.crc_state);
	chunk.typ = get_type(fd, chunk.crc_state);
	if (chunk.typ == nil)
		return 0;
#	sys->print("%s(%d)\n", chunk.typ, chunk.size);
	return 1;
}
