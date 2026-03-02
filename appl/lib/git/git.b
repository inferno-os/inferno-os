implement Git;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "keyring.m";
	keyring: Keyring;
include "string.m";
	str: String;
include "filter.m";
	inflate: Filter;
	deflate: Filter;
include "encoding.m";
	base16: Encoding;
	base64: Encoding;
include "dial.m";
	dial: Dial;
include "url.m";
	url: Url;
	ParsedUrl: import url;
include "webclient.m";
	webclient: Webclient;
	Header: import webclient;
include "crc.m";
	crcmod: Crc;
	CRCstate: import crcmod;

include "git.m";

# Internal type for pack indexing
Idxent: adt {
	hash: Hash;
	offset: big;
	crc: int;
};

# HTTP body reader with chunked transfer decoding
BodyReader: adt {
	fd: ref Sys->FD;
	chunked: int;		# 1 if Transfer-Encoding: chunked
	chunkrem: int;		# bytes remaining in current chunk
	started: int;		# 1 after first chunk header read
	eof: int;
};

stderr: ref Sys->FD;

init(): string
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		return sprint("load Bufio: %r");

	keyring = load Keyring Keyring->PATH;
	if(keyring == nil)
		return sprint("load Keyring: %r");

	str = load String String->PATH;
	if(str == nil)
		return sprint("load String: %r");

	inflate = load Filter Filter->INFLATEPATH;
	if(inflate == nil)
		return sprint("load inflate: %r");
	inflate->init();

	deflate = load Filter Filter->DEFLATEPATH;
	if(deflate == nil)
		return sprint("load deflate: %r");
	deflate->init();

	base16 = load Encoding Encoding->BASE16PATH;
	if(base16 == nil)
		return sprint("load base16: %r");

	base64 = load Encoding Encoding->BASE64PATH;
	if(base64 == nil)
		return sprint("load base64: %r");

	dial = load Dial Dial->PATH;
	if(dial == nil)
		return sprint("load Dial: %r");

	url = load Url Url->PATH;
	if(url == nil)
		return sprint("load Url: %r");
	url->init();

	webclient = load Webclient Webclient->PATH;
	if(webclient == nil)
		return sprint("load Webclient: %r");
	err := webclient->init();
	if(err != nil)
		return "Webclient init: " + err;

	crcmod = load Crc Crc->PATH;
	if(crcmod == nil)
		return sprint("load Crc: %r");

	return nil;
}

# =====================================================================
# Hash ADT
# =====================================================================

Hash.eq(h: self Hash, o: Hash): int
{
	if(h.a == nil || o.a == nil)
		return h.a == nil && o.a == nil;
	for(i := 0; i < SHA1SIZE; i++)
		if(h.a[i] != o.a[i])
			return 0;
	return 1;
}

Hash.hex(h: self Hash): string
{
	if(h.a == nil)
		return "0000000000000000000000000000000000000000";
	s := "";
	for(i := 0; i < SHA1SIZE; i++)
		s += sprint("%02x", int h.a[i]);
	return s;
}

Hash.isnil(h: self Hash): int
{
	if(h.a == nil)
		return 1;
	for(i := 0; i < SHA1SIZE; i++)
		if(h.a[i] != byte 0)
			return 0;
	return 1;
}

