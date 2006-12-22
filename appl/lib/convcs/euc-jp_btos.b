implement Btos;

# EUC-JP is based on ISO2022 but only uses the 8 bit stateless encoding.
# Thus, only the following ISO2022 shift functions are used:
#	SINGLE-SHIFT TWO
#	SINGLE-SHIFT THREE
#
# The initial state is G0 mapped into GL and G1 mapped into GR
# SINGLE-SHIFT TWO maps G2 into GR for one code-point encoding
# SINGLE-SHIFT THREE maps G3 into GR for one code-point encoding
#
# EUC-JP has pre-assigned code elements (G0..G3) that are never re-assigned
# by means on ISO2022 code-identification functions (escape sequences)
#
#	G0 =	ASCII
#	G1 = JIS X 0208
#	G2 = JIS X 0201 Kana
#	G3 = JIS X 0212

include "sys.m";
include "convcs.m";

sys : Sys;

SS2 : con 16r8E;	# ISO2022 SINGLE-SHIFT TWO
SS3 : con 16r8F;	# ISO2022 SINGLE-SHIFT THREE

MAXINT : con 16r7fffffff;
BADCHAR : con 16rFFFD;

G1PATH : con "/lib/convcs/jisx0208-1997";
G2PATH : con "/lib/convcs/jisx0201kana";
G3PATH : con "/lib/convcs/jisx0212";

g1map : string;
g2map : string;
g3map : string;

G1PAGESZ : con 94;
G1NPAGES : con 84;
G1PAGE0 : con 16rA1;
G1CHAR0 : con 16rA1;

G2PAGESZ : con 63;
G2NPAGES : con 1;
G2CHAR0 : con 16rA1;

G3PAGESZ : con 94;
G3NPAGES : con 77;
G3PAGE0 : con 16rA1;
G3CHAR0 : con 16rA1;

init(nil : string) : string
{
	sys = load Sys Sys->PATH;

	error := "";
	(error, g1map) = getmap(G1PATH, G1PAGESZ, G1NPAGES);
	if (error != nil)
		return error;
	(error, g2map) = getmap(G2PATH, G2PAGESZ, G2NPAGES);
	if (error != nil)
		return error;
	(error, g3map) = getmap(G3PATH, G3PAGESZ, G3NPAGES);
	return error;
}

getmap(path : string, pgsz, npgs : int) : (string, string)
{
	fd := sys->open(path, Sys->OREAD);
	if (fd == nil)
		return (sys->sprint("%s: %r", path), nil);

	buf := array[(pgsz * npgs) * Sys->UTFmax] of byte;
	nread := 0;
	for (;nread < len buf;) {
		n := sys->read(fd, buf[nread:], Sys->ATOMICIO);
		if (n <= 0)
			break;
		nread += n;
	}
	map := string buf[:nread];
	if (len map != (pgsz * npgs))
		return (sys->sprint("%s: bad data", path), nil);
	return (nil, map);
}

btos(nil : Convcs->State, b : array of byte, n : int) : (Convcs->State, string, int)
{
	nbytes := 0;
	str := "";

	if (n == -1)
		n = MAXINT;

	codelen := 1;
	codeix := 0;
	G0, G1, G2, G3 : con iota;
	state := G0;
	bytes := array [3] of int;

	while (len str < n) {
		for (i := nbytes + codeix; i < len b && codeix < codelen; i++)
			bytes[codeix++]= int b[i];

		if (codeix != codelen)
			break;

		case state {
		G0 =>
			case bytes[0] {
			0 to 16r7f =>
				str[len str] = bytes[0];
			G1PAGE0 to G1PAGE0+G1NPAGES =>
				state = G1;
				codelen = 2;
				continue;
			SS2 =>
				state = G2;
				codelen = 2;
				continue;
			SS3 =>
				state = G3;
				codelen = 3;
				continue;
			* =>
				str[len str] = BADCHAR;
			}
		G1 =>
			# double byte encoding
			page := bytes[0] - G1PAGE0;
			char := bytes[1] - G1CHAR0;
			str[len str] = g1map[(page * G1PAGESZ) + char];
		G2 =>
			# single byte encoding (byte 0 == SS2)
			char := bytes[1] - G2CHAR0;
			if (char < 0 || char >= len g2map)
				char = BADCHAR;
			else
				char = g2map[char];
			str[len str] = char;
		G3 =>
			# double byte encoding (byte 0 == SS3)
			page := bytes[1] - G3PAGE0;
			char := bytes[2] - G3CHAR0;
			if (page < 0 || page >= G3NPAGES) {
				# first byte is wrong - backup
				i--;
				str[len str] = BADCHAR;
			} else if (char >= G3PAGESZ)
				str[len str] = BADCHAR;
			else
				str[len str] = g3map[(page * G3PAGESZ)+char];
		}

		state = G0;
		nbytes = i;
		codelen = 1;
		codeix = 0;
	}
	return (nil, str, nbytes);
}