implement Bdf2subfont;

#
# bdf2subfont — convert a BDF bitmap font to Inferno subfont format
#
# Reads a BDF file and writes an Inferno subfont binary covering the Unicode
# range [-start N, -end N] (inclusive).
#
# Output is an Inferno "new-format" uncompressed GREY8 (k8) image strip,
# followed by the subfont info header and Fontchar table — exactly what
# readsubfonti() expects.
#
# k8 (8-bit greyscale) is used rather than k1 (1-bit) so that the font
# composites cleanly on HiDPI/Retina displays.  On macOS the Inferno canvas
# is at physical pixel resolution and is rendered at 0.5× logical scale;
# k1 monochrome pixels lose half their rows through nearest-neighbour
# sampling on diagonal strokes, producing a smeared appearance.  k8 with
# binary (0x00/0xFF) values matches the Vera font format and renders
# correctly through the same SDL3 pipeline.
#
# Usage:
#   bdf2subfont -start N -end N [-dw N] [-info] input.bdf output.subfont
#
#   -start N     first Unicode codepoint (decimal or 0x hex)
#   -end   N     last  Unicode codepoint (inclusive)
#   -dw    N     advance width for missing glyphs (default 0)
#   -info        print font metrics to stderr and exit (no file written)
#   input.bdf    Inferno namespace path to BDF source file
#   output.subfont  Inferno namespace path for output (created/replaced)
#
# Binary layout written:
#   [Inferno image: "new" uncompressed GREY8, 60-byte header + raw pixel rows (1 byte/pixel)]
#   ["%11d %11d %11d ", n, height, ascent]          ← subfont info (36 bytes)
#   [Fontchar table: 6 bytes × (n+1)]
#     each entry: x_lo x_hi top bottom left width
#     x     = uint16 LE x-offset of glyph image in strip
#     top   = uint8  first ink row from top of strip image
#     bottom= uint8  first row past ink (exclusive)
#     left  = int8   left bearing (signed, 2-complement in byte)
#     width = uint8  advance width in pixels
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

Bdf2subfont: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

# Per-glyph data collected from a BDF STARTCHAR...ENDCHAR block
Glyph: adt {
	enc:    int;          # Unicode codepoint (ENCODING field)
	dwidth: int;          # advance width in pixels (DWIDTH dx)
	bbw:    int;          # bounding box width  in pixels (BBX w ...)
	bbh:    int;          # bounding box height in pixels (BBX ... h ...)
	bbx:    int;          # left bearing: x offset from pen to left of ink (BBX ... x ...)
	bby:    int;          # bottom y: distance from baseline to bottom of ink (signed)
	bits:   array of byte;  # packed bits, MSB first, ceil(bbw/8) bytes/row × bbh rows
};

# Global font metrics set by parsebdf
fontascent:  int;
fontdescent: int;

