implement Readjpg;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Image: import draw;
include "grid/readjpg.m";
	
display: ref Display;
slowread: int;
zeroints := array[64] of { * => 0 };

init(disp: ref Draw->Display)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	display = disp;
	init_tabs();
}

fjpg2img(fd: ref sys->FD, cachepath: string, chanin, chanout: chan of string): ref Image
{
	if (fd == nil) return nil;
	sync := chan of int;
	imgchan := chan of ref Image;
	is := newImageSource(0,0);
	spawn slowreads(is,fd,cachepath, sync, chanout);
	srpid := <- sync;
	if (srpid == -1) return nil;
	spawn getjpegimg(is, chanout, imgchan, sync);
	gjipid := <- sync;

	for (;;) alt {
		ctl := <- chanin =>
			if (ctl == "kill") {
				if (srpid != -1) kill(srpid);
				kill(gjipid);
				return nil;
			}
		img := <- imgchan =>
			if (srpid != -1) kill(srpid);
			return img;
		err := <- sync =>
			if (err == 0) srpid = -1;
			else {
				kill(gjipid);
				return nil;
			}
	}
}

jpg2img(filename, cachepath: string, chanin, chanout: chan of string): ref Image
{
	fd := sys->open(filename, sys->OREAD);
	return fjpg2img(fd, cachepath, chanin, chanout);
}

kill(pid: int)
{	
	pctl := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE);
	if (pctl != nil)
		sys->write(pctl, array of byte "kill", len "kill");
}

filelength(fd : ref sys->FD): int
{
	(n, dir) := sys->fstat(fd);
	if (n == -1) return -1;
	filelen := int dir.length;
	return filelen;
}

slowreads(is: ref ImageSource, fd : ref sys->FD, cachepath: string, sync: chan of int, chanout: chan of string)
{
	filelen := filelength(fd);
	if (filelen < 1) {
		sync <-= -1;
		return;
	}
	is.data = array[filelen] of byte;
	slowread = 0;

	sync <-= sys->pctl(0, nil);

	cachefd : ref sys->FD = nil;
	if (cachepath != "") cachefd = sys->create(cachepath, sys->OWRITE, 8r666);
	if (chanout != nil) {
		chanout <-= "l2 Loading...";
		chanout <-= "pc 0";
	}
	i : int;
	for (;;) {
		i = sys->read(fd,is.data[slowread:], 8192);
		if (i < 1) break;
		if (cachefd != nil)
			sys->write(cachefd, is.data[slowread:],i);
		slowread += i;
		if (chanout != nil)
			chanout <-= "pc "+string ((slowread*100)/filelen);
		sys->sleep(0);
	}
	if (i == -1 || slowread == 0) {
		sync <-= -1;
		return;
	}
	newdata := array[slowread] of byte;
	newdata = is.data[:slowread];
	is.data = newdata;
	if (cachepath != "" && slowread < filelen)
		sys->remove(cachepath);
	sync <-= 0;
}

wait4data(n: int)
{
	for(;;) {
		if (slowread > n) break;
		sys->sleep(100);
	}
}

newImageSource(w, h: int) : ref ImageSource
{
	is := ref ImageSource(
		w,h,		# width, height
		0,0,		# origw, origh
		0,		# i
		nil,		# jhdr
		nil		# data
		);
	return is;
}

getjpeghdr(is: ref ImageSource)
{
	h := ref Jpegstate(
		0, 0,		# sr, cnt
		0,		# Nf
		nil,		# comp
		byte 0,	# mode,
		0, 0,		# X, Y
		nil,		# qt
		nil, nil,	# dcht, acht
		0,		# Ns
		nil,		# scomp
		0, 0,		# Ss, Se
		0, 0,		# Ah, Al
		0, 0,		# ri, nseg
		nil,		# nblock
		nil, nil,	# dccoeff, accoeff
		0, 0, 0, 0	# nacross, ndown, Hmax, Vmax
		);
	is.jstate = h;
	if(jpegmarker(is) != SOI)
		sys->print("Error: Jpeg expected SOI marker\n");
	(m, n) := jpegtabmisc(is);
	if(!(m == SOF || m == SOF2))
		sys->print("Error: Jpeg expected Frame marker");
	nil = getc(is);		# sample precision
	h.Y = getbew(is);
	h.X = getbew(is);
	h.Nf = getc(is);
	h.comp = array[h.Nf] of Framecomp;
	h.nblock = array[h.Nf] of int;
	for(i:=0; i<h.Nf; i++) {
		h.comp[i].C = getc(is);
		(H, V) := nibbles(getc(is));
		h.comp[i].H = H;
		h.comp[i].V = V;
		h.comp[i].Tq = getc(is);
		h.nblock[i] =H*V;
	}
	h.mode = byte m;
	is.origw = h.X;
	is.origh = h.Y;
	setdims(is);
	if(n != 6+3*h.Nf)
		sys->print("Error: Jpeg bad SOF length");
}

