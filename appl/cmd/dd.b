implement dd;

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;

include "draw.m";

dd: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

BIG:	con 2147483647;
LCASE,
UCASE,
SWAB,
NERR	,
SYNC	:	con (1<<iota);

NULL,
CNULL,
EBCDIC,
IBM,
ASCII,
BLOCK,
UNBLOCK:	con iota;

cflag:		int;
ctype:	int;

fflag:		int;
arg:		string;
ifile:		string;
ofile:		string;
ibuf:		array of byte;
obuf:		array of byte;
op:		int;
skip:		int;
oseekn:	int;
iseekn:	int;
count:	int;
files:=	1;
ibs:=		512;
obs:=		512;
bs:		int;
cbs:		int;
ibc:		int;
obc:		int;
cbc:		int;
nifr:		int;
nipr:		int;
nofr:		int;
nopr:		int;
ntrunc:	int;
ibf:		ref Sys->FD;
obf:		ref Sys->FD;
nspace:	int;

iskey(key:string, s: string): int
{
	return key[0] == '-' && key[1:] ==  s;
}

exits(msg: string)
{
	if(msg == nil)
		exit;

	raise "fail:"+msg;
}

perror(msg: string)
{
	sys->fprint(stderr, "%s: %r\n", msg);
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return;
	stderr = sys->fildes(2);

	ctype = NULL;
	argv = tl argv;
	while(argv != nil) {
		key := hd argv;
		argv = tl argv;
		if(argv == nil){
			sys->fprint(stderr, "dd: arg %s needs a value\n", key);
			exits("arg");
		}
		arg = hd argv;
		argv = tl argv;
		if(iskey(key, "ibs")) {
			ibs = number(BIG);
			continue;
		}
		if(iskey(key, "obs")) {
			obs = number(BIG);
			continue;
		}
		if(iskey(key, "cbs")) {
			cbs = number(BIG);
			continue;
		}
		if(iskey(key, "bs")) {
			bs = number(BIG);
			continue;
		}
		if(iskey(key, "if")) {
			ifile = arg[0:];
			continue;
		}
		if(iskey(key, "of")) {
			ofile = arg[0:];
			continue;
		}
		if(iskey(key, "skip")) {
			skip = number(BIG);
			continue;
		}
		if(iskey(key, "seek") || iskey(key, "oseek")) {
			oseekn = number(BIG);
			continue;
		}
		if(iskey(key, "iseek")) {
			iseekn = number(BIG);
			continue;
		}
		if(iskey(key, "count")) {
			count = number(BIG);
			continue;
		}
		if(iskey(key, "files")) {
			files = number(BIG);
			continue;
		}
		if(iskey(key, "conv")) {
			do {
				if(arg == nil)
					break;
				if(match(","))
					continue;
				if(match("ebcdic")) {
					ctype = EBCDIC;
					continue;
				}
				if(match("ibm")) {
					ctype = IBM;
					continue;
				}
				if(match("ascii")) {
					ctype = ASCII;
					continue;
				}
				if(match("block")) {
					ctype = BLOCK;
					continue;
				}
				if(match("unblock")) {
					ctype = UNBLOCK;
					continue;
				}
				if(match("lcase")) {
					cflag |= LCASE;
					continue;
				}
				if(match("ucase")) {
					cflag |= UCASE;
					continue;
				}
				if(match("swab")) {
					cflag |= SWAB;
					continue;
				}
				if(match("noerror")) {
					cflag |= NERR;
					continue;
				}
				if(match("sync")) {
					cflag |= SYNC;
					continue;
				}
			} while(1);
			continue;
		}
		sys->fprint(stderr, "dd: bad arg: %s\n", key);
		exits("arg");
	}
	if(ctype == NULL && cflag&(LCASE|UCASE))
		ctype = CNULL;
	if(ifile != nil)
		ibf = sys->open(ifile, Sys->OREAD);
	else
		ibf = sys->fildes(sys->dup(0, -1));

	if(ibf == nil) {
		sys->fprint(stderr, "dd: open %s: %r\n", ifile);
		exits("open");
	}

	if(ofile != nil){
		obf = sys->create(ofile, Sys->OWRITE, 8r664);
		if(obf == nil) {
			sys->fprint(stderr, "dd: create %s: %r\n", ofile);
			exits("create");
		}
	}else{
		obf = sys->fildes(sys->dup(1, -1));
		if(obf == nil) {
			sys->fprint(stderr, "dd: can't dup file descriptor: %r\n");
			exits("dup");
		}
	}
	if(bs)
		ibs = obs = bs;
	if(ibs == obs && ctype == NULL)
		fflag++;
	if(ibs == 0 || obs == 0) {
		sys->fprint(stderr, "dd: counts: cannot be zero\n");
		exits("counts");
	}
	ibuf = array[ibs] of byte;
	obuf = array[obs] of byte;

	if(fflag)
		obuf = ibuf;

	sys->seek(obf, big obs*big oseekn, Sys->SEEKRELA);
	sys->seek(ibf, big ibs*big iseekn,  Sys->SEEKRELA);
	while(skip) {
		sys->read(ibf, ibuf, ibs);
		skip--;
	}

	ibc = 0;
	obc = 0;
	cbc = 0;
	op = 0;
	ip := 0;
	do {
		if(ibc-- == 0) {
			ibc = 0;
			if(count==0 || nifr+nipr!=count) {
				if(cflag&(NERR|SYNC))
					for(ip=0; ip < len ibuf; ip++)
						ibuf[ip] = byte 0;
				ibc = sys->read(ibf, ibuf, ibs);
			}
			if(ibc == -1) {
				perror("read");
				if((cflag&NERR) == 0) {
					flsh();
					term();
				}
				ibc = 0;
				for(c:=0; c<ibs; c++)
					if(ibuf[c] != byte 0)
						ibc = c;
				stats();
			}
			if(ibc == 0 && --files<=0) {
				flsh();
				term();
			}
			if(ibc != ibs) {
				nipr++;
				if(cflag&SYNC)
					ibc = ibs;
			} else
				nifr++;
			ip = 0;
			c := (ibc>>1) & ~1;
			if(cflag&SWAB && c) do {
				a := ibuf[ip++];
				ibuf[ip-1] = ibuf[ip];
				ibuf[ip++] = a;
			} while(--c);
			if(fflag) {
				obc = ibc;
				flsh();
				ibc = 0;
			}
			continue;
		}
		c := 0;
		c |= int ibuf[ip++];
		c &= 8r377;
		conv(c);
	} while(1);
}