stderr: ref Sys->FD;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil) {
		sys->fprint(stderr, "bdf2subfont: cannot load bufio: %r\n");
		raise "fail:load";
	}

	args = tl args;   # drop argv[0]

	start    := -1;
	end      := -1;
	defwidth := 0;
	infoonly := 0;

	while(args != nil) {
		a := hd args;
		args = tl args;
		if(a == "-start" && args != nil) {
			start = parsenum(hd args);
			args = tl args;
		} else if(a == "-end" && args != nil) {
			end = parsenum(hd args);
			args = tl args;
		} else if(a == "-dw" && args != nil) {
			defwidth = int hd args;
			args = tl args;
		} else if(a == "-info") {
			infoonly = 1;
		} else if(a[0] != '-') {
			# Positional args: put back and break flag parsing
			args = a :: args;
			break;
		} else {
			usage();
		}
	}

	if(start < 0 || end < start) {
		sys->fprint(stderr, "bdf2subfont: -start and -end are required\n");
		usage();
	}

	# Require input and output file path arguments
	if(args == nil || tl args == nil) {
		sys->fprint(stderr, "bdf2subfont: input.bdf and output.subfont paths required\n");
		usage();
	}
	inpath  := hd args;
	outpath := hd tl args;

	inp := bufio->open(inpath, Bufio->OREAD);
	if(inp == nil) {
		sys->fprint(stderr, "bdf2subfont: cannot open %s: %r\n", inpath);
		raise "fail:open";
	}

	# Parse BDF; sets fontascent and fontdescent globals
	glyphs := parsebdf(inp, start, end);
	inp.close();

	height := fontascent + fontdescent;
	if(height <= 0) {
		sys->fprint(stderr, "bdf2subfont: bad font metrics: ascent=%d descent=%d\n",
			fontascent, fontdescent);
		raise "fail:metrics";
	}

	n := end - start + 1;   # number of code points in this block

	# Count glyphs actually found in range (diagnostic only)
	ngot := 0;
	for(i := 0; i < n; i++)
		if(glyphs[i] != nil)
			ngot++;

	sys->fprint(stderr, "bdf2subfont: range 0x%04X–0x%04X: %d/%d glyphs, height=%d ascent=%d\n",
		start, end, ngot, n, height, fontascent);

	if(infoonly)
		exit;

	# Compute x position of each glyph in the horizontal strip.
	# A glyph's image slot width = bbw (its actual ink-pixel width).
	# Missing glyphs have slot width 0.
	xpos := array[n+1] of int;
	xpos[0] = 0;
	for(i = 0; i < n; i++) {
		g := glyphs[i];
		if(g != nil)
			xpos[i+1] = xpos[i] + g.bbw;
		else
			xpos[i+1] = xpos[i];
	}
	stripw := xpos[n];
	if(stripw <= 0)
		stripw = 1;   # image must have non-zero width

	# Build the pixel strip: GREY8, 1 byte per pixel.
	# Byte value 255 = ink (opaque when used as draw mask), 0 = transparent.
	bpr    := stripw;
	pixels := array[height * bpr] of { * => byte 0 };

	for(i = 0; i < n; i++) {
		g := glyphs[i];
		if(g == nil || g.bbw <= 0 || g.bbh <= 0)
			continue;

		# Row in strip image where the glyph's top ink row starts.
		# BDF: bby = distance from baseline to bottom of ink (signed).
		#      bby + bbh = distance from baseline to top of ink.
		# Strip: row 0 = top of cell = fontascent pixels above baseline.
		#   top_in_strip = fontascent - (bby + bbh)
		top := fontascent - (g.bby + g.bbh);
		if(top < 0)
			top = 0;

		gx   := xpos[i];              # left edge of this glyph in strip
		gbpr := (g.bbw + 7) / 8;     # BDF bytes per row for this glyph

		for(row := 0; row < g.bbh; row++) {
			srow := top + row;
			if(srow >= height)
				break;
			for(col := 0; col < g.bbw; col++) {
				# Extract bit from BDF bitmap (MSB first, 1 = ink)
				srcb := int g.bits[row * gbpr + col / 8];
				bit  := (srcb >> (7 - col % 8)) & 1;
				if(bit == 0)
					continue;
				# Write pixel into strip (1 byte per pixel, 255 = full ink)
				pixels[srow * bpr + gx + col] = byte 255;
			}
		}
	}

	# Open output file for writing
	outfd := sys->create(outpath, sys->OWRITE, 8r644);
	if(outfd == nil) {
		sys->fprint(stderr, "bdf2subfont: cannot create %s: %r\n", outpath);
		raise "fail:create";
	}

	# Write Inferno "new" uncompressed GREY8 image.
	# Header: 5 fields × 12 bytes = 60 bytes total.
	#   field 0: channel string "k8" left-justified in 11 chars + space
	#   fields 1–4: min.x min.y max.x max.y, right-justified in 11 chars + space
	imghdr := sys->sprint("%-11s %11d %11d %11d %11d ",
		"k8", 0, 0, stripw, height);
	writeall(outfd, array of byte imghdr, outpath);
	writeall(outfd, pixels, outpath);

	# Write subfont info header: 3 fields × 12 bytes = 36 bytes.
	sfhdr := sys->sprint("%11d %11d %11d ", n, height, fontascent);
	writeall(outfd, array of byte sfhdr, outpath);

	# Write Fontchar table: 6 bytes per entry, n+1 entries (entry n = sentinel).
	# Sentinel: x = total strip width, all other fields = 0.
	fc := array[6 * (n+1)] of { * => byte 0 };
	for(i = 0; i <= n; i++) {
		x      := xpos[i];
		top    := 0;
		bottom := 0;
		left   := 0;
		width  := 0;

		if(i < n) {
			g := glyphs[i];
			if(g != nil) {
				top    = fontascent - (g.bby + g.bbh);
				bottom = fontascent - g.bby;
				left   = g.bbx;
				width  = g.dwidth;
				if(top < 0)         top    = 0;
				if(bottom > height) bottom = height;
				if(bottom < top)    bottom = top;
			} else {
				width = defwidth;   # missing glyph: zero ink, configurable advance
			}
		}

		off := i * 6;
		fc[off+0] = byte(x & 16rFF);
		fc[off+1] = byte((x >> 8) & 16rFF);
		fc[off+2] = byte(top    & 16rFF);
		fc[off+3] = byte(bottom & 16rFF);
		fc[off+4] = byte(left   & 16rFF);   # signed: 2-complement byte
		fc[off+5] = byte(width  & 16rFF);
	}
	writeall(outfd, fc, outpath);

	outfd = nil;   # close
}