setdims(is: ref ImageSource)
{
	sw := is.origw;
	sh := is.origh;
	dw := is.width;
	dh := is.height;
	if(dw == 0 && dh == 0) {
		dw = sw;
		dh = sh;
	}
	else if(dw == 0 || dh == 0) {
		if(dw == 0) {
			dw = int ((real sw) * (real dh/real sh));
			if(dw == 0)
				dw = 1;
		}
		else {
			dh = int ((real sh) * (real dw/real sw));
			if(dh == 0)
				dh = 1;
		}
	}
	is.width = dw;
	is.height = dh;
}

jpegmarker(is: ref ImageSource) : int
{
	if(getc(is) != 16rFF)
		sys->print("Error: Jpeg expected marker");
	return getc(is);
}

getbew(is: ref ImageSource) : int
{
	c0 := getc(is);
	c1 := getc(is);
	return (c0<<8) + c1;
}

getn(is: ref ImageSource, n: int) : (array of byte, int)
{
	if (is.i + n > slowread - 1) wait4data(is.i + n);
	a := is.data;
	i := is.i;
	if(i + n <= len a)
		is.i += n;
#	else
#		sys->print("Error: premature eof");
	return (a, i);
}

# Consume tables and miscellaneous marker segments,
# returning the marker id and length of the first non-such-segment
# (after having consumed the marker).
# May raise "premature eof" or other exception.
jpegtabmisc(is: ref ImageSource) : (int, int)
{
	h := is.jstate;
	m, n : int;
Loop:
	for(;;) {
		h.nseg++;
		m = jpegmarker(is);
		n = 0;
		if(m != EOI)
			n = getbew(is) - 2;
		case m {
		SOF or SOF2 or SOS or EOI =>
			break Loop;

		APPn+0 =>
			if(h.nseg==1 && n >= 6) {
				(buf, i) := getn(is, 6);
				n -= 6;
				if(string buf[i:i+4]=="JFIF") {
					vers0 := int buf[i+5];
					vers1 := int buf[i+6];
					if(vers0>1 || vers1>2)
						sys->print("Error: Jpeg unimplemented version");
				}
			}

		APPn+1 to APPn+15 =>
			;

		DQT =>
			jpegquanttables(is, n);
			n = 0;

		DHT =>
			jpeghuffmantables(is, n);
			n = 0;

		DRI =>
			h.ri =getbew(is);
			n -= 2;

		COM =>
			;

		* =>
			sys->print("Error: Jpeg unexpected marker");
		}
		if(n > 0)
			getn(is, n);
	}
	return (m, n);
}

# Consume huffman tables, raising exception on error.
jpeghuffmantables(is: ref ImageSource, n: int)
{
	h := is.jstate;
	if(h.dcht == nil) {
		h.dcht = array[4] of ref Huffman;
		h.acht = array[4] of ref Huffman;
	}
	for(l:= 0; l < n; )
		l += jpeghuffmantable(is);
	if(l != n)
		sys->print("Error: Jpeg huffman table bad length");
}

