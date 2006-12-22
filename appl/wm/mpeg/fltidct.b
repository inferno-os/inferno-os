implement IDCT;

include "sys.m";
include "mpegio.m";

init()
{
}

# IDCT based on Arai, Agui, and Nakajima, using flow chart Figure 4.8
# of Pennebaker & Mitchell, JPEG: Still Image Data Compression Standard.
# Remember IDCT is reverse of flow of DCT.
# Based on rob's readjpeg.b

a0: con 1.414;
a1: con 0.707;
a2: con 0.541;
a3: con 0.707;
a4: con 1.307;
a5: con -0.383;

# scaling factors from eqn 4-35 of P&M
s1: con 1.0196;
s2: con 1.0823;
s3: con 1.2026;
s4: con 1.4142;
s5: con 1.8000;
s6: con 2.6131;
s7: con 5.1258;

# overall normalization of 1/16, folded into premultiplication on vertical pass
scale: con 0.0625;

ridct(zin: array of real, zout: array of real)
{
	x, y: int;

	r := array[8*8] of real;

	# transform horizontally
	for(y=0; y<8; y++){
		eighty := y<<3;
		# if all non-DC components are zero, just propagate the DC term
		if(zin[eighty+1]==0.)
		if(zin[eighty+2]==0. && zin[eighty+3]==0.)
		if(zin[eighty+4]==0. && zin[eighty+5]==0.)
		if(zin[eighty+6]==0. && zin[eighty+7]==0.){
			v := zin[eighty]*a0;
			r[eighty+0] = v;
			r[eighty+1] = v;
			r[eighty+2] = v;
			r[eighty+3] = v;
			r[eighty+4] = v;
			r[eighty+5] = v;
			r[eighty+6] = v;
			r[eighty+7] = v;
			continue;
		}

		# step 5
		in1 := s1*zin[eighty+1];
		in3 := s3*zin[eighty+3];
		in5 := s5*zin[eighty+5];
		in7 := s7*zin[eighty+7];
		f2 := s2*zin[eighty+2];
		f3 := s6*zin[eighty+6];
		f5 := (in1+in7);
		f7 := (in5+in3);

		# step 4
		g2 := f2-f3;
		g4 := (in5-in3);
		g6 := (in1-in7);
		g7 := f5+f7;

		# step 3.5
		t := (g4+g6)*a5;

		# step 3
		f0 := a0*zin[eighty+0];
		f1 := s4*zin[eighty+4];
		f3 += f2;
		f2 = a1*g2;

		# step 2
		g0 := f0+f1;
		g1 := f0-f1;
		g3 := f2+f3;
		g4 = t-a2*g4;
		g5 := a3*(f5-f7);
		g6 = a4*g6+t;

		# step 1
		f0 = g0+g3;
		f1 = g1+f2;
		f2 = g1-f2;
		f3 = g0-g3;
		f5 = g5-g4;
		f6 := g5+g6;
		f7 = g6+g7;

		# step 6
		r[eighty+0] = (f0+f7);
		r[eighty+1] = (f1+f6);
		r[eighty+2] = (f2+f5);
		r[eighty+3] = (f3-g4);
		r[eighty+4] = (f3+g4);
		r[eighty+5] = (f2-f5);
		r[eighty+6] = (f1-f6);
		r[eighty+7] = (f0-f7);
	}

	# transform vertically
	for(x=0; x<8; x++){
		# step 5
		in1 := scale*s1*r[x+8];
		in3 := scale*s3*r[x+24];
		in5 := scale*s5*r[x+40];
		in7 := scale*s7*r[x+56];
		f2 := scale*s2*r[x+16];
		f3 := scale*s6*r[x+48];
		f5 := (in1+in7);
		f7 := (in5+in3);

		# step 4
		g2 := f2-f3;
		g4 := (in5-in3);
		g6 := (in1-in7);
		g7 := f5+f7;

		# step 3.5
		t := (g4+g6)*a5;

		# step 3
		f0 := scale*a0*r[x];
		f1 := scale*s4*r[x+32];
		f3 += f2;
		f2 = a1*g2;

		# step 2
		g0 := f0+f1;
		g1 := f0-f1;
		g3 := f2+f3;
		g4 = t-a2*g4;
		g5 := a3*(f5-f7);
		g6 = a4*g6+t;

		# step 1
		f0 = g0+g3;
		f1 = g1+f2;
		f2 = g1-f2;
		f3 = g0-g3;
		f5 = g5-g4;
		f6 := g5+g6;
		f7 = g6+g7;

		# step 6
		zout[x] = (f0+f7);
		zout[x+8] = (f1+f6);
		zout[x+16] = (f2+f5);
		zout[x+24] = (f3-g4);
		zout[x+32] = (f3+g4);
		zout[x+40] = (f2-f5);
		zout[x+48] = (f1-f6);
		zout[x+56] = (f0-f7);
	}
}

idct(b: array of int)
{
	tmp := array[64] of real;
	for (i := 0; i < 64; i++)
		tmp[i] = real b[i];
	ridct(tmp, tmp);
	for (i = 0; i < 64; i++)
		b[i] = int tmp[i];
}
