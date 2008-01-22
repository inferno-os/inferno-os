implement RImagefile;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "imagefile.m";

Header: adt
{
	fd: ref Iobuf;
	buf: array of byte;
	vers: string;
	screenw: int;
	screenh: int;
	fields: int;
	bgrnd: int;
	aspect: int;
	transp: int;
	trindex: byte;
};

Entry: adt
{
	prefix: int;
	exten: int;
};

tbl: array of Entry;

init(iomod: Bufio)
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	bufio = iomod;
}
read(fd: ref Iobuf): (ref Rawimage, string)
{
	(a, err) := readarray(fd, 0);
	if(a != nil)
		return (a[0], err);
	return (nil, err);
}

readmulti(fd: ref Iobuf): (array of ref Rawimage, string)
{
	return readarray(fd, 1);
}

readarray(fd: ref Iobuf, multi: int): (array of ref Rawimage, string)
{
	inittbl();

	buf := array[3*256] of byte;

	(header, err) := readheader(fd, buf);
	if(header == nil)
		return (nil, err);

	globalcmap: array of byte;
	if(header.fields & 16r80){
		(globalcmap, err) = readcmap(header, (header.fields&7)+1);
		if(globalcmap == nil)
			return (nil, err);
	}

	images: array of ref Rawimage;
	new: ref Rawimage;

    Loop:
	for(;;){
		case c := fd.getb(){
		Bufio->EOF =>
			if(err == "")
				err = "ReadGIF: premature EOF";
			break Loop;
		Bufio->ERROR =>
			err = sys->sprint("ReadGIF: read error: %r");
			return (nil, err);
		16r21 =>	# Extension (ignored)
			err = skipextension(header);
			if(err != nil)
				return (nil, err);

		16r2C =>	# Image Descriptor
			if(!multi && images!=nil)	# why read the rest?
				break Loop;
			(new, err) = readimage(header);
			if(new == nil)
				return (nil ,err);
			if(new.fields & 16r80){
				(new.cmap, err) = readcmap(header, (new.fields&7)+1);
				if(new.cmap == nil)
					return (nil, err);
			}else
				new.cmap = globalcmap;
			(new.chans[0], err) = decode(header, new);
			if(new.chans[0] == nil)
				return (nil, err);
			if(new.fields & 16r40)
				interlace(new);
			new.transp = header.transp;
			new.trindex = header.trindex;
			nimages := array[len images+1] of ref Rawimage;
			nimages[0:] = images[0:];
			nimages[len images] = new;
			images = nimages;

		16r3B =>	# Trailer
			break Loop;

		* =>
			err = sys->sprint("ReadGIF: unknown block type: %x", c);
			break Loop;
		}
	}

	if(images==nil || images[0].chans[0] == nil){
		if(err == nil)
			err = "ReadGIF: no picture in file";
		return (nil, err);
	}

	return (images, err);
}

readheader(fd: ref Iobuf, buf: array of byte): (ref Header, string)
{
	if(fd.read(buf, 13) != 13){
		err := sys->sprint("ReadGIF: can't read header: %r");
		return (nil, err);
	}
	h := ref Header;
	h.vers = string buf[0:6];
	if(h.vers!="GIF87a" && h.vers!="GIF89a"){
		err := sys->sprint("ReadGIF: can't recognize format %s", h.vers);
		return (nil, err);
	}
	h.screenw = int buf[6]+(int buf[7]<<8);
	h.screenh = int buf[8]+(int buf[9]<<8);
	h.fields = int buf[10];
	h.bgrnd = int buf[11];
	h.aspect = int buf[12];
	h.fd = fd;
	h.buf = buf;
	h.transp = 0;
	return (h, "");
}

readcmap(h: ref Header, size: int): (array of byte,string)
{
	size = 3*(1<<size);
	map := array[size] of byte;
	if(h.fd.read(map, size) != size)
		return (nil, "ReadGIF: short read on color map");
	return (map, "");
}

