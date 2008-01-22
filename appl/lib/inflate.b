# gzip-compatible decompression filter.

implement Filter;

include "sys.m";
	sys:	Sys;
include "filter.m";

GZMAGIC1:	con byte 16r1f;
GZMAGIC2:	con byte 16r8b;

GZDEFLATE:	con byte 8;

GZFTEXT:	con 1 << 0;		# file is text
GZFHCRC:	con 1 << 1;		# crc of header included
GZFEXTRA:	con 1 << 2;		# extra header included
GZFNAME:	con 1 << 3;		# name of file included
GZFCOMMENT:	con 1 << 4;		# header comment included
GZFMASK:	con (1 << 5) - 1;	# mask of specified bits

GZXBEST:	con byte 2;		# used maximum compression algorithm
GZXFAST:	con byte 4;		# used fast algorithm little compression

GZOSFAT:	con byte 0;		# FAT file system
GZOSAMIGA:	con byte 1;		# Amiga
GZOSVMS:	con byte 2;		# VMS or OpenVMS
GZOSUNIX:	con byte 3;		# Unix
GZOSVMCMS:	con byte 4;		# VM/CMS
GZOSATARI:	con byte 5;		# Atari TOS
GZOSHPFS:	con byte 6;		# HPFS file system
GZOSMAC:	con byte 7;		# Macintosh
GZOSZSYS:	con byte 8;		# Z-System
GZOSCPM:	con byte 9;		# CP/M
GZOSTOPS20:	con byte 10;		# TOPS-20
GZOSNTFS:	con byte 11;		# NTFS file system
GZOSQDOS:	con byte 12;		# QDOS
GZOSACORN:	con byte 13;		# Acorn RISCOS
GZOSUNK:	con byte 255;

GZCRCPOLY:	con int 16redb88320;
GZOSINFERNO:	con GZOSUNIX;

# huffman code table
Huff: adt
{
	bits:		int;		# length of the code
	encode:		int;		# the code
};

# huffman decode table
DeHuff: adt
{
	l1:		array of L1;	# the table
	nb1:		int;		# no. of bits in first level
	nb2:		int;		# no. of bits in second level
};

# first level of decode table
L1: adt
{
	bits:		int;		# length of the code
	decode:		int;		# the symbol
	l2:		array of L2;
};

# second level
L2: adt
{
	bits:		int;		# length of the code
	decode:		int;		# the symbol
};

DeflateUnc:	con 0;			# uncompressed block
DeflateFix:	con 1;			# fixed huffman codes
DeflateDyn:	con 2;			# dynamic huffman codes
DeflateErr:	con 3;			# reserved BTYPE (error)

DeflateEob:	con 256;		# end of block code in lit/len book

LenStart:	con 257;		# start of length codes in litlen
LenEnd:		con 285;		# greatest valid length code
Nlitlen:	con 288;		# number of litlen codes
Noff:		con 30;			# number of offset codes
Nclen:		con 19;			# number of codelen codes

MaxHuffBits:	con 15;			# max bits in a huffman code
RunlenBits:	con 7;			# max bits in a run-length huffman code
MaxOff:		con 32*1024;		# max lempel-ziv distance

Blocksize: con 32 * 1024;

# tables from RFC 1951, section 3.2.5
litlenbase := array[Noff] of
{
	3, 4, 5, 6, 7, 8, 9, 10, 11, 13,
	15, 17, 19, 23, 27, 31, 35, 43, 51, 59,
	67, 83, 99, 115, 131, 163, 195, 227, 258
};

litlenextra := array[Noff] of
{
	0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1,
	2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4,
	5, 5, 5, 5, 0
};

offbase := array[Noff] of
{
	1, 2, 3, 4, 5, 7, 9, 13, 17, 25,
	33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
	1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
};

offextra := array[Noff] of
{
	0,  0,  0,  0,  1,  1,  2,  2,  3,  3,
	4,  4,  5,  5,  6,  6,  7,  7,  8,  8,
	9,  9,  10, 10, 11, 11, 12, 12, 13, 13
};

# order of run-length codes
clenorder := array[Nclen] of
{
	16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
};

# fixed huffman tables
litlentab: array of Huff;
offtab: array of Huff;

# their decoding table counterparts
litlendec: ref DeHuff;
offdec: ref DeHuff;