conv(c: int)
{
	case ctype {
	NULL => null(c);
	CNULL => cnull(c);
	EBCDIC => ebcdic(c);
	IBM => ibm(c);
	ASCII => ascii(c);
	BLOCK => block(c);
	UNBLOCK => unblock(c);
	}
}

flsh()
{
	if(obc) {
		if(obc == obs)
			nofr++;
		else
			nopr++;
		c := sys->write(obf, obuf, obc);
		if(c != obc) {
			perror("write");
			term();
		}
		obc = 0;
	}
}

match(s: string): int
{
	if(len s > len arg)
		return 0;
	if(arg[:len s] == s) {
		arg = arg[len s:];
		return 1;
	}
	return 0;
}


number(bignum: int): int
{
	n := 0;
	i := 0;
	while(i < len arg && arg[i] >= '0' && arg[i] <= '9')
		n = n*10 + arg[i++] - '0';
	for(;i<len arg; i++) case(arg[i]) {
		'k' =>
			n *= 1024;
		'b' =>
			n *= 512;
		'x' =>
			arg = arg[i:];
			n *= number(BIG);
	}
	if(n>=bignum || n<0) {
		sys->fprint(stderr, "dd: argument out of range\n");
		exits("range");
	}
	return n;
}

cnull(cc: int)
{
	c := cc;
	if((cflag&UCASE) && c>='a' && c<='z')
		c += 'A'-'a';
	if((cflag&LCASE) && c>='A' && c<='Z')
		c += 'a'-'A';
	null(c);
}

null(c: int)
{
	obuf[op++] = byte c;
	if(++obc >= obs) {
		flsh();
		op = 0;
	}
}