hexval(c: int): int
{
	if(c >= '0' && c <= '9')
		return c - '0';
	if(c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if(c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}

parsehash(s: string): (Hash, string)
{
	if(len s < HEXSIZE)
		return (nullhash(), "short hash string");
	a := array [SHA1SIZE] of byte;
	for(i := 0; i < SHA1SIZE; i++) {
		hi := hexval(s[2*i]);
		lo := hexval(s[2*i+1]);
		if(hi < 0 || lo < 0)
			return (nullhash(), "bad hex in hash");
		a[i] = byte ((hi << 4) | lo);
	}
	h: Hash;
	h.a = a;
	return (h, nil);
}

nullhash(): Hash
{
	h: Hash;
	h.a = array [SHA1SIZE] of { * => byte 0 };
	return h;
}

hashobj(otype: int, data: array of byte): Hash
{
	# Git object hash: SHA-1("type size\0" + data)
	# Build header with explicit null byte (Limbo strings may truncate at \0)
	hdrstr := typename(otype) + " " + string len data;
	hdrbytes := array of byte hdrstr;
	hdr := array [len hdrbytes + 1] of byte;
	for(i := 0; i < len hdrbytes; i++)
		hdr[i] = hdrbytes[i];
	hdr[len hdrbytes] = byte 0;
	digest := array [Keyring->SHA1dlen] of byte;
	state := keyring->sha1(hdr, len hdr, nil, nil);
	keyring->sha1(data, len data, digest, state);
	h: Hash;
	h.a = digest;
	return h;
}

typename(otype: int): string
{
	case otype {
	OBJ_COMMIT => return "commit";
	OBJ_TREE   => return "tree";
	OBJ_BLOB   => return "blob";
	OBJ_TAG    => return "tag";
	}
	return "unknown";
}

typenum(name: string): int
{
	case name {
	"commit" => return OBJ_COMMIT;
	"tree"   => return OBJ_TREE;
	"blob"   => return OBJ_BLOB;
	"tag"    => return OBJ_TAG;
	}
	return 0;
}

# =====================================================================
# Inflate helpers
# =====================================================================

# Decompress a complete zlib-compressed buffer.
zdecompress(input: array of byte): (array of byte, string)
{
	rq := inflate->start("z");
	out: list of array of byte;
	total := 0;
	inoff := 0;

	for(;;) {
		pick m := <-rq {
		Start =>
			;
		Fill =>
			buf := m.buf;
			n := len input - inoff;
			if(n > len buf)
				n = len buf;
			for(k := 0; k < n; k++)
				buf[k] = input[inoff + k];
			inoff += n;
			m.reply <-= n;
		Result =>
			if(len m.buf > 0) {
				chunk := array [len m.buf] of byte;
				copybytes(chunk, 0, m.buf, 0, len m.buf);
				out = chunk :: out;
				total += len chunk;
			}
			m.reply <-= 0;
		Finished =>
			return (concatbytes(out, total), nil);
		Error =>
			return (nil, "inflate: " + m.e);
		}
	}
}

# Decompress from a file at a given offset.
# Returns (decompressed_data, consumed_bytes, err).
zdecompress_fd(fd: ref Sys->FD, offset: big, nil: int): (array of byte, int, string)
{
	sys->seek(fd, offset, Sys->SEEKSTART);

	rq := inflate->start("z");
	out: list of array of byte;
	total := 0;
	consumed := 0;

	for(;;) {
		pick m := <-rq {
		Start =>
			;
		Fill =>
			n := sys->read(fd, m.buf, len m.buf);
			if(n > 0)
				consumed += n;
			m.reply <-= n;
		Result =>
			if(len m.buf > 0) {
				chunk := array [len m.buf] of byte;
				copybytes(chunk, 0, m.buf, 0, len m.buf);
				out = chunk :: out;
				total += len chunk;
			}
			m.reply <-= 0;
		Finished =>
			# m.buf contains unconsumed input data
			consumed -= len m.buf;
			return (concatbytes(out, total), consumed, nil);
		Error =>
			return (nil, consumed, "inflate: " + m.e);
		}
	}
}

copybytes(dst: array of byte, doff: int, src: array of byte, soff, n: int)
{
	for(i := 0; i < n; i++)
		dst[doff + i] = src[soff + i];
}

concatbytes(chunks: list of array of byte, total: int): array of byte
{
	result := array [total] of byte;
	off := total;
	for(l := chunks; l != nil; l = tl l) {
		c := hd l;
		off -= len c;
		copybytes(result, off, c, 0, len c);
	}
	return result;
}

# =====================================================================
# Pkt-line Protocol
# =====================================================================

pktread(fd: ref Sys->FD): (array of byte, string)
{
	# Read 4-byte hex length
	lenbuf := array [4] of byte;
	n := readn(fd, lenbuf, 4);
	if(n != 4)
		return (nil, "pktread: short length");

	pktlen := 0;
	for(i := 0; i < 4; i++) {
		v := hexval(int lenbuf[i]);
		if(v < 0)
			return (nil, "pktread: bad hex digit");
		pktlen = (pktlen << 4) | v;
	}

	# Flush packet
	if(pktlen == 0)
		return (nil, nil);

	# Delimiter packet
	if(pktlen == 1)
		return (array [0] of byte, nil);

	if(pktlen < 4)
		return (nil, "pktread: invalid length");

	datalen := pktlen - 4;
	data := array [datalen] of byte;
	n = readn(fd, data, datalen);
	if(n != datalen)
		return (nil, sprint("pktread: short data (%d/%d)", n, datalen));

	return (data, nil);
}

# Read a pkt-line from a BodyReader (handles chunked transfer encoding).
bpktread(br: ref BodyReader): (array of byte, string)
{
	lenbuf := array [4] of byte;
	n := breadn(br, lenbuf, 4);
	if(n != 4)
		return (nil, "pktread: short length");

	pktlen := 0;
	for(i := 0; i < 4; i++) {
		v := hexval(int lenbuf[i]);
		if(v < 0)
			return (nil, sprint("pktread: bad hex digit (0x%02x at pos %d)", int lenbuf[i], i));
		pktlen = (pktlen << 4) | v;
	}

	if(pktlen == 0)
		return (nil, nil);

	if(pktlen == 1)
		return (array [0] of byte, nil);

	if(pktlen < 4)
		return (nil, "pktread: invalid length");

	datalen := pktlen - 4;
	data := array [datalen] of byte;
	n = breadn(br, data, datalen);
	if(n != datalen)
		return (nil, sprint("pktread: short data (%d/%d)", n, datalen));

	return (data, nil);
}

pktwrite(fd: ref Sys->FD, data: array of byte): string
{
	pktlen := len data + 4;
	hdr := array of byte sprint("%04x", pktlen);
	if(sys->write(fd, hdr, 4) != 4)
		return "pktwrite: header write failed";
	if(sys->write(fd, data, len data) != len data)
		return "pktwrite: data write failed";
	return nil;
}

pktflush(fd: ref Sys->FD): string
{
	flush := array of byte "0000";
	if(sys->write(fd, flush, 4) != 4)
		return "pktflush: write failed";
	return nil;
}

readn(fd: ref Sys->FD, buf: array of byte, n: int): int
{
	total := 0;
	while(total < n) {
		r := sys->read(fd, buf[total:], n - total);
		if(r <= 0)
			break;
		total += r;
	}
	return total;
}

# Read from a BodyReader, handling chunked transfer encoding.
bread(br: ref BodyReader, buf: array of byte, n: int): int
{
	if(br.eof)
		return 0;

	if(!br.chunked)
		return sys->read(br.fd, buf, n);

	# Chunked mode: read through chunk boundaries
	total := 0;
	while(total < n && !br.eof) {
		if(br.chunkrem == 0) {
			# Need to read next chunk header
			if(br.started) {
				# Consume trailing \r\n from previous chunk
				crlf := array [2] of byte;
				readn(br.fd, crlf, 2);
			}
			br.started = 1;

			# Read chunk size line: hex digits terminated by \r\n
			sizebuf := array [20] of byte;
			slen := 0;
			for(;;) {
				if(slen >= len sizebuf)
					break;
				r := sys->read(br.fd, sizebuf[slen:slen+1], 1);
				if(r <= 0) {
					br.eof = 1;
					return total;
				}
				if(slen > 0 && sizebuf[slen-1] == byte '\r' && sizebuf[slen] == byte '\n') {
					slen--;  # exclude \r
					break;
				}
				slen++;
			}

			# Parse hex chunk size
			chunksize := 0;
			for(i := 0; i < slen; i++) {
				v := hexval(int sizebuf[i]);
				if(v < 0)
					break;
				chunksize = (chunksize << 4) | v;
			}
			if(chunksize == 0) {
				br.eof = 1;
				return total;
			}
			br.chunkrem = chunksize;
		}

		# Read from current chunk
		want := n - total;
		if(want > br.chunkrem)
			want = br.chunkrem;
		r := sys->read(br.fd, buf[total:], want);
		if(r <= 0) {
			br.eof = 1;
			return total;
		}
		total += r;
		br.chunkrem -= r;
	}
	return total;
}

# Read exactly n bytes from BodyReader.
breadn(br: ref BodyReader, buf: array of byte, n: int): int
{
	total := 0;
	while(total < n) {
		r := bread(br, buf[total:], n - total);
		if(r <= 0)
			break;
		total += r;
	}
	return total;
}

# =====================================================================
# Object Parsing
# =====================================================================

parsecommit(data: array of byte): (ref Commit, string)
{
	s := string data;
	c := ref Commit;
	c.parents = nil;

	for(;;) {
		(line, rest) := splitline(s);
		if(line == nil || line == "") {
			c.msg = rest;
			break;
		}
		s = rest;

		(key, val) := splitfirst(line, ' ');
		case key {
		"tree" =>
			(h, err) := parsehash(val);
			if(err != nil)
				return (nil, "bad tree hash: " + err);
			c.tree = h;
		"parent" =>
			(h, err) := parsehash(val);
			if(err != nil)
				return (nil, "bad parent hash: " + err);
			c.parents = h :: c.parents;
		"author" =>
			c.author = val;
		"committer" =>
			c.committer = val;
		}
	}

	c.parents = revhashes(c.parents);
	return (c, nil);
}

parsetree(data: array of byte): (array of TreeEntry, string)
{
	entries: list of TreeEntry;
	i := 0;
	while(i < len data) {
		# Format: "mode name\0<20-byte-hash>"
		sp := i;
		while(sp < len data && data[sp] != byte ' ')
			sp++;
		if(sp >= len data)
			return (nil, "malformed tree: no space");

		mode := 0;
		for(j := i; j < sp; j++) {
			c := int data[j] - '0';
			if(c < 0 || c > 7)
				return (nil, "bad octal in tree mode");
			mode = (mode << 3) | c;
		}

		nul := sp + 1;
		while(nul < len data && data[nul] != byte 0)
			nul++;
		if(nul >= len data)
			return (nil, "malformed tree: no null");

		name := string data[sp+1:nul];

		hashstart := nul + 1;
		if(hashstart + SHA1SIZE > len data)
			return (nil, "malformed tree: short hash");
		h: Hash;
		h.a = array [SHA1SIZE] of byte;
		copybytes(h.a, 0, data, hashstart, SHA1SIZE);

		e: TreeEntry;
		e.mode = mode;
		e.name = name;
		e.hash = h;
		entries = e :: entries;

		i = hashstart + SHA1SIZE;
	}

	n := 0;
	for(l := entries; l != nil; l = tl l)
		n++;
	result := array [n] of TreeEntry;
	i = n - 1;
	for(l = entries; l != nil; l = tl l)
		result[i--] = hd l;

	return (result, nil);
}

parsetag(data: array of byte): (ref Tag, string)
{
	s := string data;
	t := ref Tag;

	for(;;) {
		(line, rest) := splitline(s);
		if(line == nil || line == "") {
			t.msg = rest;
			break;
		}
		s = rest;

		(key, val) := splitfirst(line, ' ');
		case key {
		"object" =>
			(h, err) := parsehash(val);
			if(err != nil)
				return (nil, "bad tag object hash: " + err);
			t.obj = h;
		"type" =>
			t.otype = typenum(val);
		"tag" =>
			t.name = val;
		"tagger" =>
			t.tagger = val;
		}
	}

	return (t, nil);
}

# =====================================================================
# Delta Application
# =====================================================================

applydelta(base, delta: array of byte): (array of byte, string)
{
	if(len delta < 2)
		return (nil, "delta too short");

	off := 0;
	srcsize := 0;
	tgtsize := 0;

	# Read source size (varint)
	(srcsize, off) = readvarint(delta, off);
	if(srcsize != len base)
		return (nil, sprint("delta source size mismatch: %d vs %d", srcsize, len base));

	# Read target size (varint)
	(tgtsize, off) = readvarint(delta, off);

	result := array [tgtsize] of byte;
	roff := 0;

	while(off < len delta) {
		cmd := int delta[off++];

		if(cmd & 16r80) {
			# Copy from source
			cpoff := 0;
			cpsize := 0;
			if(cmd & 16r01) { cpoff |= int delta[off++]; }
			if(cmd & 16r02) { cpoff |= int delta[off++] << 8; }
			if(cmd & 16r04) { cpoff |= int delta[off++] << 16; }
			if(cmd & 16r08) { cpoff |= int delta[off++] << 24; }
			if(cmd & 16r10) { cpsize |= int delta[off++]; }
			if(cmd & 16r20) { cpsize |= int delta[off++] << 8; }
			if(cmd & 16r40) { cpsize |= int delta[off++] << 16; }
			if(cpsize == 0)
				cpsize = 16r10000;

			if(cpoff + cpsize > len base)
				return (nil, "delta copy out of bounds");
			if(roff + cpsize > tgtsize)
				return (nil, "delta result overflow");
			copybytes(result, roff, base, cpoff, cpsize);
			roff += cpsize;
		} else if(cmd != 0) {
			# Insert literal bytes
			n := cmd;
			if(off + n > len delta)
				return (nil, "delta insert out of bounds");
			if(roff + n > tgtsize)
				return (nil, "delta result overflow");
			copybytes(result, roff, delta, off, n);
			off += n;
			roff += n;
		} else {
			return (nil, "delta: reserved command 0");
		}
	}

	if(roff != tgtsize)
		return (nil, sprint("delta: result size mismatch %d vs %d", roff, tgtsize));

	return (result, nil);
}

readvarint(data: array of byte, off: int): (int, int)
{
	val := 0;
	shift := 0;
	for(;;) {
		if(off >= len data)
			return (val, off);
		b := int data[off++];
		val |= (b & 16r7f) << shift;
		if((b & 16r80) == 0)
			break;
		shift += 7;
	}
	return (val, off);
}

# =====================================================================
# Pack Index
# =====================================================================

PackIdx.find(idx: self ref PackIdx, h: Hash): (big, int)
{
	if(h.a == nil)
		return (big 0, 0);

	fb := int h.a[0];
	lo := 0;
	if(fb > 0)
		lo = idx.fanout[fb - 1];
	hi := idx.fanout[fb];

	while(lo < hi) {
		mid := (lo + hi) / 2;
		cmp := hashcmp(idx.hashes, mid * SHA1SIZE, h.a);
		if(cmp < 0)
			lo = mid + 1;
		else if(cmp > 0)
			hi = mid;
		else {
			off := idx.offsets[mid];
			if(off & int 16r80000000) {
				lidx := off & int 16r7fffffff;
				if(idx.largeoffsets != nil && lidx < len idx.largeoffsets)
					return (idx.largeoffsets[lidx], 1);
				return (big 0, 0);
			}
			return (big off, 1);
		}
	}

	return (big 0, 0);
}

hashcmp(hashes: array of byte, off: int, h: array of byte): int
{
	for(i := 0; i < SHA1SIZE; i++) {
		a := int hashes[off + i];
		b := int h[i];
		if(a < b) return -1;
		if(a > b) return 1;
	}
	return 0;
}

readpackidx(idxpath: string): (ref PackIdx, string)
{
	fd := sys->open(idxpath, Sys->OREAD);
	if(fd == nil)
		return (nil, sprint("open %s: %r", idxpath));

	hdr := array [8] of byte;
	if(readn(fd, hdr, 8) != 8)
		return (nil, "short idx header");

	ver := getbe32(hdr, 4);
	if(hdr[0] != byte 16rff || hdr[1] != byte 16r74 || hdr[2] != byte 16r4f || hdr[3] != byte 16r63)
		return (nil, sprint("bad idx magic: %02x%02x%02x%02x", int hdr[0], int hdr[1], int hdr[2], int hdr[3]));
	if(ver != 2)
		return (nil, sprint("unsupported idx version: %d", ver));

	fanbuf := array [256 * 4] of byte;
	if(readn(fd, fanbuf, len fanbuf) != len fanbuf)
		return (nil, "short fanout");
	fanout := array [256] of int;
	for(i := 0; i < 256; i++)
		fanout[i] = getbe32(fanbuf, i * 4);
	nobj := fanout[255];

	hashdata := array [nobj * SHA1SIZE] of byte;
	if(readn(fd, hashdata, len hashdata) != len hashdata)
		return (nil, "short hash data");

	# Skip CRC32s
	crcdata := array [nobj * 4] of byte;
	if(readn(fd, crcdata, len crcdata) != len crcdata)
		return (nil, "short crc data");

	offdata := array [nobj * 4] of byte;
	if(readn(fd, offdata, len offdata) != len offdata)
		return (nil, "short offset data");
	offsets := array [nobj] of int;
	for(i = 0; i < nobj; i++)
		offsets[i] = getbe32(offdata, i * 4);

	nlarge := 0;
	for(i = 0; i < nobj; i++)
		if(offsets[i] & int 16r80000000)
			nlarge++;

	largeoff: array of big;
	if(nlarge > 0) {
		lobuf := array [nlarge * 8] of byte;
		if(readn(fd, lobuf, len lobuf) != len lobuf)
			return (nil, "short large offset data");
		largeoff = array [nlarge] of big;
		for(i = 0; i < nlarge; i++)
			largeoff[i] = getbe64(lobuf, i * 8);
	}

	idx := ref PackIdx(fanout, hashdata, offsets, largeoff, nobj);
	return (idx, nil);
}

# Generate a v2 .idx file from a .pack file
indexpack(packpath: string): string
{
	fd := sys->open(packpath, Sys->OREAD);
	if(fd == nil)
		return sprint("open %s: %r", packpath);

	hdr := array [12] of byte;
	if(readn(fd, hdr, 12) != 12)
		return "short pack header";

	sig := string hdr[0:4];
	if(sig != "PACK")
		return "bad pack signature: " + sig;
	ver := getbe32(hdr, 4);
	if(ver != 2 && ver != 3)
		return sprint("unsupported pack version: %d", ver);
	nobj := getbe32(hdr, 8);

	entries := array [nobj] of Idxent;

	for(i := 0; i < nobj; i++) {
		offset := sys->seek(fd, big 0, Sys->SEEKRELA);

		b := array [1] of byte;
		if(sys->read(fd, b, 1) != 1)
			return sprint("pack: short object header at %bd", offset);

		otype := (int b[0] >> 4) & 7;
		size := int b[0] & 16r0f;
		shift := 4;
		while(int b[0] & 16r80) {
			if(sys->read(fd, b, 1) != 1)
				return "pack: short extended header";
			size |= (int b[0] & 16r7f) << shift;
			shift += 7;
		}

		# For delta types, read the base reference
		case otype {
		OBJ_OFS_DELTA =>
			if(sys->read(fd, b, 1) != 1)
				return "pack: short ofs-delta header";
			negoff := int b[0] & 16r7f;
			while(int b[0] & 16r80) {
				if(sys->read(fd, b, 1) != 1)
					return "pack: short ofs-delta header";
				negoff = ((negoff + 1) << 7) | (int b[0] & 16r7f);
			}
		OBJ_REF_DELTA =>
			basehash := array [SHA1SIZE] of byte;
			if(readn(fd, basehash, SHA1SIZE) != SHA1SIZE)
				return "pack: short ref-delta hash";
		}

		dataoff := sys->seek(fd, big 0, Sys->SEEKRELA);
		(data, consumed, derr) := zdecompress_fd(fd, dataoff, size);
		if(derr != nil)
			return sprint("pack object %d: %s", i, derr);

		h: Hash;
		if(otype >= 1 && otype <= 4) {
			h = hashobj(otype, data);
		} else {
			h = nullhash();
		}

		# Compute CRC32 of raw object bytes (header + compressed data)
		endoff := dataoff + big consumed;
		objlen := int (endoff - offset);
		sys->seek(fd, offset, Sys->SEEKSTART);
		rawbuf := array [objlen] of byte;
		readn(fd, rawbuf, objlen);
		crcstate := crcmod->init(0, int 16rffffffff);
		objcrc := crcmod->crc(crcstate, rawbuf, objlen);

		entries[i] = Idxent(h, offset, objcrc);

		sys->seek(fd, endoff, Sys->SEEKSTART);
	}

	# Second pass: resolve delta objects to compute their hashes
	for(i = 0; i < nobj; i++) {
		if(!entries[i].hash.isnil())
			continue;
		(otype, data, err) := resolvepack(fd, entries[i].offset, entries, nobj);
		if(err != nil)
			return sprint("pack resolve object %d: %s", i, err);
		entries[i].hash = hashobj(otype, data);
	}

	sortidxents(entries, nobj);

	# Build index in memory so we can compute its SHA-1
	# Layout: header(8) + fanout(1024) + hashes(nobj*20) + crcs(nobj*4) + offsets(nobj*4) + packsha(20) + idxsha(20)
	idxsize := 8 + 256*4 + nobj*SHA1SIZE + nobj*4 + nobj*4 + SHA1SIZE + SHA1SIZE;
	idx := array [idxsize] of byte;
	wp := 0;

	# Header: pack idx v2 magic
	idx[wp] = byte 16rff;
	idx[wp+1] = byte 16r74;
	idx[wp+2] = byte 16r4f;
	idx[wp+3] = byte 16r63;
	putbe32(idx, wp + 4, 2);
	wp += 8;

	# Fanout table
	for(i = 0; i < 256; i++) {
		count := 0;
		for(j := 0; j < nobj; j++)
			if(int entries[j].hash.a[0] <= i)
				count++;
		putbe32(idx, wp + i*4, count);
	}
	wp += 256 * 4;

	# SHA-1 hashes
	for(i = 0; i < nobj; i++) {
		copybytes(idx, wp, entries[i].hash.a, 0, SHA1SIZE);
		wp += SHA1SIZE;
	}

	# CRC32 values
	for(i = 0; i < nobj; i++) {
		putbe32(idx, wp, entries[i].crc);
		wp += 4;
	}

	# 4-byte offsets
	for(i = 0; i < nobj; i++) {
		putbe32(idx, wp, int entries[i].offset);
		wp += 4;
	}

	# Pack checksum
	sys->seek(fd, big -20, Sys->SEEKEND);
	packsha := array [SHA1SIZE] of byte;
	readn(fd, packsha, SHA1SIZE);
	copybytes(idx, wp, packsha, 0, SHA1SIZE);
	wp += SHA1SIZE;

	# Compute index checksum (SHA-1 of everything before the checksum)
	idxsha := array [SHA1SIZE] of byte;
	keyring->sha1(idx, wp, idxsha, nil);
	copybytes(idx, wp, idxsha, 0, SHA1SIZE);

	# Write index file
	idxpath := packpath[0:len packpath - 5] + ".idx";
	ofd := sys->create(idxpath, Sys->OWRITE, 8r644);
	if(ofd == nil)
		return sprint("create %s: %r", idxpath);
	sys->write(ofd, idx, len idx);

	return nil;
}

resolvepack(fd: ref Sys->FD, offset: big, entries: array of Idxent, nobj: int): (int, array of byte, string)
{
	sys->seek(fd, offset, Sys->SEEKSTART);

	b := array [1] of byte;
	if(sys->read(fd, b, 1) != 1)
		return (0, nil, "short header");

	otype := (int b[0] >> 4) & 7;
	size := int b[0] & 16r0f;
	shift := 4;
	while(int b[0] & 16r80) {
		if(sys->read(fd, b, 1) != 1)
			return (0, nil, "short header");
		size |= (int b[0] & 16r7f) << shift;
		shift += 7;
	}

	case otype {
	OBJ_COMMIT or OBJ_TREE or OBJ_BLOB or OBJ_TAG =>
		dataoff := sys->seek(fd, big 0, Sys->SEEKRELA);
		(data, nil, derr) := zdecompress_fd(fd, dataoff, size);
		if(derr != nil)
			return (0, nil, derr);
		return (otype, data, nil);

	OBJ_OFS_DELTA =>
		if(sys->read(fd, b, 1) != 1)
			return (0, nil, "short ofs-delta");
		negoff := int b[0] & 16r7f;
		while(int b[0] & 16r80) {
			if(sys->read(fd, b, 1) != 1)
				return (0, nil, "short ofs-delta");
			negoff = ((negoff + 1) << 7) | (int b[0] & 16r7f);
		}
		baseoff := offset - big negoff;

		dataoff := sys->seek(fd, big 0, Sys->SEEKRELA);
		(deltadata, nil, derr) := zdecompress_fd(fd, dataoff, size);
		if(derr != nil)
			return (0, nil, "delta: " + derr);

		(basetype, basedata, berr) := resolvepack(fd, baseoff, entries, nobj);
		if(berr != nil)
			return (0, nil, "base: " + berr);

		(result, aerr) := applydelta(basedata, deltadata);
		if(aerr != nil)
			return (0, nil, "apply: " + aerr);
		return (basetype, result, nil);

	OBJ_REF_DELTA =>
		basehash := array [SHA1SIZE] of byte;
		if(readn(fd, basehash, SHA1SIZE) != SHA1SIZE)
			return (0, nil, "short ref-delta hash");
		bh: Hash;
		bh.a = basehash;

		dataoff := sys->seek(fd, big 0, Sys->SEEKRELA);
		(deltadata, nil, derr) := zdecompress_fd(fd, dataoff, size);
		if(derr != nil)
			return (0, nil, "delta: " + derr);

		baseoffset := big -1;
		for(i := 0; i < nobj; i++) {
			if(entries[i].hash.eq(bh)) {
				baseoffset = entries[i].offset;
				break;
			}
		}
		if(baseoffset < big 0)
			return (0, nil, "ref-delta base not found: " + bh.hex());

		(basetype, basedata, berr) := resolvepack(fd, baseoffset, entries, nobj);
		if(berr != nil)
			return (0, nil, "base: " + berr);

		(result, aerr) := applydelta(basedata, deltadata);
		if(aerr != nil)
			return (0, nil, "apply: " + aerr);
		return (basetype, result, nil);

	* =>
		return (0, nil, sprint("unknown object type %d", otype));
	}
}

sortidxents(a: array of Idxent, n: int)
{
	for(i := 1; i < n; i++) {
		key := a[i];
		j := i - 1;
		while(j >= 0 && hashcmp2(a[j].hash, key.hash) > 0) {
			a[j+1] = a[j];
			j--;
		}
		a[j+1] = key;
	}
}

hashcmp2(a, b: Hash): int
{
	for(i := 0; i < SHA1SIZE; i++) {
		av := int a.a[i];
		bv := int b.a[i];
		if(av < bv) return -1;
		if(av > bv) return 1;
	}
	return 0;
}

# =====================================================================
# Pack File Reading
# =====================================================================

Pack.lookup(p: self ref Pack, h: Hash): (int, array of byte, string)
{
	(offset, found) := p.idx.find(h);
	if(!found)
		return (0, nil, "not found");

	fd := sys->open(p.path, Sys->OREAD);
	if(fd == nil)
		return (0, nil, sprint("open pack %s: %r", p.path));

	return readpackobj(fd, offset);
}

readpackobj(fd: ref Sys->FD, offset: big): (int, array of byte, string)
{
	sys->seek(fd, offset, Sys->SEEKSTART);

	b := array [1] of byte;
	if(sys->read(fd, b, 1) != 1)
		return (0, nil, "short header");

	otype := (int b[0] >> 4) & 7;
	size := int b[0] & 16r0f;
	shift := 4;
	while(int b[0] & 16r80) {
		if(sys->read(fd, b, 1) != 1)
			return (0, nil, "short header");
		size |= (int b[0] & 16r7f) << shift;
		shift += 7;
	}

	case otype {
	OBJ_COMMIT or OBJ_TREE or OBJ_BLOB or OBJ_TAG =>
		dataoff := sys->seek(fd, big 0, Sys->SEEKRELA);
		(data, nil, derr) := zdecompress_fd(fd, dataoff, size);
		if(derr != nil)
			return (0, nil, derr);
		return (otype, data, nil);

	OBJ_OFS_DELTA =>
		if(sys->read(fd, b, 1) != 1)
			return (0, nil, "short ofs-delta");
		negoff := int b[0] & 16r7f;
		while(int b[0] & 16r80) {
			if(sys->read(fd, b, 1) != 1)
				return (0, nil, "short ofs-delta");
			negoff = ((negoff + 1) << 7) | (int b[0] & 16r7f);
		}
		baseoff := offset - big negoff;

		dataoff := sys->seek(fd, big 0, Sys->SEEKRELA);
		(deltadata, nil, derr) := zdecompress_fd(fd, dataoff, size);
		if(derr != nil)
			return (0, nil, derr);

		(basetype, basedata, berr) := readpackobj(fd, baseoff);
		if(berr != nil)
			return (0, nil, berr);

		(result, aerr) := applydelta(basedata, deltadata);
		if(aerr != nil)
			return (0, nil, aerr);
		return (basetype, result, nil);

	OBJ_REF_DELTA =>
		basehash := array [SHA1SIZE] of byte;
		if(readn(fd, basehash, SHA1SIZE) != SHA1SIZE)
			return (0, nil, "short ref-delta hash");

		# REF_DELTA needs full repo context to resolve base by hash.
		# Skip past compressed data.
		dataoff := sys->seek(fd, big 0, Sys->SEEKRELA);
		(nil, nil, derr) := zdecompress_fd(fd, dataoff, size);
		if(derr != nil)
			return (0, nil, derr);

		return (0, nil, "ref-delta requires repo context");

	* =>
		return (0, nil, sprint("unknown pack object type %d", otype));
	}
}

openpack(packpath: string): (ref Pack, string)
{
	idxpath := packpath[0:len packpath - 5] + ".idx";
	(idx, err) := readpackidx(idxpath);
	if(err != nil)
		return (nil, err);
	p := ref Pack(packpath, idx);
	return (p, nil);
}

# =====================================================================
# Repository Operations
# =====================================================================

openrepo(path: string): (ref Repo, string)
{
	(rc, nil) := sys->stat(path);
	if(rc < 0)
		return (nil, sprint("stat %s: %r", path));

	r := ref Repo;
	r.path = path;
	r.packs = nil;

	# Load pack files
	packdir := path + "/objects/pack";
	(prc, nil) := sys->stat(packdir);
	if(prc >= 0) {
		fd := sys->open(packdir, Sys->OREAD);
		if(fd != nil) {
			for(;;) {
				(nread, dirs) := sys->dirread(fd);
				if(nread <= 0)
					break;
				for(i := 0; i < nread; i++) {
					name := dirs[i].name;
					if(len name > 5 && name[len name - 5:] == ".pack") {
						ppath := packdir + "/" + name;
						(p, err) := openpack(ppath);
						if(err == nil)
							r.packs = p :: r.packs;
					}
				}
			}
		}
	}

	return (r, nil);
}

initrepo(path: string, bare: int): (ref Repo, string)
{
	dirs := array [] of {
		path,
		path + "/objects",
		path + "/objects/pack",
		path + "/refs",
		path + "/refs/heads",
		path + "/refs/tags",
		path + "/refs/remotes",
	};

	for(i := 0; i < len dirs; i++) {
		dfd := sys->create(dirs[i], Sys->OREAD, Sys->DMDIR | 8r755);
		if(dfd == nil) {
			(rc, nil) := sys->stat(dirs[i]);
			if(rc < 0)
				return (nil, sprint("mkdir %s: %r", dirs[i]));
		}
	}

	headfd := sys->create(path + "/HEAD", Sys->OWRITE, 8r644);
	if(headfd == nil)
		return (nil, sprint("create HEAD: %r"));
	headdata := array of byte "ref: refs/heads/main\n";
	sys->write(headfd, headdata, len headdata);

	configfd := sys->create(path + "/config", Sys->OWRITE, 8r644);
	if(configfd == nil)
		return (nil, sprint("create config: %r"));
	config := "[core]\n\trepositoryformatversion = 0\n\tbare = ";
	if(bare)
		config += "true\n";
	else
		config += "false\n";
	cfgdata := array of byte config;
	sys->write(configfd, cfgdata, len cfgdata);

	return openrepo(path);
}

Repo.readobj(r: self ref Repo, h: Hash): (int, array of byte, string)
{
	hexstr := h.hex();
	loosepath := r.path + "/objects/" + hexstr[0:2] + "/" + hexstr[2:];
	fd := sys->open(loosepath, Sys->OREAD);
	if(fd != nil) {
		(frc, dstat) := sys->fstat(fd);
		if(frc < 0)
			return (0, nil, sprint("fstat %s: %r", loosepath));
		raw := array [int dstat.length] of byte;
		n := readn(fd, raw, len raw);
		if(n <= 0)
			return (0, nil, sprint("read %s: short", loosepath));
		raw = raw[0:n];

		(decompressed, derr) := zdecompress(raw);
		if(derr != nil)
			return (0, nil, derr);

		nul := -1;
		for(i := 0; i < len decompressed; i++) {
			if(decompressed[i] == byte 0) {
				nul = i;
				break;
			}
		}
		if(nul < 0)
			return (0, nil, "malformed loose object");

		hdrstr := string decompressed[0:nul];
		(typstr, nil) := splitfirst(hdrstr, ' ');
		otype := typenum(typstr);
		if(otype == 0)
			return (0, nil, "unknown object type: " + typstr);

		return (otype, decompressed[nul+1:], nil);
	}

	for(pl := r.packs; pl != nil; pl = tl pl) {
		p := hd pl;
		(otype, data, err) := p.lookup(h);
		if(err == nil)
			return (otype, data, nil);
	}

	return (0, nil, "object not found: " + h.hex());
}

Repo.hasobj(r: self ref Repo, h: Hash): int
{
	(nil, nil, err) := r.readobj(h);
	return err == nil;
}

Repo.readref(r: self ref Repo, name: string): (Hash, string)
{
	refpath := r.path + "/" + name;
	fd := sys->open(refpath, Sys->OREAD);
	if(fd != nil) {
		buf := array [256] of byte;
		n := sys->read(fd, buf, len buf);
		if(n > 0) {
			s := string buf[0:n];
			while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == '\r'))
				s = s[0:len s - 1];

			if(len s > 5 && s[0:5] == "ref: ")
				return r.readref(s[5:]);

			return parsehash(s);
		}
	}

	# Try packed-refs
	pfd := sys->open(r.path + "/packed-refs", Sys->OREAD);
	if(pfd != nil) {
		bio := bufio->fopen(pfd, Bufio->OREAD);
		if(bio != nil) {
			while((line := bio.gets('\n')) != nil) {
				if(len line > 0 && line[0] == '#')
					continue;
				if(len line > 0 && line[len line - 1] == '\n')
					line = line[0:len line - 1];
				(nf, fields) := sys->tokenize(line, " \t");
				if(nf >= 2) {
					fl := tl fields;
					if(fl != nil) {
						refname := hd fl;
						if(refname == name)
							return parsehash(hd fields);
					}
				}
			}
		}
	}

	return (nullhash(), "ref not found: " + name);
}