readimage(h: ref Header): (ref Rawimage, string)
{
	if(h.fd.read(h.buf, 9) != 9){
		err := sys->sprint("ReadGIF: can't read image descriptor: %r");
		return (nil, err);
	}
	i := ref Rawimage;
	left := int h.buf[0]+(int h.buf[1]<<8);
	top := int h.buf[2]+(int h.buf[3]<<8);
	width := int h.buf[4]+(int h.buf[5]<<8);
	height := int h.buf[6]+(int h.buf[7]<<8);
	i.fields = int h.buf[8];
	i.r.min.x = left;
	i.r.min.y = top;
	i.r.max.x = left+width;
	i.r.max.y = top+height;
	i.nchans = 1;
	i.chans = array[1] of array of byte;
	i.chandesc = CRGB1;
	return (i, "");
}

readdata(h: ref Header, ch: chan of (array of byte, string))
{
	err: string;

	# send nil for error, buffer of length 0 for EOF
	for(;;){
		nbytes := h.fd.getb();
		if(nbytes < 0){
			err = sys->sprint("ReadGIF: can't read data: %r");
			ch <-= (nil, err);
			return;
		}
		d := array[nbytes] of byte;
		if(nbytes == 0){
			ch <-= (d, "");
			return;
		}
		n := h.fd.read(d, nbytes);
		if(n != nbytes){
			if(n > 0){
				ch <-= (d[0:n], nil);
				ch <-= (d[0:0], "ReadGIF: short data subblock");
			}else
				ch <-= (nil, sys->sprint("ReadGIF: can't read data: %r"));
			return;
		}
		ch <-= (d, "");
	}
}

readerr: con "ReadGIF: can't read extension: %r";

skipextension(h: ref Header): string
{
	fmterr: con "ReadGIF: bad extension format";

	hsize := 0;
	hasdata := 0;

	case h.fd.getb(){
	Bufio->ERROR or Bufio->EOF =>
		return sys->sprint(readerr);
	16r01 =>	# Plain Text Extension
		hsize = 13;
		hasdata = 1;
	16rF9 =>	# Graphic Control Extension
		return graphiccontrol(h);
	16rFE =>	# Comment Extension
		hasdata = 1;
	16rFF =>	# Application Extension
		hsize = h.fd.getb();
		# standard says this must be 11, but Adobe likes to put out 10-byte ones,
		# so we pay attention to the field.
		hasdata = 1;
	* =>
		return "ReadGIF: unknown extension";
	}
	if(hsize>0 && h.fd.read(h.buf, hsize) != hsize)
		return sys->sprint(readerr);
	if(!hasdata){
		if(int h.buf[hsize-1] != 0)
			return fmterr;
	}else{
		ch := chan of (array of byte, string);
		spawn readdata(h, ch);
		for(;;){
			(data, err) := <-ch;
			if(data == nil)
				return err;
			if(len data == 0)
				break;
		}
	}
	return "";
}

graphiccontrol(h: ref Header): string
{
	if(h.fd.read(h.buf, 5+1) != 5+1)
		return sys->sprint(readerr);
	if(int h.buf[1] & 1){
		h.transp = 1;
		h.trindex = h.buf[4];
	}
	return "";
}

inittbl()
{
	tbl = array[4096] of Entry;
	for(i:=0; i<258; i++) {
		tbl[i].prefix = -1;
		tbl[i].exten = i;
	}
}

