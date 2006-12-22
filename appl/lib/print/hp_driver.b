implement Pdriver;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Font, Rect, Point, Image, Screen: import draw;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "print.m";
	Printer: import Print;
include "scaler.m";
	scaler: Scaler;


K: con 0;
C: con 1;
M: con 2;
Y: con 3;
Clight: con 4;
Mlight: con 5;

HPTRUE: con 1;
HPFALSE: con 0;
TRUE: con 1;
FALSE: con 0;

# RGB pixel

RGB: adt {
	r, g, b: byte;
};


# KCMY pixel

KCMY: adt {
	k, c, m, y: byte;
};



DitherParms: adt {
	fNumPix: int;
	fInput: array of byte;
	fErr: array of int;
	fSymmetricFlag: int;
	fFEDRes: array of int;
	fRasterEvenOrOdd: int;
	fHifipe: int;
	fOutput1, fOutput2, fOutput3: array of byte;
};

# magic and wondrous HP colour maps
map1: array of KCMY;
map2: array of KCMY;

ABSOLUTE: con 1;
RELATIVE: con 0;

Compression := 1;

DEBUG := 0;
stderr: ref Sys->FD;
outbuf: ref Iobuf;

ESC: con 27;

# Palettes for Simple_Color

PALETTE_RGB: con 3;
PALETTE_CMY: con -3;
PALETTE_KCMY: con -4;
PALETTE_K: con 1;


# Initialization

init(debug: int)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	bufio = load Bufio Bufio->PATH;
	scaler = load Scaler Scaler->PATH;
	if (scaler == nil) fatal("Failed to load Scaler module");
	DEBUG = debug;
}


# Return printable area in pixels

printable_pixels(p: ref Printer): (int, int)
{
	HMARGIN: con 0.6;
	WMARGIN: con 0.3;
	winches := p.popt.paper.width_inches - 2.0*WMARGIN;
	hinches := p.popt.paper.height_inches - 2.0*HMARGIN;
	wres := real p.popt.mode.resx;
	hres := real p.popt.mode.resy;
	
	(x, y) := (int (winches*wres), int (hinches*hres));

	if (p.popt.orientation == Print->PORTRAIT)
		return (x, y);
	return (y, x);
}



# Send image to printer

MASK := array[] of {byte 1, byte 3, byte 15, byte 255, byte 255};
SHIFT := array[] of {7, 6, 4, 0};
GSFACTOR := array[] of {255.0, 255.0/3.0, 255.0/7.0, 1.0, 1.0};
lastp : ref Printer;

Refint: adt {
	value: int;
};

watchdog(cancel: chan of int, cancelled: ref Refint)
{
	<- cancel;
	cancelled.value = 1;
}