jpeghuffmantable(is: ref ImageSource) : int
{
	t := ref Huffman;
	h := is.jstate;
	(Tc, th) := nibbles(getc(is));
	if(Tc > 1)
		sys->print("Error: Jpeg unknown Huffman table class");
	if(th>3 || (h.mode==byte SOF && th>1))
		sys->print("Error: Jpeg unknown Huffman table index");
	if(Tc == 0)
		h.dcht[th] = t;
	else
		h.acht[th] = t;

	# flow chart C-2
	(b, bi) := getn(is, 16);
	numcodes := array[16] of int;
	nsize := 0;
	for(i:=0; i<16; i++)
		nsize += (numcodes[i] = int b[bi+i]);
	t.size = array[nsize+1] of int;
	k := 0;
	for(i=1; i<=16; i++) {
		n :=numcodes[i-1];
		for(j:=0; j<n; j++)
			t.size[k++] = i;
	}
	t.size[k] = 0;

	# initialize HUFFVAL
	t.val = array[nsize] of int;
	(b, bi) = getn(is, nsize);
	for(i=0; i<nsize; i++)
		t.val[i] = int b[bi++];

	# flow chart C-3
	t.code = array[nsize+1] of int;
	k = 0;
	code := 0;
	si := t.size[0];
	for(;;) {
		do
			t.code[k++] = code++;
		while(t.size[k] == si);
		if(t.size[k] == 0)
			break;
		do {
			code <<= 1;
			si++;
		} while(t.size[k] != si);
	}

	# flow chart F-25
	t.mincode = array[17] of int;
	t.maxcode = array[17] of int;
	t.valptr = array[17] of int;
	i = 0;
	j := 0;
    F25:
	for(;;) {
		for(;;) {
			i++;
			if(i > 16)
				break F25;
			if(numcodes[i-1] != 0)
				break;
			t.maxcode[i] = -1;
		}
		t.valptr[i] = j;
		t.mincode[i] = t.code[j];
		j += int numcodes[i-1]-1;
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

	return nsize+17;
}

jpegquanttables(is: ref ImageSource, n: int)
{
	h := is.jstate;
	if(h.qt == nil)
		h.qt = array[4] of array of int;
	for(l:=0; l<n; )
		l += jpegquanttable(is);
	if(l != n)
		sys->print("Error: Jpeg quant table bad length");
}

jpegquanttable(is: ref ImageSource): int
{
	(pq, tq) := nibbles(getc(is));
	if(pq > 1)
		sys->print("Error: Jpeg unknown quantization table class");
	if(tq > 3)
		sys->print("Error: Jpeg bad quantization table index");
	q := array[64] of int;
	is.jstate.qt[tq] = q;
	for(i:=0; i<64; i++) {
		if(pq == 0)
			q[i] =getc(is);
		else
			q[i] = getbew(is);
	}
	return 1+(64*(1+pq));;
}

# Have just read Frame header.
# Now expect:
#	((tabl/misc segment(s))* (scan header) (entropy coded segment)+)+ EOI
getjpegimg(is:ref ImageSource,chanout:chan of string,imgchan: chan of ref Image,sync: chan of int)
{
	sync <-= sys->pctl(0, nil);
	getjpeghdr(is);
	h := is.jstate;
	chans: array of array of byte = nil;
	for(;;) {
		(m, n) := jpegtabmisc(is);
		if(m == EOI)
			break;
		if(m != SOS)
			sys->print("Error: Jpeg expected start of scan");

		h.Ns = getc(is);
		scomp := array[h.Ns] of Scancomp;
		for(i := 0; i < h.Ns; i++) {
			scomp[i].C = getc(is);
			(scomp[i].tdc, scomp[i].tac) = nibbles(getc(is));
		}
		h.scomp = scomp;
		h.Ss = getc(is);
		h.Se = getc(is);
		(h.Ah, h.Al) = nibbles(getc(is));
		if(n != 4+h.Ns*2)
			sys->print("Error: Jpeg SOS header wrong length");

		if(h.mode == byte SOF) {
			if(chans != nil)
				sys->print("Error: Jpeg baseline has > 1 scan");
			chans = jpegbaselinescan(is, chanout);
		}
	}
	if(chans == nil)
		sys->print("Error: jpeg has no image");
	width := is.width;
	height := is.height;
	if(width != h.X || height != h.Y) {
		for(k := 0; k < len chans; k++)
			chans[k] = resample(chans[k], h.X, h.Y, width, height);
	}

	r := remapYCbCr(chans, chanout);
	im := newimage24(width, height);
	im.writepixels(im.r, r);
	imgchan <-= im;
}

newimage24(w, h: int) : ref Image
{
	im := display.newimage(((0,0),(w,h)), Draw->RGB24, 0, Draw->White);
	if(im == nil)
		sys->print("Error: out of memory");
	return im;
}

remapYCbCr(chans: array of array of byte, chanout: chan of string): array of byte
{
	Y := chans[0];
	Cb := chans[1];
	Cr := chans[2];

	rgb := array [3*len Y] of byte;
	bix := 0;
	lY := len Y;
	n := lY / 20;
	count := 0;
	for (i := 0; i < lY; i++) {
		if ((count == 0 || count >= n ) && chanout != nil) {
			chanout <-= "l2 Processing...";
			chanout <-= "pc "+string ((100*i)/ lY);
			count = 0;
		}
		count++;
		y := int Y[i];
		cb := int Cb[i];
		cr := int Cr[i];
		r := y + Cr2r[cr];
		g := y - Cr2g[cr] - Cb2g[cb];
		b := y + Cb2b[cb];

		rgb[bix++] = clampb[b+CLAMPBOFF];
		rgb[bix++] = clampb[g+CLAMPBOFF];
		rgb[bix++] = clampb[r+CLAMPBOFF];
	}
	if (chanout != nil) chanout <-= "pc 100";
	return rgb;
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

jpegbaselinescan(is: ref ImageSource,chanout: chan of string) : array of array of byte
{
	h := is.jstate;
	Ns := h.Ns;
	if(Ns != h.Nf)
		sys->print("Error: Jpeg baseline needs Ns==Nf");
	if(!(Ns==3 || Ns==1))
		sys->print("Error: Jpeg baseline needs Ns==1 or 3");

	
	chans := array[h.Nf] of array of byte;
	for(k:=0; k<h.Nf; k++)
		chans[k] = array[h.X*h.Y] of byte;

	# build per-component arrays
	Td := array[Ns] of int;
	Ta := array[Ns] of int;
	data := array[Ns] of array of array of int;
	H := array[Ns] of int;
	V := array[Ns] of int;
	DC := array[Ns] of int;

	# compute maximum H and V
	Hmax := 0;
	Vmax := 0;
	for(comp:=0; comp<Ns; comp++) {
		if(h.comp[comp].H > Hmax)
			Hmax = h.comp[comp].H;
		if(h.comp[comp].V > Vmax)
			Vmax = h.comp[comp].V;
	}
	# initialize data structures
	allHV1 := 1;
	for(comp=0; comp<Ns; comp++) {
		# JPEG requires scan components to be in same order as in frame,
		# so if both have 3 we know scan is Y Cb Cr and there's no need to
		# reorder
		Td[comp] = h.scomp[comp].tdc;
		Ta[comp] = h.scomp[comp].tac;
		H[comp] = h.comp[comp].H;
		V[comp] = h.comp[comp].V;
		nblock := H[comp]*V[comp];
		if(nblock != 1)
			allHV1 = 0;

		# data[comp]: needs (3+nblock)*4 + nblock*(3+8*8)*4 bytes

		data[comp] = array[nblock] of array of int;
		DC[comp] = 0;
		for(m:=0; m<nblock; m++)
			data[comp][m] = array[8*8] of int;
	}

	ri := h.ri;

	h.cnt = 0;
	h.sr = 0;
	nacross := ((h.X+(8*Hmax-1))/(8*Hmax));
	nmcu := ((h.Y+(8*Vmax-1))/(8*Vmax))*nacross;
	n1 := 0;
	n2 := nmcu / 20;
	for(mcu:=0; mcu<nmcu; ) {
		if ((n1 == 0 || n1 >= n2) && chanout != nil && slowread == len is.data) {
			chanout <-= "l2 Scanning... ";
			chanout <-= "pc "+string ((100*mcu)/nmcu);
			n1 = 0;
		}
		n1 ++;
		for(comp=0; comp<Ns; comp++) {
			dcht := h.dcht[Td[comp]];
			acht := h.acht[Ta[comp]];
			qt := h.qt[h.comp[comp].Tq];

			for(block:=0; block<H[comp]*V[comp]; block++) {
				# F-22
				t := jdecode(is, dcht);
				diff := jreceive(is, t);
				DC[comp] += diff;

				# F-23
				zz := data[comp][block];
				zz[0:] = zeroints;
				zz[0] = qt[0]*DC[comp];
				k = 1;

				for(;;) {
					rs := jdecode(is, acht);
					(rrrr, ssss) := nibbles(rs);
					if(ssss == 0){
						if(rrrr != 15)
							break;
						k += 16;
					}else{
						k += rrrr;
						z := jreceive(is, ssss);
						zz[zig[k]] = z*qt[k];
						if(k == 63)
							break;
						k++;
					}
				}

				idct(zz);
			}
		}

		# rotate colors to RGB and assign to bytes
		colormap(h, chans, data[0], data[1], data[2], mcu, nacross, Hmax, Vmax, H, V);

		# process restart marker, if present
		mcu++;
		if(ri>0 && mcu<nmcu && mcu%ri==0){
			jrestart(is, mcu);
			for(comp=0; comp<Ns; comp++)
				DC[comp] = 0;
		}
	}
	if (chanout != nil) chanout <-= "pc 100";
	return chans;
}

jrestart(is: ref ImageSource, mcu: int)
{
	h := is.jstate;
	ri := h.ri;
	restart := mcu/ri-1;
	rst, nskip: int;
	nskip = 0;
	do {
		do{
			rst = jnextborm(is);
			nskip++;
		}while(rst>=0 && rst!=16rFF);
		if(rst == 16rFF){
			rst = jnextborm(is);
			nskip++;
		}
	} while(rst>=0 && (rst&~7)!= RST);
	if(nskip != 2 || rst < 0 || ((rst&7) != (restart&7)))
		sys->print("Error: Jpeg restart problem");
	h.cnt = 0;
	h.sr = 0;
}

jc1: con 2871;		# 1.402 * 2048
jc2: con 705;		# 0.34414 * 2048
jc3: con 1463;		# 0.71414 * 2048
jc4: con 3629;		# 1.772 * 2048

CLAMPBOFF: con 300;
NCLAMPB: con CLAMPBOFF+256+CLAMPBOFF;
CLAMPNOFF: con 64;
NCLAMPN: con CLAMPNOFF+256+CLAMPNOFF;

clampb: array of byte;		# clamps byte values

init_tabs()
{
	j: int;
	clampb = array[NCLAMPB] of byte;
	for(j=0; j<CLAMPBOFF; j++)
		clampb[j] = byte 0;
	for(j=0; j<256; j++)
		clampb[CLAMPBOFF+j] = byte j;
	for(j=0; j<CLAMPBOFF; j++)
		clampb[CLAMPBOFF+256+j] = byte 16rFF;
}


# Fills in pixels (x,y) for x = minx=8*Hmax*(mcu%nacross), minx+1, ..., minx+8*Hmax-1 (or h.X-1, if less)
# and for y = miny=8*Vmax*(mcu/nacross), miny+1, ..., miny+8*Vmax-1 (or h.Y-1, if less)
colormap(h: ref Jpegstate, chans: array of array of byte, data0, data1, data2: array of array of int, mcu, nacross, Hmax, Vmax: int,  H, V: array of int)
{
	rpic := chans[0];
	gpic := chans[1];
	bpic := chans[2];
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
	for(y:=0; y<dy; y++) {
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
		for(x:=0; x<dx; x++) {
			rpic[pici+x] = clampb[data0[b0][y0+x0++*H0/Hmax] + 128 + CLAMPBOFF];
			gpic[pici+x] = clampb[data1[b1][y1+x1++*H1/Hmax] + 128 + CLAMPBOFF];
			bpic[pici+x] = clampb[data2[b2][y2+x2++*H2/Hmax] + 128 + CLAMPBOFF];
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
		}
		pici += h.X;
	}
}

# decode next 8-bit value from entropy-coded input.  chart F-26
jdecode(is: ref ImageSource, t: ref Huffman): int
{
	h := is.jstate;
	maxcode := t.maxcode;
	if(h.cnt < 8)
		jnextbyte(is);
	# fast lookup
	code := (h.sr>>(h.cnt-8))&16rFF;
	v := t.value[code];
	if(v >= 0){
		h.cnt -= t.shift[code];
		return v;
	}

	h.cnt -= 8;
	if(h.cnt == 0)
		jnextbyte(is);
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
			sr = jnextbyte(is);
			m = 16r80;
			cnt = 8;
		}
		cnt--;
	}
	h.cnt = cnt;
	return t.val[t.valptr[i]+(code-t.mincode[i])];
}

