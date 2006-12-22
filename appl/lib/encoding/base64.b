implement Encoding;

include "encoding.m";

enc(a: array of byte) : string
{
	n := len a;
	if(n == 0)
		return "";
	out := "";
	j := 0;
	i := 0;
	while(i < n) {
		x := int a[i++] << 16;
		if(i < n)
			x |= (int a[i++]&255) << 8;
		if(i < n)
			x |= (int a[i++]&255);
		out[j++] = c64(x>>18);
		out[j++] = c64(x>>12);
		out[j++] = c64(x>> 6);
		out[j++] = c64(x);
	}
	nmod3 := n % 3;
	if(nmod3 != 0) {
		out[j-1] = '=';
		if(nmod3 == 1)
			out[j-2] = '=';
	}
	return out;
}

c64(c: int) : int
{
	v: con "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	return v[c&63];
}

INVAL: con byte 255;

t64d := array[256] of {
   INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,
   INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,
   INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,   byte 62,INVAL,INVAL,INVAL,   byte 63,
      byte 52,   byte 53,   byte 54,   byte 55,   byte 56,   byte 57,   byte 58,   byte 59,   byte 60,   byte 61,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,
   INVAL,    byte 0,    byte 1,    byte 2,    byte 3,    byte 4,    byte 5,    byte 6,    byte 7,    byte 8,    byte 9,   byte 10,   byte 11,   byte 12,   byte 13,   byte 14,
      byte 15,   byte 16,   byte 17,   byte 18,   byte 19,   byte 20,   byte 21,   byte 22,   byte 23,   byte 24,   byte 25,INVAL,INVAL,INVAL,INVAL,INVAL,
   INVAL,   byte 26,   byte 27,   byte 28,   byte 29,   byte 30,   byte 31,   byte 32,   byte 33,   byte 34,   byte 35,   byte 36,   byte 37,   byte 38,   byte 39,   byte 40,
      byte 41,   byte 42,   byte 43,   byte 44,   byte 45,   byte 46,   byte 47,   byte 48,   byte 49,   byte 50,   byte 51,INVAL,INVAL,INVAL,INVAL,INVAL,
   INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,
   INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,
   INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,
   INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,
   INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,
   INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,
   INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,
   INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL,INVAL
};

dec(s: string): array of byte
{
	b24 := 0;
	i := 0;
	out := array[(3*len s+3)/4] of byte;	# upper bound, especially if s contains white space
	o := 0;
	for(n := 0; n < len s; n++){
		if((c := s[n]) > 16rFF || (c = int t64d[c]) == int INVAL)
			continue;
		case i++ {
		0 =>
			b24 = c<<18;
		1 =>
			b24 |= c<<12;
		2 =>
			b24 |= c<<6;
		3 =>
			b24 |= c;
			out[o++] = byte (b24>>16);
			out[o++] = byte (b24>>8);
			out[o++] = byte b24;
			i = 0;
		}
	}
	case i {
	2 =>
		out[o++] = byte (b24>>16);
	3 =>
		out[o++] = byte (b24>>16);
		out[o++] = byte (b24>>8);
	}
	return out[0:o];
}