decode(h: ref Header, i: ref Rawimage): (array of byte, string)
{
	c, incode: int;

	err := "";
	if(h.fd.read(h.buf, 1) != 1){
		err = sys->sprint("ReadGIF: can't read data: %r");
		return (nil, err);
	}
	codesize := int h.buf[0];
	if(codesize>8 || 0>codesize){
		err = sys->sprint("ReadGIF: can't handle codesize %d", codesize);
		return (nil, err);
	}
	err1 := "";
	if(i.cmap!=nil && len i.cmap!=3*(1<<codesize)
	  && (codesize!=2 || len i.cmap!=3*2)) # peculiar GIF bitmap files...
		err1 = sys->sprint("ReadGIF: codesize %d doesn't match color map 3*%d", codesize, len i.cmap/3);

	ch := chan of (array of byte, string);

	spawn readdata(h, ch);

	CTM :=1<<codesize;
	EOD := CTM+1;

	pic := array[(i.r.max.x-i.r.min.x)*(i.r.max.y-i.r.min.y)] of byte;
	pici := 0;
	data := array[0] of byte;
	datai := 0;

	nbits := 0;
	sreg := 0;
	stack := array[4096] of byte;
	stacki: int;
	fc := 0;

Init:
	for(;;){
		csize := codesize+1;
		nentry := EOD+1;
		maxentry := (1<<csize)-1;
		first := 1;
		ocode := -1;

		for(;; ocode = incode) {
			while(nbits < csize) {
				if(datai == len data){
					(data, err) = <-ch;
					if(data == nil)
						return (nil, err);
					if(err!="" && err1=="")
						err1 = err;
					if(len data == 0)
						break Init;
					datai = 0;
				}
				c = int data[datai++];
				sreg |= c<<nbits;
				nbits += 8;
			}
			code := sreg & ((1<<csize) - 1);
			sreg >>= csize;
			nbits -= csize;

			if(code == EOD){
				(data, err) = <-ch;
				if(len data != 0)
					err = "ReadGIF: unexpected data past EOD";
				if(err!="" && err1=="")
					err1 = err;
				break Init;
			}

			if(code == CTM)
				continue Init;

			stacki = len stack-1;

			incode = code;

			# special case for KwKwK 
			if(code == nentry) {
				stack[stacki--] = byte fc;
				code = ocode;
			}

			if(code > nentry) {
				err = sys->sprint("ReadGIF: bad code %x %x", code, nentry);
				return (nil, err);
			}
		
			for(c=code; c>=0; c=tbl[c].prefix)
				stack[stacki--] = byte tbl[c].exten;

			nb := len stack-(stacki+1);
			if(pici+nb > len pic){
				if(err1 == "")
					err1 = "ReadGIF: data overflows picture";
			}else{
				pic[pici:] = stack[stacki+1:];
				pici += nb;
			}

			fc = int stack[stacki+1];

			if(first){
				first = 0;
				continue;
			}
			early:=0; # peculiar tiff feature here for reference
			if(nentry == maxentry-early) {
				if(csize >= 12)
					continue;
				csize++;
				maxentry = (1<<csize);
				if(csize < 12)
					maxentry--;
			}
			tbl[nentry].prefix = ocode;
			tbl[nentry].exten = fc;
			nentry++;
		}
	}
	return (pic, err1);
}

interlace(image: ref Rawimage)
{
	pic := image.chans[0];
	r := image.r;
	dx := r.max.x-r.min.x;
	ipic := array[dx*(r.max.y-r.min.y)] of byte;

	# Group 1: every 8th row, starting with row 0
	yy := 0;
	for(y:=r.min.y; y<r.max.y; y+=8){
		ipic[y*dx:] = pic[yy*dx:(yy+1)*dx];
		yy++;
	}

	# Group 2: every 8th row, starting with row 4
	for(y=r.min.y+4; y<r.max.y; y+=8){
		ipic[y*dx:] = pic[yy*dx:(yy+1)*dx];
		yy++;
	}

	# Group 3: every 4th row, starting with row 2
	for(y=r.min.y+2; y<r.max.y; y+=4){
		ipic[y*dx:] = pic[yy*dx:(yy+1)*dx];
		yy++;
	}

	# Group 4: every 2nd row, starting with row 1
	for(y=r.min.y+1; y<r.max.y; y+=2){
		ipic[y*dx:] = pic[yy*dx:(yy+1)*dx];
		yy++;
	}

	image.chans[0] = ipic;
}
