implement Base64;
include "base64.m";

PADCH: con '=';
encode(b: array of byte): string
{
	chmap := "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
			"abcdefghijklmnopqrstuvwxyz0123456789+/";
	r := "";
	blen := len b;
	full := (blen + 2)/ 3;
	rplen := (4*blen + 2) / 3;
	ip := 0;
	rp := 0;
	for (i:=0; i<full; i++) {
		word := 0;
		for (j:=2; j>=0; j--)
			if (ip < blen)
				word = word | int b[ip++] << 8*j;
		for (l:=3; l>=0; l--)
			if (rp < rplen)
				r[rp++] = chmap[(word >> (6*l)) & 16r3f];
			else
				r[rp++] = PADCH;
	}
	return r;
}

# Decode a base 64 string to a byte stream
# Must be a multiple of 4 characters in length
decode(s: string): array of byte
{

	tch: int;
	slen := len s;
	rlen := (3*slen+3)/4;
	if (slen >= 4 && s[slen-1] == PADCH)
		rlen--;
	if (slen >= 4 && s[slen-2] == PADCH)
		rlen--;
	r := array[rlen] of byte;
	full := slen / 4;
	sp := 0;
	rp := 0;
	for (i:=0; i<full; i++) {
		word := 0; 
		for (j:=0; j<4; j++) {
			ch := s[sp++];
			case ch {
			'A' to 'Z' =>
				tch = ch - 'A';
			'a' to 'z' =>
				tch = ch - 'a' + 26;
			'0' to '9' =>
				tch = ch - '0' + 52;
			'+' =>
				tch = 62;
			'/' =>
				tch = 63;
			* =>
				tch = 0;
			}
			word = (word << 6) | tch;
		}
		for (l:=2; l>=0; l--)
			if (rp < rlen)
				r[rp++] = byte( (word >> 8*l) & 16rff);

	}
	return r;
}

