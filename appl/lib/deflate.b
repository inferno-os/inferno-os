# gzip-compatible compression filter.

implement Filter;

include "sys.m";
	sys:	Sys;

include "filter.m";

GZMAGIC1:	con byte 16r1f;
GZMAGIC2:	con byte 16r8b;

GZDEFLATE:	con byte 8;

GZFTEXT:	con byte 1 << 0;		# file is text
GZFHCRC:	con byte 1 << 1;		# crc of header included
GZFEXTRA:	con byte 1 << 2;		# extra header included
GZFNAME:	con byte 1 << 3;		# name of file included
GZFCOMMENT:	con byte 1 << 4;		# header comment included
GZFMASK:	con (byte 1 << 5) - byte 1;	# mask of specified bits

GZXFAST:	con byte 2;			# used fast algorithm little compression
GZXBEST:	con byte 4;			# used maximum compression algorithm

GZOSFAT:	con byte 0;			# FAT file system
GZOSAMIGA:	con byte 1;			# Amiga
GZOSVMS:	con byte 2;			# VMS or OpenVMS
GZOSUNIX:	con byte 3;			# Unix
GZOSVMCMS:	con byte 4;			# VM/CMS
GZOSATARI:	con byte 5;			# Atari TOS
GZOSHPFS:	con byte 6;			# HPFS file system
GZOSMAC:	con byte 7;			# Macintosh
GZOSZSYS:	con byte 8;			# Z-System
GZOSCPM:	con byte 9;			# CP/M
GZOSTOPS20:	con byte 10;			# TOPS-20
GZOSNTFS:	con byte 11;			# NTFS file system
GZOSQDOS:	con byte 12;			# QDOS
GZOSACORN:	con byte 13;			# Acorn RISCOS
GZOSUNK:	con byte 255;

GZCRCPOLY:	con int 16redb88320;
GZOSINFERNO:	con GZOSUNIX;


Hnone, Hgzip, Hzlib: con iota;  # LZstate.headers
LZstate: adt
{
	hist:		array of byte;		# [HistSize];
	epos:		int;			# end of history buffer
	pos:		int;			# current location in history buffer
	eof:		int;
	hash:		array of int;		# [Nhash] hash chains
	nexts:		array of int;		# [MaxOff]
	me:		int;			# pos in hash chains
	dot:		int;			# dawn of time in history
	prevlen:	int;			# lazy matching state
	prevoff:	int;
	maxchars:	int;			# compressor tuning
	maxdefer:	int;
	level:		int;

	crctab: array of int;			# for gzip trailer
	crc:		int;
	tot:		int;
	sum:		big;			# for zlib trailer
	headers:	int;			# which header to print, if any

	outbuf:		array of byte;		# current output buffer;
	out:		int;			# current position in the output buffer
	bits:		int;			# bit shift register
	nbits:		int;

	verbose:	int;
	debug:		int;

	lzb:		ref LZblock;
	slop:		array of byte;
	dlitlentab:	array of Huff;		# [Nlitlen]
	dofftab:	array of Huff;		# [Noff];
	hlitlentab:	array of Huff;		# [Nlitlen];
	dyncode:	ref Dyncode;
	hdyncode:	ref Dyncode;
	c:		chan of ref Rq;
	rc:		chan of int;
};

#
# lempel-ziv compressed block
#
LZblock: adt
{
	litlen:		array of byte;			# [MaxUncBlock+1];
	off:		array of int;			# [MaxUncBlock+1];
	litlencount:	array of int;			# [Nlitlen];
	offcount:	array of int;			# [Noff];
	entries:	int;				# entries in litlen & off tables
	bytes:		int;				# consumed from the input
	excost:		int;				# cost of encoding extra len & off bits
};

#
# encoding of dynamic huffman trees
#
Dyncode: adt
{
	nlit:		int;
	noff:		int;
	nclen:		int;
	ncode:		int;
	codetab:	array of Huff;		# [Nclen];
	codes:		array of byte;		# [Nlitlen+Noff];
	codeaux:	array of byte;		# [Nlitlen+Noff];
};

#
# huffman code table
#
Huff: adt
{
	bits:		int;				# length of the code
	encode:		int;				# the code
};

DeflateBlock:	con 64*1024-258-1;
DeflateOut:	con 258+10;


DeflateUnc:	con 0;			# uncompressed block
DeflateFix:	con 1;			# fixed huffman codes
DeflateDyn:	con 2;			# dynamic huffman codes

DeflateEob:	con 256;		# end of block code in lit/len book

LenStart:	con 257;		# start of length codes in litlen
Nlitlen:	con 288;		# number of litlen codes
Noff:		con 30;			# number of offset codes
Nclen:		con 19;			# number of codelen codes

MaxLeaf:	con Nlitlen;
MaxHuffBits:	con 15;			# max bits in a huffman code
ChainMem:	con 2 * MaxHuffBits * (MaxHuffBits + 1);

MaxUncBlock:	con 64*1024-1;		# maximum size of uncompressed block

MaxOff:		con 32*1024;
MinMatch:	con 3;			# shortest match possible
MaxMatch:	con 258;		# longest match possible
MinMatchMaxOff:	con 4096;		# max profitable offset for small match;
					#  assumes 8 bits for len; 5+10 for offset
HistSlop:	con 4096;		# slop for fewer calls to lzcomp
HistSize:	con MaxOff + 2*HistSlop;

Hshift:		con 4;			# nice compromise between space & time
Nhash:		con 1<<(Hshift*MinMatch);
Hmask:		con Nhash-1;

MaxOffCode:	con 256;		# biggest offset looked up in direct table

EstLitBits:	con 8;
EstLenBits:	con 4;
EstOffBits:	con 5;