sendimage(p: ref Printer, pfd: ref Sys->FD, display: ref Draw->Display, im: ref Draw->Image, width: int, lmargin: int, cancel: chan of int): int
{
	grppid := sys->pctl(Sys->NEWPGRP, nil);
	cancelled := ref Refint(0);
	spawn watchdog(cancel, cancelled);

	outopen(pfd);
	dbg(sys->sprint("image depth=%d from %d,%d to %d,%d\n", im.depth, im.r.min.x, im.r.min.y, im.r.max.x, im.r.max.y));
	if (p != lastp) {
		(map1, map2) = readmaps(p);
		lastp = p;
	}

	bpp := im.depth;
	linechan := chan of array of int;
	if (p.popt.orientation == Print->PORTRAIT)
		InputWidth := im.r.max.x-im.r.min.x;
	else
		InputWidth = im.r.max.y-im.r.min.y;
	AdjustedInputWidth := (InputWidth+7) - ((InputWidth+7) % 8);
	dbg(sys->sprint("bpp=%d, InputWidth=%d, AdjustedInputWidth=%d\n",
						 bpp, InputWidth, AdjustedInputWidth));
	if (p.popt.orientation == Print->PORTRAIT)
		spawn row_by_row(im, linechan, AdjustedInputWidth);
	else
		spawn rotate(im, linechan, AdjustedInputWidth);
	DesiredOutputWidth := AdjustedInputWidth;
	if (width > AdjustedInputWidth)
		DesiredOutputWidth = width;
	ScaledWidth := 8*((DesiredOutputWidth)/8);
	mode := p.popt.mode;
	Nplanes := 4;
	if (map2 != nil)
		Nplanes += 2;
	Contone := array[Nplanes] of array of byte;
	ColorDepth := array[Nplanes] of int;
	ColorDepth[K] = mode.blackdepth;
	for (col:=1; col<Nplanes; col++)
		ColorDepth[col] = mode.coldepth;
	OutputWidth := array[Nplanes] of int;
	fDitherParms := array[Nplanes] of DitherParms;
	ErrBuff := array[Nplanes] of array of int;
	ColorPlane := array[Nplanes] of array of array of array of byte;
	MixedRes := 0;
	BaseResX := mode.resx;
	BaseResY := mode.resy;
	ResBoost := BaseResX / BaseResY;
	ResolutionX := array[Nplanes] of int;
	ResolutionY := array[Nplanes] of int;
	ResolutionX[K] = mode.resx*mode.blackresmult;
	ResolutionY[K] = mode.resy*mode.blackresmult;
	for (col=1; col<Nplanes; col++) {
		ResolutionX[col] = mode.resx;
		ResolutionY[col] = mode.resy;
	}
	NumRows := array[Nplanes] of int;
	for (j:=0; j<Nplanes; j++) {
		if (ResolutionX[j] != ResolutionX[K])
			MixedRes++;
		if (MixedRes)
			# means res(K) !+ res(C,M,Y)
			NumRows[j] = ResolutionX[j] / BaseResX;
		else
			NumRows[j]=1;
		OutputWidth[j]= ScaledWidth * NumRows[j] * ResBoost;
		PlaneSize:= OutputWidth[j]/8;
		Contone[j] = array[OutputWidth[j]] of byte;
		ColorPlane[j] = array[NumRows[j]] of array of array of  byte;
		for (jj:=0; jj<NumRows[j]; jj++) {
			ColorPlane[j][jj] = array[ColorDepth[j]] of array of  byte;
			for (jjj:=0; jjj<ColorDepth[j]; jjj++) {
				ColorPlane[j][jj][jjj] = array[PlaneSize] of byte;
			}
		}
		ErrBuff[j] = array[OutputWidth[j]+2] of {* => 0};
	}

	pcl_startjob(p);
	if (p.popt.paper.hpcode != "")
		PCL_Page_Size(p.popt.paper.hpcode);
	PCL_Move_CAP_H_Units(lmargin*300/BaseResX, ABSOLUTE);
	PCL_Configure_Raster_Data4(BaseResX, BaseResY, ColorDepth);
	PCL_Source_Raster_Width(ScaledWidth);
	PCL_Compression_Method(Compression);
	PCL_Start_Raster(1);
	cmap1 := setup_color_map(display, map1, im.depth);
	if (map2 != nil)
		cmap2 := setup_color_map(display, map2, im.depth);
	numerator, denominator: int;
	if ((ScaledWidth % AdjustedInputWidth)==0) {
		numerator = ScaledWidth / AdjustedInputWidth;
		denominator = 1;
	} else {
		numerator = ScaledWidth;
		denominator = AdjustedInputWidth;
	}
	rs := scaler->init(DEBUG, AdjustedInputWidth, numerator, denominator);
	rasterno := 0;
	col_row: array of int;
	eof := 0;

	while (!eof) {
		col_row = <- linechan;
		if (col_row == nil)
			eof++;
		scaler->rasterin(rs, col_row);
		while ((scaled_col_row := scaler->rasterout(rs)) != nil) {
			rasterno++;
			fRasterOdd := rasterno & 1;
			kcmy_row := SimpleColorMatch(cmap1, scaled_col_row);
			if (DEBUG) {
				dbg("Scaled Raster line:");
				for (q:=0; q<len scaled_col_row; q++) {
					(r, g, b) := display.cmap2rgb(scaled_col_row[q]);
					dbg(sys->sprint("%d rgb=(%d,%d,%d) kcmy=(%d,%d,%d,%d)\n", int scaled_col_row[q],
						r, g, b, int kcmy_row[q].k, int kcmy_row[q].c, int kcmy_row[q].m, int kcmy_row[q].y));
				}
				dbg("\n");
			}
			Contone_K := Contone[K];
			Contone_C := Contone[C];
			Contone_M := Contone[M];
			Contone_Y := Contone[Y];
			for (ii:=0; ii<len Contone[K]; ii++) {
				kcmy := kcmy_row[ii];
				Contone_K[ii] = kcmy.k;
				Contone_C[ii] = kcmy.c;
				Contone_M[ii] = kcmy.m;
				Contone_Y[ii] = kcmy.y;
			}
			if (map2 != nil) {		# For lighter inks
				kcmy_row_light := SimpleColorMatch(cmap2, scaled_col_row);
				Contone_Clight := Contone[Clight];
				Contone_Mlight := Contone[Mlight];
				for (ii=0; ii<len Contone[Clight]; ii++) {
					kcmy := kcmy_row_light[ii];
					Contone_Clight[ii] = kcmy.c;
					Contone_Mlight[ii] = kcmy.m;
				}
			}

			for (i:=0; i< Nplanes; i++) {
# Pixel multiply here!!
				fDitherParms[i].fNumPix = OutputWidth[i];
				fDitherParms[i].fInput = Contone[i];
				fDitherParms[i].fErr = ErrBuff[i];
#				fDitherParms[i].fErr++;		// serpentine (?)
				fDitherParms[i].fSymmetricFlag = 1;
#				if (i == K)
#					fDitherParms[i].fFEDResPtr = fBlackFEDResPtr;
#				else
#					fDitherParms[i].fFEDResPtr = fColorFEDResPtr;
				fDitherParms[i].fFEDRes = FEDarray;
				fDitherParms[i].fRasterEvenOrOdd = fRasterOdd;
				fDitherParms[i].fHifipe = ColorDepth[i] > 1;
				for (j=0; j < NumRows[i]; j++) {
					fDitherParms[i].fOutput1 = ColorPlane[i][j][0];
					if (fDitherParms[i].fHifipe)
						fDitherParms[i].fOutput2 = ColorPlane[i][j][1];
#					dbg(sys->sprint("Dither for Row %d ColorPlane[%d][%d]\n", rasterno, i, j));   
					Dither(fDitherParms[i]);
				}
			}

			FINALPLANE: con 3;
#			NfinalPlanes := 4;
			for (i=0; i<=FINALPLANE; i++) {
				cp_i := ColorPlane[i];
				coldepth_i := ColorDepth[i];
				finalrow := NumRows[i]-1;
				for (j=0; j<=finalrow; j++) {
					cp_i_j := cp_i[j];
					for (k:=0; k<coldepth_i; k++) {
						if (i == FINALPLANE && j == finalrow && k == coldepth_i-1)
							PCL_Transfer_Raster_Row(cp_i_j[k]);
						else 
							PCL_Transfer_Raster_Plane(cp_i_j[k]);
						if (cancelled.value) {
							PCL_Reset();
							outclose();
							killgrp(grppid);
							return -1;
						}
					}
				}
			}
		}
	}
	PCL_End_Raster();
	PCL_Reset();
	outclose();
	killgrp(grppid);
	if (cancelled.value)
		return -1;
#sys->print("dlen %d, clen %d overruns %d\n", dlen, clen, overruns);
	return 0;
}


# Send text to printer

sendtextfd(p: ref Print->Printer, pfd, tfd: ref Sys->FD, pointsize: real, proportional: int, wrap: int): int
{
	outopen(pfd);
	pcl_startjob(p);
	if (wrap) PCL_End_of_Line_Wrap(0);
	LATIN1: con "0N";
	PCL_Font_Symbol_Set(LATIN1);
	if (proportional) PCL_Font_Spacing(1);
	if (pointsize > 0.0) {
		PCL_Font_Height(pointsize);
		pitch := 10.0*12.0/pointsize;
		PCL_Font_Pitch(pitch);
		spacing := int (6.0*12.0/pointsize);
		PCL_Line_Spacing(spacing);
		dbg(sys->sprint("Text: pointsize %f pitch %f spacing %d\n", pointsize, pitch, spacing));
	}
	PCL_Line_Termination(3);
	inbuf := bufio->fopen(tfd, Bufio->OREAD);
	while ((line := inbuf.gets('\n')) != nil) {
		ob := array of byte line;
		outwrite(ob, len ob);
	}
	PCL_Reset();
	outclose();
	return 0;
}



# Common PCL start

pcl_startjob(p: ref Printer)
{
	PCL_Reset();
	if (p.popt.duplex) {
		esc("%-12345X@PJL DEFAULT DUPLEX=ON\n");
		esc("%-12345X");
	}
	if (p.popt.paper.hpcode != "")
		PCL_Page_Size(p.popt.paper.hpcode);
	PCL_Orientation(p.popt.orientation);
	PCL_Duplex(p.popt.duplex);
}


# Spawned to return  sequence of rotated image rows

rotate(im: ref Draw->Image, linechan: chan of array of int, adjwidth: int)
{
	xmin := im.r.min.x;	
	xmax := im.r.max.x;
	InputWidth := xmax - xmin;
	rawchan := chan of array of int;
	spawn row_by_row(im, rawchan, InputWidth);
	r_image := array[InputWidth] of {* => array [adjwidth] of {* => 0}};
	r_row := 0;
	while ((col_row := <- rawchan) != nil) {
		endy := len col_row - 1;
		for (i:=0; i<len col_row; i++)
			r_image[endy - i][r_row] = col_row[i];
		r_row++;
	}
	for (i:=0; i<len r_image; i++)
		linechan <-= r_image[i];
	linechan <-= nil;
}


# Spawned to return sequence of image rows