Repo.listrefs(r: self ref Repo): list of (string, Hash)
{
	refs: list of (string, Hash);
	refs = listrefs_dir(r, r.path + "/refs", "refs", refs);

	pfd := sys->open(r.path + "/packed-refs", Sys->OREAD);
	if(pfd != nil) {
		bio := bufio->fopen(pfd, Bufio->OREAD);
		if(bio != nil) {
			while((line := bio.gets('\n')) != nil) {
				if(len line > 0 && line[0] == '#')
					continue;
				if(len line > 0 && line[len line - 1] == '\n')
					line = line[0:len line - 1];
				(nf, fields) := sys->tokenize(line, " \t");
				if(nf >= 2) {
					fl := tl fields;
					if(fl != nil) {
						refname := hd fl;
						(h, err) := parsehash(hd fields);
						if(err == nil)
							refs = (refname, h) :: refs;
					}
				}
			}
		}
	}

	return refs;
}

listrefs_dir(r: ref Repo, dirpath, prefix: string, refs: list of (string, Hash)): list of (string, Hash)
{
	fd := sys->open(dirpath, Sys->OREAD);
	if(fd == nil)
		return refs;
	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			name := prefix + "/" + dirs[i].name;
			fullpath := dirpath + "/" + dirs[i].name;
			if(dirs[i].qid.qtype & Sys->QTDIR) {
				refs = listrefs_dir(r, fullpath, name, refs);
			} else {
				(h, err) := r.readref(name);
				if(err == nil)
					refs = (name, h) :: refs;
			}
		}
	}
	return refs;
}