# conversion from len to code word
lencode := array[MaxMatch] of int;

#
# conversion from off to code word
# off <= MaxOffCode ? offcode[off] : bigoffcode[(off-1) >> 7]
#
offcode := array[MaxOffCode + 1] of int;
bigoffcode := array[256] of int;

# litlen code words LenStart-285 extra bits
litlenbase := array[Nlitlen-LenStart] of int;
litlenextra := array[Nlitlen-LenStart] of
{
	0, 0, 0,
	0, 0, 0, 0, 0, 1, 1, 1, 1, 2,
	2, 2, 2, 3, 3, 3, 3, 4, 4, 4,
	4, 5, 5, 5, 5, 0, 0, 0
};

# offset code word extra bits
offbase := array[Noff] of int;
offextra := array[] of
{
	0,  0,  0,  0,  1,  1,  2,  2,  3,  3,
	4,  4,  5,  5,  6,  6,  7,  7,  8,  8,
	9,  9,  10, 10, 11, 11, 12, 12, 13, 13,
	0,  0,
};

# order code lengths
clenorder := array[Nclen] of
{
        16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
};

# static huffman tables
litlentab : array of Huff;
offtab : array of Huff;
hofftab : array of Huff;

# bit reversal for brain dead endian swap in huffman codes
revtab: array of byte;

init()
{
	sys = load Sys Sys->PATH;

	bitcount := array[MaxHuffBits] of int;
	i, j, ci, n: int;

	# byte reverse table
	revtab = array[256] of byte;
	for(i=0; i<256; i++){
		revtab[i] = byte 0;
		for(j=0; j<8; j++)
			if(i & (1<<j))
				revtab[i] |= byte 16r80 >> j;
	}

	litlentab = array[Nlitlen] of Huff;
	offtab = array[Noff] of Huff;
	hofftab = array[Noff] of { * => Huff(0, 0) };

	# static Litlen bit lengths
	for(i=0; i<144; i++)
		litlentab[i].bits = 8;
	for(i=144; i<256; i++)
		litlentab[i].bits = 9;
	for(i=256; i<280; i++)
		litlentab[i].bits = 7;
	for(i=280; i<Nlitlen; i++)
		litlentab[i].bits = 8;

	for(i = 0; i < 10; i++)
		bitcount[i] = 0;
	bitcount[8] += 144 - 0;
	bitcount[9] += 256 - 144;
	bitcount[7] += 280 - 256;
	bitcount[8] += Nlitlen - 280;

	hufftabinit(litlentab, Nlitlen, bitcount, 9);

	# static offset bit lengths
	for(i = 0; i < Noff; i++)
		offtab[i].bits = 5;

	for(i = 0; i < 5; i++)
		bitcount[i] = 0;
	bitcount[5] = Noff;

	hufftabinit(offtab, Noff, bitcount, 5);

	bitcount[0] = 0;
	bitcount[1] = 0;
	mkprecode(hofftab, bitcount, 2, MaxHuffBits);

	# conversion tables for lens & offs to codes
	ci = 0;
	for(i = LenStart; i < 286; i++){
		n = ci + (1 << litlenextra[i - LenStart]);
		litlenbase[i - LenStart] = ci;
		for(; ci < n; ci++)
			lencode[ci] = i;
	}
	# patch up special case for len MaxMatch
	lencode[MaxMatch-MinMatch] = 285;
	litlenbase[285-LenStart] = MaxMatch-MinMatch;

	ci = 1;
	for(i = 0; i < 16; i++){
		n = ci + (1 << offextra[i]);
		offbase[i] = ci;
		for(; ci < n; ci++)
			offcode[ci] = i;
	}

	ci = (LenStart - 1) >> 7;
	for(; i < 30; i++){
		n = ci + (1 << (offextra[i] - 7));
		offbase[i] = (ci << 7) + 1;
		for(; ci < n; ci++)
			bigoffcode[ci] = i;
	}
}

start(param: string): chan of ref Rq
{
	# param contains flags:
	# [0-9] - compression level
	# h gzip header/trailer
	# z zlib header/trailer
	# v verbose
	# d debug
	lz := ref LZstate;
	lz.level = 6;
	lz.verbose = lz.debug = 0;
	lz.headers = Hnone;
	lz.crc = lz.tot = 0;
	lz.sum = big 1;
	# XXX could also put filename and modification time in param
	for (i := 0; i < len param; i++) {
		case param[i] {
		'0' to '9' =>
			lz.level = param[i] - '0';
		'v' =>
			lz.verbose = 1;
		'h' =>
			lz.headers = Hgzip;
		'z' =>
			lz.headers = Hzlib;
		'd' =>
			lz.debug = 1;
		}
	}
	
	lz.hist = array[HistSize] of byte;
	lz.hash = array[Nhash] of int;
	lz.nexts = array[MaxOff] of int;
	lz.slop = array[2*MaxMatch] of byte;
	lz.dlitlentab = array[Nlitlen] of Huff;
	lz.dofftab = array[Noff] of Huff;
	lz.hlitlentab = array[Nlitlen] of Huff;

	lz.lzb = ref LZblock;
	lzb := lz.lzb;
	lzb.litlen = array[MaxUncBlock+1] of byte;
	lzb.off = array[MaxUncBlock+1] of int;
	lzb.litlencount = array[Nlitlen] of int;
	lzb.offcount = array[Noff] of int;

	lz.dyncode = ref Dyncode;
	lz.dyncode.codetab =array[Nclen] of Huff;
	lz.dyncode.codes =array[Nlitlen+Noff] of byte;
	lz.dyncode.codeaux = array[Nlitlen+Noff] of byte;
	lz.hdyncode = ref Dyncode;
	lz.hdyncode.codetab =array[Nclen] of Huff;
	lz.hdyncode.codes =array[Nlitlen+Noff] of byte;
	lz.hdyncode.codeaux = array[Nlitlen+Noff] of byte;

	for(i = 0; i < MaxOff; i++)
		lz.nexts[i] = 0;
	for(i = 0; i < Nhash; i++)
		lz.hash[i] = 0;
	lz.pos = 0;
	lz.epos = 0;
	lz.prevlen = MinMatch - 1;
	lz.prevoff = 0;
	lz.eof = 0;
	lz.me = 4 * MaxOff;
	lz.dot = lz.me;
	lz.bits = 0;
	lz.nbits = 0;
	if(lz.level < 5) {
		lz.maxchars = 1;
		lz.maxdefer = 0;
	} else if(lz.level == 9) {
		lz.maxchars = 4000;
		lz.maxdefer = MaxMatch;
	} else {
		lz.maxchars = 200;
		lz.maxdefer = MaxMatch / 4;
	}
	if (lz.headers == Hgzip)
		lz.crctab = mkcrctab(GZCRCPOLY);
	lz.c = chan of ref Rq;
	lz.rc = chan of int;
	spawn deflate(lz);
	return lz.c;
}

