implement Scaler;

include "sys.m";
	sys: Sys;
include "draw.m";
include "print.m";
include "scaler.m";

DEBUG := 0;

# Scaler initialisation

init(debug: int, WidthInPixels, ScaleFactorMultiplier, ScaleFactorDivisor: int): ref RESSYNSTRUCT
{
	DEBUG = debug;
	ScaleFactor := real ScaleFactorMultiplier / real ScaleFactorDivisor;
	ScaleBound := int ScaleFactor;
	if  (ScaleFactor > real ScaleBound) ScaleBound++;
	ResSynStruct := ref RESSYNSTRUCT (
					WidthInPixels+2,	# add 2 for edges
					ScaleFactorMultiplier,
					ScaleFactorDivisor,
					ScaleFactor,
					int ((real WidthInPixels / real ScaleFactorDivisor))*ScaleFactorMultiplier + 1,
					ScaleFactorMultiplier != ScaleFactorDivisor,
					ScaleFactor < 2.0,
					(ScaleFactorMultiplier * 256 / ScaleFactorDivisor)
										  -  ((ScaleFactorMultiplier/ScaleFactorDivisor) * 256),
					0,
					0,
					array[NUMBER_RASTERS] of array of int,
					array[ScaleBound] of array of int,
					0,
					0
				);
	if (ResSynStruct.ScaleFactor > real ScaleBound) ScaleBound++;
	for (i:=0; i<len ResSynStruct.Buffer; i++) ResSynStruct.Buffer[i] = array[WidthInPixels*NUMBER_RASTERS] of int;
	for (i=0; i<len ResSynStruct.oBuffer; i++) ResSynStruct.oBuffer[i] = array[ResSynStruct.iOutputWidth] of int;
	return ResSynStruct;
}


# Input a raster line to the scaler

rasterin(rs: ref RESSYNSTRUCT, inraster: array of int)
{
	if (!rs.scaling) {		# Just copy to output buffer
		if (inraster == nil) return;
		rs.oBuffer[0] = inraster;
		rs.nready = 1;
		rs.ndelivered = 0;
		return;
	}

	if (rs.ReplicateOnly) {	# for scaling between 1 and 2
#		for (i:=0; i<len inraster; i++) rs.oBuffer[0][i] = inraster[i];
		rs.oBuffer[0][:] = inraster[0:];
		create_out(rs, 1);
		return;
	}

	if (rs.RastersinBuffer == 0) {	# First time through
		if (inraster == nil) return;
		for (i:=0; i<2; i++) {
			rs.Buffer[i][0] = inraster[0];
#			for (j:=1; j<rs.Width-1; j++) rs.Buffer[i][j] = inraster[j-1];
			rs.Buffer[i][1:] = inraster[0:rs.Width-2];
			rs.Buffer[i][rs.Width-1] = inraster[rs.Width-3];
		}
		rs.RastersinBuffer = 2;
		return;
	}

	if (rs.RastersinBuffer == 2) {	# Just two buffers in so far
		if (inraster != nil) {
			i := 2;
			rs.Buffer[i][0] = inraster[0];
#			for (j:=1; j<rs.Width-1; j++) rs.Buffer[i][j] = inraster[j-1];
			rs.Buffer[i][1:] = inraster[0:rs.Width-2];
			rs.Buffer[i][rs.Width-1] = inraster[rs.Width-3];
			rs.RastersinBuffer = 3;
		} else {	# nil means end of image
			rez_synth(rs, rs.oBuffer[0], rs.oBuffer[1]);
			create_out(rs, 0);
		}
		return;
	}
	if (rs.RastersinBuffer == 3) {	# All three buffers are full
		(rs.Buffer[0], rs.Buffer[1], rs.Buffer[2]) = (rs.Buffer[1], rs.Buffer[2], rs.Buffer[0]);
		if (inraster != nil) {
			i := 2;
			rs.Buffer[i][0] = inraster[0];
#			for (j:=1; j<rs.Width-1; j++) rs.Buffer[i][j] = inraster[j-1];
			rs.Buffer[i][1:] = inraster[0:rs.Width-2];
			rs.Buffer[i][rs.Width-1] = inraster[rs.Width-3];
		} else {	# nil means end of image
#			for (j:=0; j<len rs.Buffer[1]; j++) rs.Buffer[2][j] = rs.Buffer[1][j];
			rs.Buffer[2][:] = rs.Buffer[1];
			rs.RastersinBuffer = 0;

		}
		rez_synth(rs, rs.oBuffer[0], rs.oBuffer[1]);
		create_out(rs, 0);
	}

}


# Get a raster output line from the scaler

rasterout(rs: ref RESSYNSTRUCT): array of int
{
	if (rs.nready-- > 0) {
		return rs.oBuffer[rs.ndelivered++][:rs.iOutputWidth-1];
	} else return nil;
}



# Create output raster

create_out(rs: ref RESSYNSTRUCT, simple: int)
{
	factor: int;
	if (simple) factor = 1;
	else factor = 2;

	out_width := (rs.Width-2) * rs.ScaleFactorMultiplier / rs.ScaleFactorDivisor;
	number_out := rs.ScaleFactorMultiplier / rs.ScaleFactorDivisor; 
	if (number_out == 2 && !(rs.ScaleFactorMultiplier % rs.ScaleFactorDivisor) ) {
		rs.nready = 2;
		rs.ndelivered = 0;
		return;
	}

	if (rs.ScaleFactorMultiplier % rs.ScaleFactorDivisor)
	{
		rs.Remainder = rs.Remainder + rs.Repeat;  

		if (rs.Remainder >= 256)	# send extra raster
		{
			number_out++;
			rs.Remainder = rs.Remainder - 256; 
		}
	}
	# set up pointers into the output buffer
	output_raster := array[number_out] of array of int;
	output_raster[:] = rs.oBuffer[0:number_out];

	ScaleFactorMultiplier := rs.ScaleFactorMultiplier;
	ScaleFactorDivisor := rs.ScaleFactorDivisor;
	sf := factor * ScaleFactorDivisor;

	# Convert the input data by starting at the bottom right hand corner and move left + up
	for (i:=(number_out-1); i>=0; i--) {
		y_index := i*sf/ScaleFactorMultiplier;
		orast_i := output_raster[i];
		orast_y := output_raster[y_index];
		for (lx := out_width-1; lx>=0; --lx) {
			x_index := lx*sf/ScaleFactorMultiplier;
			orast_i[lx] = orast_y[x_index];
		}
	}

	rs.nready = number_out;
	rs.ndelivered = 0;
	return;
}


# Synthesise raster line

rez_synth(rs: ref RESSYNSTRUCT, output_raster0, output_raster1: array of int)
{

	i := 1;
	Buffer := rs.Buffer[i];
	h_offset := 0;
	for (j:=1; j<rs.Width-1; j++) {
		rgb := Buffer[j];
		output_raster0[h_offset] = rgb;
		output_raster1[h_offset++] = rgb;
		output_raster0[h_offset] = rgb;
		output_raster1[h_offset++] = rgb;
	}
}