revtab: array of byte;	# bit reversal for endian swap of huffman codes
mask: array of int;		# for masking low-order n bits of an int

State: adt {
	ibuf, obuf: array of byte;
	c: chan of ref Rq;
	rc: chan of int;
	in: int;		# next byte to consume from input buffer
	ein: int;		# valid bytes in input buffer
	out: int;		# valid bytes in output buffer
	hist: array of byte;	# history buffer for lempel-ziv backward references
	usehist: int;		# == 1 if 'hist' is valid
	crctab: array of int;
	crc, tot: int;
	
	reg: int;		# 24-bit shift register
	nbits: int;		# number of valid bits in reg
	svreg: int;		# save reg for efficient ungets
	svn: int;		# number of bits gotten in last call to getn()
	# reg bits are consumed from right to left
	# so low-order byte of reg came first in the input stream
	headers: int;
};


init()
{
	sys = load Sys Sys->PATH;

	# byte reverse table
	revtab = array[256] of byte;
	for(i := 0; i < 256; i++){
		revtab[i] = byte 0;
		for(j := 0; j < 8; j++) {
			if(i & (1 << j))
				revtab[i] |= byte 16r80 >> j;
		}
	}

	# bit-masking table
	mask = array[MaxHuffBits+1] of int;
	for(i = 0; i <= MaxHuffBits; i++)
		mask[i] = (1 << i) - 1;

	litlentab = array[Nlitlen] of Huff;

	# static litlen bit lengths
	for(i = 0; i < 144; i++)
		litlentab[i].bits = 8;
	for(i = 144; i < 256; i++)
		litlentab[i].bits = 9;
	for(i = 256; i < 280; i++)
		litlentab[i].bits = 7;
	for(i = 280; i < Nlitlen; i++)
		litlentab[i].bits = 8;

	bitcount := array[MaxHuffBits+1] of { * => 0 };
	bitcount[8] += 144 - 0;
	bitcount[9] += 256 - 144;
	bitcount[7] += 280 - 256;
	bitcount[8] += Nlitlen - 280;

	hufftabinit(litlentab, Nlitlen, bitcount, 9);
	litlendec = decodeinit(litlentab, Nlitlen, 9, 0);

	offtab = array[Noff] of Huff;

	# static offset bit lengths
	for(i = 0; i < Noff; i++)
		offtab[i].bits = 5;

	for(i = 0; i < 5; i++)
		bitcount[i] = 0;
	bitcount[5] = Noff;

	hufftabinit(offtab, Noff, bitcount, 5);
	offdec = decodeinit(offtab, Noff, 5, 0);
}

start(params: string): chan of ref Rq
{
	s := ref State;
	s.c = chan of ref Rq;
	s.rc = chan of int;
	s.ibuf = array[Blocksize] of byte;
	s.obuf = array[Blocksize] of byte;
	s.in = 0;
	s.ein = 0;
	s.out = 0;
	s.usehist = 0;
	s.reg = 0;
	s.nbits = 0;
	s.crc = 0;
	s.tot = 0;
	s.hist = array[Blocksize] of byte;
	s.headers = (params != nil && params[0] == 'h');
	if (s.headers)
		s.crctab = mkcrctab(GZCRCPOLY);
	spawn inflate(s);
	return s.c;
}

inflate(s: ref State)
{
	s.c <-= ref Rq.Start(sys->pctl(0, nil));
	if (s.headers)
		header(s);

	for(;;) {
		bfinal := getn(s, 1, 0);
		btype := getn(s, 2, 0);
		case(btype) {
		DeflateUnc =>
			flushbits(s);
			unclen := getb(s);
			unclen |= getb(s) << 8;
			nlen := getb(s);
			nlen |= getb(s) << 8;
			if(unclen != (~nlen & 16rFFFF))
				fatal(s, "corrupted data");
			for(; unclen > 0; unclen--) {
				# inline putb(s, getb(s));
				b := byte getb(s);
				if(s.out >= MaxOff)
					flushout(s);
				s.obuf[s.out++] = b;
			}
		DeflateFix =>
			decodeblock(s, litlendec, offdec);
		DeflateDyn =>
			dynhuff(s);
		DeflateErr =>
			fatal(s, "bad block type");
		}
		if(bfinal) {
			if(s.out) {
				if (s.headers)
					outblock(s);
				s.c <- = ref Rq.Result(s.obuf[0:s.out], s.rc);
				flag := <- s.rc;
				if (flag == -1)
					exit;
			}
			flushbits(s);
			if (s.headers)
				footer(s);
			s.c <-= ref Rq.Finished(s.ibuf[s.in - s.nbits/8:s.ein]);
			exit;
		}
	}
}

