implement Raw2Iaf;

include "sys.m";
include "draw.m";

sys:	Sys;
FD:	import sys;
stderr:	ref FD;

rateK:	con "rate";
rateV:	string = "44100";
chanK:	con "chans";
chanV:	string = "2";
bitsK:	con "bits";
bitsV:	string = "16";
encK:	con "enc";
encV:	string = "pcm";

progV:	string;
inV:	string = nil;
outV:	string = nil;
inf:	ref FD;
outf:	ref FD;

pad	:= array[] of { "  ", " ", "", "   " };

Raw2Iaf: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(stderr, "usage: %s -8124 -ms -bw -aup -o out in\n", progV);
	exit;
}

options(s: string)
{
	for (i := 0; i < len s; i++) {
		case s[i] {
		'8' =>	rateV = "8000";
		'1' =>	rateV = "11025";
		'2' =>	rateV = "22050";
		'4' =>	rateV = "44100";
		'm' =>	chanV = "1";
		's' =>	chanV = "2";
		'b' =>	bitsV = "8";
		'w' =>	bitsV = "16";
		'a' =>	encV = "alaw";
		'u' =>	encV = "ulaw";
		'p' =>	encV = "pcm";
		* =>	usage();
		}
	}
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	progV = hd argv;
	v := tl argv;

	while (v != nil) {
		a := hd v;
		v = tl v;
		if (len a == 0)
			continue;
		if (a[0] == '-') {
			if (len a == 1) {
				if (inV == nil)
					inV = "-";
				else
					usage();
			}
			else if (a[1] == 'o') {
				if (outV != nil)
					usage();
				if (len a > 2)
					outV = a[2:len a];
				else if (v == nil)
					usage();
				else {
					outV = hd v;
					v = tl v;
				}
			}
			else
				options(a[1:len a]);
		}
		else if (inV == nil)
			inV = a;
		else
			usage();
	}
	if (inV == nil || inV == "-")
		inf = sys->fildes(0);
	else {
		inf = sys->open(inV, Sys->OREAD);
		if (inf == nil) {
			sys->fprint(stderr, "%s: could not open %s: %r\n", progV, inV);
			exit;
		}
	}
	if (outV == nil || outV == "-")
		outf = sys->fildes(1);
	else {
		outf = sys->create(outV, Sys->OWRITE, 8r666);
		if (outf == nil) {
			sys->fprint(stderr, "%s: could not create %s: %r\n", progV, outV);
			exit;
		}
	}
	s := rateK + "\t" + rateV + "\n"
		+  chanK + "\t" + chanV + "\n"
		+  bitsK + "\t" + bitsV + "\n"
		+  encK + "\t" + encV;
	sys->fprint(outf, "%s%s\n\n", s, pad[len s % 4]);
	if (sys->stream(inf, outf, Sys->ATOMICIO) < 0)
		sys->fprint(stderr, "%s: data copy error: %r\n", progV);
}