# load next byte of input
jnextbyte(is: ref ImageSource): int
{
	b :=getc(is);

	if(b == 16rFF) {
		b2 :=getc(is);
		if(b2 != 0) {
			if(b2 == int DNL)
				sys->print("Error: Jpeg  DNL marker unimplemented");
			# decoder is reading into marker; satisfy it and restore state
			ungetc2(is, byte b);
		}
	}
	h := is.jstate;
	h.cnt += 8;
	h.sr = (h.sr<<8)| b;
	return b;
}

ungetc2(is: ref ImageSource, nil: byte)
{
	if(is.i < 2) {
		if(is.i != 1)
			sys->print("Error: EXInternal: ungetc2 past beginning of buffer");
		is.i = 0;
	}
	else
		is.i -= 2;
}


getc(is: ref ImageSource) : int
{
	if(is.i >= len is.data) {
		sys->print("Error: premature eof");
	}
	if (is.i >= slowread)
		wait4data(is.i);
	return int is.data[is.i++];
}

# like jnextbyte, but look for marker too
jnextborm(is: ref ImageSource): int
{
	b :=getc(is);

	if(b == 16rFF)
		return b;
	h := is.jstate;
	h.cnt += 8;
	h.sr = (h.sr<<8)| b;
	return b;
}

# return next s bits of input, MSB first, and level shift it
jreceive(is: ref ImageSource, s: int): int
{
	h := is.jstate;
	while(h.cnt < s)
		jnextbyte(is);
	h.cnt -= s;
	v := h.sr >> h.cnt;
	m := (1<<s);
	v &= m-1;
	# level shift
	if(v < (m>>1))
		v += ~(m-1)+1;
	return v;
}