row_by_row(im: ref Draw->Image, linechan: chan of array of int, adjwidth: int)
{
	xmin := im.r.min.x;	
	ymin := im.r.min.y;	
	xmax := im.r.max.x;
	ymax := im.r.max.y;
	InputWidth := xmax - xmin;
	bpp := im.depth;
	ld := ldepth(im.depth);
	bytesperline := (InputWidth*bpp+7)/8;	
	rdata := array[bytesperline+10] of byte;
	pad0 := array [7] of { * => 0};
	for (y:=ymin; y<ymax; y++) {
		col_row := array[adjwidth] of int;
		rect := Rect((xmin, y), (xmax, y+1));
		np := im.readpixels(rect, rdata);
		if (np < 0)
			fatal("Error reading image\n");
		dbg(sys->sprint("Input Raster line %d: np=%d\n  ", y, np));
		ind := 0;
		mask := MASK[ld];
		shift := SHIFT[ld];
		col_row[adjwidth-7:] = pad0;	# Pad to adjusted width with white
		data := rdata[ind];
		for (q:=0; q<InputWidth; q++) {
			col := int ((data  >> shift) & mask);
			shift -= bpp;
			if (shift < 0) {
				shift = SHIFT[ld];
				ind++;
				data = rdata[ind];
			}
			col_row[q] = col;
		}
		linechan <-= col_row;
	}
	linechan <-= nil;
}


# PCL output routines


PCL_Reset()
{	
	esc("E");
}


PCL_Orientation(value: int)
{
	esc(sys->sprint("&l%dO", value));
}

PCL_Duplex(value: int)
{
	esc(sys->sprint("&l%dS", value));
}


PCL_Left_Margin(value: int)
{
	esc(sys->sprint("&a%dL", value));
}

PCL_Page_Size(value: string)
{
	esc(sys->sprint("&l%sA", value));
}


PCL_End_of_Line_Wrap(value: int)
{
	esc(sys->sprint("&s%dC", value));
}

PCL_Line_Termination(value: int)
{
	esc(sys->sprint("&k%dG", value));
}


PCL_Font_Symbol_Set(value: string)
{
	esc(sys->sprint("(%s", value));
}


PCL_Font_Pitch(value: real)
{
	esc(sys->sprint("(s%2.2fH", value));
}

PCL_Font_Spacing(value: int)
{
	esc(sys->sprint("(s%dP", value));
}

PCL_Font_Height(value: real)
{
	esc(sys->sprint("(s%2.2fV", value));
}

PCL_Line_Spacing(value: int)
{
	esc(sys->sprint("&l%dD", value));
}



PCL_Start_Raster(current: int)
{	
	flag := 0;
	if (current) flag = 1;
	esc(sys->sprint("*r%dA", flag));
}



PCL_End_Raster()
{	
	esc("*rC");
}


PCL_Raster_Resolution(ppi: int)
{	
	esc(sys->sprint("*t%dR", ppi));
}


PCL_Source_Raster_Width(pixels: int)
{	
	esc(sys->sprint("*r%dS", pixels));
}


PCL_Simple_Color(palette: int)
{	
	esc(sys->sprint("*r%dU", palette));
}

PCL_Compression_Method(ctype: int)
{
	esc(sys->sprint("*b%dM", ctype));

}


PCL_Move_CAP_V_Rows(pos: int, absolute: int)
{
	plus := "";
	if (!absolute && pos > 0) plus = "+";
	esc(sys->sprint("&a%s%dR", plus, pos));
}

PCL_Move_CAP_H_Cols(pos: int, absolute: int)
{
	plus := "";
	if (!absolute && pos > 0) plus = "+";
	esc(sys->sprint("&a%s%dC", plus, pos));
}

# These Units are 1/300 of an inch.

PCL_Move_CAP_H_Units(pos: int, absolute: int)
{
	plus := "";
	if (!absolute && pos > 0) plus = "+";
	esc(sys->sprint("*p%s%dX", plus, pos));
}



PCL_Move_CAP_V_Units(pos: int, absolute: int)
{
	plus := "";
	if (!absolute && pos > 0) plus = "+";
	esc(sys->sprint("*p%s%dY", plus, pos));
}



PCL_Configure_Raster_Data4(hres, vres: int, ColorDepth: array of int)
{	
	ncomponents := 4;
	msg := array[ncomponents*6 + 2] of byte;
	i := 0;
	msg[i++] = byte 2;	# Format
	msg[i++] = byte ncomponents;	# KCMY
	for (c:=0; c<ncomponents; c++) {
		msg[i++] = byte (hres/256);
		msg[i++] = byte (hres%256);
		msg[i++] = byte (vres/256);
		msg[i++] = byte (vres%256);

		depth := 1 << ColorDepth[c];
		msg[i++] = byte (depth/256);
		msg[i++] = byte (depth%256);
	}
	if (DEBUG) {
		dbg("CRD: ");
		for (ii:=0; ii<len msg; ii++) dbg(sys->sprint("%d(%x) ", int msg[ii], int msg[ii]));
		dbg("\n");
	}
	esc(sys->sprint("*g%dW", len msg));
	outwrite(msg, len msg);
}

dlen := 0;
clen := 0;
overruns := 0;
PCL_Transfer_Raster_Plane(data: array of byte)
{	
	if (DEBUG) {
		dbg("Transfer_Raster_Plane:");
		for (i:=0; i<len data; i++) dbg(sys->sprint(" %x", int data[i]));
		dbg("\n");
	}
	if (Compression) {
d := len data;
dlen += d;
		data = compress(data);
c := len data;
clen += c;
if (c > d)
	overruns += c-d;
		if (DEBUG) {
			dbg("Compressed Transfer_Raster_Plane:");
			for (i:=0; i<len data; i++) dbg(sys->sprint(" %x", int data[i]));
			dbg("\n");
		}
	}
	esc(sys->sprint("*b%dV", len data));
	outwrite(data, len data);
}


PCL_Transfer_Raster_Row(data: array of byte)
{
	if (DEBUG) {
		dbg("Transfer_Raster_Row:");
		for (i:=0; i<len data; i++) dbg(sys->sprint(" %x", int data[i]));
		dbg("\n");
	}
	if (Compression) {
		data = compress(data);	
		if (DEBUG) {
			dbg("Compressed Transfer_Raster_Row:");
			for (i:=0; i<len data; i++) dbg(sys->sprint(" %x", int data[i]));
			dbg("\n");
		}
	}
	esc(sys->sprint("*b%dW", len data));
	outwrite(data, len data);
}


outopen(fd: ref Sys->FD)
{
	outbuf = bufio->fopen(fd, Bufio->OWRITE);
	if (outbuf == nil) sys->fprint(stderr, "Failed to open output fd: %r\n");
}

outclose()
{
	outbuf.close();
}


# Write to output using buffered io

outwrite(data: array of byte, length: int)
{
	outbuf.write(data, length);
}


# Send escape code to printer

esc(s: string) 
{
	os := sys->sprint("%c%s", ESC, s);
	ob := array of byte os;
	outwrite(ob, len ob);
}


# Read all the maps
readmaps(p: ref Printer): (array of KCMY, array of KCMY)
{

	mapfile := p.ptype.hpmapfile;
	mapf1 := Pdriver->DATAPREFIX + mapfile + ".map";
	m1 := read_map(mapf1);
	if (m1 == nil) fatal("Failed to read map file");
	mapf2 := Pdriver->DATAPREFIX + mapfile + "_2.map";
	m2 := read_map(mapf2);
	return (m1, m2);
}


