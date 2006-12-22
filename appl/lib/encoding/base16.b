implement Encoding;

include "encoding.m";

hex: con "0123456789ABCDEF";

enc(a: array of byte): string
{
	o: string;
	for(i := 0; i < len a; i++){
		n := int a[i];
		o[len o] = hex[n>>4];
		o[len o] = hex[n & 16rF];
	}
	return o;
}

dec(s: string): array of byte
{
	a := array[(len s+1)/2] of byte;	# upper bound
	o := 0;
	j := 0;
	n := 0;
	for(i := 0; i < len s; i++){
		c := s[i];
		n <<= 4;
		case c {
		'0' to '9' =>
			n |= c-'0';
		'A' to 'F' =>
			n |= c-'A'+10;
		'a' to 'f' =>
			n |= c-'a'+10;
		* =>
			continue;
		}
		if(++j == 2){
			a[o++] = byte n;
			j = n = 0;
		}
	}
	return a[0:o];
}