header(s: ref State)
{
	if(byte getb(s) != GZMAGIC1 || byte getb(s) != GZMAGIC2)
		fatal(s, "not a gzip file");

	if(byte getb(s) != GZDEFLATE)
		fatal(s, "not compressed with deflate");

	flags := getb(s);
	if(flags & ~GZFMASK)
		fatal(s, "reserved flag bits set");

	# read modification time (ignored)
	mtime := getb(s);
	mtime |= (getb(s) << 8);
	mtime |= (getb(s) << 16);
	mtime |= (getb(s) << 24);
	s.c <-= ref Rq.Info("mtime " + string mtime);
	getb(s);	# xfl
	getb(s);	# os

	# skip optional "extra field"
	if(flags & GZFEXTRA) {
		skip := getb(s);
		skip |= getb(s) << 8;
		while (skip-- > 0)
			getb(s);
	}

	# read optional filename (ignored)
	file: string;
	if(flags & GZFNAME){
		n := 0;
		while(c := getb(s))
			file[n++] = c;
		s.c <-= ref Rq.Info("file " + file);
	}

	# skip optional comment
	if(flags & GZFCOMMENT) {
		while(getb(s))
			;
	}

	# skip optional CRC16 field
	if(flags & GZFHCRC) {
		getb(s);
		getb(s);
	}
}

footer(s: ref State)
{
	fcrc := getword(s);
	if(s.crc != fcrc)
		fatal(s, sys->sprint("crc mismatch: computed %ux, expected %ux", s.crc, fcrc));
	ftot := getword(s);
	if(s.tot != ftot)
		fatal(s, sys->sprint("byte count mismatch: computed %d, expected %d", s.tot, ftot));
}

getword(s: ref State): int
{
	n := 0;
	for(i := 0; i < 4; i++)
		n |= getb(s) << (8 * i);
	return n;
}

#
# uncompress a block using given huffman decoding tables
#
decodeblock(s: ref State, litlendec, offdec: ref DeHuff)
{
	b: byte;

	for(;;) {
		sym := decodesym(s, litlendec);
		if(sym < DeflateEob) {		# literal byte
			# inline putb(s, byte sym);
			b = byte sym;
			if(s.out >= MaxOff)
				flushout(s);
			s.obuf[s.out++] = b;
		} else if(sym == DeflateEob) {	# End-of-block
			break;
		} else {			# lempel-ziv <length, distance>
			if(sym > LenEnd)
				fatal(s, "symbol too long");
			xbits := litlenextra[sym - LenStart];
			xtra := 0;
			if(xbits)
				xtra = getn(s, xbits, 0);
			length := litlenbase[sym - LenStart] + xtra;

			sym = decodesym(s, offdec);
			if(sym >= Noff)
				fatal(s, "symbol too long");
			xbits = offextra[sym];
			if(xbits)
				xtra = getn(s, xbits, 0);
			else
				xtra = 0;
			dist := offbase[sym] + xtra;
			if(dist > s.out && s.usehist == 0)
				fatal(s, "corrupted data");
			for(i := 0; i < length; i++) {
				# inline putb(lzbyte(dist));
				ix := s.out - dist;
				if(dist <= s.out)
					b = s.obuf[ix];
				else
					b = s.hist[MaxOff + ix];
				if(s.out >= MaxOff)
					flushout(s);
				s.obuf[s.out++] = b;
			}
		}
	}
}