# Read a map file

read_map(mapfile: string) : array of KCMY
{
	mf := bufio->open(mapfile, bufio->OREAD);
	if (mf == nil) return nil;
	CUBESIZE: con 9*9*9;
	marray := array[CUBESIZE] of KCMY;
	i := 0;
	while (i <CUBESIZE && (lstr := bufio->mf.gets('\n')) != nil) {
		(n, toks) := sys->tokenize(lstr, " \t");
		if (n >= 4) {
			marray[i].k = byte int hd toks;
			toks = tl toks;
			marray[i].c = byte int hd toks;
			toks = tl toks;
			marray[i].m = byte int hd toks;
			toks = tl toks;
			marray[i].y = byte int hd toks;
			i++;
		}
	}
	return marray;
}




# Big interpolation routine

# static data
prev := RGB (byte 255, byte 255, byte 255);
result: KCMY;
offset := array[] of { 0, 1, 9, 10, 81, 82, 90, 91 };


Interpolate(map: array of KCMY, start: int, rgb: RGB, firstpixel: int): KCMY
{
	cyan := array[8] of int;
	magenta := array[8] of int;
	yellow := array[8] of int;
	black := array[8] of int;

	if (firstpixel || prev.r != rgb.r || prev.g != rgb.g || prev.b != rgb.b) {
		prev = rgb;
		for (j:=0; j<8; j++) {
			ioff := start+offset[j];
			cyan[j] = int map[ioff].c;
			magenta[j] = int map[ioff].m;
			yellow[j] = int map[ioff].y;
			black[j] = int map[ioff].k;
		}

		diff_red := int rgb.r & 16r1f;
		diff_green := int rgb.g & 16r1f;
		diff_blue := int rgb.b & 16r1f;


        result.c   = byte (((cyan[0] + ( ( (cyan[4] - cyan[0] ) * diff_red) >> 5)) + ( ( ((cyan[2] + ( ( (cyan[6] - cyan[2] ) * diff_red) >> 5)) -(cyan[0] + ( ( (cyan[4] - cyan[0] ) * diff_red) >> 5)) ) * diff_green) >> 5)) + ( ( (((cyan[1] + ( ( (cyan[5] - cyan[1] ) * diff_red) >> 5)) + ( ( ((cyan[3] + ( ( (cyan[7] - cyan[3] ) * diff_red) >> 5)) -(cyan[1] + ( ( (cyan[5] - cyan[1] ) * diff_red) >> 5)) ) * diff_green) >> 5)) -((cyan[0] + ( ( (cyan[4] - cyan[0] ) * diff_red) >> 5)) + ( ( ((cyan[2] + ( ( (cyan[6] - cyan[2] ) * diff_red) >> 5)) -(cyan[0] + ( ( (cyan[4] - cyan[0] ) * diff_red) >> 5)) ) * diff_green) >> 5)) ) * diff_blue) >> 5));

        result.m = byte (((magenta[0] + ( ( (magenta[4] - magenta[0] ) * diff_red) >> 5)) + ( ( ((magenta[2] + ( ( (magenta[6] - magenta[2] ) * diff_red) >> 5)) -(magenta[0] + ( ( (magenta[4] - magenta[0] ) * diff_red) >> 5)) ) * diff_green) >> 5)) + ( ( (((magenta[1] + ( ( (magenta[5] - magenta[1] ) * diff_red) >> 5)) + ( ( ((magenta[3] + ( ( (magenta[7] - magenta[3] ) * diff_red) >> 5)) -(magenta[1] + ( ( (magenta[5] - magenta[1] ) * diff_red) >> 5)) ) * diff_green) >> 5)) -((magenta[0] + ( ( (magenta[4] - magenta[0] ) * diff_red) >> 5)) + ( ( ((magenta[2] + ( ( (magenta[6] - magenta[2] ) * diff_red) >> 5)) -(magenta[0] + ( ( (magenta[4] - magenta[0] ) * diff_red) >> 5)) ) * diff_green) >> 5)) ) * diff_blue) >> 5));

        result.y = byte (((yellow[0] + ( ( (yellow[4] - yellow[0] ) * diff_red) >> 5)) + ( ( ((yellow[2] + ( ( (yellow[6] - yellow[2] ) * diff_red) >> 5)) -(yellow[0] + ( ( (yellow[4] - yellow[0] ) * diff_red) >> 5)) ) * diff_green) >> 5)) + ( ( (((yellow[1] + ( ( (yellow[5] - yellow[1] ) * diff_red) >> 5)) + ( ( ((yellow[3] + ( ( (yellow[7] - yellow[3] ) * diff_red) >> 5)) -(yellow[1] + ( ( (yellow[5] - yellow[1] ) * diff_red) >> 5)) ) * diff_green) >> 5)) -((yellow[0] + ( ( (yellow[4] - yellow[0] ) * diff_red) >> 5)) + ( ( ((yellow[2] + ( ( (yellow[6] - yellow[2] ) * diff_red) >> 5)) -(yellow[0] + ( ( (yellow[4] - yellow[0] ) * diff_red) >> 5)) ) * diff_green) >> 5)) ) * diff_blue) >> 5));

        result.k  = byte (((black[0] + ( ( (black[4] - black[0] ) * diff_red) >> 5)) + ( ( ((black[2] + ( ( (black[6] - black[2] ) * diff_red) >> 5)) -(black[0] + ( ( (black[4] - black[0] ) * diff_red) >> 5)) ) * diff_green) >> 5)) + ( ( (((black[1] + ( ( (black[5] - black[1] ) * diff_red) >> 5)) + ( ( ((black[3] + ( ( (black[7] - black[3] ) * diff_red) >> 5)) -(black[1] + ( ( (black[5] - black[1] ) * diff_red) >> 5)) ) * diff_green) >> 5)) -((black[0] + ( ( (black[4] - black[0] ) * diff_red) >> 5)) + ( ( ((black[2] + ( ( (black[6] - black[2] ) * diff_red) >> 5)) -(black[0] + ( ( (black[4] - black[0] ) * diff_red) >> 5)) ) * diff_green) >> 5)) ) * diff_blue) >> 5));

	}
	return result;
}

# Colour RGB to KCMY convertor

ColorMatch(map: array of KCMY, row: array of RGB): array of KCMY
{
	kcmy := array[len row] of KCMY;
	first := 1;
	for (i:=0; i<len row; i++) {
		r := int row[i].r;
		g := int row[i].g;
		b := int row[i].b;
		start := ((r & 16re0) << 1) + ((r & 16re0) >> 1) + (r >> 5) +
				((g & 16re0) >> 2) + (g >> 5) + (b >> 5);
		kcmy[i] =  Interpolate(map, start, row[i],  first);
#		dbg(sys->sprint("+++ for (%d,%d,%d) Interpolate returned (%d,%d,%d,%d)\n", r, g, b, int kcmy[i].k, int kcmy[i].c, int kcmy[i].m, int kcmy[i].y));
		first = 0;
	}
	return kcmy;
}


