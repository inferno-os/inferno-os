#
# Li-Yeung character recognition
#
Strokes: module
{
	PATH:	con "/dis/lib/strokes/strokes.dis";

	Penpoint: adt
	{
		x, y: int;
		chaincode: int;
	};

	Stroke: adt
	{
		npts:	int;
		pts:	array of Penpoint;
		xrange, yrange: int;

		new:	fn(n: int): ref Stroke;
		copy:	fn(nil: self ref Stroke): ref Stroke;
		trim:	fn(nil: self ref Stroke, n: int);
		bbox:	fn(nil: self ref Stroke): (int, int, int, int);
		scaleup:	fn(nil: self ref Stroke): int;
		translate:	fn(nil: self ref Stroke, minx: int, miny: int, scalex: int, scaley: int);
		center:	fn(nil: self ref Stroke);
		regions:	fn(nil: self ref Stroke): ref Region;
		dominant:	fn(nil: self ref Stroke): ref Stroke;
		interpolate:	fn(points: self ref Stroke): ref Stroke;
		length:	fn(nil: self ref Stroke): int;
		pathlen:	fn(nil: self ref Stroke, first: int, last: int): int;
		contourangles:	fn(nil: self ref Stroke, regions: ref Region): array of int;
		filter:	fn(nil: self ref Stroke): ref Stroke;
	};

	# ordered list of regions
	Region: adt
	{
		rtype: int;
		start: int;
		end: int;
		next: cyclic ref Region;
	};

	#  region types
	Rconvex, Rconcave, Rplain, Rpseudo: con iota;

	Classifier: adt
	{
		nclasses:	int;	# number of symbols in class
		examples:	array of list of ref Stroke;	# optional training examples
		cnames:	array of string;		# the class names
		canonex:	array of ref Stroke;		# optional canonical versions of the strokes
		dompts:	array of ref Stroke;	# dominant points

		match:	fn(nil: self ref Classifier, stroke: ref Stroke): (int, string);
	};

	init:	fn();

	preprocess_stroke:	fn(nil: ref Stroke);
	score_stroke:	fn(a: ref Stroke, b: ref Stroke): (int, int);

	compute_similarity:	fn(a: ref Stroke, b: ref Stroke): int;
	compute_distance:	fn(a: ref Stroke, b: ref Stroke): int;
	compute_chain_code:	fn(nil: ref Stroke);
	compute_unit_chain_code:	fn(pts: ref Stroke);

	regiontype:	fn(ang: int): int;

	sqrt:		fn(n: int): int;
	likeatan:	fn(top: int, bot: int): int;
	quadr:	fn(t: int): int;

	printpoints:	fn(fd: ref Sys->FD, nil: ref Stroke, sep: string);

	MAXDIST:	con 16r7FFFFFFF;
};

Readstrokes: module
{
	PATH: con "/dis/lib/strokes/readstrokes.dis";

	init:	fn(nil: Strokes);
	read_classifier:	fn(file: string, build: int, needex: int): (string, ref Strokes->Classifier);
	read_digest:	fn(fd: ref Sys->FD): (string, array of string, array of ref Strokes->Stroke);
	read_examples:	fn(fd: ref Sys->FD): (string, array of string, array of list of ref Strokes->Stroke);
};

Writestrokes: module
{
	PATH: con "/dis/lib/strokes/writestrokes.dis";

	init:	fn(nil: Strokes);
	write_digest:	fn(fd: ref Sys->FD, nil: array of string, nil: array of ref Strokes->Stroke): string;
	write_examples:	fn(fd: ref Sys->FD, nil: array of string, nil: array of list of ref Strokes->Stroke): string;
};

Buildstrokes: module
{
	PATH: con "/dis/lib/strokes/buildstrokes.dis";

	init:	fn(nil: Strokes);
	canonical_example:	fn(n: int, cnames: array of string, nil: array of list of ref Strokes->Stroke): (string, array of ref Strokes->Stroke, array of ref Strokes->Stroke);
	canonical_stroke:	fn(points: ref Strokes->Stroke): ref Strokes->Stroke;
	compute_equipoints:	fn(nil: ref Strokes->Stroke): ref Strokes->Stroke;
};

# special characters and gestures
#	in digits.cl:	BNASRPUVWX
#	in punc.cl:	TFGHIJK
#	in letters.cl:	ABNPRSUVWX

#	L caps lock
#	N num lock
#	P ctrl (Unix), punc shift (orig)
#	S shift

#	A space
#	B backspace
#	R return
#	. puncshift
