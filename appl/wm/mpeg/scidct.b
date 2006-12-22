implement IDCT;

include "sys.m";
include "mpegio.m";

init()
{
}

# Scaled integer implementation.
# inverse two dimensional DCT, Chen-Wang algorithm
# (IEEE ASSP-32, pp. 803-816, Aug. 1984)
# 32-bit integer arithmetic (8 bit coefficients)
# 11 mults, 29 adds per DCT
#
# coefficients extended to 12 bit for IEEE1180-1990
# compliance

W1:	con 2841;	# 2048*sqrt(2)*cos(1*pi/16)
W2:	con 2676;	# 2048*sqrt(2)*cos(2*pi/16)
W3:	con 2408;	# 2048*sqrt(2)*cos(3*pi/16)
W5:	con 1609;	# 2048*sqrt(2)*cos(5*pi/16)
W6:	con 1108;	# 2048*sqrt(2)*cos(6*pi/16)
W7:	con 565;	# 2048*sqrt(2)*cos(7*pi/16)

W1pW7:	con 3406;	# W1+W7
W1mW7:	con 2276;	# W1-W7
W3pW5:	con 4017;	# W3+W5
W3mW5:	con 799;	# W3-W5
W2pW6:	con 3784;	# W2+W6
W2mW6:	con 1567;	# W2-W6

R2:	con 181;	# 256/sqrt(2)

idct(b: array of int)
{
	# transform horizontally
	for(y:=0; y<8; y++){
		eighty := y<<3;
		# if all non-DC components are zero, just propagate the DC term
		if(b[eighty+1]==0)
		if(b[eighty+2]==0 && b[eighty+3]==0)
		if(b[eighty+4]==0 && b[eighty+5]==0)
		if(b[eighty+6]==0 && b[eighty+7]==0){
			v := b[eighty]<<3;
			b[eighty+0] = v;
			b[eighty+1] = v;
			b[eighty+2] = v;
			b[eighty+3] = v;
			b[eighty+4] = v;
			b[eighty+5] = v;
			b[eighty+6] = v;
			b[eighty+7] = v;
			continue;
		}
		# prescale
		x0 := (b[eighty+0]<<11)+128;
		x1 := b[eighty+4]<<11;
		x2 := b[eighty+6];
		x3 := b[eighty+2];
		x4 := b[eighty+1];
		x5 := b[eighty+7];
		x6 := b[eighty+5];
		x7 := b[eighty+3];
		# first stage
		x8 := W7*(x4+x5);
		x4 = x8 + W1mW7*x4;
		x5 = x8 - W1pW7*x5;
		x8 = W3*(x6+x7);
		x6 = x8 - W3mW5*x6;
		x7 = x8 - W3pW5*x7;
		# second stage
		x8 = x0 + x1;
		x0 -= x1;
		x1 = W6*(x3+x2);
		x2 = x1 - W2pW6*x2;
		x3 = x1 + W2mW6*x3;
		x1 = x4 + x6;
		x4 -= x6;
		x6 = x5 + x7;
		x5 -= x7;
		# third stage
		x7 = x8 + x3;
		x8 -= x3;
		x3 = x0 + x2;
		x0 -= x2;
		x2 = (R2*(x4+x5)+128)>>8;
		x4 = (R2*(x4-x5)+128)>>8;
		# fourth stage
		b[eighty+0] = (x7+x1)>>8;
		b[eighty+1] = (x3+x2)>>8;
		b[eighty+2] = (x0+x4)>>8;
		b[eighty+3] = (x8+x6)>>8;
		b[eighty+4] = (x8-x6)>>8;
		b[eighty+5] = (x0-x4)>>8;
		b[eighty+6] = (x3-x2)>>8;
		b[eighty+7] = (x7-x1)>>8;
	}
	# transform vertically
	for(x:=0; x<8; x++){
		# if all non-DC components are zero, just propagate the DC term
		if(b[x+8*1]==0)
		if(b[x+8*2]==0 && b[x+8*3]==0)
		if(b[x+8*4]==0 && b[x+8*5]==0)
		if(b[x+8*6]==0 && b[x+8*7]==0){
			v := (b[x+8*0]+32)>>6;
			b[x+8*0] = v;
			b[x+8*1] = v;
			b[x+8*2] = v;
			b[x+8*3] = v;
			b[x+8*4] = v;
			b[x+8*5] = v;
			b[x+8*6] = v;
			b[x+8*7] = v;
			continue;
		}
		# prescale
		x0 := (b[x+8*0]<<8)+8192;
		x1 := b[x+8*4]<<8;
		x2 := b[x+8*6];
		x3 := b[x+8*2];
		x4 := b[x+8*1];
		x5 := b[x+8*7];
		x6 := b[x+8*5];
		x7 := b[x+8*3];
		# first stage
		x8 := W7*(x4+x5) + 4;
		x4 = (x8+W1mW7*x4)>>3;
		x5 = (x8-W1pW7*x5)>>3;
		x8 = W3*(x6+x7) + 4;
		x6 = (x8-W3mW5*x6)>>3;
		x7 = (x8-W3pW5*x7)>>3;
		# second stage
		x8 = x0 + x1;
		x0 -= x1;
		x1 = W6*(x3+x2) + 4;
		x2 = (x1-W2pW6*x2)>>3;
		x3 = (x1+W2mW6*x3)>>3;
		x1 = x4 + x6;
		x4 -= x6;
		x6 = x5 + x7;
		x5 -= x7;
		# third stage
		x7 = x8 + x3;
		x8 -= x3;
		x3 = x0 + x2;
		x0 -= x2;
		x2 = (R2*(x4+x5)+128)>>8;
		x4 = (R2*(x4-x5)+128)>>8;
		# fourth stage
		b[x+8*0] = (x7+x1)>>14;
		b[x+8*1] = (x3+x2)>>14;
		b[x+8*2] = (x0+x4)>>14;
		b[x+8*3] = (x8+x6)>>14;
		b[x+8*4] = (x8-x6)>>14;
		b[x+8*5] = (x0-x4)>>14;
		b[x+8*6] = (x3-x2)>>14;
		b[x+8*7] = (x7-x1)>>14;
	}
}