# return (eof, nbytes)
fillbuf(lz: ref LZstate, buf: array of byte): (int, int)
{
	n := 0;
	while (n < len buf) {
		lz.c <-= ref Rq.Fill(buf[n:], lz.rc);
		nr := <-lz.rc;
		if (nr == -1)
			exit;
		if (nr == 0)
			return (1, n);
		n += nr;
	}
	return (0, n);
}

deflate(lz: ref LZstate)
{
	lz.c <-= ref Rq.Start(sys->pctl(0, nil));

	header(lz);
	buf := array[DeflateBlock] of byte;
	out := array[DeflateBlock + DeflateOut] of byte;
	eof := 0;
	for (;;) {
		nslop := lz.epos - lz.pos;
		nbuf := 0;
		if (!eof) {
			(eof, nbuf) = fillbuf(lz, buf);
			inblock(lz, buf[0:nbuf]);
		}
		if(eof && nbuf == 0 && nslop == 0) {
			if(lz.nbits) {
				out[0] = byte lz.bits;
				lz.nbits = 0;
				lz.c <-= ref Rq.Result(out[0:1], lz.rc);
				if (<-lz.rc == -1)
					exit;
				continue;
			}
			footer(lz);
			lz.c <-= ref Rq.Finished(nil);
			exit;
		}

		lz.outbuf = out;

		if(nslop > 2*MaxMatch) {
			lz.c <-= ref Rq.Error(sys->sprint("slop too large: %d", nslop));
			exit;
		}
		lz.slop[0:] = lz.hist[lz.pos:lz.epos];	# memmove(slop, lz.pos, nslop);
	
		lzb := lz.lzb;
		for(i := 0; i < Nlitlen; i++)
			lzb.litlencount[i] = 0;
		for(i = 0; i < Noff; i++)
			lzb.offcount[i] = 0;
		lzb.litlencount[DeflateEob]++;
	
		lzb.bytes = 0;
		lzb.entries = 0;
		lzb.excost = 0;
		lz.eof = 0;
	
		n := 0;
		while(n < nbuf || eof && !lz.eof){
			if(!lz.eof) {
				if(lz.pos >= MaxOff + HistSlop) {
					lz.pos -= MaxOff + HistSlop;
					lz.epos -= MaxOff + HistSlop;
					lz.hist[:] = lz.hist[MaxOff + HistSlop: MaxOff + HistSlop + lz.epos];
				}
				m := HistSlop - (lz.epos - lz.pos);
				if(lz.epos + m > HistSize) {
					lz.c <-= ref Rq.Error("read too long");
					exit;
				}
				if(m >= nbuf - n) {
					m = nbuf - n;
					lz.eof = eof;
				}
				lz.hist[lz.epos:] = buf[n:n+m];
				n += m;
				lz.epos += m;
			}
			lzcomp(lz, lzb, lz.epos - lz.pos);
		}
	
		lz.outbuf = out;
		lz.out = 0;
	
		nunc := lzb.bytes;
		if(nunc < nslop)
			nslop = nunc;
	
		mkprecode(lz.dlitlentab, lzb.litlencount, Nlitlen, MaxHuffBits);
		mkprecode(lz.dofftab, lzb.offcount, Noff, MaxHuffBits);
			
		ndyn := huffcodes(lz.dyncode, lz.dlitlentab, lz.dofftab)
			+ bitcost(lz.dlitlentab, lzb.litlencount, Nlitlen)
			+ bitcost(lz.dofftab, lzb.offcount, Noff)
			+ lzb.excost;
	
		litcount := array[Nlitlen] of int;
		for(i = 0; i < Nlitlen; i++)
			litcount[i] = 0;
		for(i = 0; i < nslop; i++)
			litcount[int lz.slop[i]]++;
		for(i = 0; i < nunc-nslop; i++)
			litcount[int buf[i]]++;
		litcount[DeflateEob]++;
	
		mkprecode(lz.hlitlentab, litcount, Nlitlen, MaxHuffBits);
		nhuff := huffcodes(lz.hdyncode, lz.hlitlentab, hofftab)
			+ bitcost(lz.hlitlentab, litcount, Nlitlen);
	
		nfix := bitcost(litlentab, lzb.litlencount, Nlitlen)
			+ bitcost(offtab, lzb.offcount, Noff)
			+ lzb.excost;
	
		lzput(lz, lz.eof && lz.pos == lz.epos, 1);
	
		if(lz.verbose) {
			lz.c <-= ref Rq.Info(sys->sprint("block: %d bytes %d entries %d extra bits",
						nunc, lzb.entries, lzb.excost));
			lz.c <-= ref Rq.Info(sys->sprint("\tuncompressed %d fixed %d dynamic %d huffman %d",
				(nunc + 4) * 8, nfix, ndyn, nhuff));
		}
	
		if((nunc + 4) * 8 < ndyn && (nunc + 4) * 8 < nfix && (nunc + 4) * 8 < nhuff) {
			lzput(lz, DeflateUnc, 2);
			lzflushbits(lz);
	
			lz.outbuf[lz.out++] = byte(nunc);
			lz.outbuf[lz.out++] = byte(nunc >> 8);
			lz.outbuf[lz.out++] = byte(~nunc);
			lz.outbuf[lz.out++] = byte(~nunc >> 8);
	
			lz.outbuf[lz.out:] = lz.slop[:nslop];
			lz.out += nslop;
			lz.outbuf[lz.out:] = buf[:nunc - nslop];
			lz.out += nunc - nslop;
		} else if(ndyn < nfix && ndyn < nhuff) {
			lzput(lz, DeflateDyn, 2);
	
			wrdyncode(lz, lz.dyncode);
			wrblock(lz, lzb.entries, lzb.litlen, lzb.off, lz.dlitlentab, lz.dofftab);
			lzput(lz, lz.dlitlentab[DeflateEob].encode, lz.dlitlentab[DeflateEob].bits);
		} else if(nhuff < nfix){
			lzput(lz, DeflateDyn, 2);
	
			wrdyncode(lz, lz.hdyncode);
			for(i = 0; i < len lzb.off; i++)
				lzb.off[i] = 0;
	
			wrblock(lz, nslop, lz.slop, lzb.off, lz.hlitlentab, hofftab);
			wrblock(lz, nunc-nslop, buf, lzb.off, lz.hlitlentab, hofftab);
			lzput(lz, lz.hlitlentab[DeflateEob].encode, lz.hlitlentab[DeflateEob].bits);
		} else {
			lzput(lz, DeflateFix, 2);
	
			wrblock(lz, lzb.entries, lzb.litlen, lzb.off, litlentab, offtab);
			lzput(lz, litlentab[DeflateEob].encode, litlentab[DeflateEob].bits);
		}

		lz.c <-= ref Rq.Result(out[0:lz.out], lz.rc);
		if (<-lz.rc == -1)
			exit;
	}
}

