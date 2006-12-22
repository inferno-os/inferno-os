Scaler: module
{
	PATH: con "/dis/lib/print/scaler.dis";

	init: fn(debug: int, WidthInPixels, ScaleFactorMultiplier, ScaleFactorDivisor: int): ref RESSYNSTRUCT;
	rasterin: fn(rs: ref RESSYNSTRUCT, inraster: array of int);
	rasterout: fn(rs: ref RESSYNSTRUCT ): array of int;

	RESSYNSTRUCT: adt {
		Width: int;
		ScaleFactorMultiplier: int;
		ScaleFactorDivisor: int;
		ScaleFactor: real;
		iOutputWidth: int;
		scaling: int;
		ReplicateOnly: int;
		Repeat: int;
		RastersinBuffer: int;
		Remainder: int;
		Buffer: array of array of int;
		oBuffer: array of array of int;
		nready: int;
		ndelivered: int;
	};


};


NUMBER_RASTERS: con 3;	# no of rasters to buffer
