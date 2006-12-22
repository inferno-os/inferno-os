implement RImagefile;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "imagefile.m";

# Constants, all preceded by byte 16rFF
SOF:	con byte 16rC0;	# Start of Frame
SOF2:	con byte 16rC2;	# Start of Frame; progressive Huffman
JPG:	con byte 16rC8;	# Reserved for JPEG extensions
DHT:	con byte 16rC4;	# Define Huffman Tables
DAC:	con byte 16rCC;	# Arithmetic coding conditioning
RST:	con byte 16rD0;	# Restart interval termination
RST7:	con byte 16rD7;	# Restart interval termination (highest value)
SOI:	con byte 16rD8;	# Start of Image
EOI:	con byte 16rD9;	# End of Image
SOS:	con byte 16rDA;	# Start of Scan
DQT:	con byte 16rDB;	# Define quantization tables
DNL:	con byte 16rDC;	# Define number of lines
DRI:	con byte 16rDD;	# Define restart interval
DHP:	con byte 16rDE;	# Define hierarchical progression
EXP:	con byte 16rDF;	# Expand reference components
APPn:	con byte 16rE0;	# Reserved for application segments
JPGn:	con byte 16rF0;	# Reserved for JPEG extensions
COM:	con byte 16rFE;	# Comment

Header: adt
{
	fd:	ref Iobuf;
	ch:	chan of (ref Rawimage, string);
	# variables in i/o routines
	sr:	int;	# shift register, right aligned
	cnt:	int;	# # bits in right part of sr
	buf:	array of byte;
	bufi:	int;
	nbuf:	int;

	Nf:		int;
	comp:	array of Framecomp;
	mode:	byte;
	X,Y:		int;
	qt:		array of array of int;	# quantization tables
	dcht:		array of ref Huffman;
	acht:		array of ref Huffman;
	sf:		array of byte;	# start of frame; do better later
	ss:		array of byte;	# start of scan; do better later
	ri:		int;
};

NBUF:	con 16*1024;

Huffman: adt
{
	bits:	array of int;
	size:	array of int;
	code:	array of int;
	val:	array of int;
	mincode:	array of int;
	maxcode:	array of int;
	valptr:	array of int;
	# fast lookup
	value:	array of int;
	shift:	array of int;
};

Framecomp: adt	# Frame component specifier from SOF marker
{
	C:	int;
	H:	int;
	V:	int;
	Tq:	int;
};

zerobytes: array of byte;
zeroints: array of int;
zeroreals: array of real;
clamp: array of byte;
NCLAMP: con 1000;
CLAMPOFF: con 300;

init(iomod: Bufio)
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	bufio = iomod;
	zerobytes = array[8*8] of byte;
	zeroints = array[8*8] of int;
	zeroreals = array[8*8] of real;
	for(k:=0; k<8*8; k++){
		zerobytes[k] = byte 0;
		zeroints[k] = 0;
		zeroreals[k] = 0.0;
	}
	clamp = array[NCLAMP] of byte;
	for(k=0; k<CLAMPOFF; k++)
		clamp[k] = byte 0;
	for(; k<CLAMPOFF+256; k++)
		clamp[k] = byte(k-CLAMPOFF);
	for(; k<NCLAMP; k++)
		clamp[k] = byte 255;
}