ascii(cc: int)
{
	c := etoa[cc];
	if(cbs == 0) {
		cnull(int c);
		return;
	}
	if(c == byte ' ')
		nspace++;
	else {
		while(nspace > 0) {
			null(' ');
			nspace--;
		}
		cnull(int c);
	}

	if(++cbc >= cbs) {
		null('\n');
		cbc = 0;
		nspace = 0;
	}
}

unblock(cc: int)
{
	c := cc & 8r377;
	if(cbs == 0) {
		cnull(c);
		return;
	}
	if(c == ' ')
		nspace++;
	else {
		while(nspace > 0) {
			null(' ');
			nspace--;
		}
		cnull(c);
	}

	if(++cbc >= cbs) {
		null('\n');
		cbc = 0;
		nspace = 0;
	}
}

ebcdic(cc: int)
{

	c := cc;
	if(cflag&UCASE && c>='a' && c<='z')
		c += 'A'-'a';
	if(cflag&LCASE && c>='A' && c<='Z')
		c += 'a'-'A';
	c = int atoe[c];
	if(cbs == 0) {
		null(c);
		return;
	}
	if(cc == '\n') {
		while(cbc < cbs) {
			null(int atoe[' ']);
			cbc++;
		}
		cbc = 0;
		return;
	}
	if(cbc == cbs)
		ntrunc++;
	cbc++;
	if(cbc <= cbs)
		null(c);
}

ibm(cc: int)
{
	c := cc;
	if(cflag&UCASE && c>='a' && c<='z')
		c += 'A'-'a';
	if(cflag&LCASE && c>='A' && c<='Z')
		c += 'a'-'A';
	c = int atoibm[c] & 8r377;
	if(cbs == 0) {
		null(c);
		return;
	}
	if(cc == '\n') {
		while(cbc < cbs) {
			null(int atoibm[' ']);
			cbc++;
		}
		cbc = 0;
		return;
	}
	if(cbc == cbs)
		ntrunc++;
	cbc++;
	if(cbc <= cbs)
		null(c);
}

block(cc: int)
{
	c := cc;
	if(cflag&UCASE && c>='a' && c<='z')
		c += 'A'-'a';
	if(cflag&LCASE && c>='A' && c<='Z')
		c += 'a'-'A';
	c &= 8r377;
	if(cbs == 0) {
		null(c);
		return;
	}
	if(cc == '\n') {
		while(cbc < cbs) {
			null(' ');
			cbc++;
		}
		cbc = 0;
		return;
	}
	if(cbc == cbs)
		ntrunc++;
	cbc++;
	if(cbc <= cbs)
		null(c);
}

term()
{
	stats();
	exits(nil);
}

stats()
{
	sys->fprint(stderr, "%ud+%ud records in\n", nifr, nipr);
	sys->fprint(stderr, "%ud+%ud records out\n", nofr, nopr);
	if(ntrunc)
		sys->fprint(stderr, "%ud truncated records\n", ntrunc);
}