nibbles(c: int) : (int, int)
{
	return (c>>4, c&15);

}

# Scaled integer implementation.
# inverse two dimensional DCT, Chen-Wang algorithm
# (IEEE ASSP-32, pp. 803-816, Aug. 1984)
# 32-bit integer arithmetic (8 bit coefficients)
# 11 mults, 29 adds per DCT
#
# coefficients extended to 12 bit for IEEE1180-1990
# compliance

W1:	con 2841;	# 2048*sqrt(2)*cos(1*pi/16)
W2:	con 2676;	# 2048*sqrt(2)*cos(2*pi/16)
W3:	con 2408;	# 2048*sqrt(2)*cos(3*pi/16)
W5:	con 1609;	# 2048*sqrt(2)*cos(5*pi/16)
W6:	con 1108;	# 2048*sqrt(2)*cos(6*pi/16)
W7:	con 565;	# 2048*sqrt(2)*cos(7*pi/16)

W1pW7:	con 3406;	# W1+W7
W1mW7:	con 2276;	# W1-W7
W3pW5:	con 4017;	# W3+W5
W3mW5:	con 799;	# W3-W5
W2pW6:	con 3784;	# W2+W6
W2mW6:	con 1567;	# W2-W6

R2:	con 181;	# 256/sqrt(2)