#
# decode next symbol in input stream using given huffman decoding table
#
decodesym(s: ref State, dec: ref DeHuff): int
{
	code, bits, n: int;

	l1 := dec.l1;
	nb1 := dec.nb1;
	nb2 := dec.nb2;

	code = getn(s, nb1, 1);
	l2 := l1[code].l2;
	if(l2 == nil) {		# first level table has answer
		bits = l1[code].bits;
		if(bits == 0)
			fatal(s, "corrupt data");
		if(nb1 > bits) {
			# inline ungetn(nb1 - bits);
			n = nb1 - bits;
			s.reg = s.svreg >> (s.svn - n);
			s.nbits += n;
		}
		return l1[code].decode;
	}
	# must advance to second-level table
	code = getn(s, nb2, 1);
	bits = l2[code].bits;
	if(bits == 0)
		fatal(s, "corrupt data");
	if(nb1 + nb2 > bits) {
		# inline ungetn(nb1 + nb2 - bits);
		n = nb1 + nb2 - bits;
		s.reg = s.svreg >> (s.svn - n);
		s.nbits += n;
	}
	return l2[code].decode;
}

#
# uncompress a block that was encoded with dynamic huffman codes
# RFC 1951, section 3.2.7
#
dynhuff(s: ref State)
{
	hlit := getn(s, 5, 0) + 257;
	hdist := getn(s, 5, 0) + 1;
	hclen := getn(s, 4, 0) + 4;
	if(hlit > Nlitlen || hlit < 257 || hdist > Noff)
		fatal(s, "corrupt data");

	runlentab := array[Nclen] of { * => Huff(0, 0) };
	count := array[RunlenBits+1] of { * => 0 };
	for(i := 0; i < hclen; i++) {
		nb := getn(s, 3, 0);
		if(nb) {
			runlentab[clenorder[i]].bits = nb;
			count[nb]++;
		}
	}
	hufftabinit(runlentab, Nclen, count, RunlenBits);
	runlendec := decodeinit(runlentab, Nclen, RunlenBits, 0);
	if(runlendec == nil)
		fatal(s, "corrupt data");

	lengths := decodelen(s, runlendec, hlit+hdist);
	if(lengths == nil)
		fatal(s, "corrupt length table");

	dlitlendec := decodedyn(s, lengths[0:hlit], hlit, 9);
	doffdec := decodedyn(s, lengths[hlit:], hdist, 5);
	decodeblock(s, dlitlendec, doffdec);
}

#
# return the decoded combined length table for literal and distance alphabets
#
decodelen(s: ref State, runlendec: ref DeHuff, nlen: int): array of int
{
	lengths := array[nlen] of int;
	for(n := 0; n < nlen;) {
		nb := decodesym(s, runlendec);
		nr := 1;
		case nb {
		0 to 15 =>
			;
		16 =>
			nr = getn(s, 2, 0) + 3;
			if(n == 0)
				return nil;
			nb = lengths[n-1];
		17 =>
			nr = getn(s, 3, 0) + 3;
			nb = 0;
		18 =>
			nr = getn(s, 7, 0) + 11;
			nb = 0;
		* =>
			return nil;
		}
		if(n+nr > nlen)
			return nil;
		while(--nr >= 0)
			lengths[n++] = nb;
	}
	return lengths;
}

#
# (1) read a dynamic huffman code from the input stream
# (2) decode it using the run-length huffman code
# (3) return the decode table for the dynamic huffman code
#
decodedyn(s: ref State, lengths: array of int, nlen, nb1: int): ref DeHuff
{
	hufftab := array[nlen] of Huff;
	count := array[MaxHuffBits+1] of { * => 0 };

	maxnb := 0;
	for(n := 0; n < nlen; n++) {
		c := lengths[n];
		if(c) {
			hufftab[n].bits = c;
			count[c]++;
			if(c > maxnb)
				maxnb = c;
		}else
			hufftab[n].bits = 0;
		hufftab[n].encode = 0;
	}
	hufftabinit(hufftab, nlen, count, maxnb);
	nb2 := 0;
	if(maxnb > nb1)
		nb2 = maxnb - nb1;
	d := decodeinit(hufftab, nlen, nb1, nb2);
	if (d == nil)
		fatal(s, "decodeinit failed");
	return d;
}

#
# RFC 1951, section 3.2.2
#
hufftabinit(tab: array of Huff, n: int, bitcount: array of int, nbits: int)
{
	nc := array[MaxHuffBits+1] of int;

	code := 0;
	for(bits := 1; bits <= nbits; bits++) {
		code = (code + bitcount[bits-1]) << 1;
		nc[bits] = code;
	}

	for(i := 0; i < n; i++) {
		bits = tab[i].bits;
		# differences from Deflate module:
		#  (1) leave huffman code right-justified in encode
		#  (2) don't reverse it
		if(bits != 0)
			tab[i].encode = nc[bits]++;
	}
}