etoa := array[] of
{
	byte 8r000,byte 8r001,byte 8r002,byte 8r003,byte 8r234,byte 8r011,byte 8r206,byte 8r177,
	byte 8r227,byte 8r215,byte 8r216,byte 8r013,byte 8r014,byte 8r015,byte 8r016,byte 8r017,
	byte 8r020,byte 8r021,byte 8r022,byte 8r023,byte 8r235,byte 8r205,byte 8r010,byte 8r207,
	byte 8r030,byte 8r031,byte 8r222,byte 8r217,byte 8r034,byte 8r035,byte 8r036,byte 8r037,
	byte 8r200,byte 8r201,byte 8r202,byte 8r203,byte 8r204,byte 8r012,byte 8r027,byte 8r033,
	byte 8r210,byte 8r211,byte 8r212,byte 8r213,byte 8r214,byte 8r005,byte 8r006,byte 8r007,
	byte 8r220,byte 8r221,byte 8r026,byte 8r223,byte 8r224,byte 8r225,byte 8r226,byte 8r004,
	byte 8r230,byte 8r231,byte 8r232,byte 8r233,byte 8r024,byte 8r025,byte 8r236,byte 8r032,
	byte 8r040,byte 8r240,byte 8r241,byte 8r242,byte 8r243,byte 8r244,byte 8r245,byte 8r246,
	byte 8r247,byte 8r250,byte 8r133,byte 8r056,byte 8r074,byte 8r050,byte 8r053,byte 8r041,
	byte 8r046,byte 8r251,byte 8r252,byte 8r253,byte 8r254,byte 8r255,byte 8r256,byte 8r257,
	byte 8r260,byte 8r261,byte 8r135,byte 8r044,byte 8r052,byte 8r051,byte 8r073,byte 8r136,
	byte 8r055,byte 8r057,byte 8r262,byte 8r263,byte 8r264,byte 8r265,byte 8r266,byte 8r267,
	byte 8r270,byte 8r271,byte 8r174,byte 8r054,byte 8r045,byte 8r137,byte 8r076,byte 8r077,
	byte 8r272,byte 8r273,byte 8r274,byte 8r275,byte 8r276,byte 8r277,byte 8r300,byte 8r301,
	byte 8r302,byte 8r140,byte 8r072,byte 8r043,byte 8r100,byte 8r047,byte 8r075,byte 8r042,
	byte 8r303,byte 8r141,byte 8r142,byte 8r143,byte 8r144,byte 8r145,byte 8r146,byte 8r147,
	byte 8r150,byte 8r151,byte 8r304,byte 8r305,byte 8r306,byte 8r307,byte 8r310,byte 8r311,
	byte 8r312,byte 8r152,byte 8r153,byte 8r154,byte 8r155,byte 8r156,byte 8r157,byte 8r160,
	byte 8r161,byte 8r162,byte 8r313,byte 8r314,byte 8r315,byte 8r316,byte 8r317,byte 8r320,
	byte 8r321,byte 8r176,byte 8r163,byte 8r164,byte 8r165,byte 8r166,byte 8r167,byte 8r170,
	byte 8r171,byte 8r172,byte 8r322,byte 8r323,byte 8r324,byte 8r325,byte 8r326,byte 8r327,
	byte 8r330,byte 8r331,byte 8r332,byte 8r333,byte 8r334,byte 8r335,byte 8r336,byte 8r337,
	byte 8r340,byte 8r341,byte 8r342,byte 8r343,byte 8r344,byte 8r345,byte 8r346,byte 8r347,
	byte 8r173,byte 8r101,byte 8r102,byte 8r103,byte 8r104,byte 8r105,byte 8r106,byte 8r107,
	byte 8r110,byte 8r111,byte 8r350,byte 8r351,byte 8r352,byte 8r353,byte 8r354,byte 8r355,
	byte 8r175,byte 8r112,byte 8r113,byte 8r114,byte 8r115,byte 8r116,byte 8r117,byte 8r120,
	byte 8r121,byte 8r122,byte 8r356,byte 8r357,byte 8r360,byte 8r361,byte 8r362,byte 8r363,
	byte 8r134,byte 8r237,byte 8r123,byte 8r124,byte 8r125,byte 8r126,byte 8r127,byte 8r130,
	byte 8r131,byte 8r132,byte 8r364,byte 8r365,byte 8r366,byte 8r367,byte 8r370,byte 8r371,
	byte 8r060,byte 8r061,byte 8r062,byte 8r063,byte 8r064,byte 8r065,byte 8r066,byte 8r067,
	byte 8r070,byte 8r071,byte 8r372,byte 8r373,byte 8r374,byte 8r375,byte 8r376,byte 8r377,
};
atoe := array[] of
{
	byte 8r000,byte 8r001,byte 8r002,byte 8r003,byte 8r067,byte 8r055,byte 8r056,byte 8r057,
	byte 8r026,byte 8r005,byte 8r045,byte 8r013,byte 8r014,byte 8r015,byte 8r016,byte 8r017,
	byte 8r020,byte 8r021,byte 8r022,byte 8r023,byte 8r074,byte 8r075,byte 8r062,byte 8r046,
	byte 8r030,byte 8r031,byte 8r077,byte 8r047,byte 8r034,byte 8r035,byte 8r036,byte 8r037,
	byte 8r100,byte 8r117,byte 8r177,byte 8r173,byte 8r133,byte 8r154,byte 8r120,byte 8r175,
	byte 8r115,byte 8r135,byte 8r134,byte 8r116,byte 8r153,byte 8r140,byte 8r113,byte 8r141,
	byte 8r360,byte 8r361,byte 8r362,byte 8r363,byte 8r364,byte 8r365,byte 8r366,byte 8r367,
	byte 8r370,byte 8r371,byte 8r172,byte 8r136,byte 8r114,byte 8r176,byte 8r156,byte 8r157,
	byte 8r174,byte 8r301,byte 8r302,byte 8r303,byte 8r304,byte 8r305,byte 8r306,byte 8r307,
	byte 8r310,byte 8r311,byte 8r321,byte 8r322,byte 8r323,byte 8r324,byte 8r325,byte 8r326,
	byte 8r327,byte 8r330,byte 8r331,byte 8r342,byte 8r343,byte 8r344,byte 8r345,byte 8r346,
	byte 8r347,byte 8r350,byte 8r351,byte 8r112,byte 8r340,byte 8r132,byte 8r137,byte 8r155,
	byte 8r171,byte 8r201,byte 8r202,byte 8r203,byte 8r204,byte 8r205,byte 8r206,byte 8r207,
	byte 8r210,byte 8r211,byte 8r221,byte 8r222,byte 8r223,byte 8r224,byte 8r225,byte 8r226,
	byte 8r227,byte 8r230,byte 8r231,byte 8r242,byte 8r243,byte 8r244,byte 8r245,byte 8r246,
	byte 8r247,byte 8r250,byte 8r251,byte 8r300,byte 8r152,byte 8r320,byte 8r241,byte 8r007,
	byte 8r040,byte 8r041,byte 8r042,byte 8r043,byte 8r044,byte 8r025,byte 8r006,byte 8r027,
	byte 8r050,byte 8r051,byte 8r052,byte 8r053,byte 8r054,byte 8r011,byte 8r012,byte 8r033,
	byte 8r060,byte 8r061,byte 8r032,byte 8r063,byte 8r064,byte 8r065,byte 8r066,byte 8r010,
	byte 8r070,byte 8r071,byte 8r072,byte 8r073,byte 8r004,byte 8r024,byte 8r076,byte 8r341,
	byte 8r101,byte 8r102,byte 8r103,byte 8r104,byte 8r105,byte 8r106,byte 8r107,byte 8r110,
	byte 8r111,byte 8r121,byte 8r122,byte 8r123,byte 8r124,byte 8r125,byte 8r126,byte 8r127,
	byte 8r130,byte 8r131,byte 8r142,byte 8r143,byte 8r144,byte 8r145,byte 8r146,byte 8r147,
	byte 8r150,byte 8r151,byte 8r160,byte 8r161,byte 8r162,byte 8r163,byte 8r164,byte 8r165,
	byte 8r166,byte 8r167,byte 8r170,byte 8r200,byte 8r212,byte 8r213,byte 8r214,byte 8r215,
	byte 8r216,byte 8r217,byte 8r220,byte 8r232,byte 8r233,byte 8r234,byte 8r235,byte 8r236,
	byte 8r237,byte 8r240,byte 8r252,byte 8r253,byte 8r254,byte 8r255,byte 8r256,byte 8r257,
	byte 8r260,byte 8r261,byte 8r262,byte 8r263,byte 8r264,byte 8r265,byte 8r266,byte 8r267,
	byte 8r270,byte 8r271,byte 8r272,byte 8r273,byte 8r274,byte 8r275,byte 8r276,byte 8r277,
	byte 8r312,byte 8r313,byte 8r314,byte 8r315,byte 8r316,byte 8r317,byte 8r332,byte 8r333,
	byte 8r334,byte 8r335,byte 8r336,byte 8r337,byte 8r352,byte 8r353,byte 8r354,byte 8r355,
	byte 8r356,byte 8r357,byte 8r372,byte 8r373,byte 8r374,byte 8r375,byte 8r376,byte 8r377,
};
atoibm := array[] of
{
	byte 8r000,byte 8r001,byte 8r002,byte 8r003,byte 8r067,byte 8r055,byte 8r056,byte 8r057,
	byte 8r026,byte 8r005,byte 8r045,byte 8r013,byte 8r014,byte 8r015,byte 8r016,byte 8r017,
	byte 8r020,byte 8r021,byte 8r022,byte 8r023,byte 8r074,byte 8r075,byte 8r062,byte 8r046,
	byte 8r030,byte 8r031,byte 8r077,byte 8r047,byte 8r034,byte 8r035,byte 8r036,byte 8r037,
	byte 8r100,byte 8r132,byte 8r177,byte 8r173,byte 8r133,byte 8r154,byte 8r120,byte 8r175,
	byte 8r115,byte 8r135,byte 8r134,byte 8r116,byte 8r153,byte 8r140,byte 8r113,byte 8r141,
	byte 8r360,byte 8r361,byte 8r362,byte 8r363,byte 8r364,byte 8r365,byte 8r366,byte 8r367,
	byte 8r370,byte 8r371,byte 8r172,byte 8r136,byte 8r114,byte 8r176,byte 8r156,byte 8r157,
	byte 8r174,byte 8r301,byte 8r302,byte 8r303,byte 8r304,byte 8r305,byte 8r306,byte 8r307,
	byte 8r310,byte 8r311,byte 8r321,byte 8r322,byte 8r323,byte 8r324,byte 8r325,byte 8r326,
	byte 8r327,byte 8r330,byte 8r331,byte 8r342,byte 8r343,byte 8r344,byte 8r345,byte 8r346,
	byte 8r347,byte 8r350,byte 8r351,byte 8r255,byte 8r340,byte 8r275,byte 8r137,byte 8r155,
	byte 8r171,byte 8r201,byte 8r202,byte 8r203,byte 8r204,byte 8r205,byte 8r206,byte 8r207,
	byte 8r210,byte 8r211,byte 8r221,byte 8r222,byte 8r223,byte 8r224,byte 8r225,byte 8r226,
	byte 8r227,byte 8r230,byte 8r231,byte 8r242,byte 8r243,byte 8r244,byte 8r245,byte 8r246,
	byte 8r247,byte 8r250,byte 8r251,byte 8r300,byte 8r117,byte 8r320,byte 8r241,byte 8r007,
	byte 8r040,byte 8r041,byte 8r042,byte 8r043,byte 8r044,byte 8r025,byte 8r006,byte 8r027,
	byte 8r050,byte 8r051,byte 8r052,byte 8r053,byte 8r054,byte 8r011,byte 8r012,byte 8r033,
	byte 8r060,byte 8r061,byte 8r032,byte 8r063,byte 8r064,byte 8r065,byte 8r066,byte 8r010,
	byte 8r070,byte 8r071,byte 8r072,byte 8r073,byte 8r004,byte 8r024,byte 8r076,byte 8r341,
	byte 8r101,byte 8r102,byte 8r103,byte 8r104,byte 8r105,byte 8r106,byte 8r107,byte 8r110,
	byte 8r111,byte 8r121,byte 8r122,byte 8r123,byte 8r124,byte 8r125,byte 8r126,byte 8r127,
	byte 8r130,byte 8r131,byte 8r142,byte 8r143,byte 8r144,byte 8r145,byte 8r146,byte 8r147,
	byte 8r150,byte 8r151,byte 8r160,byte 8r161,byte 8r162,byte 8r163,byte 8r164,byte 8r165,
	byte 8r166,byte 8r167,byte 8r170,byte 8r200,byte 8r212,byte 8r213,byte 8r214,byte 8r215,
	byte 8r216,byte 8r217,byte 8r220,byte 8r232,byte 8r233,byte 8r234,byte 8r235,byte 8r236,
	byte 8r237,byte 8r240,byte 8r252,byte 8r253,byte 8r254,byte 8r255,byte 8r256,byte 8r257,
	byte 8r260,byte 8r261,byte 8r262,byte 8r263,byte 8r264,byte 8r265,byte 8r266,byte 8r267,
	byte 8r270,byte 8r271,byte 8r272,byte 8r273,byte 8r274,byte 8r275,byte 8r276,byte 8r277,
	byte 8r312,byte 8r313,byte 8r314,byte 8r315,byte 8r316,byte 8r317,byte 8r332,byte 8r333,
	byte 8r334,byte 8r335,byte 8r336,byte 8r337,byte 8r352,byte 8r353,byte 8r354,byte 8r355,
	byte 8r356,byte 8r357,byte 8r372,byte 8r373,byte 8r374,byte 8r375,byte 8r376,byte 8r377,
};
