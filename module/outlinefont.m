#
# OutlineFont - vector outline font rendering
#
# General-purpose module for parsing and rendering outline fonts.
# Consumers provide raw font program bytes; the module returns
# rendered glyphs and metrics.  Decoupled from PDF — usable by
# any application that needs vector text rendering.
#
# Currently supports CFF (Compact Font Format / Type 2).
#

OutlineFont: module {
	PATH: con "/dis/lib/outlinefont.dis";

	init:	fn(d: ref Draw->Display);

	# Parse font from raw data.  format: "cff" or "ttf"
	open:	fn(data: array of byte, format: string): (ref Face, string);

	Face: adt {
		nglyphs:	int;	# number of glyphs
		upem:		int;	# units per em
		ascent:		int;	# in font units
		descent:	int;	# in font units (negative)
		name:		string;	# font name from the font program
		iscid:		int;	# 1 if CID-keyed font

		# Map CID to GID (for CID-keyed fonts).  Returns -1 if not found.
		cidtogid:	fn(f: self ref Face, cid: int): int;

		# Map character code to GID via cmap (TrueType).  Identity for CFF.
		chartogid:	fn(f: self ref Face, charcode: int): int;

		# Render glyph at given size.  Returns advance width in pixels.
		drawglyph:	fn(f: self ref Face, gid: int, size: real,
				   dst: ref Draw->Image, p: Draw->Point,
				   src: ref Draw->Image): int;

		# Get glyph advance width in pixels at given size
		glyphwidth:	fn(f: self ref Face, gid: int, size: real): int;

		# Get scaled metrics: (height, ascent, descent) in pixels
		metrics:	fn(f: self ref Face, size: real): (int, int, int);
	};
};