Repo.head(r: self ref Repo): (string, string)
{
	fd := sys->open(r.path + "/HEAD", Sys->OREAD);
	if(fd == nil)
		return (nil, sprint("open HEAD: %r"));
	buf := array [256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return (nil, "empty HEAD");
	s := string buf[0:n];
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == '\r'))
		s = s[0:len s - 1];

	if(len s > 5 && s[0:5] == "ref: ")
		return (s[5:], nil);

	return (s, nil);
}

Repo.checkout(r: self ref Repo, treehash: Hash, destpath: string): string
{
	(otype, data, err) := r.readobj(treehash);
	if(err != nil)
		return "read tree: " + err;
	if(otype != OBJ_TREE)
		return "not a tree object";

	(entries, perr) := parsetree(data);
	if(perr != nil)
		return "parse tree: " + perr;

	for(i := 0; i < len entries; i++) {
		e := entries[i];
		path := destpath + "/" + e.name;

		if(e.mode == 8r40000) {
			# Directory — create and recurse
			sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
			cerr := r.checkout(e.hash, path);
			if(cerr != nil)
				return cerr;
		} else if(e.mode == 8r120000) {
			# Symlink — skip silently
			;
		} else {
			# Regular file (100644 or 100755)
			(btype, bdata, berr) := r.readobj(e.hash);
			if(berr != nil)
				return "read blob " + e.name + ": " + berr;
			if(btype != OBJ_BLOB)
				return e.name + ": not a blob";

			perm := 8r644;
			if(e.mode == 8r100755)
				perm = 8r755;
			fd := sys->create(path, Sys->OWRITE, perm);
			if(fd == nil)
				return sprint("create %s: %r", path);
			if(len bdata > 0)
				sys->write(fd, bdata, len bdata);
		}
	}

	return nil;
}