idct(b: array of int)
{
	# transform horizontally
	for(y:=0; y<8; y++){
		eighty := y<<3;
		# if all non-DC components are zero, just propagate the DC term
		if(b[eighty+1]==0)
		if(b[eighty+2]==0 && b[eighty+3]==0)
		if(b[eighty+4]==0 && b[eighty+5]==0)
		if(b[eighty+6]==0 && b[eighty+7]==0){
			v := b[eighty]<<3;
			b[eighty+0] = v;
			b[eighty+1] = v;
			b[eighty+2] = v;
			b[eighty+3] = v;
			b[eighty+4] = v;
			b[eighty+5] = v;
			b[eighty+6] = v;
			b[eighty+7] = v;
			continue;
		}
		# prescale
		x0 := (b[eighty+0]<<11)+128;
		x1 := b[eighty+4]<<11;
		x2 := b[eighty+6];
		x3 := b[eighty+2];
		x4 := b[eighty+1];
		x5 := b[eighty+7];
		x6 := b[eighty+5];
		x7 := b[eighty+3];
		# first stage
		x8 := W7*(x4+x5);
		x4 = x8 + W1mW7*x4;
		x5 = x8 - W1pW7*x5;
		x8 = W3*(x6+x7);
		x6 = x8 - W3mW5*x6;
		x7 = x8 - W3pW5*x7;
		# second stage
		x8 = x0 + x1;
		x0 -= x1;
		x1 = W6*(x3+x2);
		x2 = x1 - W2pW6*x2;
		x3 = x1 + W2mW6*x3;
		x1 = x4 + x6;
		x4 -= x6;
		x6 = x5 + x7;
		x5 -= x7;
		# third stage
		x7 = x8 + x3;
		x8 -= x3;
		x3 = x0 + x2;
		x0 -= x2;
		x2 = (R2*(x4+x5)+128)>>8;
		x4 = (R2*(x4-x5)+128)>>8;
		# fourth stage
		b[eighty+0] = (x7+x1)>>8;
		b[eighty+1] = (x3+x2)>>8;
		b[eighty+2] = (x0+x4)>>8;
		b[eighty+3] = (x8+x6)>>8;
		b[eighty+4] = (x8-x6)>>8;
		b[eighty+5] = (x0-x4)>>8;
		b[eighty+6] = (x3-x2)>>8;
		b[eighty+7] = (x7-x1)>>8;
	}
	# transform vertically
	for(x:=0; x<8; x++){
		# if all non-DC components are zero, just propagate the DC term
		if(b[x+8*1]==0)
		if(b[x+8*2]==0 && b[x+8*3]==0)
		if(b[x+8*4]==0 && b[x+8*5]==0)
		if(b[x+8*6]==0 && b[x+8*7]==0){
			v := (b[x+8*0]+32)>>6;
			b[x+8*0] = v;
			b[x+8*1] = v;
			b[x+8*2] = v;
			b[x+8*3] = v;
			b[x+8*4] = v;
			b[x+8*5] = v;
			b[x+8*6] = v;
			b[x+8*7] = v;
			continue;
		}
		# prescale
		x0 := (b[x+8*0]<<8)+8192;
		x1 := b[x+8*4]<<8;
		x2 := b[x+8*6];
		x3 := b[x+8*2];
		x4 := b[x+8*1];
		x5 := b[x+8*7];
		x6 := b[x+8*5];
		x7 := b[x+8*3];
		# first stage
		x8 := W7*(x4+x5) + 4;
		x4 = (x8+W1mW7*x4)>>3;
		x5 = (x8-W1pW7*x5)>>3;
		x8 = W3*(x6+x7) + 4;
		x6 = (x8-W3mW5*x6)>>3;
		x7 = (x8-W3pW5*x7)>>3;
		# second stage
		x8 = x0 + x1;
		x0 -= x1;
		x1 = W6*(x3+x2) + 4;
		x2 = (x1-W2pW6*x2)>>3;
		x3 = (x1+W2mW6*x3)>>3;
		x1 = x4 + x6;
		x4 -= x6;
		x6 = x5 + x7;
		x5 -= x7;
		# third stage
		x7 = x8 + x3;
		x8 -= x3;
		x3 = x0 + x2;
		x0 -= x2;
		x2 = (R2*(x4+x5)+128)>>8;
		x4 = (R2*(x4-x5)+128)>>8;
		# fourth stage
		b[x+8*0] = (x7+x1)>>14;
		b[x+8*1] = (x3+x2)>>14;
		b[x+8*2] = (x0+x4)>>14;
		b[x+8*3] = (x8+x6)>>14;
		b[x+8*4] = (x8-x6)>>14;
		b[x+8*5] = (x0-x4)>>14;
		b[x+8*6] = (x3-x2)>>14;
		b[x+8*7] = (x7-x1)>>14;
	}
}