#
# convert 'array of Huff' produced by hufftabinit()
# into 2-level lookup table for decoding
#
# nb1(nb2): number of bits handled by first(second)-level table
#
decodeinit(tab: array of Huff, n, nb1, nb2: int): ref DeHuff
{
	i, j, k, d: int;

	dehuff := ref DeHuff(array[1<<nb1] of { * => L1(0, 0, nil) }, nb1, nb2);
	l1 := dehuff.l1;
	for(i = 0; i < n; i++) {
		bits := tab[i].bits;
		if(bits == 0)
			continue;
		l1x := tab[i].encode;
		if(l1x >= (1 << bits))
			return nil;
		if(bits <= nb1) {
			d = nb1 - bits;
			l1x <<= d;
			k = l1x + mask[d];
			for(j = l1x; j <= k; j++) {
				l1[j].decode = i;
				l1[j].bits = bits;
			}
			continue;
		}
		# advance to second-level table
		d = bits - nb1;
		l2x := l1x & mask[d];
		l1x >>= d;
		if(l1[l1x].l2 == nil)
			l1[l1x].l2 = array[1<<nb2] of { * => L2(0, 0) };
		l2 := l1[l1x].l2;
		d = (nb1 + nb2) - bits;
		l2x <<= d;
		k = l2x + mask[d];
		for(j = l2x; j <= k; j++) {
			l2[j].decode = i;
			l2[j].bits = bits;
		}
	}

	return dehuff;
}

#
# get next byte from reg
# assumptions:
#  (1) flushbits() has been called
#  (2) ungetn() won't be called after a getb()
#
getb(s: ref State): int
{
	if(s.nbits < 8)
		need(s, 8);
	b := byte s.reg;
	s.reg >>= 8;
	s.nbits -= 8;
	return int b;
}

#
# get next n bits from reg; if r != 0, reverse the bits
#
getn(s: ref State, n, r: int): int
{
	if(s.nbits < n)
		need(s, n);
	s.svreg = s.reg;
	s.svn = n;
	i := s.reg & mask[n];
	s.reg >>= n;
	s.nbits -= n;
	if(r) {
		if(n <= 8) {
			i = int revtab[i];
			i >>= 8 - n;
		} else {
			i = ((int revtab[i & 16rff]) << 8)
				| (int revtab[i >> 8]);
			i >>= 16 - n;
		}
	}
	return i;
}

#
# ensure that at least n bits are available in reg
#
need(s: ref State, n: int)
{
	while(s.nbits < n) {
		if(s.in >= s.ein) {
			s.c <-= ref Rq.Fill(s.ibuf, s.rc);
			s.ein = <- s.rc;
			if (s.ein < 0)
				exit;
			if (s.ein == 0)
				fatal(s, "premature end of stream");
			s.in = 0;
		}
		s.reg = ((int s.ibuf[s.in++]) << s.nbits) | s.reg;
		s.nbits += 8;
	}
}

#
# if partial byte consumed from reg, dispose of remaining bits
#
flushbits(s: ref State)
{
	drek := s.nbits % 8;
	if(drek) {
		s.reg >>= drek;
		s.nbits -= drek;
	}
}

#
# output buffer is full, so flush it
#
flushout(s: ref State)
{
	if (s.headers)
		outblock(s);
	s.c <-= ref Rq.Result(s.obuf[0:s.out], s.rc);
	flag := <- s.rc;
	if (flag == -1)
		exit;
	buf := s.hist;
	s.hist = s.obuf;
	s.usehist = 1;
	s.obuf = buf;
	s.out = 0;
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

outblock(s: ref State)
{
	buf := s.obuf;
	n := s.out;
	crc := s.crc;
	crc ^= int 16rffffffff;
	for(i := 0; i < n; i++)
		crc = s.crctab[int(byte crc ^ buf[i])] ^ ((crc >> 8) & 16r00ffffff);
	s.crc = crc ^ int 16rffffffff;
	s.tot += n;
}

#
# irrecoverable error; invariably denotes data corruption
#
fatal(s: ref State, e: string)
{
	s.c <-= ref Rq.Error(e);
	exit;
}