# =====================================================================
# Transport: Smart HTTP
# =====================================================================

discover(remoteurl: string): (list of Ref, list of string, string)
{
	infourl := remoteurl;
	if(len infourl > 0 && infourl[len infourl - 1] == '/')
		infourl = infourl[0:len infourl - 1];
	infourl += "/info/refs?service=git-upload-pack";

	(resp, err) := webclient->get(infourl);
	if(err != nil)
		return (nil, nil, "discover: " + err);
	if(resp.statuscode != 200)
		return (nil, nil, sprint("discover: HTTP %d", resp.statuscode));

	body := resp.body;
	if(body == nil || len body == 0)
		return (nil, nil, "discover: empty response");

	refs: list of Ref;
	caps: list of string;

	off := 0;
	while(off < len body) {
		if(off + 4 > len body)
			break;
		pktlen := 0;
		for(i := 0; i < 4; i++) {
			v := hexval(int body[off + i]);
			if(v < 0)
				break;
			pktlen = (pktlen << 4) | v;
		}
		off += 4;

		if(pktlen == 0)
			continue;

		datalen := pktlen - 4;
		if(off + datalen > len body)
			break;
		line := string body[off:off+datalen];
		off += datalen;

		if(len line > 0 && line[0] == '#')
			continue;

		while(len line > 0 && (line[len line - 1] == '\n' || line[len line - 1] == '\r'))
			line = line[0:len line - 1];

		if(len line < HEXSIZE)
			continue;

		hashstr := line[0:HEXSIZE];
		rest := line[HEXSIZE:];

		refname: string;
		if(len rest > 0 && rest[0] == ' ')
			rest = rest[1:];

		# Check for null byte (capabilities separator)
		for(i = 0; i < len rest; i++) {
			if(rest[i] == 0) {
				refname = rest[0:i];
				capstr := rest[i+1:];
				(nil, caplist) := sys->tokenize(capstr, " ");
				caps = caplist;
				break;
			}
		}
		if(refname == nil)
			refname = rest;

		(h, herr) := parsehash(hashstr);
		if(herr != nil)
			continue;

		r: Ref;
		r.name = refname;
		r.hash = h;
		refs = r :: refs;
	}

	refs = revrefs(refs);
	return (refs, caps, nil);
}

fetchpack(remoteurl: string, want: list of Hash,
	  have: list of Hash, outpath: string): string
{
	if(want == nil)
		return "nothing to fetch";

	u := url->makeurl(remoteurl);
	if(u == nil)
		return "bad url: " + remoteurl;

	host := u.host;
	port := u.port;
	if(port == nil || port == "") {
		if(u.scheme == Url->HTTPS)
			port = "443";
		else
			port = "80";
	}
	addr := "tcp!" + host + "!" + port;

	fd: ref Sys->FD;
	ferr: string;
	if(u.scheme == Url->HTTPS) {
		(fd, ferr) = webclient->tlsdial(addr, host);
		if(ferr != nil)
			return "connect: " + ferr;
	} else {
		c := dial->dial(addr, nil);
		if(c == nil)
			return sprint("dial %s: %r", addr);
		fd = c.dfd;
	}

	path := u.pstart + u.path;
	if(path == nil || path == "")
		path = "/";
	if(len path > 0 && path[len path - 1] == '/')
		path = path[0:len path - 1];
	path += "/git-upload-pack";

	# Build request body with pkt-lines
	reqbody: list of array of byte;
	reqsize := 0;

	first := 1;
	for(wl := want; wl != nil; wl = tl wl) {
		h := hd wl;
		line: string;
		if(first) {
			line = "want " + h.hex() + " side-band-64k ofs-delta\n";
			first = 0;
		} else {
			line = "want " + h.hex() + "\n";
		}
		pkt := mkpktline(array of byte line);
		reqbody = pkt :: reqbody;
		reqsize += len pkt;
	}

	fl := array of byte "0000";
	reqbody = fl :: reqbody;
	reqsize += 4;

	for(hl := have; hl != nil; hl = tl hl) {
		h := hd hl;
		line := "have " + h.hex() + "\n";
		pkt := mkpktline(array of byte line);
		reqbody = pkt :: reqbody;
		reqsize += len pkt;
	}

	donepkt := mkpktline(array of byte "done\n");
	reqbody = donepkt :: reqbody;
	reqsize += len donepkt;

	reqbody = fl :: reqbody;
	reqsize += 4;

	# Reverse and concatenate body chunks
	body := array [reqsize] of byte;
	boff := reqsize;
	for(bl := reqbody; bl != nil; bl = tl bl) {
		chunk := hd bl;
		boff -= len chunk;
		copybytes(body, boff, chunk, 0, len chunk);
	}

	# Send HTTP request
	req := "POST " + path + " HTTP/1.1\r\n";
	req += "Host: " + host + "\r\n";
	req += "Content-Type: application/x-git-upload-pack-request\r\n";
	req += "Content-Length: " + string reqsize + "\r\n";
	req += "User-Agent: Infernode-git/1.0\r\n";
	req += "\r\n";
	reqhdr := array of byte req;

	if(sys->write(fd, reqhdr, len reqhdr) != len reqhdr)
		return "write request header failed";
	if(sys->write(fd, body, len body) != len body)
		return "write request body failed";

	# Read HTTP response headers
	hdrbuf := array [32768] of byte;
	hlen := 0;
	headersdone := 0;
	while(!headersdone && hlen < len hdrbuf) {
		n := sys->read(fd, hdrbuf[hlen:hlen+1], 1);
		if(n <= 0)
			break;
		hlen++;
		if(hlen >= 4 && hdrbuf[hlen-4] == byte '\r' && hdrbuf[hlen-3] == byte '\n'
		   && hdrbuf[hlen-2] == byte '\r' && hdrbuf[hlen-1] == byte '\n')
			headersdone = 1;
	}

	if(!headersdone)
		return "incomplete HTTP response headers";

	hdrstr := string hdrbuf[0:hlen];
	(statusline, nil) := splitline(hdrstr);
	(nil, sfields) := sys->tokenize(statusline, " ");
	if(sfields == nil || tl sfields == nil)
		return "bad HTTP status line";
	code := int hd tl sfields;
	if(code != 200)
		return sprint("HTTP %d", code);

	# Detect chunked transfer encoding
	chunked := 0;
	lhdr := str->tolower(hdrstr);
	if(contains(lhdr, "transfer-encoding: chunked"))
		chunked = 1;

	br := ref BodyReader(fd, chunked, 0, 0, 0);

	# Read pack data from sideband-multiplexed pkt-line stream
	ofd := sys->create(outpath, Sys->OWRITE, 8r644);
	if(ofd == nil)
		return sprint("create %s: %r", outpath);

	# First, read the NAK line
	(nil, nakerr) := bpktread(br);
	if(nakerr != nil)
		return "reading NAK: " + nakerr;

	for(;;) {
		(pdata, perr) := bpktread(br);
		if(perr != nil)
			return "pack read: " + perr;
		if(pdata == nil)
			break;
		if(len pdata == 0)
			continue;

		band := int pdata[0];
		case band {
		1 =>
			if(len pdata > 1) {
				d := pdata[1:];
				if(sys->write(ofd, d, len d) != len d)
					return "write pack data failed";
			}
		2 =>
			if(len pdata > 1)
				sys->fprint(stderr, "%s", string pdata[1:]);
		3 =>
			if(len pdata > 1)
				return "remote: " + string pdata[1:];
		* =>
			return sprint("unknown sideband channel %d", band);
		}
	}

	return nil;
}