resample(src: array of byte, sw, sh: int, dw, dh: int) : array of byte
{
	if(src == nil || sw == 0 || sh == 0 || dw == 0 || dh == 0)
		return src;
	xfac := real sw / real dw;
	yfac := real sh / real dh;
	totpix := dw*dh;
	dst := array[totpix] of byte;
	dindex := 0;

	# precompute index in src row corresponding to each index in dst row
	sindices := array[dw] of int;
	dx := 0.0;
	for(x := 0; x < dw; x++) {
		sx := int dx;
		dx += xfac;
		if(sx >= sw)
			sx = sw-1;
		sindices[x] = sx;
	}
	dy := 0.0;
	for(y := 0; y < dh; y++) {
		sy := int dy;
		dy += yfac;
		if(sy >= sh)
			sy = sh-1;
		soffset := sy * sw;
		for(x = 0; x < dw; x++)
			dst[dindex++] = src[soffset + sindices[x]];
	}

	return dst;
}

Cr2r := array [256] of {
	-179, -178, -177, -175, -174, -172, -171, -170, -168, -167, -165, -164, -163, -161, -160, -158,
	-157, -156, -154, -153, -151, -150, -149, -147, -146, -144, -143, -142, -140, -139, -137, -136,
	-135, -133, -132, -130, -129, -128, -126, -125, -123, -122, -121, -119, -118, -116, -115, -114,
	-112, -111, -109, -108, -107, -105, -104, -102, -101, -100, -98, -97, -95, -94, -93, -91,
	-90, -88, -87, -86, -84, -83, -81, -80, -79, -77, -76, -74, -73, -72, -70, -69,
	-67, -66, -64, -63, -62, -60, -59, -57, -56, -55, -53, -52, -50, -49, -48, -46,
	-45, -43, -42, -41, -39, -38, -36, -35, -34, -32, -31, -29, -28, -27, -25, -24,
	-22, -21, -20, -18, -17, -15, -14, -13, -11, -10, -8, -7, -6, -4, -3, -1,
	0, 1, 3, 4, 6, 7, 8, 10, 11, 13, 14, 15, 17, 18, 20, 21,
	22, 24, 25, 27, 28, 29, 31, 32, 34, 35, 36, 38, 39, 41, 42, 43,
	45, 46, 48, 49, 50, 52, 53, 55, 56, 57, 59, 60, 62, 63, 64, 66,
	67, 69, 70, 72, 73, 74, 76, 77, 79, 80, 81, 83, 84, 86, 87, 88,
	90, 91, 93, 94, 95, 97, 98, 100, 101, 102, 104, 105, 107, 108, 109, 111,
	112, 114, 115, 116, 118, 119, 121, 122, 123, 125, 126, 128, 129, 130, 132, 133,
	135, 136, 137, 139, 140, 142, 143, 144, 146, 147, 149, 150, 151, 153, 154, 156,
	157, 158, 160, 161, 163, 164, 165, 167, 168, 170, 171, 172, 174, 175, 177, 178,
};

Cr2g := array [256] of {
	-91, -91, -90, -89, -89, -88, -87, -86, -86, -85, -84, -84, -83, -82, -81, -81,
	-80, -79, -79, -78, -77, -76, -76, -75, -74, -74, -73, -72, -71, -71, -70, -69,
	-69, -68, -67, -66, -66, -65, -64, -64, -63, -62, -61, -61, -60, -59, -59, -58,
	-57, -56, -56, -55, -54, -54, -53, -52, -51, -51, -50, -49, -49, -48, -47, -46,
	-46, -45, -44, -44, -43, -42, -41, -41, -40, -39, -39, -38, -37, -36, -36, -35,
	-34, -34, -33, -32, -31, -31, -30, -29, -29, -28, -27, -26, -26, -25, -24, -24,
	-23, -22, -21, -21, -20, -19, -19, -18, -17, -16, -16, -15, -14, -14, -13, -12,
	-11, -11, -10, -9, -9, -8, -7, -6, -6, -5, -4, -4, -3, -2, -1, -1,
	0, 1, 1, 2, 3, 4, 4, 5, 6, 6, 7, 8, 9, 9, 10, 11,
	11, 12, 13, 14, 14, 15, 16, 16, 17, 18, 19, 19, 20, 21, 21, 22,
	23, 24, 24, 25, 26, 26, 27, 28, 29, 29, 30, 31, 31, 32, 33, 34,
	34, 35, 36, 36, 37, 38, 39, 39, 40, 41, 41, 42, 43, 44, 44, 45,
	46, 46, 47, 48, 49, 49, 50, 51, 51, 52, 53, 54, 54, 55, 56, 56,
	57, 58, 59, 59, 60, 61, 61, 62, 63, 64, 64, 65, 66, 66, 67, 68,
	69, 69, 70, 71, 71, 72, 73, 74, 74, 75, 76, 76, 77, 78, 79, 79,
	80, 81, 81, 82, 83, 84, 84, 85, 86, 86, 87, 88, 89, 89, 90, 91,
};