read(fd: ref Iobuf): (ref Rawimage, string)
{
	# spawn a subprocess so I/O errors can clean up easily

	ch := chan of (ref Rawimage, string);
	spawn readslave(fd, ch);

	return <-ch;
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

readslave(fd: ref Iobuf, ch: chan of (ref Rawimage, string))
{
	image: ref Rawimage;

	(header, err) := soiheader(fd, ch);
	if(header == nil){
		ch <-= (nil, err);
		exit;
	}
	buf := header.buf;
	nseg := 0;

    Loop:
	while(err == ""){
		m: int;
		b: array of byte;
		nseg++;
		(m, b, err) = readsegment(header);
		case m{
		-1 =>
			break Loop;

		int APPn+0 =>
			if(nseg==1 && string b[0:4]=="JFIF"){  # JFIF header; check version
				vers0 := int b[5];
				vers1 := int b[6];
				if(vers0>1 || vers1>2)
					err = sys->sprint("ReadJPG: can't handle JFIF version %d.%2d", vers0, vers1);
			}

		int APPn+1 to int APPn+15 =>
			;

		int DQT =>
			err = quanttables(header, b);

		int SOF =>
			header.Y = int2(b, 1);
			header.X = int2(b, 3);
			header.Nf = int b[5];
			header.comp = array[header.Nf] of Framecomp;
			for(i:=0; i<header.Nf; i++){
				header.comp[i].C = int b[6+3*i+0];
				(H, V) := nibbles(b[6+3*i+1]);
				header.comp[i].H = H;
				header.comp[i].V = V;
				header.comp[i].Tq = int b[6+3*i+2];
			}
			header.mode = SOF;
			header.sf = b;

		int SOF2 =>
			err = sys->sprint("ReadJPG: can't handle progressive Huffman mode");
			break Loop;

		int SOS =>
			header.ss = b;
			(image, err) = decodescan(header);
			if(err != "")
				break Loop;

			# BUG: THIS SHOULD USE THE LOOP TO FINISH UP
			x := nextbyte(header, 1);
			if(x != 16rFF)
				err = sys->sprint("ReadJPG: didn't see marker at end of scan; saw %x", x);
		 	else{
				x = nextbyte(header, 1);
				if(x != int EOI)
					err = sys->sprint("ReadJPG: expected EOI saw %x", x);
			}
			break Loop;

		int DHT =>
			err = huffmantables(header, b);

		int DRI =>
			header.ri = int2(b, 0);

		int COM =>
			;

		int EOI =>
			break Loop;

		* =>
			err = sys->sprint("ReadJPG: unknown marker %.2x", m);
		}
	}
	ch <-= (image, err);
}

readerror(): string
{
	return sys->sprint("ReadJPG: read error: %r");
}

marker(buf: array of byte, n: int): byte
{
	if(buf[n] != byte 16rFF)
		return byte 0;
	return buf[n+1];
}

int2(buf: array of byte, n: int): int
{
	return (int buf[n]<<8)+(int buf[n+1]);
}

nibbles(b: byte): (int, int)
{
	i := int b;
	return (i>>4, i&15);
}

soiheader(fd: ref Iobuf, ch: chan of (ref Rawimage, string)): (ref Header, string)
{
	# 1+ for restart preamble (see nextbyte), +1 for sentinel
	buf := array[1+NBUF+1] of byte;
	if(fd.read(buf, 2) != 2)
		return (nil, sys->sprint("ReadJPG: can't read header: %r"));
	if(marker(buf, 0) != SOI)
		return (nil, sys->sprint("ReadJPG: unrecognized marker in header"));
	h := ref Header;
	h.buf = buf;
	h.bufi = 0;
	h.nbuf = 0;
	h.fd = fd;
	h.ri = 0;
	h.ch = ch;
	return (h, nil);
}

readsegment(h: ref Header): (int, array of byte, string)
{
	if(h.fd.read(h.buf, 2) != 2)
		return (-1, nil, readerror());
	m := int marker(h.buf, 0);
	case m{
	int EOI =>
		return (m, nil, nil);
	0 =>
		err := sys->sprint("ReadJPG: expecting marker; saw %.2x%.2x)",
			int h.buf[0], int h.buf[1]);
		return (-1, nil, err);
	}
	if(h.fd.read(h.buf, 2) != 2)
		return (-1, nil, readerror());
	n := int2(h.buf, 0);
	if(n < 2)
		return (-1, nil, readerror());
	n -= 2;
#	if(n > len h.buf){
#		h.buf = array[n+1] of byte;	# +1 for sentinel
#		#h.nbuf = n;
#	}
	b := array[n] of byte;
	if(h.fd.read(b, n) != n)
		return (-1, nil, readerror());
	return (m, b, nil);
}

huffmantables(h: ref Header, b: array of byte): string
{
	if(h.dcht == nil){
		h.dcht = array[4] of ref Huffman;
		h.acht = array[4] of ref Huffman;
	}
	err: string;
	mt: int;
	for(l:=0; l<len b; l+=17+mt){
		(mt, err) = huffmantable(h, b[l:]);
		if(err != nil)
			return err;
	}
	return nil;
}

huffmantable(h: ref Header, b: array of byte): (int, string)
{
	t := ref Huffman;
	(Tc, th) := nibbles(b[0]);
	if(Tc > 1)
		return (0, sys->sprint("ReadJPG: unknown Huffman table class %d", Tc));
	if(th>3 || (h.mode==SOF && th>1))
		return (0, sys->sprint("ReadJPG: unknown Huffman table index %d", th));
	if(Tc == 0)
		h.dcht[th] = t;
	else
		h.acht[th] = t;

	# flow chart C-2
	nsize := 0;
	for(i:=0; i<16; i++)
		nsize += int b[1+i];
	t.size = array[nsize+1] of int;
	k := 0;
	for(i=1; i<=16; i++){
		n := int b[i];
		for(j:=0; j<n; j++)
			t.size[k++] = i;
	}
	t.size[k] = 0;

	# initialize HUFFVAL
	t.val = array[nsize] of int;
	for(i=0; i<nsize; i++){
		t.val[i] = int b[17+i];
	}

	# flow chart C-3
	t.code = array[nsize+1] of int;
	k = 0;
	code := 0;
	si := t.size[0];
	for(;;){
		do
			t.code[k++] = code++;
		while(t.size[k] == si);
		if(t.size[k] == 0)
			break;
		do{
			code <<= 1;
			si++;
		}while(t.size[k] != si);
	}

	# flow chart F-25
	t.mincode = array[17] of int;
	t.maxcode = array[17] of int;
	t.valptr = array[17] of int;
	i = 0;
	j := 0;
    F25:
	for(;;){
		for(;;){
			i++;
			if(i > 16)
				break F25;
			if(int b[i] != 0)
				break;
			t.maxcode[i] = -1;
		}
		t.valptr[i] = j;
		t.mincode[i] = t.code[j];
		j += int b[i]-1;
		t.maxcode[i] = t.code[j];
		j++;
	}

	# create byte-indexed fast path tables
	t.value = array[256] of int;
	t.shift = array[256] of int;
	maxcode := t.maxcode;
	# stupid startup algorithm: just run machine for each byte value
  Bytes:
	for(v:=0; v<256; v++){
		cnt := 7;
		m := 1<<7;
		code = 0;
		sr := v;
		i = 1;
		for(;;i++){
			if(sr & m)
				code |= 1;
			if(code <= maxcode[i])
				break;
			code <<= 1;
			m >>= 1;
			if(m == 0){
				t.shift[v] = 0;
				t.value[v] = -1;
				continue Bytes;
			}
			cnt--;
		}
		t.shift[v] = 8-cnt;
		t.value[v] = t.val[t.valptr[i]+(code-t.mincode[i])];
	}

	return (nsize, nil);
}

quanttables(h: ref Header, b: array of byte): string
{
	if(h.qt == nil)
		h.qt = array[4] of array of int;
	err: string;
	n: int;
	for(l:=0; l<len b; l+=1+n){
		(n, err) = quanttable(h, b[l:]);
		if(err != nil)
			return err;
	}
	return nil;
}

quanttable(h: ref Header, b: array of byte): (int, string)
{
	(pq, tq) := nibbles(b[0]);
	if(pq > 1)
		return (0, sys->sprint("ReadJPG: unknown quantization table class %d", pq));
	if(tq > 3)
		return (0, sys->sprint("ReadJPG: unknown quantization table index %d", tq));
	q := array[64] of int;
	h.qt[tq] = q;
	for(i:=0; i<64; i++){
		if(pq == 0)
			q[i] = int b[1+i];
		else
			q[i] = int2(b, 1+2*i);
	}
	return (64*(1+pq), nil);
}

zig := array[64] of {
	0, 1, 8, 16, 9, 2, 3, 10, 17, # 0-7
	24, 32, 25, 18, 11, 4, 5, # 8-15
	12, 19, 26, 33, 40, 48, 41, 34, # 16-23
	27, 20, 13, 6, 7, 14, 21, 28, # 24-31
	35, 42, 49, 56, 57, 50, 43, 36, # 32-39
	29, 22, 15, 23, 30, 37, 44, 51, # 40-47
	58, 59, 52, 45, 38, 31, 39, 46, # 48-55
	53, 60, 61, 54, 47, 55, 62, 63 # 56-63
};

decodescan(h: ref Header): (ref Rawimage, string)
{
	ss := h.ss;
	Ns := int ss[0];
	if((Ns!=3 && Ns!=1) || Ns!=h.Nf)
		return (nil, "ReadJPG: can't handle scan not 3 components");

	image := ref Rawimage;
	image.r = ((0, 0), (h.X, h.Y));
	image.cmap = nil;
	image.transp = 0;
	image.trindex = byte 0;
	image.fields = 0;
	image.chans = array[h.Nf] of array of byte;
	if(Ns == 3)
		image.chandesc = CRGB;
	else
		image.chandesc = CY;
	image.nchans = h.Nf;
	for(k:=0; k<h.Nf; k++)
		image.chans[k] = array[h.X*h.Y] of byte;

	# build per-component arrays
	Td := array[Ns] of int;
	Ta := array[Ns] of int;
	data := array[Ns] of array of array of real;
	H := array[Ns] of int;
	V := array[Ns] of int;
	DC := array[Ns] of int;

	# compute maximum H and V
	Hmax := 0;
	Vmax := 0;
	for(comp:=0; comp<Ns; comp++){
		if(h.comp[comp].H > Hmax)
			Hmax = h.comp[comp].H;
		if(h.comp[comp].V > Vmax)
			Vmax = h.comp[comp].V;
	}

	# initialize data structures
	allHV1 := 1;
	for(comp=0; comp<Ns; comp++){
		# JPEG requires scan components to be in same order as in frame,
		# so if both have 3 we know scan is Y Cb Cr and there's no need to
		# reorder
		cs := int ss[1+2*comp];
		(Td[comp], Ta[comp]) = nibbles(ss[2+2*comp]);
		H[comp] = h.comp[comp].H;
		V[comp] = h.comp[comp].V;
		nblock := H[comp]*V[comp];
		if(nblock != 1)
			allHV1 = 0;
		data[comp] = array[nblock] of array of real;
		DC[comp] = 0;
		for(m:=0; m<nblock; m++)
			data[comp][m] = array[8*8] of real;
	}

	ri := h.ri;

	h.buf[0] = byte 16rFF;	# see nextbyte()
	h.cnt = 0;
	h.sr = 0;
	nacross := ((h.X+(8*Hmax-1))/(8*Hmax));
	nmcu := ((h.Y+(8*Vmax-1))/(8*Vmax))*nacross;
	zz := array[64] of real;
	err := "";
	for(mcu:=0; mcu<nmcu; ){
		for(comp=0; comp<Ns; comp++){
			dcht := h.dcht[Td[comp]];
			acht := h.acht[Ta[comp]];
			qt := h.qt[h.comp[comp].Tq];

			for(block:=0; block<H[comp]*V[comp]; block++){
				# F-22
				t := decode(h, dcht);
				diff := receive(h, t);
				DC[comp] += diff;

				# F-23
				zz[0:] = zeroreals;
				zz[0] = real (qt[0]*DC[comp]);
				k = 1;
				for(;;){
					rs := decode(h, acht);
					(rrrr, ssss) := nibbles(byte rs);
					if(ssss == 0){
						if(rrrr != 15)
							break;
						k += 16;
					}else{
						k += rrrr;
						z := receive(h, ssss);
						zz[zig[k]] = real (z*qt[k]);
						if(k == 63)
							break;
						k++;
					}
				}

				idct(zz, data[comp][block]);	
			}
		}

		# rotate colors to RGB and assign to bytes
		if(Ns == 1) # very easy
			colormap1(h, image, data[0][0], mcu, nacross);
		else if(allHV1) # fairly easy
			colormapall1(h, image, data[0][0], data[1][0], data[2][0], mcu, nacross);
		else # miserable general case
			colormap(h, image, data[0], data[1], data[2], mcu, nacross, Hmax, Vmax, H, V);

		# process restart marker, if present
		mcu++;
		if(ri>0 && mcu<nmcu-1 && mcu%ri==0){
			restart := mcu/ri-1;
			rst, nskip: int;
			nskip = 0;
			do{
				do{
					rst = nextbyte(h, 1);
					nskip++;
				}while(rst>=0 && rst!=16rFF);
				if(rst == 16rFF){
					rst = nextbyte(h, 1);
					nskip++;
				}
			}while(rst>=0 && (rst&~7)!=int RST);
			if(nskip != 2)
				err = sys->sprint("skipped %d bytes at restart %d\n", nskip-2, restart);
			if(rst < 0)
				return (nil, readerror());
			if((rst&7) != (restart&7))
				return (nil, sys->sprint("ReadJPG: expected RST%d got %d", restart&7, int rst&7));
			h.cnt = 0;
			h.sr = 0;
			for(comp=0; comp<Ns; comp++)
				DC[comp] = 0;
		}
	}
	return (image, err);
}

colormap1(h: ref Header, image: ref Rawimage, data: array of real, mcu, nacross: int)
{
	pic := image.chans[0];
	minx := 8*(mcu%nacross);
		dx := 8;
	if(minx+dx > h.X)
		dx = h.X-minx;
	miny := 8*(mcu/nacross);
	dy := 8;
	if(miny+dy > h.Y)
		dy = h.Y-miny;
	pici := miny*h.X+minx;
	k := 0;
	for(y:=0; y<dy; y++){
		for(x:=0; x<dx; x++){
			r := clamp[int (data[k+x]+128.)+CLAMPOFF];
			pic[pici+x] = r;
		}
		pici += h.X;
		k += 8;
	}
}

colormapall1(h: ref Header, image: ref Rawimage, data0, data1, data2: array of real, mcu, nacross: int)
{
	rpic := image.chans[0];
	gpic := image.chans[1];
	bpic := image.chans[2];
	minx := 8*(mcu%nacross);
	dx := 8;
	if(minx+dx > h.X)
		dx = h.X-minx;
	miny := 8*(mcu/nacross);
	dy := 8;
	if(miny+dy > h.Y)
		dy = h.Y-miny;
	pici := miny*h.X+minx;
	k := 0;
	for(y:=0; y<dy; y++){
		for(x:=0; x<dx; x++){
			Y := data0[k+x]+128.;
			Cb := data1[k+x];
			Cr := data2[k+x];
			r := int (Y+1.402*Cr);
			g := int (Y-0.34414*Cb-0.71414*Cr);
			b := int (Y+1.772*Cb);
			rpic[pici+x] = clamp[r+CLAMPOFF];
			gpic[pici+x] = clamp[g+CLAMPOFF];
			bpic[pici+x] = clamp[b+CLAMPOFF];
		}
		pici += h.X;
		k += 8;
	}
}

colormap(h: ref Header, image: ref Rawimage, data0, data1, data2: array of array of real, mcu, nacross, Hmax, Vmax: int,  H, V: array of int)
{
	rpic := image.chans[0];
	gpic := image.chans[1];
	bpic := image.chans[2];
	minx := 8*Hmax*(mcu%nacross);
	dx := 8*Hmax;
	if(minx+dx > h.X)
		dx = h.X-minx;
	miny := 8*Vmax*(mcu/nacross);
	dy := 8*Vmax;
	if(miny+dy > h.Y)
		dy = h.Y-miny;
	pici := miny*h.X+minx;
	H0 := H[0];
	H1 := H[1];
	H2 := H[2];
	for(y:=0; y<dy; y++){
		t := y*V[0];
		b0 := H0*(t/(8*Vmax));
		y0 := 8*((t/Vmax)&7);
		t = y*V[1];
		b1 := H1*(t/(8*Vmax));
		y1 := 8*((t/Vmax)&7);
		t = y*V[2];
		b2 := H2*(t/(8*Vmax));
		y2 := 8*((t/Vmax)&7);
		x0 := 0;
		x1 := 0;
		x2 := 0;
		for(x:=0; x<dx; x++){
			Y := data0[b0][y0+x0++*H0/Hmax]+128.;
			Cb := data1[b1][y1+x1++*H1/Hmax];
			Cr := data2[b2][y2+x2++*H2/Hmax];
			if(x0*H0/Hmax >= 8){
				x0 = 0;
				b0++;
			}
			if(x1*H1/Hmax >= 8){
				x1 = 0;
				b1++;
			}
			if(x2*H2/Hmax >= 8){
				x2 = 0;
				b2++;
			}
			r := int (Y+1.402*Cr);
			g := int (Y-0.34414*Cb-0.71414*Cr);
			b := int (Y+1.772*Cb);
			rpic[pici+x] = clamp[r+CLAMPOFF];
			gpic[pici+x] = clamp[g+CLAMPOFF];
			bpic[pici+x] = clamp[b+CLAMPOFF];
		}
		pici += h.X;
	}
}

# decode next 8-bit value from entropy-coded input.  chart F-26
decode(h: ref Header, t: ref Huffman): int
{
	maxcode := t.maxcode;
	if(h.cnt < 8)
		nextbyte(h, 0);
	# fast lookup
	code := (h.sr>>(h.cnt-8))&16rFF;
	v := t.value[code];
	if(v >= 0){
		h.cnt -= t.shift[code];
		return v;
	}

	h.cnt -= 8;
	if(h.cnt == 0)
		nextbyte(h, 0);
	h.cnt--;
	cnt := h.cnt;
	m := 1<<cnt;
	sr := h.sr;
	code <<= 1;
	i := 9;
	for(;;i++){
		if(sr & m)
			code |= 1;
		if(code <= maxcode[i])
			break;
		code <<= 1;
		m >>= 1;
		if(m == 0){
			sr = nextbyte(h, 0);
			m = 16r80;
			cnt = 8;
		}
		cnt--;
	}
	h.cnt = cnt;
	return t.val[t.valptr[i]+(code-t.mincode[i])];
}

#
# load next byte of input
# we should really just call h.fd.getb(), but it's faster just to use Bufio
# to load big chunks and manage our own byte-at-a-time input.
#
nextbyte(h: ref Header, marker: int): int
{
	b := int h.buf[h.bufi++];
	if(b == 16rFF){
		# check for sentinel at end of buffer
		if(h.bufi >= h.nbuf){
			underflow := (h.bufi > h.nbuf);
			h.nbuf = h.fd.read(h.buf, NBUF);
			if(h.nbuf <= 0){
				h.ch <-= (nil, readerror());
				exit;
			}
			h.buf[h.nbuf] = byte 16rFF;
			h.bufi = 0;
			if(underflow)	# if ran off end of buffer, just restart
				return nextbyte(h, marker);
		}
		if(marker)
			return b;
		b2 := h.buf[h.bufi++];
		if(b2 != byte 0){
			if(b2 == DNL){
				h.ch <-= (nil, "ReadJPG: DNL marker unimplemented");
				exit;
			}else if(b2<RST && RST7<b2){
				h.ch <-= (nil, sys->sprint("ReadJPG: unrecognized marker %x", int b2));
				exit;
			}
			# decode is reading into restart marker; satisfy it and restore state
			if(h.bufi < 2){
				# misery: must shift up buffer
				h.buf[1:] = h.buf[0:h.nbuf+1];
				h.nbuf++;
				h.buf[0] = byte 16rFF;
				h.bufi -= 1;
			}else
				h.bufi -= 2;
			b = 16rFF;
		}
	}
	h.cnt += 8;
	h.sr = (h.sr<<8)|b;
	return b;
}

# return next s bits of input, MSB first, and level shift it
receive(h: ref Header, s: int): int
{
	while(h.cnt < s)
		nextbyte(h, 0);
	v := h.sr >> (h.cnt-s);
	m := (1<<s);
	v &= m-1;
	h.cnt -= s;
	# level shift
	if(v < (m>>1))
		v += ~(m-1)+1;
	return v;
}

# IDCT based on Arai, Agui, and Nakajima, using flow chart Figure 4.8
# of Pennebaker & Mitchell, JPEG: Still Image Data Compression Standard.
# Remember IDCT is reverse of flow of DCT.

a0: con 1.414;
a1: con 0.707;
a2: con 0.541;
a3: con 0.707;
a4: con 1.307;
a5: con -0.383;

# scaling factors from eqn 4-35 of P&M
s1: con 1.0196;
s2: con 1.0823;
s3: con 1.2026;
s4: con 1.4142;
s5: con 1.8000;
s6: con 2.6131;
s7: con 5.1258;

# overall normalization of 1/16, folded into premultiplication on vertical pass
scale: con 0.0625;

idct(zin: array of real, zout: array of real)
{
	x, y: int;

	r := array[8*8] of real;

	# transform horizontally
	for(y=0; y<8; y++){
		eighty := y<<3;
		# if all non-DC components are zero, just propagate the DC term
		if(zin[eighty+1]==0.)
		if(zin[eighty+2]==0. && zin[eighty+3]==0.)
		if(zin[eighty+4]==0. && zin[eighty+5]==0.)
		if(zin[eighty+6]==0. && zin[eighty+7]==0.){
			v := zin[eighty]*a0;
			r[eighty+0] = v;
			r[eighty+1] = v;
			r[eighty+2] = v;
			r[eighty+3] = v;
			r[eighty+4] = v;
			r[eighty+5] = v;
			r[eighty+6] = v;
			r[eighty+7] = v;
			continue;
		}

		# step 5
		in1 := s1*zin[eighty+1];
		in3 := s3*zin[eighty+3];
		in5 := s5*zin[eighty+5];
		in7 := s7*zin[eighty+7];
		f2 := s2*zin[eighty+2];
		f3 := s6*zin[eighty+6];
		f5 := (in1+in7);
		f7 := (in5+in3);

		# step 4
		g2 := f2-f3;
		g4 := (in5-in3);
		g6 := (in1-in7);
		g7 := f5+f7;

		# step 3.5
		t := (g4+g6)*a5;

		# step 3
		f0 := a0*zin[eighty+0];
		f1 := s4*zin[eighty+4];
		f3 += f2;
		f2 = a1*g2;

		# step 2
		g0 := f0+f1;
		g1 := f0-f1;
		g3 := f2+f3;
		g4 = t-a2*g4;
		g5 := a3*(f5-f7);
		g6 = a4*g6+t;

		# step 1
		f0 = g0+g3;
		f1 = g1+f2;
		f2 = g1-f2;
		f3 = g0-g3;
		f5 = g5-g4;
		f6 := g5+g6;
		f7 = g6+g7;

		# step 6
		r[eighty+0] = (f0+f7);
		r[eighty+1] = (f1+f6);
		r[eighty+2] = (f2+f5);
		r[eighty+3] = (f3-g4);
		r[eighty+4] = (f3+g4);
		r[eighty+5] = (f2-f5);
		r[eighty+6] = (f1-f6);
		r[eighty+7] = (f0-f7);
	}

	# transform vertically
	for(x=0; x<8; x++){
		# step 5
		in1 := scale*s1*r[x+8];
		in3 := scale*s3*r[x+24];
		in5 := scale*s5*r[x+40];
		in7 := scale*s7*r[x+56];
		f2 := scale*s2*r[x+16];
		f3 := scale*s6*r[x+48];
		f5 := (in1+in7);
		f7 := (in5+in3);

		# step 4
		g2 := f2-f3;
		g4 := (in5-in3);
		g6 := (in1-in7);
		g7 := f5+f7;

		# step 3.5
		t := (g4+g6)*a5;

		# step 3
		f0 := scale*a0*r[x];
		f1 := scale*s4*r[x+32];
		f3 += f2;
		f2 = a1*g2;

		# step 2
		g0 := f0+f1;
		g1 := f0-f1;
		g3 := f2+f3;
		g4 = t-a2*g4;
		g5 := a3*(f5-f7);
		g6 = a4*g6+t;

		# step 1
		f0 = g0+g3;
		f1 = g1+f2;
		f2 = g1-f2;
		f3 = g0-g3;
		f5 = g5-g4;
		f6 := g5+g6;
		f7 = g6+g7;

		# step 6
		zout[x] = (f0+f7);
		zout[x+8] = (f1+f6);
		zout[x+16] = (f2+f5);
		zout[x+24] = (f3-g4);
		zout[x+32] = (f3+g4);
		zout[x+40] = (f2-f5);
		zout[x+48] = (f1-f6);
		zout[x+56] = (f0-f7);
	}
}