headergzip(lz: ref LZstate)
{
	buf := array[20] of byte;
	i := 0;
	buf[i++] = byte GZMAGIC1;
	buf[i++] = byte GZMAGIC2;
	buf[i++] = byte GZDEFLATE;

	flags := 0;
	#if(file != nil)
	#	flags |= GZFNAME;
	buf[i++] = byte flags;

	mtime := 0;
	buf[i++] = byte(mtime);
	buf[i++] = byte(mtime>>8);
	buf[i++] = byte(mtime>>16);
	buf[i++] = byte(mtime>>24);

	buf[i++] = byte 0;
	buf[i++] = byte GZOSINFERNO;

	#if((flags & GZFNAME) == GZFNAME){
	#	bout.puts(file);
	#	bout.putb(byte 0);
	#}
	lz.c <-= ref Rq.Result(buf[0:i], lz.rc);
	if (<-lz.rc == -1)
		exit;
}

headerzlib(lz: ref LZstate)
{
	CIshift:	con 12;
	CMdeflate:	con 8;
	CMshift:	con 8;
	LVshift:	con 6;
	LVfastest, LVfast, LVnormal, LVbest: con iota;

	level := LVnormal;
	if(lz.level < 6)
		level = LVfastest;
	else if(lz.level >= 9)
		level = LVbest;

	h := 0;
	h |= 7<<CIshift; # value is: (log2 of window size)-8
	h |= CMdeflate<<CMshift;
	h |= level<<LVshift;
	h += 31-(h%31);

	buf := array[2] of byte;
	buf[0] = byte (h>>8);
	buf[1] = byte (h>>0);

	lz.c <-= ref Rq.Result(buf, lz.rc);
	if (<-lz.rc == -1)
		exit;
}

header(lz: ref LZstate)
{
	case lz.headers {
	Hgzip =>	headergzip(lz);
	Hzlib =>	headerzlib(lz);
	}
}

footergzip(lz: ref LZstate)
{
	buf := array[8] of byte;
	i := 0;
	buf[i++] = byte(lz.crc);
	buf[i++] = byte(lz.crc>>8);
	buf[i++] = byte(lz.crc>>16);
	buf[i++] = byte(lz.crc>>24);

	buf[i++] = byte(lz.tot);
	buf[i++] = byte(lz.tot>>8);
	buf[i++] = byte(lz.tot>>16);
	buf[i++] = byte(lz.tot>>24);
	lz.c <-= ref Rq.Result(buf[0:i], lz.rc);
	if (<-lz.rc == -1)
		exit;
}

footerzlib(lz: ref LZstate)
{
        buf := array[4] of byte;
	i := 0;
        buf[i++] = byte (lz.sum>>24);
        buf[i++] = byte (lz.sum>>16);
        buf[i++] = byte (lz.sum>>8);
        buf[i++] = byte (lz.sum>>0);

	lz.c <-= ref Rq.Result(buf, lz.rc);
	if(<-lz.rc == -1)
		exit;
}

footer(lz: ref LZstate)
{
	case lz.headers {
	Hgzip =>	footergzip(lz);
	Hzlib =>	footerzlib(lz);
	}
}

