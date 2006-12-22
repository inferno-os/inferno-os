implement Encoding;

include "encoding.m";

b32: con "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

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
	while(len out & 7)
		out[len out] = '=';	# RFC3548 says pad: we pad.
	return out;
}

Naughty: con 255;

t32d := array[256] of {
	'a' => byte 0, 'b' => byte 1, 'c' => byte 2, 'd' => byte 3, 'e' => byte 4, 'f' => byte 5, 'g' => byte 6, 'h' => byte 7,
	'i' => byte 8, 'j' => byte 9, 'k' => byte 10, 'l' => byte 11, 'm' => byte 12, 'n' => byte 13, 'o' => byte 14, 'p' => byte 15,
	'q' => byte 16, 'r' => byte 17, 's' => byte 18, 't' => byte 19, 'u' => byte 20, 'v' => byte 21, 'w' => byte 22, 'x' => byte 23,
	'y' => byte 24, 'z' => byte 25,
	'A' => byte 0, 'B' => byte 1, 'C' => byte 2, 'D' => byte 3, 'E' => byte 4, 'F' => byte 5, 'G' => byte 6, 'H' => byte 7,
	'I' => byte 8, 'J' => byte 9, 'K' => byte 10, 'L' => byte 11, 'M' => byte 12, 'N' => byte 13, 'O' => byte 14, 'P' => byte 15,
	'Q' => byte 16, 'R' => byte 17, 'S' => byte 18, 'T' => byte 19, 'U' => byte 20, 'V' => byte 21, 'W' => byte 22, 'X' => byte 23,
	'Y' => byte 24, 'Z' => byte 25,
	'2' => byte 26, '3' => byte 27, '4' => byte 28, '5' => byte 29, '6' => byte 30, '7' => byte 31,
	* => byte Naughty
};

dec(s: string): array of byte
{
	a := array[(8*len s + 4)/5] of byte;
	o := 0;
	v := 0;
	j := 0;
	for(i := 0; i < len s; i++){
		if((c := s[i]) > 16rFF || (c = int t32d[c]) == Naughty)
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