# parsebdf reads BDF from inp and returns an array of n Glyph refs indexed
# [0 .. n-1] where index i corresponds to codepoint (start+i).
# Sets the fontascent and fontdescent globals.
parsebdf(inp: ref Iobuf, start, end: int): array of ref Glyph
{
	n      := end - start + 1;
	glyphs := array[n] of ref Glyph;

	inbits := 0;
	bitrow := 0;
	cur: ref Glyph;
	cur = nil;

	for(;;) {
		s := inp.gets('\n');
		if(s == nil)
			break;

		s = trimright(s);
		if(len s == 0)
			continue;

		tok  := token(s);
		rest := after(s, len tok);

		if(inbits) {
			# Inside a BITMAP section: collect hex rows until ENDCHAR
			if(tok == "ENDCHAR") {
				if(cur != nil) {
					idx := cur.enc - start;
					if(cur.enc >= start && cur.enc <= end)
						glyphs[idx] = cur;
				}
				cur    = nil;
				inbits = 0;
				bitrow = 0;
			} else if(cur != nil && cur.bits != nil) {
				gbpr := (cur.bbw + 7) / 8;
				if(bitrow < cur.bbh)
					parsehex(s, cur.bits, bitrow * gbpr, gbpr);
				bitrow++;
			}
			continue;
		}

		case tok {
		"FONT_ASCENT" =>
			fontascent = int rest;
		"FONT_DESCENT" =>
			fontdescent = int rest;
		"STARTCHAR" =>
			cur    = ref Glyph(0, 0, 0, 0, 0, 0, nil);
			bitrow = 0;
		"ENCODING" =>
			if(cur != nil)
				cur.enc = int rest;
		"DWIDTH" =>
			if(cur != nil)
				cur.dwidth = int token(rest);
		"BBX" =>
			if(cur != nil) {
				f := splitfields(rest);
				if(len f >= 4) {
					cur.bbw = int f[0];
					cur.bbh = int f[1];
					cur.bbx = int f[2];
					cur.bby = int f[3];
					if(cur.bbw > 0 && cur.bbh > 0) {
						gbpr   := (cur.bbw + 7) / 8;
						cur.bits = array[cur.bbh * gbpr] of { * => byte 0 };
					}
				}
			}
		"BITMAP" =>
			if(cur != nil) {
				inbits = 1;
				bitrow = 0;
			}
		"ENDCHAR" =>
			# ENDCHAR without a preceding BITMAP (space-like glyph)
			if(cur != nil) {
				idx := cur.enc - start;
				if(cur.enc >= start && cur.enc <= end)
					glyphs[idx] = cur;
			}
			cur    = nil;
			inbits = 0;
			bitrow = 0;
		* =>
			;   # unknown BDF keyword: skip
		}
	}
	return glyphs;
}