lzput(lz: ref LZstate, bits, nbits: int): int
{
	bits = (bits << lz.nbits) | lz.bits;
	for(nbits += lz.nbits; nbits >= 8; nbits -= 8){
		lz.outbuf[lz.out++] = byte bits;
		bits >>= 8;
	}
	lz.bits = bits;
	lz.nbits = nbits;
	return 0;
}

lzflushbits(lz: ref LZstate): int
{
	if(lz.nbits & 7)
		lzput(lz, 0, 8 - (lz.nbits & 7));
	return 0;
}

#
# write out a block of n samples,
# given lz encoding and counts for huffman tables
# todo: inline lzput
#
wrblock(lz: ref LZstate, n: int, litlen: array of byte, off: array of int, litlentab, offtab: array of Huff): int
{
	for(i := 0; i < n; i++) {
		offset := off[i];
		lit := int litlen[i];
		if(lz.debug) {
			if(offset == 0)
				lz.c <-= ref Rq.Info(sys->sprint("\tlit %.2ux %c", lit, lit));
			else
				lz.c <-= ref Rq.Info(sys->sprint("\t<%d, %d>", offset, lit + MinMatch));
		}
		if(offset == 0)
			lzput(lz, litlentab[lit].encode, litlentab[lit].bits);
		else {
			c := lencode[lit];
			lzput(lz, litlentab[c].encode, litlentab[c].bits);
			c -= LenStart;
			if(litlenextra[c])
				lzput(lz, lit - litlenbase[c], litlenextra[c]);

			if(offset <= MaxOffCode)
				c = offcode[offset];
			else
				c = bigoffcode[(offset - 1) >> 7];
			lzput(lz, offtab[c].encode, offtab[c].bits);
			if(offextra[c])
				lzput(lz, offset - offbase[c], offextra[c]);
		}
	}

	return n;
}

lzcomp(lz: ref LZstate, lzb: ref LZblock, max: int)
{
	q, s, es, t: int;
	you, m: int;

#	hashcheck(lz, "start");

	hist := lz.hist;
	nexts := lz.nexts;
	hash := lz.hash;
	me := lz.me;

	p := lz.pos;
	ep := lz.epos;
	if(p + max < ep)
		ep = p + max;
	if(lz.prevlen != MinMatch - 1)
		p++;

	#
	# hash in the links for any hanging link positions,
	# and calculate the hash for the current position.
	#
	n := MinMatch;
	if(n > ep - p)
		n = ep - p;
	h := 0;
	for(i := 0; i < n - 1; i++) {
		m = me - ((MinMatch-1) - i);
		if(m < lz.dot)
			continue;
		s = p - (me - m);
		if(s < 0)
			s += MaxOff + HistSlop;
		h = hashit(s, hist);
		for(you = hash[h]; me - you < me - m; you = nexts[you & (MaxOff-1)])
			;
		if(you == m)
			continue;
		nexts[m & (MaxOff-1)] = hash[h];
		hash[h] = m;
	}
	for(i = 0; i < n; i++)
		h = ((h << Hshift) ^ int hist[p+i]) & Hmask;

	#
	# me must point to the index in the next/prev arrays
	# corresponding to p's position in the history
	#
	entries := lzb.entries;
	litlencount := lzb.litlencount;
	offcount := lzb.offcount;
	litlen := lzb.litlen;
	off := lzb.off;
	prevlen := lz.prevlen;
	prevoff := lz.prevoff;
	maxdefer := lz.maxdefer;
	maxchars := lz.maxchars;
	excost := 0;
	for(;;) {
		es = p + MaxMatch;
		if(es > ep) {
			if(!lz.eof || ep != lz.epos || p >= ep)
				break;
			es = ep;
		}

		#
		# look for the longest, closest string which
		# matches what we are going to send.  the clever
		# part here is looking for a string 1 longer than
		# are previous best match.
		#
		runlen := prevlen;
		m = 0;
		chars := maxchars;
	matchloop:
		for(you = hash[h]; me-you <= MaxOff && chars > 0; you = nexts[you & (MaxOff-1)]) {
			s = p + runlen;
			if(s >= es)
				break;
			t = s - me + you;
			if(t - runlen < 0)
				t += MaxOff + HistSlop;
			for(; s >= p; s--) {
				if(hist[s] != hist[t]) {
					chars -= p + runlen - s + 1;
					continue matchloop;
				}
				t--;
			}

			#
			# we have a new best match.
			# extend it to it's maximum length
			#
			t += runlen + 2;
			s += runlen + 2;
			for(; s < es; s++) {
				if(hist[s] != hist[t])
					break;
				t++;
			}
			runlen = s - p;
			m = you;
			if(s == es)
				break;
			if(runlen > 7)
				chars >>= 1;
			chars -= runlen;
		}

		#
		# back out of small matches too far in the past
		#
		if(runlen == MinMatch && me - m >= MinMatchMaxOff) {
			runlen = MinMatch - 1;
			m = 0;
		}

		#
		# record the encoding and increment counts for huffman trees
		# if we get a match, defer selecting it until we check for
		# a longer match at the next position.
		#
		if(prevlen >= runlen && prevlen != MinMatch - 1) {
			#
			# old match at least as good; use that one
			#
			n = prevlen - MinMatch;
			litlen[entries] = byte n;
			n = lencode[n];
			litlencount[n]++;
			excost += litlenextra[n - LenStart];

			off[entries++] = prevoff;
			if(prevoff <= MaxOffCode)
				n = offcode[prevoff];
			else
				n = bigoffcode[(prevoff - 1) >> 7];
			offcount[n]++;
			excost += offextra[n];

			runlen = prevlen - 1;
			prevlen = MinMatch - 1;
		} else if(runlen == MinMatch - 1) {
			#
			# no match; just put out the literal
			#
			n = int hist[p];
			litlen[entries] = byte n;
			litlencount[n]++;
			off[entries++] = 0;
			runlen = 1;
		} else {
			if(prevlen != MinMatch - 1) {
				#
				# longer match now. output previous literal,
				# update current match, and try again
				#
				n = int hist[p - 1];
				litlen[entries] = byte n;
				litlencount[n]++;
				off[entries++] = 0;
			}

			prevoff = me - m;

			if(runlen < maxdefer) {
				prevlen = runlen;
				runlen = 1;
			} else {
				n = runlen - MinMatch;
				litlen[entries] = byte n;
				n = lencode[n];
				litlencount[n]++;
				excost += litlenextra[n - LenStart];

				off[entries++] = prevoff;
				if(prevoff <= MaxOffCode)
					n = offcode[prevoff];
				else
					n = bigoffcode[(prevoff - 1) >> 7];
				offcount[n]++;
				excost += offextra[n];
				prevlen = MinMatch - 1;
			}
		}

		#
		# update the hash for the newly matched data
		# this is constructed so the link for the old
		# match in this position must at the end of a chain,
		# and will expire when this match is added, ie it will
		# never be examined for by the match loop.
		# add to the hash chain only if we have the real hash data.
		#
		for(q = p + runlen; p != q; p++) {
			if(p + MinMatch <= ep) {
				nexts[me & (MaxOff-1)] = hash[h];
				hash[h] = me;
				if(p + MinMatch < ep)
					h = ((h << Hshift) ^ int hist[p + MinMatch]) & Hmask;
			}
			me++;
		}
	}

	#
	# we can just store away the lazy state and
	# pick it up next time.  the last block will have eof
	# so we won't have any pending matches
	# however, we need to correct for how much we've encoded
	#
	if(prevlen != MinMatch - 1)
		p--;

	lzb.excost += excost;
	lzb.bytes += p - lz.pos;
	lzb.entries = entries;

	lz.pos = p;
	lz.me = me;
	lz.prevlen = prevlen;
	lz.prevoff = prevoff;

#	hashcheck(lz, "stop");
}

