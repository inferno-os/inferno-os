Freetype: module {
	PATH: con "$Freetype";

	Matrix: adt {
		a, b: int;	# 16.16 fixed-point coefficients
		c, d: int;
	};

	Vector: adt {
		dx: int;	# 26.6 fixed-point deltas
		dy: int;
	};

	STYLE_ITALIC,
	STYLE_BOLD: con 1 << iota;

	Face: adt {
		nfaces: int;
		index: int;
		style: int;		# STYLE_xxx
		height: int;
		ascent: int;
		familyname: string;
		stylename: string;

		# pts - point size as a 26.6 fixed-point value
		setcharsize: fn(face: self ref Face, pts, hdpi, vdpi: int): string;
		settransform: fn(face: self ref Face, m: ref Matrix, v: ref Vector): string;
		haschar: fn(face: self ref Face, c: int): int;
		loadglyph: fn(face: self ref Face, c: int): ref Glyph;
	};

	Glyph: adt {
		top: int;
		left: int;
		height: int;
		width: int;
		advance: Draw->Point;	# 26.6 fixed-point
		bitmap:	array of byte;	# (width*height) 8-bit greyscale
	};

	newface: fn(path: string, index: int): ref Face;
	newmemface: fn(data: array of byte, index: int): ref Face;
};
