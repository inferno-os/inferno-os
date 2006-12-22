Math: module
{
	PATH:	con	"$Math";

	Infinity:	con 1e400;
	NaN:		con 0./0.;
	MachEps:	con 2.2204460492503131e-16;
	Pi:		con 3.14159265358979323846;
	Degree:		con Pi/180.;
	INVAL:		con (1<<0);
	ZDIV:		con (1<<1);
	OVFL:		con (1<<2);
	UNFL:		con (1<<3);
	INEX:		con (1<<4);
	RND_NR:		con (0<<8);
	RND_NINF:	con (1<<8);
	RND_PINF:	con (2<<8);
	RND_Z:		con (3<<8);
	RND_MASK:	con (3<<8);
	acos:		fn(x: real): real;	# arccos(x) in [0,pi]
	acosh:		fn(x: real): real;
	asin:		fn(x: real): real;	# arcsin(x) in [-pi/2,pi/2]
	asinh:		fn(x: real): real;
	atan:		fn(x: real): real;	# arctan(x) in [-pi/2,pi/2]
	atan2:		fn(y, x: real): real;	# arctan(y/x) in [-pi,pi]
	atanh:		fn(x: real): real;
	cbrt:		fn(x: real): real;
	ceil:		fn(x: real): real;
	copysign:	fn(x, s: real): real;
	cos:		fn(x: real): real;
	cosh:		fn(x: real): real;
	dot:		fn(x, y: array of real): real;
	erf:		fn(x: real): real;
	erfc:		fn(x: real): real;
	exp:		fn(x: real): real;
	expm1:		fn(x: real): real;
	fabs:		fn(x: real): real;
	fdim, fmin, fmax: fn(x, y: real): real;
	finite:		fn(x: real): int;
	floor:		fn(x: real): real;
	fmod:		fn(x, y: real): real;
	gemm:		fn(transa, transb: int,  # upper case N or T
			m, n, k: int, alpha: real,
			a: array of real, lda: int,
			b: array of real, ldb: int, beta: real,
			c: array of real, ldc: int);
	getFPcontrol, getFPstatus: fn(): int;
	FPcontrol, FPstatus: fn(r, mask: int): int;
	hypot:		fn(x, y: real): real;
	iamax:		fn(x: array of real): int;
	ilogb:		fn(x: real): int;
	isnan:		fn(x: real): int;
	j0:		fn(x: real): real;
	j1:		fn(x: real): real;
	jn:		fn(n: int, x: real): real;
	lgamma:		fn(x: real): (int,real);
	log:		fn(x: real): real;
	log10:		fn(x: real): real;
	log1p:		fn(x: real): real;
	modf:		fn(x: real): (int,real);
	nextafter:	fn(x, y: real): real;
	norm1, norm2:	fn(x: array of real): real;
	pow:		fn(x, y: real): real;
	pow10:		fn(p: int): real;
	remainder:	fn(x, p: real): real;
	rint:		fn(x: real): real;
	scalbn:		fn(x: real, n: int): real;
	sin:		fn(x: real): real;
	sinh:		fn(x: real): real;
	sort:		fn(x: array of real, pi: array of int);
	sqrt:		fn(x: real): real;
	tan:		fn(x: real): real;
	tanh:		fn(x: real): real;
	y0:		fn(x: real): real;
	y1:		fn(x: real): real;
	yn:		fn(n: int, x: real): real;


	import_int:	fn(b: array of byte, x: array of int);
	import_real32:	fn(b: array of byte, x: array of real);
	import_real:	fn(b: array of byte, x: array of real);
	export_int:	fn(b: array of byte, x: array of int);
	export_real32:	fn(b: array of byte, x: array of real);
	export_real:	fn(b: array of byte, x: array of real);

	# undocumented, of specialized interest only    DEPRECATED
	bits32real:	fn(b: int): real; # IEEE 32-bit format to real
	bits64real:	fn(b: big): real; # IEEE 64-bit format to real
	realbits32:	fn(x: real): int; # real to IEEE 32-bit format
	realbits64:	fn(x: real): big; # real to IEEE 64-bit format
};