#
# check all the hash list invariants are really satisfied
#
hashcheck(lz: ref LZstate, where: string)
{
	s, age, a, you: int;

	nexts := lz.nexts;
	hash := lz.hash;
	me := lz.me;
	start := lz.pos;
	if(lz.prevlen != MinMatch-1)
		start++;
	found := array [MaxOff] of byte;
	for(i := 0; i < MaxOff; i++)
		found[i] = byte 0;
	for(i = 0; i < Nhash; i++) {
		age = 0;
		for(you = hash[i]; me-you <= MaxOff; you = nexts[you & (MaxOff-1)]) {
			a = me - you;
			if(a < age)
				fatal(lz, sys->sprint("%s: out of order links age %d a %d me %d you %d",
					where, age, a, me, you));

			age = a;

			s = start - a;
			if(s < 0)
				s += MaxOff + HistSlop;

			if(hashit(s, lz.hist) != i)
				fatal(lz, sys->sprint("%s: bad hash chain you %d me %d s %d start %d chain %d hash %d %d %d",
					where, you, me, s, start, i, hashit(s - 1, lz.hist), hashit(s, lz.hist), hashit(s + 1, lz.hist)));

			if(found[you & (MaxOff - 1)] != byte 0)
				fatal(lz, where + ": found link again");
			found[you & (MaxOff - 1)] = byte 1;
		}
	}

	for(you = me - (MaxOff-1); you != me; you++)
		found[you & (MaxOff - 1)] = byte 1;

	for(i = 0; i < MaxOff; i++){
		if(found[i] == byte 0 && nexts[i] != 0)
			fatal(lz, sys->sprint("%s: link not found: max %d at %d", where, me & (MaxOff-1), i));
	}
}

hashit(p: int, hist: array of byte): int
{
	h := 0;
	for(ep := p + MinMatch; p < ep; p++)
		h = ((h << Hshift) ^ int hist[p]) & Hmask;
	return h;
}

#
# make up the dynamic code tables, and return the number of bits
# needed to transmit them.
#
huffcodes(dc: ref Dyncode, littab, offtab: array of Huff): int
{
	i, n, m, c, nlit, noff, ncode, nclen: int;

	codetab := dc.codetab;
	codes := dc.codes;
	codeaux := dc.codeaux;

	#
	# trim the sizes of the tables
	#
	for(nlit = Nlitlen; nlit > 257 && littab[nlit-1].bits == 0; nlit--)
		;
	for(noff = Noff; noff > 1 && offtab[noff-1].bits == 0; noff--)
		;

	#
	# make the code-length code
	#
	for(i = 0; i < nlit; i++)
		codes[i] = byte littab[i].bits;
	for(i = 0; i < noff; i++)
		codes[i + nlit] = byte offtab[i].bits;

	#
	# run-length compress the code-length code
	#
	excost := 0;
	c = 0;
	ncode = nlit+noff;
	for(i = 0; i < ncode; ) {
		n = i + 1;
		v := codes[i];
		while(n < ncode && v == codes[n])
			n++;
		n -= i;
		i += n;
		if(v == byte 0) {
			while(n >= 11) {
				m = n;
				if(m > 138)
					m = 138;
				codes[c] = byte 18;
				codeaux[c++] = byte(m - 11);
				n -= m;
				excost += 7;
			}
			if(n >= 3) {
				codes[c] = byte 17;
				codeaux[c++] = byte(n - 3);
				n = 0;
				excost += 3;
			}
		}
		while(n--) {
			codes[c++] = v;
			while(n >= 3) {
				m = n;
				if(m > 6)
					m = 6;
				codes[c] = byte 16;
				codeaux[c++] = byte(m - 3);
				n -= m;
				excost += 3;
			}
		}
	}

	codecount := array[Nclen] of {* => 0};
	for(i = 0; i < c; i++)
		codecount[int codes[i]]++;
	mkprecode(codetab, codecount, Nclen, 7);

	for(nclen = Nclen; nclen > 4 && codetab[clenorder[nclen-1]].bits == 0; nclen--)
		;

	dc.nlit = nlit;
	dc.noff = noff;
	dc.nclen = nclen;
	dc.ncode = c;

	return 5 + 5 + 4 + nclen * 3 + bitcost(codetab, codecount, Nclen) + excost;
}