# parsehex decodes up to n bytes of hex from s into dst[off..off+n-1].
parsehex(s: string, dst: array of byte, off, n: int)
{
	i := 0;
	j := 0;
	while(i+1 < len s && j < n) {
		hi := hexval(s[i]);
		lo := hexval(s[i+1]);
		if(hi < 0 || lo < 0)
			break;
		dst[off+j] = byte((hi << 4) | lo);
		i += 2;
		j++;
	}
}

hexval(c: int): int
{
	if(c >= '0' && c <= '9') return c - '0';
	if(c >= 'a' && c <= 'f') return c - 'a' + 10;
	if(c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

# parsenum handles decimal or 0x/0X-prefixed hex integers.
# Limbo's int() does not reliably handle 0x; parse hex manually.
parsenum(s: string): int
{
	if(len s > 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
		val := 0;
		for(i := 2; i < len s; i++) {
			c := s[i];
			if(c >= '0' && c <= '9')
				val = (val << 4) | (c - '0');
			else if(c >= 'a' && c <= 'f')
				val = (val << 4) | (c - 'a' + 10);
			else if(c >= 'A' && c <= 'F')
				val = (val << 4) | (c - 'A' + 10);
			else
				break;
		}
		return val;
	}
	return int s;
}

# token returns the first whitespace-delimited token in s.
token(s: string): string
{
	i := 0;
	while(i < len s && s[i] != ' ' && s[i] != '\t')
		i++;
	return s[0:i];
}

# after returns s after the first n bytes, skipping any leading whitespace.
after(s: string, n: int): string
{
	i := n;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;
	return s[i:];
}

# trimright strips trailing CR, LF, space, and tab.
trimright(s: string): string
{
	i := len s;
	while(i > 0) {
		c := s[i-1];
		if(c == '\n' || c == '\r' || c == ' ' || c == '\t')
			i--;
		else
			break;
	}
	return s[0:i];
}

# splitfields splits s on whitespace and returns fields in order.
splitfields(s: string): array of string
{
	fields: list of string;
	nf := 0;
	i  := 0;
	for(;;) {
		while(i < len s && (s[i] == ' ' || s[i] == '\t'))
			i++;
		if(i >= len s)
			break;
		j := i;
		while(j < len s && s[j] != ' ' && s[j] != '\t')
			j++;
		fields = s[i:j] :: fields;   # prepend: list is reversed
		nf++;
		i = j;
	}
	# Restore correct order
	a := array[nf] of string;
	for(l := fields; l != nil; l = tl l) {
		nf -= 1;
		a[nf] = hd l;
	}
	return a;
}

# writeall writes all of data to fd, retrying on short writes.
writeall(fd: ref Sys->FD, data: array of byte, path: string)
{
	n   := len data;
	off := 0;
	while(off < n) {
		m := sys->write(fd, data[off:], n - off);
		if(m <= 0) {
			sys->fprint(stderr, "bdf2subfont: write error on %s: %r\n", path);
			raise "fail:write";
		}
		off += m;
	}
}

usage()
{
	sys->fprint(stderr,
		"usage: bdf2subfont -start N -end N [-dw N] [-info] input.bdf output.subfont\n");
	sys->fprint(stderr,
		"  N may be decimal or 0x hex\n");
	raise "fail:usage";
}
