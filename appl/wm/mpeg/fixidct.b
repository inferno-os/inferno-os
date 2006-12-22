implement IDCT;

include "sys.m";
include "mpegio.m";

init()
{
}

# IDCT based on Arai, Agui, and Nakajima, using flow chart Figure 4.8
# of Pennebaker & Mitchell, JPEG: Still Image Data Compression Standard.
# Remember IDCT is reverse of flow of DCT.
# Nasty truncated integer version (not compliant).

B0: con 16;
B1: con 16;
M: con (1 << B0);
N: con (1 << B1);

a0: con 1.414;
a1: con 0.707;
a2: con 0.541;
a3: con 0.707;
a4: con 1.307;
a5: con -0.383;

A0: con int (a0 * real N);
A1: con int (a1 * real M);
A2: con int (a2 * real M);
A3: con int (a3 * real M);
A4: con int (a4 * real M);
A5: con int (a5 * real M);

# scaling factors from eqn 4-35 of P&M
s1: con 1.0196;
s2: con 1.0823;
s3: con 1.2026;
s4: con 1.4142;
s5: con 1.8000;
s6: con 2.6131;
s7: con 5.1258;

S1: con int (s1 * real N);
S2: con int (s2 * real N);
S3: con int (s3 * real N);
S4: con int (s4 * real N);
S5: con int (s5 * real N);
S6: con int (s6 * real N);
S7: con int (s7 * real N);

# overall normalization of 1/16, folded into premultiplication on vertical pass
S: con 4;
scale: con 0.0625;

idct(b: array of int)
{
	x, y: int;

	r := array[8*8] of int;

	# transform horizontally
	for(y=0; y<8; y++){
		eighty := y<<3;
		# if all non-DC components are zero, just propagate the DC term
		if(b[eighty+1]==0)
		if(b[eighty+2]==0 && b[eighty+3]==0)
		if(b[eighty+4]==0 && b[eighty+5]==0)
		if(b[eighty+6]==0 && b[eighty+7]==0){
			v := b[eighty]*A0;
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
		in1 := S1*b[eighty+1];
		in3 := S3*b[eighty+3];
		in5 := S5*b[eighty+5];
		in7 := S7*b[eighty+7];
		f2 := S2*b[eighty+2];
		f3 := S6*b[eighty+6];
		f5 := (in1+in7);
		f7 := (in5+in3);

		# step 4
		g2 := f2-f3;
		g4 := (in5-in3);
		g6 := (in1-in7);
		g7 := f5+f7;

		# step 3.5
		t := ((g4+g6)>>B0)*A5;

		# step 3
		f0 := A0*b[eighty+0];
		f1 := S4*b[eighty+4];
		f3 += f2;
		f2 = A1*(g2>>B0);

		# step 2
		g0 := f0+f1;
		g1 := f0-f1;
		g3 := f2+f3;
		g4 = t-A2*(g4>>B0);
		g5 := A3*((f5-f7)>>B0);
		g6 = A4*(g6>>B0)+t;

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
		in1 := S1*(r[x+8]>>(B1+S));
		in3 := S3*(r[x+24]>>(B1+S));
		in5 := S5*(r[x+40]>>(B1+S));
		in7 := S7*(r[x+56]>>(B1+S));
		f2 := S2*(r[x+16]>>(B1+S));
		f3 := S6*(r[x+48]>>(B1+S));
		f5 := (in1+in7);
		f7 := (in5+in3);

		# step 4
		g2 := f2-f3;
		g4 := (in5-in3);
		g6 := (in1-in7);
		g7 := f5+f7;

		# step 3.5
		t := ((g4+g6)>>B0)*A5;

		# step 3
		f0 := A0*(r[x]>>(B1+S));
		f1 := S4*(r[x+32]>>(B1+S));
		f3 += f2;
		f2 = A1*(g2>>B0);

		# step 2
		g0 := f0+f1;
		g1 := f0-f1;
		g3 := f2+f3;
		g4 = t-A2*(g4>>B0);
		g5 := A3*((f5-f7)>>B0);
		g6 = A4*(g6>>B0)+t;

		# step 1
		f0 = g0+g3;
		f1 = g1+f2;
		f2 = g1-f2;
		f3 = g0-g3;
		f5 = g5-g4;
		f6 := g5+g6;
		f7 = g6+g7;

		# step 6
		b[x] = (f0+f7)>>B1;
		b[x+8] = (f1+f6)>>B1;
		b[x+16] = (f2+f5)>>B1;
		b[x+24] = (f3-g4)>>B1;
		b[x+32] = (f3+g4)>>B1;
		b[x+40] = (f2-f5)>>B1;
		b[x+48] = (f1-f6)>>B1;
		b[x+56] = (f0-f7)>>B1;
	}
}