wrdyncode(out: ref LZstate, dc: ref Dyncode)
{
	#
	# write out header, then code length code lengths,
	# and code lengths
	#
	lzput(out, dc.nlit-257, 5);
	lzput(out, dc.noff-1, 5);
	lzput(out, dc.nclen-4, 4);

	codetab := dc.codetab;
	for(i := 0; i < dc.nclen; i++)
		lzput(out, codetab[clenorder[i]].bits, 3);

	codes := dc.codes;
	codeaux := dc.codeaux;
	c := dc.ncode;
	for(i = 0; i < c; i++){
		v := int codes[i];
		lzput(out, codetab[v].encode, codetab[v].bits);
		if(v >= 16){
			if(v == 16)
				lzput(out, int codeaux[i], 2);
			else if(v == 17)
				lzput(out, int codeaux[i], 3);
			else # v == 18
				lzput(out, int codeaux[i], 7);
		}
	}
}

bitcost(tab: array of Huff, count: array of int, n: int): int
{
	tot := 0;
	for(i := 0; i < n; i++)
		tot += count[i] * tab[i].bits;
	return tot;
}

hufftabinit(tab: array of Huff, n: int, bitcount: array of int, nbits: int)
{
	nc := array[MaxHuffBits + 1] of int;

	code := 0;
	for(bits := 1; bits <= nbits; bits++) {
		code = (code + bitcount[bits-1]) << 1;
		nc[bits] = code;
	}

	for(i := 0; i < n; i++) {
		bits = tab[i].bits;
		if(bits != 0) {
			code = nc[bits]++ << (16 - bits);
			tab[i].encode = int(revtab[code >> 8]) | (int(revtab[code & 16rff]) << 8);
		}
	}
}

Chain: adt
{
	count:		int;				# occurances of everything in the chain
	leaf:		int;				# leaves to the left of chain, or leaf value
	col:		byte;				# ref count for collecting unused chains
	gen:		byte;				# need to generate chains for next lower level
	up:		int;				# Chain up in the lists
};

Chains: adt
{
	lists:		array of int;			# [MaxHuffBits * 2]
	chains:		array of Chain;			# [ChainMem]
	nleaf:		int;				# number of leaves
	free:		int;
	col:		byte;
	nlists:		int;
};

Nil:	con -1;

#
# fast, low space overhead algorithm for max depth huffman type codes
#
# J. Katajainen, A. Moffat and A. Turpin, "A fast and space-economical
# algorithm for length-limited coding," Proc. Intl. Symp. on Algorithms
# and Computation, Cairns, Australia, Dec. 1995, Lecture Notes in Computer
# Science, Vol 1004, J. Staples, P. Eades, N. Katoh, and A. Moffat, eds.,
# pp 12-21, Springer Verlag, New York, 1995.
#
mkprecode(tab: array of Huff, count: array of int, n, maxbits: int)
{
	cs := ref Chains(array[MaxHuffBits * 2] of int, array[MaxLeaf+ChainMem] of Chain, 0, 0, byte 0, 0);
	bits: int;

	for(i := 0; i < n; i++){
		tab[i].bits = 0;
		tab[i].encode = 0;
	}

	#
	# set up the sorted list of leaves
	#
	m := 0;
	for(i = 0; i < n; i++) {
		if(count[i] != 0){
			cs.chains[m].count = count[i];
			cs.chains[m].leaf = i;
			m++;
		}
	}
	if(m < 2) {
		if(m != 0) {
			m = cs.chains[0].leaf;
			tab[m].bits = 1;
			tab[m].encode = 0;
		}
		return;
	}
	cs.nleaf = m;
	csorts(cs.chains, 0, m);

	cs.free = cs.nleaf + 2;
	cs.col = byte 1;

	#
	# initialize chains for each list
	#
	c := cs.chains;
	cl := cs.nleaf;
	c[cl].count = cs.chains[0].count;
	c[cl].leaf = 1;
	c[cl].col = cs.col;
	c[cl].up = Nil;
	c[cl].gen = byte 0;
	c[cl + 1] = c[cl];
	c[cl + 1].leaf = 2;
	c[cl + 1].count = cs.chains[1].count;
	for(i = 0; i < maxbits; i++){
		cs.lists[i * 2] = cl;
		cs.lists[i * 2 + 1] = cl + 1;
	}

	cs.nlists = 2 * maxbits;
	m = 2 * m - 2;
	for(i = 2; i < m; i++)
		nextchain(cs, cs.nlists - 2);

	bitcount := array[MaxHuffBits + 1] of int;
	bits = 0;
	bitcount[0] = cs.nleaf;
	for(cl = cs.lists[2 * maxbits - 1]; cl != Nil; cl = c[cl].up) {
		m = c[cl].leaf;
		for(i = 0; i < m; i++)
			tab[cs.chains[i].leaf].bits++;
		bitcount[bits++] -= m;
		bitcount[bits] = m;
	}

	hufftabinit(tab, n, bitcount, bits);
}