Cb2g := array [256] of {
	-44, -44, -43, -43, -43, -42, -42, -42, -41, -41, -41, -40, -40, -40, -39, -39,
	-39, -38, -38, -38, -37, -37, -36, -36, -36, -35, -35, -35, -34, -34, -34, -33,
	-33, -33, -32, -32, -32, -31, -31, -31, -30, -30, -30, -29, -29, -29, -28, -28,
	-28, -27, -27, -26, -26, -26, -25, -25, -25, -24, -24, -24, -23, -23, -23, -22,
	-22, -22, -21, -21, -21, -20, -20, -20, -19, -19, -19, -18, -18, -18, -17, -17,
	-17, -16, -16, -15, -15, -15, -14, -14, -14, -13, -13, -13, -12, -12, -12, -11,
	-11, -11, -10, -10, -10, -9, -9, -9, -8, -8, -8, -7, -7, -7, -6, -6,
	-6, -5, -5, -4, -4, -4, -3, -3, -3, -2, -2, -2, -1, -1, -1, 0,
	0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5,
	6, 6, 6, 7, 7, 7, 8, 8, 8, 9, 9, 9, 10, 10, 10, 11,
	11, 11, 12, 12, 12, 13, 13, 13, 14, 14, 14, 15, 15, 15, 16, 16,
	17, 17, 17, 18, 18, 18, 19, 19, 19, 20, 20, 20, 21, 21, 21, 22,
	22, 22, 23, 23, 23, 24, 24, 24, 25, 25, 25, 26, 26, 26, 27, 27,
	28, 28, 28, 29, 29, 29, 30, 30, 30, 31, 31, 31, 32, 32, 32, 33,
	33, 33, 34, 34, 34, 35, 35, 35, 36, 36, 36, 37, 37, 38, 38, 38,
	39, 39, 39, 40, 40, 40, 41, 41, 41, 42, 42, 42, 43, 43, 43, 44,
};

Cb2b := array [256] of {
	-227, -225, -223, -222, -220, -218, -216, -214, -213, -211, -209, -207, -206, -204, -202, -200,
	-198, -197, -195, -193, -191, -190, -188, -186, -184, -183, -181, -179, -177, -175, -174, -172,
	-170, -168, -167, -165, -163, -161, -159, -158, -156, -154, -152, -151, -149, -147, -145, -144,
	-142, -140, -138, -136, -135, -133, -131, -129, -128, -126, -124, -122, -120, -119, -117, -115,
	-113, -112, -110, -108, -106, -105, -103, -101, -99, -97, -96, -94, -92, -90, -89, -87,
	-85, -83, -82, -80, -78, -76, -74, -73, -71, -69, -67, -66, -64, -62, -60, -58,
	-57, -55, -53, -51, -50, -48, -46, -44, -43, -41, -39, -37, -35, -34, -32, -30,
	-28, -27, -25, -23, -21, -19, -18, -16, -14, -12, -11, -9, -7, -5, -4, -2,
	0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 18, 19, 21, 23, 25, 27,
	28, 30, 32, 34, 35, 37, 39, 41, 43, 44, 46, 48, 50, 51, 53, 55,
	57, 58, 60, 62, 64, 66, 67, 69, 71, 73, 74, 76, 78, 80, 82, 83,
	85, 87, 89, 90, 92, 94, 96, 97, 99, 101, 103, 105, 106, 108, 110, 112,
	113, 115, 117, 119, 120, 122, 124, 126, 128, 129, 131, 133, 135, 136, 138, 140,
	142, 144, 145, 147, 149, 151, 152, 154, 156, 158, 159, 161, 163, 165, 167, 168,
	170, 172, 174, 175, 177, 179, 181, 183, 184, 186, 188, 190, 191, 193, 195, 197,
	198, 200, 202, 204, 206, 207, 209, 211, 213, 214, 216, 218, 220, 222, 223, 225,
};