# Simple version of above to lookup precalculated values

SimpleColorMatch(cmap: array of KCMY, colrow: array of int): array of KCMY
{
	ncolrow := len colrow;
	kcmy_row := array[ncolrow] of KCMY;
	for (i:=0; i<ncolrow; i++) 
		kcmy_row[i] = cmap[colrow[i]];
	return kcmy_row;
}


ldepth(d: int): int
{
	if(d & (d-1) || d >= 16)
		return 4;
	for(i := 0; i < 3; i++)
		if(d <= (1<<i))
			break;
	return i;
}


# Set up color map once and for all

setup_color_map(display: ref Display, map: array of KCMY, depth: int): array of KCMY
{
	gsfactor := GSFACTOR[ldepth(depth)];
	bpp := depth;
	max := 1 << bpp;
	rgb_row := array[max] of RGB;
	for (i:=0; i<max; i++) {
		if (depth >= 8) {
			(r, g, b) := display.cmap2rgb(i);
			rgb_row[i] = RGB (byte r, byte g, byte b);
		} else {	# BW or Greyscale
			grey := byte (255-int (real i * gsfactor));
			rgb_row[i] = RGB (grey, grey, grey);
		}
	}
	kcmy_row := ColorMatch(map, rgb_row);

	return kcmy_row;
}



# Dithering

tmpShortStore: int;
diffusionErrorPtr := 1;	# for serpentine??
errPtr: array of int;
rasterByte1 := 0;
rasterByte2 := 0;

rand8 := array [8] of int;
pad8 := array [8] of {* => 0};

Dither(ditherParms: DitherParms)
{
	errPtr = ditherParms.fErr;
	numLoop := ditherParms.fNumPix;
	inputPtr := 0;    
	fedResTbl := ditherParms.fFEDRes;
	symmetricFlag := ditherParms.fSymmetricFlag;
	doNext8Pixels : int;
	hifipe := ditherParms.fHifipe;        
	outputPtr1 := 0;
	outputPtr2 := 0;
	diffusionErrorPtr = 1;
	fInput := ditherParms.fInput;

	if(ditherParms.fRasterEvenOrOdd) {
		tmpShortStore = errPtr[diffusionErrorPtr];
		errPtr[diffusionErrorPtr]  = 0;

		for (pixelCount := numLoop + 8; (pixelCount -= 8) > 0; ) {
			if (pixelCount > 16) {
				# if next 16 pixels are white, skip 8
#				doNext8Pixels = Forward16PixelsNonWhite(fInput, inputPtr);
				doNext8Pixels = 0;
				lim := inputPtr + 16;
				for (i := inputPtr; i < lim; i++) {
					if (fInput[i] != byte 0) {
						doNext8Pixels = 1;
						break;
					}
				}
			} else {
				doNext8Pixels = 1;
			}
			if (doNext8Pixels) {
FORWARD_FED8(fInput, inputPtr, fedResTbl);
inputPtr += 8;
#				HPRand8();
#				FORWARD_FED(rand8[0], 16r80, fInput[inputPtr++], fedResTbl);
#				FORWARD_FED(rand8[1], 16r40, fInput[inputPtr++], fedResTbl);
#				FORWARD_FED(rand8[2], 16r20, fInput[inputPtr++], fedResTbl);
#				FORWARD_FED(rand8[3], 16r10, fInput[inputPtr++], fedResTbl);
#				FORWARD_FED(rand8[4], 16r08, fInput[inputPtr++], fedResTbl);
#				FORWARD_FED(rand8[5], 16r04, fInput[inputPtr++], fedResTbl);
#				FORWARD_FED(rand8[6], 16r02, fInput[inputPtr++], fedResTbl);
#				FORWARD_FED(rand8[7], 16r01, fInput[inputPtr++], fedResTbl);

				ditherParms.fOutput1[outputPtr1++] = byte rasterByte1;   
				rasterByte1 = 0; 

				if (hifipe) {      
					ditherParms.fOutput2[outputPtr2++] = byte rasterByte2;
					rasterByte2 = 0;  
				}
			} else {
				 # Do white space skipping
				inputPtr += 8;
				ditherParms.fOutput1[outputPtr1++] = byte 0;
				if (hifipe) {      
	 				ditherParms.fOutput2[outputPtr2++] = byte 0;
				}
				errPtr[diffusionErrorPtr:] = pad8;
				diffusionErrorPtr += 8;
		
				rasterByte1 = 0;
				rasterByte2 = 0;
				tmpShortStore = 0;
			}
		} # for pixelCount
	} else {
		rasterByte1 = 0;
		rasterByte2 = 0;
		inputPtr  += ( numLoop-1 );
		outputPtr1 += ( numLoop/8 - 1 ); 
		outputPtr2 += ( numLoop/8 - 1 );
		diffusionErrorPtr += ( numLoop-1 ); 

		tmpShortStore = errPtr[diffusionErrorPtr];  
		errPtr[diffusionErrorPtr] = 0;

        	for (pixelCount := numLoop + 8; (pixelCount -= 8) > 0; ) {
			if (pixelCount > 16) {
				# if next 16 pixels are white, skip 8
#				doNext8Pixels = Backward16PixelsNonWhite(fInput, inputPtr);
				doNext8Pixels = 0;
				lim := inputPtr - 16;
				for (i := inputPtr; i > lim; i--) {
					if (fInput[i] != byte 0) {
						doNext8Pixels = 1;
						break;
					}
				}
			} else {
				doNext8Pixels = HPTRUE;
			}

			if (doNext8Pixels) {
				BACKWARD_FED8(fInput, inputPtr, fedResTbl);
				inputPtr -= 8;
#				HPRand8();
#				BACKWARD_FED(rand8[0], 16r01, fInput[inputPtr--], fedResTbl);
#				BACKWARD_FED(rand8[1], 16r02, fInput[inputPtr--], fedResTbl);
#				BACKWARD_FED(rand8[2], 16r04, fInput[inputPtr--], fedResTbl);
#				BACKWARD_FED(rand8[3], 16r08, fInput[inputPtr--], fedResTbl);
#				BACKWARD_FED(rand8[4], 16r10, fInput[inputPtr--], fedResTbl);
#				BACKWARD_FED(rand8[5], 16r20, fInput[inputPtr--], fedResTbl);
#				BACKWARD_FED(rand8[6], 16r40, fInput[inputPtr--], fedResTbl);
#				BACKWARD_FED(rand8[7], 16r80, fInput[inputPtr--], fedResTbl);

				ditherParms.fOutput1[outputPtr1-- ]= byte rasterByte1;  
				rasterByte1 = 0; 

				if (hifipe) {
					ditherParms.fOutput2[outputPtr2--] = byte rasterByte2;
					rasterByte2 = 0;
				}
			} else {
				# Do white space skipping
				inputPtr -= 8;
				ditherParms.fOutput1[outputPtr1--] = byte 0;
				if (hifipe) {
					ditherParms.fOutput2[outputPtr2--] = byte 0;
				}
				diffusionErrorPtr -= 8;
  				errPtr[diffusionErrorPtr:] = pad8;

                		rasterByte1 = 0;
				rasterByte2 = 0;
				tmpShortStore = 0;
			}
		}
	}
}