#
# calculate the next chain on the list
# we can always toss out the old chain
#
nextchain(cs: ref Chains, clist: int)
{
	i, nleaf, sumc: int;

	oc := cs.lists[clist + 1];
	cs.lists[clist] = oc;
	if(oc == Nil)
		return;

	#
	# make sure we have all chains needed to make sumc
	# note it is possible to generate only one of these,
	# use twice that value for sumc, and then generate
	# the second if that preliminary sumc would be chosen.
	# however, this appears to be slower on current tests
	#
	chains := cs.chains;
	if(chains[oc].gen != byte 0) {
		nextchain(cs, clist - 2);
		nextchain(cs, clist - 2);
		chains[oc].gen = byte 0;
	}

	#
	# pick up the chain we're going to add;
	# collect unused chains no free ones are left
	#
	for(c := cs.free; ; c++) {
		if(c >= ChainMem) {
			cs.col++;
			for(i = 0; i < cs.nlists; i++)
				for(c = cs.lists[i]; c != Nil; c = chains[c].up)
					chains[c].col = cs.col;
			c = cs.nleaf;
		}
		if(chains[c].col != cs.col)
			break;
	}

	#
	# pick the cheapest of
	# 1) the next package from the previous list
	# 2) the next leaf
	#
	nleaf = chains[oc].leaf;
	sumc = 0;
	if(clist > 0 && cs.lists[clist-1] != Nil)
		sumc = chains[cs.lists[clist-2]].count + chains[cs.lists[clist-1]].count;
	if(sumc != 0 && (nleaf >= cs.nleaf || chains[nleaf].count > sumc)) {
		chains[c].count = sumc;
		chains[c].leaf = chains[oc].leaf;
		chains[c].up = cs.lists[clist-1];
		chains[c].gen = byte 1;
	} else if(nleaf >= cs.nleaf) {
		cs.lists[clist + 1] = Nil;
		return;
	} else {
		chains[c].leaf = nleaf + 1;
		chains[c].count = chains[nleaf].count;
		chains[c].up = chains[oc].up;
		chains[c].gen = byte 0;
	}
	cs.free = c + 1;

	cs.lists[clist + 1] = c;
	chains[c].col = cs.col;
}

chaincmp(chain: array of Chain, ai, bi: int): int
{
	ac := chain[ai].count;
	bc := chain[bi].count;
	if(ac < bc)
		return -1;
	if(ac > bc)
		return 1;
	ac = chain[ai].leaf;
	bc = chain[bi].leaf;
	if(ac > bc)
		return -1;
	return ac < bc;
}

pivot(chain: array of Chain, a, n: int): int
{
	j := n/6;
	pi := a + j;	# 1/6
	j += j;
	pj := pi + j;	# 1/2
	pk := pj + j;	# 5/6
	if(chaincmp(chain, pi, pj) < 0) {
		if(chaincmp(chain, pi, pk) < 0) {
			if(chaincmp(chain, pj, pk) < 0)
				return pj;
			return pk;
		}
		return pi;
	}
	if(chaincmp(chain, pj, pk) < 0) {
		if(chaincmp(chain, pi, pk) < 0)
			return pi;
		return pk;
	}
	return pj;
}

csorts(chain: array of Chain, a, n: int)
{
	j, pi, pj, pn: int;

	while(n > 1) {
		if(n > 10)
			pi = pivot(chain, a, n);
		else
			pi = a + (n>>1);

		t := chain[pi];
		chain[pi] = chain[a];
		chain[a] = t;
		pi = a;
		pn = a + n;
		pj = pn;
		for(;;) {
			do
				pi++;
			while(pi < pn && chaincmp(chain, pi, a) < 0);
			do
				pj--;
			while(pj > a && chaincmp(chain, pj, a) > 0);
			if(pj < pi)
				break;
			t = chain[pi];
			chain[pi] = chain[pj];
			chain[pj] = t;
		}
		t = chain[a];
		chain[a] = chain[pj];
		chain[pj] = t;
		j = pj - a;

		n = n-j-1;
		if(j >= n) {
			csorts(chain, a, j);
			a += j+1;
		} else {
			csorts(chain, a + (j+1), n);
			n = j;
		}
	}
}

mkcrctab(poly: int): array of int
{
	crctab := array[256] of int;
	for(i := 0; i < 256; i++){
		crc := i;
		for(j := 0; j < 8; j++){
			c := crc & 1;
			crc = (crc >> 1) & 16r7fffffff;
			if(c)
				crc ^= poly;
		}
		crctab[i] = crc;
	}
	return crctab;
}

inblockcrc(lz: ref LZstate, buf: array of byte)
{
	crc := lz.crc;
	n := len buf;
	crc ^= int 16rffffffff;
	for(i := 0; i < n; i++)
		crc = lz.crctab[int(byte crc ^ buf[i])] ^ ((crc >> 8) & 16r00ffffff);
	lz.crc = crc ^ int 16rffffffff;
	lz.tot += n;
}

inblockadler(lz: ref LZstate, buf: array of byte)
{
	ZLADLERBASE:	con big 65521;

	s1 := lz.sum & big 16rffff;
	s2 := (lz.sum>>16) & big 16rffff;

	for(i := 0; i < len buf; i++) {
		s1 = (s1 + big buf[i]) % ZLADLERBASE;
		s2 = (s2 + s1) % ZLADLERBASE;
	}
	lz.sum = (s2<<16) + s1;
}

inblock(lz: ref LZstate, buf: array of byte)
{
	case lz.headers {
	Hgzip =>	inblockcrc(lz, buf);
	Hzlib =>	inblockadler(lz, buf);
	}
}

fatal(lz: ref LZstate, s: string)
{
	lz.c <-= ref Rq.Error(s);
	exit;
}