mkpktline(data: array of byte): array of byte
{
	pktlen := len data + 4;
	hdr := sprint("%04x", pktlen);
	hdrbytes := array of byte hdr;
	result := array [pktlen] of byte;
	copybytes(result, 0, hdrbytes, 0, 4);
	copybytes(result, 4, data, 0, len data);
	return result;
}

# =====================================================================
# String Helpers
# =====================================================================

splitline(s: string): (string, string)
{
	for(i := 0; i < len s; i++) {
		if(s[i] == '\n')
			return (s[0:i], s[i+1:]);
		if(s[i] == '\r' && i+1 < len s && s[i+1] == '\n')
			return (s[0:i], s[i+2:]);
	}
	return (s, "");
}

splitfirst(s: string, sep: int): (string, string)
{
	for(i := 0; i < len s; i++) {
		if(s[i] == sep)
			return (s[0:i], s[i+1:]);
	}
	return (s, "");
}

contains(s, sub: string): int
{
	slen := len s;
	sublen := len sub;
	if(sublen > slen)
		return 0;
	for(i := 0; i <= slen - sublen; i++) {
		if(s[i:i+sublen] == sub)
			return 1;
	}
	return 0;
}

# =====================================================================
# Byte Order Helpers
# =====================================================================

getbe32(buf: array of byte, off: int): int
{
	return (int buf[off] << 24) |
	       (int buf[off+1] << 16) |
	       (int buf[off+2] << 8) |
	       int buf[off+3];
}

getbe64(buf: array of byte, off: int): big
{
	return (big getbe32(buf, off) << 32) |
	       (big getbe32(buf, off+4) & big 16rffffffff);
}

putbe32(buf: array of byte, off: int, v: int)
{
	buf[off]   = byte (v >> 24);
	buf[off+1] = byte (v >> 16);
	buf[off+2] = byte (v >> 8);
	buf[off+3] = byte v;
}

# =====================================================================
# List Helpers
# =====================================================================

revhashes(l: list of Hash): list of Hash
{
	r: list of Hash;
	for(; l != nil; l = tl l)
		r = (hd l) :: r;
	return r;
}

revrefs(l: list of Ref): list of Ref
{
	r: list of Ref;
	for(; l != nil; l = tl l)
		r = (hd l) :: r;
	return r;
}

# =====================================================================
# Shared Helpers (exported)
# =====================================================================

findgitdir(dir: string): string
{
	for(depth := 0; depth < 20; depth++) {
		gitdir := dir + "/.git";
		(n, nil) := sys->stat(gitdir);
		if(n >= 0)
			return gitdir;
		dir = dir + "/..";
	}
	return nil;
}