# Take a step back

Backward16PixelsNonWhite(ba: array of byte, inputPtr: int): int
{
	lim := inputPtr - 16;
	for (i := inputPtr; i > lim; i--) {
		if (ba[i] != byte 0)
			return TRUE;
	}
	return FALSE;
}

# Take a step forward

Forward16PixelsNonWhite(ba: array of byte, inputPtr: int): int
{
	lim := inputPtr + 16;
	for (i := inputPtr; i < lim; i++) {
		if (ba[i] != byte 0)
			return TRUE;
	}
	return FALSE;
}

FORWARD_FED8(input: array of byte, ix: int, fedResTbl: array of int)
{
	HPRand8();
	randix := 0;

	for (bitMask := 16r80; bitMask; bitMask >>= 1) {
		tone := int input[ix++];
		fedResPtr := tone << 2;
		level := fedResTbl[fedResPtr];
		if (tone != 0) {
			tone = ( tmpShortStore + int fedResTbl[fedResPtr+1] );
			if (tone >= rand8[randix++]) {
				tone -= 255;
				level++;
			}
			case (level) {
			0=>
				break;
			1=>
				rasterByte1 |= bitMask;
				break;
			2=>
				rasterByte2 |= bitMask;
				break;
			3=>
				rasterByte2 |= bitMask; rasterByte1 |= bitMask;
				break;
			4=>
				break;
			5=>
				rasterByte1 |= bitMask;
				break;
			6=>
				rasterByte2 |= bitMask;
				break;
			7=>
				rasterByte2 |= bitMask; rasterByte1 |= bitMask;
				break;
			}
		} else {
			tone = tmpShortStore;
		}
		halftone := tone >> 1;
		errPtr[diffusionErrorPtr++] = halftone;
		tmpShortStore = errPtr[diffusionErrorPtr] + (tone - halftone);
	}
}

#FORWARD_FED(thresholdValue: int, bitMask: int, toneb: byte, fedResTbl : array of int)
#{
#	tone := int toneb;
#	fedResPtr := (tone << 2);
#	level := fedResTbl[fedResPtr];
#	if (tone != 0) {
#		tone = ( tmpShortStore + int fedResTbl[fedResPtr+1] );
#		if (tone >= thresholdValue) {
#			tone -= 255;
#			level++;
#		}
#		case (level) {
#		0=>
#			break;
#		1=>
#			rasterByte1 |= bitMask;
#			break;
#		2=>
#			rasterByte2 |= bitMask;
#			break;
#		3=>
#			rasterByte2 |= bitMask; rasterByte1 |= bitMask;
#			break;
#		4=>
#			break;
#		5=>
#			rasterByte1 |= bitMask;
#			break;
#		6=>
#			rasterByte2 |= bitMask;
#			break;
#		7=>
#			rasterByte2 |= bitMask; rasterByte1 |= bitMask;
#			break;
#		}
#	} else {
#		tone = tmpShortStore;
#	}
#	halftone := tone >> 1;
#	errPtr[diffusionErrorPtr++] = halftone;
#	tmpShortStore = errPtr[diffusionErrorPtr] + (tone - halftone);
##	dbg(sys->sprint("FORWARD_FED: thresh %d bitMask %x toneb %d => rasterbytes %d,%d,%d\n", thresholdValue, bitMask, int toneb, rasterByte1, rasterByte2));
#}

BACKWARD_FED8(input: array of byte, ix: int, fedResTbl: array of int)
{
	HPRand8();
	randix := 0;

	for (bitMask := 16r01; bitMask <16r100; bitMask <<= 1) {
		tone := int input[ix--];
		fedResPtr := (tone << 2);
		level := fedResTbl[fedResPtr];
		if (tone != 0) {
			tone = ( tmpShortStore + int fedResTbl[fedResPtr+1] );
			if (tone >= rand8[randix++]) {
				tone -= 255;
				level++;
			}
			case (level) {
			0=>
				break;
			1=>
				rasterByte1 |= bitMask;
				break;
			2=>
				rasterByte2 |= bitMask;
				break;
			3=>
				rasterByte2 |= bitMask; rasterByte1 |= bitMask;
				break;
			4=>
				break;
			5=>
				rasterByte1 |= bitMask;
				break;
			6=>
				rasterByte2 |= bitMask;
				break;
			7=>
				rasterByte2 |= bitMask; rasterByte1 |= bitMask;
				break;
			}
		} else {
			tone = tmpShortStore;
		 }
		halftone := tone >> 1;
		errPtr[diffusionErrorPtr--] = halftone;
		tmpShortStore = errPtr[diffusionErrorPtr] + (tone - halftone);
	}
}


#BACKWARD_FED(thresholdValue: int, bitMask: int, toneb: byte, fedResTbl : array of int)
#{
#	tone := int toneb;
#	fedResPtr := (tone << 2);
#	level := fedResTbl[fedResPtr];
#	if (tone != 0) {
#		tone = ( tmpShortStore + int fedResTbl[fedResPtr+1] );
#		if (tone >= thresholdValue) {
#			tone -= 255;
#			level++;
#		}
#		case (level) {
#		0=>
#			break;
#		1=>
#			rasterByte1 |= bitMask;
#			break;
#		2=>
#			rasterByte2 |= bitMask;
#			break;
#		3=>
#			rasterByte2 |= bitMask; rasterByte1 |= bitMask;
#			break;
#		4=>
#			break;
#		5=>
#			rasterByte1 |= bitMask;
#			break;
#		6=>
#			rasterByte2 |= bitMask;
#			break;
#		7=>
#			rasterByte2 |= bitMask; rasterByte1 |= bitMask;
#			break;
#		}
#	} else {
#		tone = tmpShortStore;
#	 }
#	halftone := tone >> 1;
#	errPtr[diffusionErrorPtr--] = halftone;
#	tmpShortStore = errPtr[diffusionErrorPtr] + (tone - halftone);
##	dbg(sys->sprint("BACWARD_FED: thresh %d bitMask %x toneb %d => rasterbytes %d,%d,%d\n", thresholdValue, bitMask, int toneb, rasterByte1, rasterByte2));
#}


# Pixel replication

pixrep(in: array of RGB): array of RGB
{
	out := array[2*len in] of RGB;
	for (i:=0; i<len in; i++) {
		out[i*2] = in[i];
		out[i*2+1] = in[i];
	}
	return out;
}






# Random numbers

IM: con 139968;
IA: con  3877;
IC: con 29573;

last := 42;

# Use a really simple and quick random number generator

HPRand(): int
{
	return (74 * (last = (last* IA + IC) % IM) / IM ) + 5;
}

HPRand8()
{
	for (i:= 0; i < 8; i++)
		rand8[i] = (74 * (last = (last* IA + IC) % IM) / IM ) + 5;
}

# Compression

