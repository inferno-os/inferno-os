implement Btos;

# encoding details
# (Traditional) Shift-JIS
#
# 00..1f	control characters
# 20		space
# 21..7f	JIS X 0201:1976/1997 roman (see notes)
# 80		undefined
# 81..9f	lead byte of JIS X 0208-1983 or JIS X 0202:1990/1997
# a0		undefined
# a1..df	JIS X 0201:1976/1997 katakana
# e0..ea	lead byte of JIS X 0208-1983 or JIS X 0202:1990/1997
# eb..ff	undefined
#
# CP932 (windows-31J)
#
# this encoding scheme extends Shift-JIS in the following way
#
# eb..ec	undefined (marked as lead bytes - see notes below)
# ed..ee	lead byte of NEC-selected IBM extended characters
# ef		undefined (marked as lead byte - see notes below)
# f0..f9	lead byte of User defined GAIJI (see note below)
# fa..fc	lead byte of IBM extended characters
# fd..ff	undefined
#
#
# Notes
#
# JISX 0201:1976/1997 roman
#	this is the same as ASCII but with 0x5c (ASCII code for '\')
#	representing the Yen currency symbol '¥' (U+00a5)
#	This mapping is contentious, some conversion packages implent it
#	others do not.
#	The mapping files from The Unicode Consortium show cp932 mapping
#	plain ascii in the range 00..7f whereas shift-jis maps 16r5c ('\') to the yen
#	symbol (¥) and 16r7e ('~') to overline (¯)
#
# CP932 double-byte character codes:
#
# eb-ec, ef, f0-f9:
# 	Marked as DBCS LEAD BYTEs in the unicode mapping data
#	obtained from:
#		https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/WINDOWS/CP932.TXT
#
# 	but there are no defined mappings for codes in this range.
# 	It is not clear whether or not an implementation should
# 	consume one or two bytes before emitting an error char.
#

include "sys.m";
include "convcs.m";

sys : Sys;

MAXINT : con 16r7fffffff;
BADCHAR : con 16rFFFD;

KANAPAGES : con 1;
KANAPAGESZ : con 63;
KANACHAR0 : con 16ra1;

CP932PAGES : con 45;		# 81..84, 87..9f, e0..ea, ed..ee, fa..fc
CP932PAGESZ : con 189;		# 40..fc (including 7f)
CP932CHAR0 : con 16r40;


shiftjis := 0;
page0 := array [256] of { * => BADCHAR };
cp932 : string;
dbcsoff := array [256] of { * => -1 };

init(arg : string) : string
{
	sys = load Sys Sys->PATH;
	shiftjis = arg == "shiftjis";

	(error, kana) := getmap("/lib/convcs/jisx0201kana", KANAPAGESZ, KANAPAGES);
	if (error != nil)
		return error;

	(error, cp932) = getmap("/lib/convcs/cp932", CP932PAGESZ, CP932PAGES);
	if (error != nil)
		return error;

	# jisx0201kana is mapped into 16rA1..16rDF
	for (i := 0; i < KANAPAGESZ; i++)
		page0[i + KANACHAR0] = kana[i];

	# 00..7f same as ascii in cp932
	for (i = 0; i <= 16r7f; i++)
		page0[i] = i;
	if (shiftjis) {
		# shift-jis uses JIS X 0201 for the ASCII range
		# this is the same as ASCII apart from
		# 16r5c ('\') maps to yen symbol (¥) and 16r7e ('~') maps to overline (¯)
		page0['\\'] = '¥';
		page0['~'] = '¯';
	}

	# pre-calculate DBCS page numbers to mapping file page numbers
	# and mark codes in page0 that are DBCS lead bytes
	pnum := 0;
	for (i = 16r81; i <= 16r84; i++){
		page0[i] = -1;
		dbcsoff[i] = pnum++;
	}
	for (i = 16r87; i <= 16r9f; i++){
		page0[i] = -1;
		dbcsoff[i] = pnum++;
	}
	for (i = 16re0; i <= 16rea; i++) {
		page0[i] = -1;
		dbcsoff[i] = pnum++;
	}
	if (!shiftjis) {
		# add in cp932 extensions
		for (i = 16red; i <= 16ree; i++) {
			page0[i] = -1;
			dbcsoff[i] = pnum++;
		}
		for (i = 16rfa; i <= 16rfc; i++) {
			page0[i] = -1;
			dbcsoff[i] = pnum++;
		}
	}
	return nil;
}

btos(nil : Convcs->State, b : array of byte, n : int) : (Convcs->State, string, int)
{
	nbytes := 0;
	str := "";

	if (n == -1)
		n = MAXINT;

	for (i := 0; i < len b && len str < n; i++) {
		b1 := int b[i];
		ch := page0[b1];
		if (ch != -1) {
			str[len str] = ch;
			nbytes++;
			continue;
		}
		# DBCS
		i++;
		if (i >= len b)
			break;
		pnum := dbcsoff[b1];
		ix := (int b[i]) - CP932CHAR0;
		if (pnum == -1 || ix < 0 || ix >= CP932PAGESZ)
			str[len str] = BADCHAR;
		else
			str[len str] = cp932[(pnum * CP932PAGESZ)+ix];
		nbytes += 2;
	}
	return (nil, str, nbytes);
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
