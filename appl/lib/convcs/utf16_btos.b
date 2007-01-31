implement Btos;

include "sys.m";
include "convcs.m";

Littleendian, Bigendian: con iota;

sys : Sys;
default := Bigendian;

init(arg : string) : string
{
	sys = load Sys Sys->PATH;
	case arg {
	"le" =>
		default = Littleendian;
	"be" =>
		default = Bigendian;
	}
	return nil;
}


btos(state : Convcs->State, b : array of byte, n : int) : (Convcs->State, string, int)
{
	endian: int;
	i := 0;
	if(state != nil)
		endian = state[0];
	else if (len b >= 2) {
		state = " ";
		# XXX should probably not do this if we've been told the endianness
		case (int b[0] << 8) | int b[1] {
		16rfeff =>
			endian = Bigendian;
			i += 2;
		16rfffe =>
			endian = Littleendian;
			i += 2;
		* =>
			endian = guessendian(b);
		}
		state[0] = endian;
	}
	nb := len b & ~1;
	if(n > 0 && nb - i > n * 2)
		nb = i + n * 2;
	out := "";
	if(endian == Bigendian){
		for(; i < nb; i += 2)
			out[len out] = (int b[i] << 8) | int b[i + 1];
	}else{
		for(; i < nb; i += 2)
			out[len out] = int b[i] | int b[i + 1] << 8;
	}
	if(n == 0 && i < len b)
		out[len out] = Sys->UTFerror;
		
	return (state, out, i);
}

guessendian(nil: array of byte): int
{
	# XXX might be able to do better than this in the absence of endian hints.
	return default;
}
