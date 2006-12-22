Geodesy: module
{
	PATH: con "/dis/math/geodesy.dis";

	# easting, northing in metres
	Eano: adt{
		e: real;
		n: real;
	};

	# latitude, longitude in radians
	Lalo: adt{
		la: real;
		lo: real;
	};

	# datums
	# WGS84 and ITRS2000 effectively the same
	OSGB36, Ireland65, ED50, WGS84, ITRS2000, ETRS89: con iota;

	# transverse Mercator projections
	Natgrid, IrishNatgrid, UTMEur, UTM: con iota;

	# call first
	# d specifies the datum (default WGS84)
	# t specifies the transverse Mercator projection (default Natgrid)
	# z specifies the UTM zone if relevant (default 30)
	# calls format below
	init: fn(d: int, t: int, z: int);

	# alters the current datum, transverse Mercator projection and UTM zone
	# use a negative value to leave unaltered
	format: fn(d: int, t: int, z: int);

	# OS string to (easting, northing) and back
	# formats XYen, XYeenn, XYeeennn, XYeeeennnn, XYeeeeennnnn or
	# formats eenn, eeennn, eeeennnn, eeeeennnnn, eeeeeennnnnn
	os2en: fn(s: string): (int, Eano);	# returns (0, ...) if bad string format
	en2os: fn(en: Eano): string;

	# latitude/longitude string to (latitude, longitude) and back
	# format latitude longitude
	# formats deg[N|S], deg:min[N|S], deg:min:sec[N|S] for latitude
	# formats deg[E|W], deg:min[E|W], deg:min:sec[E|W] for longitude
	str2lalo: fn(s: string): (int, Lalo);	# returns (0, ...) if bad string format
	lalo2str: fn(lalo: Lalo): string;

	# general string to (easting, northing)
	# OS grid or latitude/longitude format as above
	str2en: fn(s: string): (int, Eano);	# returns (0, ...) if bad string format

	# (easting, northing) to (latitude, longitude) and back
	en2lalo: fn(en: Eano): Lalo;
	lalo2en: fn(lalo: Lalo): Eano;

	# approximate transformations between any of OSGB36, WGS84, ITRS2000, ETRS89
	datum2datum: fn(lalo: Lalo, f: int, t: int): Lalo;
};
