implement genjisx0201kana;

include "sys.m";
include "draw.m";

genjisx0201kana : module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

DATAFILE : con "/lib/convcs/jisx0201kana";

init(nil: ref Draw->Context, nil: list of string)
{
	sys := load Sys Sys->PATH;
	fd := sys->create(DATAFILE, Sys->OWRITE, 8r644);
	if (fd == nil) {
		sys->print("cannot create %s: %r\n", DATAFILE);
		return;
	}

	s := "";
	for (slen := 0; slen < len mapdata; slen ++) {
		(nil, code) := sys->tokenize(mapdata[slen], " \t");
		u := hex2int(hd tl code);
		s[slen] = u;
	}
	buf := array of byte s;
	sys->write(fd, buf, len buf);
}

hex2int(s: string): int
{
	n := 0;
	for (i := 0; i < len s; i++) {
		case s[i] {
		'0' to '9' =>
			n = 16*n + s[i] - '0';
		'A' to 'F' =>
			n = 16*n + s[i] + 10 - 'A';
		'a' to 'f' =>
			n = 16*n + s[i] + 10 - 'a';
		* =>
			return n;
		}
	}
	return n;
}


# data derived from Unicode Consortium "CharmapML" data for EUC-JP
# (G2 charset of EUC-JP is JIS X 0201 Kana)
# the leading code point value is not used, it just appears for convenience
mapdata := array [] of {
		"A1	FF61",
		"A2	FF62",
		"A3	FF63",
		"A4	FF64",
		"A5	FF65",
		"A6	FF66",
		"A7	FF67",
		"A8	FF68",
		"A9	FF69",
		"AA	FF6A",
		"AB	FF6B",
		"AC	FF6C",
		"AD	FF6D",
		"AE	FF6E",
		"AF	FF6F",
		"B0	FF70",
		"B1	FF71",
		"B2	FF72",
		"B3	FF73",
		"B4	FF74",
		"B5	FF75",
		"B6	FF76",
		"B7	FF77",
		"B8	FF78",
		"B9	FF79",
		"BA	FF7A",
		"BB	FF7B",
		"BC	FF7C",
		"BD	FF7D",
		"BE	FF7E",
		"BF	FF7F",
		"C0	FF80",
		"C1	FF81",
		"C2	FF82",
		"C3	FF83",
		"C4	FF84",
		"C5	FF85",
		"C6	FF86",
		"C7	FF87",
		"C8	FF88",
		"C9	FF89",
		"CA	FF8A",
		"CB	FF8B",
		"CC	FF8C",
		"CD	FF8D",
		"CE	FF8E",
		"CF	FF8F",
		"D0	FF90",
		"D1	FF91",
		"D2	FF92",
		"D3	FF93",
		"D4	FF94",
		"D5	FF95",
		"D6	FF96",
		"D7	FF97",
		"D8	FF98",
		"D9	FF99",
		"DA	FF9A",
		"DB	FF9B",
		"DC	FF9C",
		"DD	FF9D",
		"DE	FF9E",
		"DF	FF9F",
};