compress(rawdata: array of byte): array of byte
{
	nraw := len rawdata;
	comp := array [2*nraw] of byte;	# worst case
	ncomp := 0;
	for (i:=0; i<nraw;) {
		rpt := 0;
		val := rawdata[i++];
		while (i<nraw && rpt < 255 && rawdata[i] == val) {
			rpt++;
			i++;
		}
		comp[ncomp++] = byte rpt;
		comp[ncomp++] = val;
	}
	return comp[0:ncomp];
}



# Print error message and exit

fatal(s: string)
{
	sys->fprint(stderr, "%s\n", s);
	exit;
}

killgrp(pid: int)
{
	sys->fprint(sys->open("/prog/" + string pid +"/ctl", Sys->OWRITE), "killgrp");
}


dbg(s: string)
{
	if (DEBUG) sys->fprint(stderr, "%s", s);
}



# Uninteresting constants

FEDarray := array[1024] of
{
   0 ,    0 ,    0 ,    0 ,
   0 ,    0 ,    0 ,    0 ,
   0 ,    2 ,    0 ,    0 ,
   0 ,    3 ,    0 ,    0 ,
   0 ,    4 ,    0 ,    0 ,
   0 ,    5 ,    0 ,    0 ,
   0 ,    6 ,    0 ,    0 ,
   0 ,    7 ,    0 ,    0 ,
   0 ,    8 ,    0 ,    0 ,
   0 ,    9 ,    0 ,    0 ,
   0 ,   10 ,    0 ,    0 ,
   0 ,   11 ,    0 ,    0 ,
   0 ,   12 ,    0 ,    0 ,
   0 ,   13 ,    0 ,    0 ,
   0 ,   14 ,    0 ,    0 ,
   0 ,   15 ,    0 ,    0 ,
   0 ,   16 ,    0 ,    0 ,
   0 ,   17 ,    0 ,    0 ,
   0 ,   18 ,    0 ,    0 ,
   0 ,   19 ,    0 ,    0 ,
   0 ,   20 ,    0 ,    0 ,
   0 ,   21 ,    0 ,    0 ,
   0 ,   22 ,    0 ,    0 ,
   0 ,   23 ,    0 ,    0 ,
   0 ,   24 ,    0 ,    0 ,
   0 ,   25 ,    0 ,    0 ,
   0 ,   26 ,    0 ,    0 ,
   0 ,   27 ,    0 ,    0 ,
   0 ,   28 ,    0 ,    0 ,
   0 ,   29 ,    0 ,    0 ,
   0 ,   30 ,    0 ,    0 ,
   0 ,   31 ,    0 ,    0 ,
   0 ,   32 ,    0 ,    0 ,
   0 ,   33 ,    0 ,    0 ,
   0 ,   34 ,    0 ,    0 ,
   0 ,   35 ,    0 ,    0 ,
   0 ,   36 ,    0 ,    0 ,
   0 ,   37 ,    0 ,    0 ,
   0 ,   38 ,    0 ,    0 ,
   0 ,   39 ,    0 ,    0 ,
   0 ,   40 ,    0 ,    0 ,
   0 ,   41 ,    0 ,    0 ,
   0 ,   42 ,    0 ,    0 ,
   0 ,   43 ,    0 ,    0 ,
   0 ,   44 ,    0 ,    0 ,
   0 ,   45 ,    0 ,    0 ,
   0 ,   46 ,    0 ,    0 ,
   0 ,   47 ,    0 ,    0 ,
   0 ,   48 ,    0 ,    0 ,
   0 ,   49 ,    0 ,    0 ,
   0 ,   50 ,    0 ,    0 ,
   0 ,   51 ,    0 ,    0 ,
   0 ,   52 ,    0 ,    0 ,
   0 ,   53 ,    0 ,    0 ,
   0 ,   54 ,    0 ,    0 ,
   0 ,   55 ,    0 ,    0 ,
   0 ,   56 ,    0 ,    0 ,
   0 ,   57 ,    0 ,    0 ,
   0 ,   58 ,    0 ,    0 ,
   0 ,   59 ,    0 ,    0 ,
   0 ,   60 ,    0 ,    0 ,
   0 ,   61 ,    0 ,    0 ,
   0 ,   62 ,    0 ,    0 ,
   0 ,   63 ,    0 ,    0 ,
   0 ,   64 ,    0 ,    0 ,
   0 ,   65 ,    0 ,    0 ,
   0 ,   66 ,    0 ,    0 ,
   0 ,   67 ,    0 ,    0 ,
   0 ,   68 ,    0 ,    0 ,
   0 ,   69 ,    0 ,    0 ,
   0 ,   70 ,    0 ,    0 ,
   0 ,   71 ,    0 ,    0 ,
   0 ,   72 ,    0 ,    0 ,
   0 ,   73 ,    0 ,    0 ,
   0 ,   74 ,    0 ,    0 ,
   0 ,   75 ,    0 ,    0 ,
   0 ,   76 ,    0 ,    0 ,
   0 ,   77 ,    0 ,    0 ,
   0 ,   78 ,    0 ,    0 ,
   0 ,   79 ,    0 ,    0 ,
   0 ,   80 ,    0 ,    0 ,
   0 ,   81 ,    0 ,    0 ,
   0 ,   82 ,    0 ,    0 ,
   0 ,   83 ,    0 ,    0 ,
   0 ,   84 ,    0 ,    0 ,
   0 ,   85 ,    0 ,    0 ,
   0 ,   86 ,    0 ,    0 ,
   0 ,   87 ,    0 ,    0 ,
   0 ,   88 ,    0 ,    0 ,
   0 ,   89 ,    0 ,    0 ,
   0 ,   90 ,    0 ,    0 ,
   0 ,   91 ,    0 ,    0 ,
   0 ,   92 ,    0 ,    0 ,
   0 ,   93 ,    0 ,    0 ,
   0 ,   94 ,    0 ,    0 ,
   0 ,   95 ,    0 ,    0 ,
   0 ,   96 ,    0 ,    0 ,
   0 ,   97 ,    0 ,    0 ,
   0 ,   98 ,    0 ,    0 ,
   0 ,   99 ,    0 ,    0 ,
   0 ,  100 ,    0 ,    0 ,
   0 ,  101 ,    0 ,    0 ,
   0 ,  102 ,    0 ,    0 ,
   0 ,  103 ,    0 ,    0 ,
   0 ,  104 ,    0 ,    0 ,
   0 ,  105 ,    0 ,    0 ,
   0 ,  106 ,    0 ,    0 ,
   0 ,  107 ,    0 ,    0 ,
   0 ,  108 ,    0 ,    0 ,
   0 ,  109 ,    0 ,    0 ,
   0 ,  110 ,    0 ,    0 ,
   0 ,  111 ,    0 ,    0 ,
   0 ,  112 ,    0 ,    0 ,
   0 ,  113 ,    0 ,    0 ,
   0 ,  114 ,    0 ,    0 ,
   0 ,  115 ,    0 ,    0 ,
   0 ,  116 ,    0 ,    0 ,
   0 ,  117 ,    0 ,    0 ,
   0 ,  118 ,    0 ,    0 ,
   0 ,  119 ,    0 ,    0 ,
   0 ,  120 ,    0 ,    0 ,
   0 ,  121 ,    0 ,    0 ,
   0 ,  122 ,    0 ,    0 ,
   0 ,  123 ,    0 ,    0 ,
   0 ,  124 ,    0 ,    0 ,
   0 ,  125 ,    0 ,    0 ,
   0 ,  126 ,    0 ,    0 ,
   0 ,  127 ,    0 ,    0 ,
   0 ,  128 ,    0 ,    0 ,
   0 ,  129 ,    0 ,    0 ,
   0 ,  130 ,    0 ,    0 ,
   0 ,  131 ,    0 ,    0 ,
   0 ,  132 ,    0 ,    0 ,
   0 ,  133 ,    0 ,    0 ,
   0 ,  134 ,    0 ,    0 ,
   0 ,  135 ,    0 ,    0 ,
   0 ,  136 ,    0 ,    0 ,
   0 ,  137 ,    0 ,    0 ,
   0 ,  138 ,    0 ,    0 ,
   0 ,  139 ,    0 ,    0 ,
   0 ,  140 ,    0 ,    0 ,
   0 ,  141 ,    0 ,    0 ,
   0 ,  142 ,    0 ,    0 ,
   0 ,  143 ,    0 ,    0 ,
   0 ,  144 ,    0 ,    0 ,
   0 ,  145 ,    0 ,    0 ,
   0 ,  146 ,    0 ,    0 ,
   0 ,  147 ,    0 ,    0 ,
   0 ,  148 ,    0 ,    0 ,
   0 ,  149 ,    0 ,    0 ,
   0 ,  150 ,    0 ,    0 ,
   0 ,  151 ,    0 ,    0 ,
   0 ,  152 ,    0 ,    0 ,
   0 ,  153 ,    0 ,    0 ,
   0 ,  154 ,    0 ,    0 ,
   0 ,  155 ,    0 ,    0 ,
   0 ,  156 ,    0 ,    0 ,
   0 ,  157 ,    0 ,    0 ,
   0 ,  158 ,    0 ,    0 ,
   0 ,  159 ,    0 ,    0 ,
   0 ,  160 ,    0 ,    0 ,
   0 ,  161 ,    0 ,    0 ,
   0 ,  162 ,    0 ,    0 ,
   0 ,  163 ,    0 ,    0 ,
   0 ,  164 ,    0 ,    0 ,
   0 ,  165 ,    0 ,    0 ,
   0 ,  166 ,    0 ,    0 ,
   0 ,  167 ,    0 ,    0 ,
   0 ,  168 ,    0 ,    0 ,
   0 ,  169 ,    0 ,    0 ,
   0 ,  170 ,    0 ,    0 ,
   0 ,  171 ,    0 ,    0 ,
   0 ,  172 ,    0 ,    0 ,
   0 ,  173 ,    0 ,    0 ,
   0 ,  174 ,    0 ,    0 ,
   0 ,  175 ,    0 ,    0 ,
   0 ,  176 ,    0 ,    0 ,
   0 ,  177 ,    0 ,    0 ,
   0 ,  178 ,    0 ,    0 ,
   0 ,  179 ,    0 ,    0 ,
   0 ,  180 ,    0 ,    0 ,
   0 ,  181 ,    0 ,    0 ,
   0 ,  182 ,    0 ,    0 ,
   0 ,  183 ,    0 ,    0 ,
   0 ,  184 ,    0 ,    0 ,
   0 ,  185 ,    0 ,    0 ,
   0 ,  186 ,    0 ,    0 ,
   0 ,  187 ,    0 ,    0 ,
   0 ,  188 ,    0 ,    0 ,
   0 ,  189 ,    0 ,    0 ,
   0 ,  190 ,    0 ,    0 ,
   0 ,  191 ,    0 ,    0 ,
   0 ,  192 ,    0 ,    0 ,
   0 ,  193 ,    0 ,    0 ,
   0 ,  194 ,    0 ,    0 ,
   0 ,  195 ,    0 ,    0 ,
   0 ,  196 ,    0 ,    0 ,
   0 ,  197 ,    0 ,    0 ,
   0 ,  198 ,    0 ,    0 ,
   0 ,  199 ,    0 ,    0 ,
   0 ,  200 ,    0 ,    0 ,
   0 ,  201 ,    0 ,    0 ,
   0 ,  202 ,    0 ,    0 ,
   0 ,  203 ,    0 ,    0 ,
   0 ,  204 ,    0 ,    0 ,
   0 ,  205 ,    0 ,    0 ,
   0 ,  206 ,    0 ,    0 ,
   0 ,  207 ,    0 ,    0 ,
   0 ,  208 ,    0 ,    0 ,
   0 ,  209 ,    0 ,    0 ,
   0 ,  210 ,    0 ,    0 ,
   0 ,  211 ,    0 ,    0 ,
   0 ,  212 ,    0 ,    0 ,
   0 ,  213 ,    0 ,    0 ,
   0 ,  214 ,    0 ,    0 ,
   0 ,  215 ,    0 ,    0 ,
   0 ,  216 ,    0 ,    0 ,
   0 ,  217 ,    0 ,    0 ,
   0 ,  218 ,    0 ,    0 ,
   0 ,  219 ,    0 ,    0 ,
   0 ,  220 ,    0 ,    0 ,
   0 ,  221 ,    0 ,    0 ,
   0 ,  222 ,    0 ,    0 ,
   0 ,  223 ,    0 ,    0 ,
   0 ,  224 ,    0 ,    0 ,
   0 ,  225 ,    0 ,    0 ,
   0 ,  226 ,    0 ,    0 ,
   0 ,  227 ,    0 ,    0 ,
   0 ,  228 ,    0 ,    0 ,
   0 ,  229 ,    0 ,    0 ,
   0 ,  230 ,    0 ,    0 ,
   0 ,  231 ,    0 ,    0 ,
   0 ,  232 ,    0 ,    0 ,
   0 ,  233 ,    0 ,    0 ,
   0 ,  234 ,    0 ,    0 ,
   0 ,  235 ,    0 ,    0 ,
   0 ,  236 ,    0 ,    0 ,
   0 ,  237 ,    0 ,    0 ,
   0 ,  238 ,    0 ,    0 ,
   0 ,  239 ,    0 ,    0 ,
   0 ,  240 ,    0 ,    0 ,
   0 ,  241 ,    0 ,    0 ,
   0 ,  242 ,    0 ,    0 ,
   0 ,  243 ,    0 ,    0 ,
   0 ,  244 ,    0 ,    0 ,
   0 ,  245 ,    0 ,    0 ,
   0 ,  246 ,    0 ,    0 ,
   0 ,  247 ,    0 ,    0 ,
   0 ,  248 ,    0 ,    0 ,
   0 ,  249 ,    0 ,    0 ,
   0 ,  250 ,    0 ,    0 ,
   0 ,  251 ,    0 ,    0 ,
   0 ,  252 ,    0 ,    0 ,
   0 ,  253 ,    0 ,    0 ,
   0 ,  254 ,    0 ,    0 ,
   0 ,  254 ,    0 ,    0
};