getremoteurl(gitdir, remote: string): string
{
	fd := sys->open(gitdir + "/config", Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array [8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;

	config := string buf[:n];
	target := "[remote \"" + remote + "\"]";
	insection := 0;

	s := config;
	for(;;) {
		(line, rest) := splitline(s);
		if(line == nil && rest == "")
			break;
		s = rest;

		line = strtrim(line);

		if(len line > 0 && line[0] == '[') {
			insection = (line == target);
			continue;
		}

		if(insection) {
			(key, val) := splitfirst(line, '=');
			key = strtrim(key);
			val = strtrim(val);
			if(key == "url")
				return val;
		}
	}
	return nil;
}

writeref(gitdir, name: string, h: Hash)
{
	path := gitdir + "/" + name;
	mkdirp(path);
	fd := sys->create(path, Sys->OWRITE, 8r644);
	if(fd == nil)
		return;
	data := array of byte (h.hex() + "\n");
	sys->write(fd, data, len data);
}

writesymref(gitdir, name, target: string)
{
	p := gitdir + "/" + name;
	fd := sys->create(p, Sys->OWRITE, 8r644);
	if(fd != nil) {
		d := array of byte ("ref: " + target + "\n");
		sys->write(fd, d, len d);
	}
}

mkdirp(filepath: string)
{
	for(i := 1; i < len filepath; i++)
		if(filepath[i] == '/')
			sys->create(filepath[:i], Sys->OREAD, Sys->DMDIR | 8r755);
}

copyfile(src, dst: string)
{
	sfd := sys->open(src, Sys->OREAD);
	if(sfd == nil)
		return;
	dfd := sys->create(dst, Sys->OWRITE, 8r644);
	if(dfd == nil)
		return;
	buf := array [8192] of byte;
	for(;;) {
		n := sys->read(sfd, buf, len buf);
		if(n <= 0)
			break;
		sys->write(dfd, buf[:n], n);
	}
}

strtrim(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\r' || s[j-1] == '\n'))
		j--;
	return s[i:j];
}

inlist(s: string, l: list of string): int
{
	for(; l != nil; l = tl l)
		if(hd l == s)
			return 1;
	return 0;
}

renamepak(gitdir, packpath, packname: string)
{
	pfd := sys->open(packpath, Sys->OREAD);
	if(pfd == nil)
		return;
	sys->seek(pfd, big -20, Sys->SEEKEND);
	sha := array [20] of byte;
	sys->read(pfd, sha, 20);
	pfd = nil;

	packhex := "";
	for(i := 0; i < 20; i++)
		packhex += sprint("%02x", int sha[i]);

	newpackpath := gitdir + "/objects/pack/pack-" + packhex + ".pack";
	newidxpath := gitdir + "/objects/pack/pack-" + packhex + ".idx";
	oldidxpath := gitdir + "/objects/pack/" + packname + ".idx";

	copyfile(packpath, newpackpath);
	copyfile(oldidxpath, newidxpath);
	sys->remove(packpath);
	sys->remove(oldidxpath);
}

updaterefs(gitdir, remote: string, refs: list of Ref, verbose: int)
{
	for(rl := refs; rl != nil; rl = tl rl) {
		r := hd rl;
		name := r.name;

		if(name == "HEAD")
			continue;

		if(len name > 11 && name[:11] == "refs/heads/") {
			branchname := name[11:];
			refname := "refs/remotes/" + remote + "/" + branchname;
			writeref(gitdir, refname, r.hash);
			if(verbose)
				sys->fprint(stderr, "  -> %s\n", refname);
		}

		if(len name > 10 && name[:10] == "refs/tags/") {
			writeref(gitdir, name, r.hash);
			if(verbose)
				sys->fprint(stderr, "  -> %s\n", name);
		}
	}
}

isancestor(repo: ref Repo, ancestor, descendant: Hash): int
{
	if(ancestor.eq(descendant))
		return 1;

	queue: list of Hash = descendant :: nil;
	seen: list of string;

	while(queue != nil) {
		hash := hd queue;
		queue = tl queue;

		hex := hash.hex();
		if(inlist(hex, seen))
			continue;
		seen = hex :: seen;

		(otype, data, err) := repo.readobj(hash);
		if(err != nil || otype != OBJ_COMMIT)
			continue;

		(commit, cperr) := parsecommit(data);
		if(cperr != nil || commit == nil)
			continue;

		for(pl := commit.parents; pl != nil; pl = tl pl) {
			if((hd pl).eq(ancestor))
				return 1;
			queue = (hd pl) :: queue;
		}
	}
	return 0;
}

# =====================================================================
# Write Path (exported)
# =====================================================================

zcompress(input: array of byte): (array of byte, string)
{
	rq := deflate->start("z");
	out: list of array of byte;
	total := 0;
	inoff := 0;

	for(;;) {
		pick m := <-rq {
		Start =>
			;
		Fill =>
			buf := m.buf;
			n := len input - inoff;
			if(n > len buf)
				n = len buf;
			for(k := 0; k < n; k++)
				buf[k] = input[inoff + k];
			inoff += n;
			m.reply <-= n;
		Result =>
			if(len m.buf > 0) {
				chunk := array [len m.buf] of byte;
				copybytes(chunk, 0, m.buf, 0, len m.buf);
				out = chunk :: out;
				total += len chunk;
			}
			m.reply <-= 0;
		Finished =>
			return (concatbytes(out, total), nil);
		Error =>
			return (nil, "deflate: " + m.e);
		}
	}
}

writelooseobj(repopath: string, otype: int, data: array of byte): (Hash, string)
{
	h := hashobj(otype, data);

	# Build raw object: "type size\0" + data
	hdrstr := typename(otype) + " " + string len data;
	hdrbytes := array of byte hdrstr;
	raw := array [len hdrbytes + 1 + len data] of byte;
	copybytes(raw, 0, hdrbytes, 0, len hdrbytes);
	raw[len hdrbytes] = byte 0;
	copybytes(raw, len hdrbytes + 1, data, 0, len data);

	# Compress
	(compressed, cerr) := zcompress(raw);
	if(cerr != nil)
		return (nullhash(), cerr);

	# Write to objects/HH/xxx...
	hexstr := h.hex();
	objdir := repopath + "/objects/" + hexstr[0:2];
	sys->create(objdir, Sys->OREAD, Sys->DMDIR | 8r755);
	objpath := objdir + "/" + hexstr[2:];

	# Don't overwrite if already exists
	(rc, nil) := sys->stat(objpath);
	if(rc >= 0)
		return (h, nil);

	fd := sys->create(objpath, Sys->OWRITE, 8r444);
	if(fd == nil)
		return (nullhash(), sprint("create %s: %r", objpath));
	if(sys->write(fd, compressed, len compressed) != len compressed)
		return (nullhash(), sprint("write %s: %r", objpath));

	return (h, nil);
}

encodetree(entries: array of TreeEntry): array of byte
{
	# Calculate total size
	total := 0;
	for(i := 0; i < len entries; i++) {
		modestr := sprint("%o", entries[i].mode);
		total += len array of byte modestr + 1 + len array of byte entries[i].name + 1 + SHA1SIZE;
	}

	data := array [total] of byte;
	off := 0;
	for(i = 0; i < len entries; i++) {
		modestr := sprint("%o", entries[i].mode);
		mb := array of byte modestr;
		copybytes(data, off, mb, 0, len mb);
		off += len mb;
		data[off++] = byte ' ';
		nb := array of byte entries[i].name;
		copybytes(data, off, nb, 0, len nb);
		off += len nb;
		data[off++] = byte 0;
		copybytes(data, off, entries[i].hash.a, 0, SHA1SIZE);
		off += SHA1SIZE;
	}

	return data;
}

sorttreeentries(entries: array of TreeEntry)
{
	# Insertion sort by name (git requires sorted tree entries)
	for(i := 1; i < len entries; i++) {
		key := entries[i];
		j := i - 1;
		while(j >= 0 && entries[j].name > key.name) {
			entries[j+1] = entries[j];
			j--;
		}
		entries[j+1] = key;
	}
}

# =====================================================================
# Index (exported)
# =====================================================================

loadindex(repopath: string): (list of IndexEntry, string)
{
	fd := sys->open(repopath + "/index", Sys->OREAD);
	if(fd == nil)
		return (nil, nil);  # no index is not an error

	buf := array [65536] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return (nil, nil);

	s := string buf[:n];
	entries: list of IndexEntry;
	for(;;) {
		(line, rest) := splitline(s);
		if(line == nil || line == "")
			break;
		s = rest;

		# Format: "mode hash path"
		(modestr, r2) := splitfirst(line, ' ');
		(hashstr, path) := splitfirst(r2, ' ');

		mode := parseoctal(modestr);
		(h, herr) := parsehash(hashstr);
		if(herr != nil)
			continue;

		e: IndexEntry;
		e.mode = mode;
		e.hash = h;
		e.path = path;
		entries = e :: entries;
	}

	# Reverse to maintain file order
	result: list of IndexEntry;
	for(; entries != nil; entries = tl entries)
		result = (hd entries) :: result;

	return (result, nil);
}

saveindex(repopath: string, entries: list of IndexEntry): string
{
	s := "";
	for(el := entries; el != nil; el = tl el) {
		e := hd el;
		s += sprint("%06o", e.mode) + " " + e.hash.hex() + " " + e.path + "\n";
	}

	fd := sys->create(repopath + "/index", Sys->OWRITE, 8r644);
	if(fd == nil)
		return sprint("create index: %r");
	data := array of byte s;
	if(sys->write(fd, data, len data) != len data)
		return sprint("write index: %r");
	return nil;
}

clearindex(repopath: string): string
{
	if(sys->remove(repopath + "/index") < 0)
		return sprint("remove index: %r");
	return nil;
}

parseoctal(s: string): int
{
	v := 0;
	for(i := 0; i < len s; i++) {
		c := s[i] - '0';
		if(c < 0 || c > 7)
			break;
		v = (v << 3) | c;
	}
	return v;
}

# =====================================================================
# Working Tree Comparison
# =====================================================================

isclean(repo: ref Repo, treehash: Hash, workdir: string): (int, string)
{
	(otype, data, err) := repo.readobj(treehash);
	if(err != nil)
		return (1, nil);	# no tree = empty repo, treat as clean
	if(otype != OBJ_TREE)
		return (0, "not a tree object");

	(entries, perr) := parsetree(data);
	if(perr != nil)
		return (0, "parse tree: " + perr);

	for(i := 0; i < len entries; i++) {
		e := entries[i];
		fpath := workdir + "/" + e.name;

		if(e.mode == 8r40000) {
			# Directory — recurse
			(clean, reason) := isclean(repo, e.hash, fpath);
			if(!clean)
				return (0, reason);
			continue;
		}

		if(e.mode == 8r120000)
			continue;	# skip symlinks

		# Regular file
		fd := sys->open(fpath, Sys->OREAD);
		if(fd == nil)
			return (0, "deleted: " + e.name);

		(rc, dir) := sys->fstat(fd);
		if(rc < 0)
			return (0, "stat: " + e.name);

		fdata := array [int dir.length] of byte;
		total := 0;
		while(total < len fdata) {
			n := sys->read(fd, fdata[total:], len fdata - total);
			if(n <= 0)
				break;
			total += n;
		}
		fdata = fdata[:total];

		fhash := hashobj(OBJ_BLOB, fdata);
		if(!fhash.eq(e.hash))
			return (0, "modified: " + e.name);
	}

	return (1, nil);
}

# =====================================================================
# Object Enumeration for Push
# =====================================================================

enumobjects(repo: ref Repo, want, have: list of Hash): (list of ref ObjRef, string)
{
	# Build have-set: all objects reachable from have commits
	haveset: list of string;
	for(hl := have; hl != nil; hl = tl hl)
		haveset = (hd hl).hex() :: haveset;

	objects: list of ref ObjRef;
	seen: list of string;

	# BFS from want commits
	queue := want;
	while(queue != nil) {
		hash := hd queue;
		queue = tl queue;

		hex := hash.hex();
		if(inlist(hex, seen) || inlist(hex, haveset))
			continue;
		seen = hex :: seen;

		(otype, data, err) := repo.readobj(hash);
		if(err != nil)
			continue;

		obj := ref ObjRef(hash, otype, data);
		objects = obj :: objects;

		if(otype == OBJ_COMMIT) {
			(commit, cperr) := parsecommit(data);
			if(cperr != nil)
				continue;
			# Enqueue parents
			for(pl := commit.parents; pl != nil; pl = tl pl) {
				phex := (hd pl).hex();
				if(!inlist(phex, seen) && !inlist(phex, haveset))
					queue = (hd pl) :: queue;
			}
			# Enqueue tree
			thex := commit.tree.hex();
			if(!inlist(thex, seen) && !inlist(thex, haveset))
				queue = commit.tree :: queue;
		} else if(otype == OBJ_TREE) {
			(entries, perr) := parsetree(data);
			if(perr != nil)
				continue;
			for(i := 0; i < len entries; i++) {
				ehex := entries[i].hash.hex();
				if(!inlist(ehex, seen) && !inlist(ehex, haveset))
					queue = entries[i].hash :: queue;
			}
		}
	}

	return (objects, nil);
}

# =====================================================================
# Pack File Writing
# =====================================================================

writepack(objects: list of ref ObjRef): (array of byte, string)
{
	# Count objects
	nobj := 0;
	for(ol := objects; ol != nil; ol = tl ol)
		nobj++;

	# Build pack: header + objects + SHA-1 trailer
	# First pass: compress all objects and calculate total size
	hdrs: list of array of byte;
	comps: list of array of byte;
	datasize := 0;

	for(ol = objects; ol != nil; ol = tl ol) {
		obj := hd ol;

		# Build varint header: (type<<4 | size_low4), continuation bytes
		size := len obj.data;
		hdr := packvarint(obj.otype, size);

		# Compress object data
		(compressed, cerr) := zcompress(obj.data);
		if(cerr != nil)
			return (nil, "compress: " + cerr);

		hdrs = hdr :: hdrs;
		comps = compressed :: comps;
		datasize += len hdr + len compressed;
	}

	# Total: 12-byte header + objects + 20-byte SHA-1
	total := 12 + datasize + SHA1SIZE;
	pack := array [total] of byte;
	off := 0;

	# Header: "PACK" + version 2 + nobj
	pack[off++] = byte 'P';
	pack[off++] = byte 'A';
	pack[off++] = byte 'C';
	pack[off++] = byte 'K';
	putbe32(pack, off, 2);
	off += 4;
	putbe32(pack, off, nobj);
	off += 4;

	# Objects
	hl := hdrs;
	cl := comps;
	while(hl != nil) {
		h := hd hl;
		c := hd cl;
		copybytes(pack, off, h, 0, len h);
		off += len h;
		copybytes(pack, off, c, 0, len c);
		off += len c;
		hl = tl hl;
		cl = tl cl;
	}

	# SHA-1 trailer
	digest := array [SHA1SIZE] of byte;
	keyring->sha1(pack, off, digest, nil);
	copybytes(pack, off, digest, 0, SHA1SIZE);

	return (pack, nil);
}

# Encode pack object header: type in bits 6-4 of first byte, size varint
packvarint(otype, size: int): array of byte
{
	buf := array [10] of byte;
	n := 0;

	# First byte: (type << 4) | (size & 0xf), continuation bit
	b := (otype << 4) | (size & 16r0f);
	size >>= 4;
	if(size > 0)
		b |= 16r80;
	buf[n++] = byte b;

	# Continuation bytes
	while(size > 0) {
		b = size & 16r7f;
		size >>= 7;
		if(size > 0)
			b |= 16r80;
		buf[n++] = byte b;
	}

	result := array [n] of byte;
	copybytes(result, 0, buf, 0, n);
	return result;
}

# =====================================================================
# Push Transport: Smart HTTP receive-pack
# =====================================================================

discover_receive(remoteurl: string): (list of Ref, list of string, string)
{
	infourl := remoteurl;
	if(len infourl > 0 && infourl[len infourl - 1] == '/')
		infourl = infourl[0:len infourl - 1];
	infourl += "/info/refs?service=git-receive-pack";

	(resp, err) := webclient->get(infourl);
	if(err != nil)
		return (nil, nil, "discover_receive: " + err);
	if(resp.statuscode != 200)
		return (nil, nil, sprint("discover_receive: HTTP %d", resp.statuscode));

	body := resp.body;
	if(body == nil || len body == 0)
		return (nil, nil, "discover_receive: empty response");

	refs: list of Ref;
	caps: list of string;

	off := 0;
	while(off < len body) {
		if(off + 4 > len body)
			break;
		pktlen := 0;
		for(i := 0; i < 4; i++) {
			v := hexval(int body[off + i]);
			if(v < 0)
				break;
			pktlen = (pktlen << 4) | v;
		}
		off += 4;

		if(pktlen == 0)
			continue;

		datalen := pktlen - 4;
		if(off + datalen > len body)
			break;
		line := string body[off:off+datalen];
		off += datalen;

		if(len line > 0 && line[0] == '#')
			continue;

		while(len line > 0 && (line[len line - 1] == '\n' || line[len line - 1] == '\r'))
			line = line[0:len line - 1];

		if(len line < HEXSIZE)
			continue;

		hashstr := line[0:HEXSIZE];
		rest := line[HEXSIZE:];

		refname: string;
		if(len rest > 0 && rest[0] == ' ')
			rest = rest[1:];

		for(i = 0; i < len rest; i++) {
			if(rest[i] == 0) {
				refname = rest[0:i];
				capstr := rest[i+1:];
				(nil, caplist) := sys->tokenize(capstr, " ");
				caps = caplist;
				break;
			}
		}
		if(refname == nil)
			refname = rest;

		(h, herr) := parsehash(hashstr);
		if(herr != nil)
			continue;

		r: Ref;
		r.name = refname;
		r.hash = h;
		refs = r :: refs;
	}

	refs = revrefs(refs);
	return (refs, caps, nil);
}

sendpack(remoteurl: string, updates: list of ref RefUpdate,
	 packdata: array of byte, creds: string): string
{
	u := url->makeurl(remoteurl);
	if(u == nil)
		return "bad url: " + remoteurl;

	host := u.host;
	port := u.port;
	if(port == nil || port == "") {
		if(u.scheme == Url->HTTPS)
			port = "443";
		else
			port = "80";
	}
	addr := "tcp!" + host + "!" + port;

	fd: ref Sys->FD;
	ferr: string;
	if(u.scheme == Url->HTTPS) {
		(fd, ferr) = webclient->tlsdial(addr, host);
		if(ferr != nil)
			return "connect: " + ferr;
	} else {
		c := dial->dial(addr, nil);
		if(c == nil)
			return sprint("dial %s: %r", addr);
		fd = c.dfd;
	}

	path := u.pstart + u.path;
	if(path == nil || path == "")
		path = "/";
	if(len path > 0 && path[len path - 1] == '/')
		path = path[0:len path - 1];
	path += "/git-receive-pack";

	# Build request body: pkt-line ref updates + flush + pack data
	reqparts: list of array of byte;
	reqsize := 0;

	first := 1;
	for(ul := updates; ul != nil; ul = tl ul) {
		upd := hd ul;
		line: string;
		if(first) {
			# First line includes capabilities (null byte separator)
			linedata := upd.oldhash.hex() + " " + upd.newhash.hex() + " " + upd.name;
			# Build with explicit null byte for capabilities
			lb := array of byte linedata;
			capstr := array of byte " report-status\n";
			pktdata := array [len lb + 1 + len capstr] of byte;
			copybytes(pktdata, 0, lb, 0, len lb);
			pktdata[len lb] = byte 0;
			copybytes(pktdata, len lb + 1, capstr, 0, len capstr);
			pkt := mkpktline(pktdata);
			reqparts = pkt :: reqparts;
			reqsize += len pkt;
			first = 0;
		} else {
			line = upd.oldhash.hex() + " " + upd.newhash.hex() + " " + upd.name + "\n";
			pkt := mkpktline(array of byte line);
			reqparts = pkt :: reqparts;
			reqsize += len pkt;
		}
	}

	# Flush after ref updates
	fl := array of byte "0000";
	reqparts = fl :: reqparts;
	reqsize += 4;

	# Pack data
	if(packdata != nil && len packdata > 0) {
		reqparts = packdata :: reqparts;
		reqsize += len packdata;
	}

	# Assemble body (reverse the cons list)
	body := array [reqsize] of byte;
	boff := reqsize;
	for(bl := reqparts; bl != nil; bl = tl bl) {
		chunk := hd bl;
		boff -= len chunk;
		copybytes(body, boff, chunk, 0, len chunk);
	}

	# Build Authorization header
	authhdr := "";
	if(creds != nil && len creds > 0) {
		encoded := base64->enc(array of byte creds);
		authhdr = "Authorization: Basic " + encoded + "\r\n";
	}

	# Send HTTP request
	req := "POST " + path + " HTTP/1.1\r\n";
	req += "Host: " + host + "\r\n";
	req += "Content-Type: application/x-git-receive-pack-request\r\n";
	req += "Content-Length: " + string reqsize + "\r\n";
	req += "User-Agent: Infernode-git/1.0\r\n";
	req += authhdr;
	req += "\r\n";
	reqhdr := array of byte req;

	if(sys->write(fd, reqhdr, len reqhdr) != len reqhdr)
		return "write request header failed";
	if(sys->write(fd, body, len body) != len body)
		return "write request body failed";

	# Read HTTP response headers
	hdrbuf := array [32768] of byte;
	hlen := 0;
	headersdone := 0;
	while(!headersdone && hlen < len hdrbuf) {
		n := sys->read(fd, hdrbuf[hlen:hlen+1], 1);
		if(n <= 0)
			break;
		hlen++;
		if(hlen >= 4 && hdrbuf[hlen-4] == byte '\r' && hdrbuf[hlen-3] == byte '\n'
		   && hdrbuf[hlen-2] == byte '\r' && hdrbuf[hlen-1] == byte '\n')
			headersdone = 1;
	}

	if(!headersdone)
		return "incomplete HTTP response headers";

	hdrstr := string hdrbuf[0:hlen];
	(statusline, nil) := splitline(hdrstr);
	(nil, sfields) := sys->tokenize(statusline, " ");
	if(sfields == nil || tl sfields == nil)
		return "bad HTTP status line";
	code := int hd tl sfields;
	if(code != 200)
		return sprint("HTTP %d", code);

	# Detect chunked transfer encoding
	chunked := 0;
	lhdr := str->tolower(hdrstr);
	if(contains(lhdr, "transfer-encoding: chunked"))
		chunked = 1;

	br := ref BodyReader(fd, chunked, 0, 0, 0);

	# Read response pkt-lines: expect "unpack ok" and "ok <refname>"
	for(;;) {
		(pdata, perr) := bpktread(br);
		if(perr != nil)
			return "response read: " + perr;
		if(pdata == nil)
			break;
		if(len pdata == 0)
			continue;

		# Check for sideband
		band := int pdata[0];
		respline: string;
		if(band == 1 || band == 2 || band == 3) {
			if(band == 3 && len pdata > 1)
				return "remote error: " + string pdata[1:];
			if(band == 1 && len pdata > 1)
				respline = string pdata[1:];
			else
				continue;
		} else {
			respline = string pdata;
		}

		respline = strtrim(respline);
		if(len respline >= 2 && respline[:2] == "ng")
			return "push rejected: " + respline;
	}

	return nil;
}

readcredentials(gitdir: string): string
{
	fd := sys->open(gitdir + "/credentials", Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array [1024] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	s := string buf[:n];
	return strtrim(s);
}
