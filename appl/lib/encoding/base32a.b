implement Encoding;

include "encoding.m";

b32: con "23456789abcdefghijkmnpqrstuvwxyz";

enc(a: array of byte): string
{
	if(len a == 0)
		return "========";
	out := "";
	nbit := len a * 8;
	for(bit := 0; bit < nbit; bit += 5){
		b := bit >> 3;
		r := bit & 7;
		v := int a[b] << r;
		if(r > 3){
			if(b+1 < len a)
				v |= int (a[b+1] >> (8-r));
		}
		out[len out] = b32[(v>>3) & 16r1F];
	}
	# RFC3548 says pad with =; this follows alternative tradition (a)
	return out;
}

INVAL: con 255;

t32d := array[256] of {
	'2' => byte 0, '3' => byte 1, '4' => byte 2, '5' => byte 3, '6' => byte 4, '7' => byte 5, '8' => byte 6, '9' => byte 7,
	'a' => byte 8, 'b' => byte 9, 'c' => byte 10, 'd' => byte 11, 'e' => byte 12, 'f' => byte 13, 'g' => byte 14, 'h' => byte 15,
	'i' => byte 16, 'j' => byte 17, 'k' => byte 18, 'm' => byte 19, 'n' => byte 20, 'p' => byte 21, 'q' => byte 22, 'r' => byte 23,
	's' => byte 24, 't' => byte 25, 'u' => byte 26, 'v' => byte 27, 'w' => byte 28, 'x' => byte 29, 'y' => byte 30, 'z' => byte 31,
	'A' => byte 8, 'B' => byte 9, 'C' => byte 10, 'D' => byte 11, 'E' => byte 12, 'F' => byte 13, 'G' => byte 14, 'H' => byte 15,
	'I' => byte 16, 'J' => byte 17, 'K' => byte 18, 'M' => byte 19, 'N' => byte 20, 'P' => byte 21, 'Q' => byte 22, 'R' => byte 23,
	'S' => byte 24, 'T' => byte 25, 'U' => byte 26, 'V' => byte 27, 'W' => byte 28, 'X' => byte 29, 'Y' => byte 30, 'Z' => byte 31,
	* => byte INVAL
};

dec(s: string): array of byte
{
	a := array[(8*len s + 4)/5] of byte;
	o := 0;
	v := 0;
	j := 0;
	for(i := 0; i < len s; i++){
		if((c := s[i]) > 16rFF || (c = int t32d[c]) == INVAL)
			continue;
		v <<= 5;
		v |= c;
		if((j += 5) >= 8){
			a[o++] = byte (v>>(j-8));
			j -= 8;
		}
	}
	return a[0:o];
}
