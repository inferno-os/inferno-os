#
# Editor
#

implement Editor;

include "sys.m";
   sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "regex.m";
	regex: Regex;
	Re: import regex;
include "sh.m";
	sh: Sh;

Editor: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

FNSIZE: con 128;		# file name 
LBSIZE: con 4096;		# max line size 
BLKSIZE: con 4096;		# block size in temp file 
NBLK: con 8191;		# max size of temp file 
ESIZE: con 256;			# max size of reg exp 
GBSIZE: con 256;		# max size of global command 
MAXSUB: con 9;		# max number of sub reg exp 
ESCFLG: con 16rFFFF;	# escape Rune - user defined code 
EOF: con -1;
BytesPerRune: con 2;
RunesPerBlock: con BLKSIZE / BytesPerRune;

APPEND_GETTTY, APPEND_GETSUB, APPEND_GETCOPY, APPEND_GETFILE: con iota;

Subexp: adt {
	rsp, rep: int;
};

Globp: adt {
	s: string;
	isnil: int;
};

addr1: int;
addr2: int;
anymarks: int;
col: int;
count: int;
dol: int;
dot: int;
fchange: int;
file: string;
genbuf := array[LBSIZE] of int;
given: int;
globp: Globp;
iblock: int;
ichanged: int;
io: ref Sys->FD;
iobuf: ref Iobuf;
lastc: int;
line := array [70] of byte;
linebp := -1;
linebuf := array [LBSIZE] of int;
listf: int;
listn: int;
loc1: int;
loc2: int;
names := array [26] of int;
oblock: int;
oflag: int;
pattern: Re;
peekc: int;
pflag: int;
rescuing: int;
rhsbuf := array [LBSIZE/2] of int;
savedfile: string;
subnewa: int;
subolda: int;
subexp: array of Subexp;
tfname: string;
tline: int;
waiting: int;
wrapp: int;
zero: array of int;
drawctxt: ref Draw->Context;

Q: con "";
T: con "TMP";
WRERR: con "WRITE ERROR";
bpagesize := 20;
hex: con "0123456789abcdef";
linp: int;
nlall := 128;
tfile: ref Sys->FD;
vflag := 1;

debug(s: string)
{
	sys->print("%s", s);
}

init(ctxt: ref Draw->Context, args: list of string)
{
	drawctxt = ctxt;

	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->fprint(sys->fildes(2), "can't load %s\n", Bufio->PATH);
		return;
	}
	regex = load Regex Regex->PATH;
	if (regex == nil) {
		sys->fprint(sys->fildes(2), "can't load %s\n", Regex->PATH);
		return;
	}

#	notify(notifyf);

	if (args != nil)
		args = tl args;

	if (args != nil && hd args == "-o") {
		oflag = 1;
		vflag = 0;
		args = tl args;
	}

	if (args != nil && hd args == "-") {
		vflag = 0;
		args = tl args;
	}

	if (oflag) {
		savedfile = "/fd/1";
		globp = ("a", 0);
	} else if (args != nil) {
		savedfile = hd args;
		globp = ("r", 0);
	}
	else
		globp = (nil, 1);
	zero = array [nlall + 5] of int;
	tfname = mktemp("/tmp/eXXXXX");
#	debug(sys->sprint("tfname %s\n", tfname));
	_init();
	for(;;){
		{
			commands();
			quit();
		}exception{
		"savej" =>
			;
		}
	}
}

casee(c: int)
{
	setnoaddr();
	if(vflag && fchange) {
		fchange = 0;
		error(Q);
	}
	filename(c);
	_init();
	addr2 = 0;
	caseread();
}

casep()
{
	newline();
	printcom();
}

caseq()
{
	setnoaddr();
	newline();
	quit();
}

caseread()
{
#debug("caseread " + file);
	if((io=sys->open(file, Sys->OREAD)) == nil) {
		lastc = '\n';
		error(file);
	}
	iobuf = bufio->fopen(io, Sys->OREAD);
	setwide();
	squeeze(0);
	c := 0 != dol;
	append(APPEND_GETFILE, addr2);
	exfile(Sys->OREAD);

	fchange = c;
}

commands()
{
	a1: int;
	c, temp: int;
	lastsep: int;

	for(;;) {
		if(pflag) {
			pflag = 0;
			addr1 = addr2 = dot;
			printcom();
		}
		c = '\n';
		for(addr1 = -1;;) {
			lastsep = c;
			a1 = address();
			c = getchr();
			if(c != ',' && c != ';')
				break;
			if(lastsep == ',')
				error(Q);
			if(a1 < 0) {
				a1 = 1;
				if(a1 > dol)
					a1--;
			}
			addr1 = a1;
			if(c == ';')
				dot = a1;
		}
		if(lastsep != '\n' && a1 < 0)
			a1 = dol;
		if((addr2=a1) < 0) {
			given = 0;
			addr2 = dot;	
		} else
			given = 1;
		if(addr1 < 0)
			addr1 = addr2;
#debug(sys->sprint("%d,%d %c\n", addr1, addr2, c));
		case c {
		'a' =>
			add(0);
			continue;

		'b' =>
			nonzero();
			browse();
			continue;

		'c' =>
			nonzero();
			newline();
			rdelete(addr1, addr2);
			append(APPEND_GETTTY, addr1-1);
			continue;

		'd' =>
			nonzero();
			newline();
			rdelete(addr1, addr2);
			continue;

		'E' =>
			fchange = 0;
			c = 'e';
			casee(c);
			continue;

		'e' =>
			casee(c);
			continue;

		'f' =>
			setnoaddr();
			filename(c);
			putst(savedfile);
			continue;

		'g' =>
			global(1);
			continue;

		'i' =>
			add(-1);
			continue;

		'j' =>
			if(!given)
				addr2++;
			newline();
			join();
			continue;

		'k' =>
			nonzero();
			c = getchr();
			if(c < 'a' || c > 'z')
				error(Q);
			newline();
			names[c-'a'] = zero[addr2] & ~16r1;
			anymarks |= 16r1;
			continue;

		'm' =>
			move(0);
			continue;

		'n' =>
			listn++;
			newline();
			printcom();
			continue;

		'\n' =>
			if(a1 < 0) {
				a1 = dot+1;
				addr2 = a1;
				addr1 = a1;
			}
			if(lastsep==';')
				addr1 = a1;
			printcom();
			continue;

		'l' =>
			listf++;
			casep();
			continue;

		'p' or 'P' =>
			casep();
			continue;

		'Q' =>
			fchange = 0;
			caseq();
			continue;

		'q' =>
			caseq();
			continue;

		'r' =>
			filename(c);
			caseread();
			continue;

		's' =>
			nonzero();
			substitute(!globp.isnil);
			continue;

		't' =>
			move(1);
			continue;

		'u' =>
			nonzero();
			newline();
			if((zero[addr2]&~8r01) != subnewa)
				error(Q);
			zero[addr2] = subolda;
			dot = addr2;
			continue;

		'v' =>
			global(0);
			continue;

		'W' or 'w' =>
			if (c == 'W')
				wrapp++;
			setwide();
			squeeze(dol>0);
			temp = getchr();
			if(temp != 'q' && temp != 'Q') {
				peekc = temp;
				temp = 0;
			}
			filename(c);
			if(!wrapp ||
			  ((io = sys->open(file, Sys->OWRITE)) == nil) ||
			  ((sys->seek(io, big 0, Sys->SEEKEND)) < big 0))
				if((io = sys->create(file, Sys->OWRITE, 8r0666)) == nil)
					error(file);
			iobuf = bufio->fopen(io, Sys->OWRITE);
			wrapp = 0;
			if(dol > 0)
				putfile();
			exfile(Sys->OWRITE);
			if(addr1<=1 && addr2==dol)
				fchange = 0;
			if(temp == 'Q')
				fchange = 0;
			if(temp)
				quit();
			continue;

		'=' =>
			setwide();
			squeeze(0);
			newline();
			count = addr2 - 0;
			putd();
			putchr('\n');
			continue;

		'!' =>
			callunix();
			continue;

		EOF =>
			return;

		}
		error(Q);
	}
}

printcom()
{
	a1: int;

	nonzero();
	a1 = addr1;
	do {
		if(listn) {
			count = a1-0;
			putd();
			putchr('\t');
		}
		putshst(getline(zero[a1++]));
	} while(a1 <= addr2);
	dot = addr2;
	listf = 0;
	listn = 0;
	pflag = 0;
}


address(): int
{
	sign, a, opcnt, nextopand, b, c: int;

	nextopand = -1;
	sign = 1;
	opcnt = 0;
	a = dot;
	do {
		do {
			c = getchr();
		} while(c == ' ' || c == '\t');
		if(c >= '0' && c <= '9') {
			peekc = c;
			if(!opcnt)
				a = 0;
			a += sign*getnum();
		} else
		case c {
		'$' or '.' =>
			if (c == '$')
				a = dol;
			if(opcnt)
				error(Q);

		'\'' =>
			c = getchr();
			if(opcnt || c < 'a' || c > 'z')
				error(Q);
			a = 0;
			do {
				a++;
			} while(a <= dol && names[c-'a'] != (zero[a] & ~8r01));

		'?' or '/' =>
			if (c == '?')
				sign = -sign;
			compile(c);
			b = a;
			for(;;) {
				a += sign;
				if(a <= 0)
					a = dol;
				if(a > dol)
					a = 0;
				if(match(a))
					break;
				if(a == b)
					error(Q);
			}
			break;

		* =>
			if(nextopand == opcnt) {
				a += sign;
				if(a < 0 || dol < a)
					continue;       # error(Q); 
			}
			if(c != '+' && c != '-' && c != '^') {
				peekc = c;
				if(opcnt == 0)
					a = -1;
				return a;
			}
			sign = 1;
			if(c != '+')
				sign = -sign;
			nextopand = ++opcnt;
			continue;
		}
		sign = 1;
		opcnt++;
	} while(0 <= a && a <= dol);
	error(Q);
	return -1;
}

getnum(): int
{
	r, c: int;

	r = 0;
	for(;;) {
		c = getchr();
		if(c < '0' || c > '9')
			break;
		r = r*10 + (c-'0');
	}
	peekc = c;
	return r;
}

setwide()
{
	if(!given) {
		addr1 = 0 + (dol>0);
		addr2 = dol;
	}
}

setnoaddr()
{
	if(given)
		error(Q);
}

nonzero()
{
	squeeze(1);
}

squeeze(i: int)
{
	if(addr1 < 0+i || addr2 > dol || addr1 > addr2)
		error(Q);
}

newline()
{
	c: int;

	c = getchr();
	if(c == '\n' || c == EOF)
		return;
	if(c == 'p' || c == 'l' || c == 'n') {
		pflag++;
		if(c == 'l')
			listf++;
		else
		if(c == 'n')
			listn++;
		c = getchr();
		if(c == '\n')
			return;
	}
	error(Q);
}

filename(comm: int)
{
	rune: int;
	c: int;

	count = 0;
	c = getchr();
	if(c == '\n' || c == EOF) {
		if(savedfile == nil && comm != 'f')
			error(Q);
		file = savedfile;
		return;
	}
	if(c != ' ')
		error(Q);
	while((c=getchr()) == ' ')
		;
	if(c == '\n')
		error(Q);
	file = nil;
	do {
		if(c == ' ' || c == EOF)
			error(Q);
		rune = c;
		file[len file] = c;
	} while((c=getchr()) != '\n');
	if(savedfile == nil || comm == 'e' || comm == 'f')
		savedfile = file;
}

exfile(om: int)
{

	if(om == Sys->OWRITE)
		if(iobuf.flush() < 0)
			error(Q);
	iobuf.close();
	iobuf = nil;
	io = nil;
	if(vflag) {
		putd();
		putchr('\n');
	}
}

error1(s: string)
{
	c: int;

	wrapp = 0;
	listf = 0;
	listn = 0;
	count = 0;
	sys->seek(sys->fildes(0), big 0, Sys->SEEKEND);	# what does this do?
	pflag = 0;
	if(!globp.isnil)
		lastc = '\n';
	globp = (nil, 1);
	peekc = lastc;
	if(lastc)
		for(;;) {
			c = getchr();
			if(c == '\n' || c == EOF)
				break;
		}
	if(io != nil)
		io = nil;
	putchr('?');
	putst(s);
}

error(s: string)
{
	error1(s);
	raise "savej";
}

rescue()
{
	rescuing = 1;
	if(dol > 0) {
		addr1 = 0+1;
		addr2 = dol;
		io = sys->create("ed.hup", Sys->OWRITE, 8r0666);
		if(io != nil){
			iobuf = bufio->fopen(io, Sys->OWRITE);
			putfile();
		}
	}
	fchange = 0;
	quit();
}

# void
# notifyf(void *a, char *s)
# {
# 	if(strcmp(s, "interrupt") == 0){
# 		if(rescuing || waiting)
# 			noted(NCONT);
# 		putchr(L'\n');
# 		lastc = '\n';
# 		error1(Q);
# 		notejmp(a, savej, 0);
# 	}
# 	if(strcmp(s, "hangup") == 0){
# 		if(rescuing)
# 			noted(NDFLT);
# 		rescue();
# 	}
# 	fprint(2, "ed: note: %s\n", s);
# 	abort();
# }

getchr(): int
{
	s := array [Sys->UTFmax] of byte;
	i: int;
	r: int;
	status: int;
	if(lastc = peekc) {
		peekc = 0;
#debug(sys->sprint("getchr: peekc %c\n", lastc));
		return lastc;
	}
	if(!globp.isnil) {
		if (globp.s != nil) {
			lastc = globp.s[0];
			globp.s = globp.s[1:];
#debug(sys->sprint("getchr: globp %c remaining %d\n", lastc, len globp.s));
			return lastc;
		}
		globp = (nil, 1);
#debug(sys->sprint("getchr: globp end\n"));
		return EOF;
	}
#debug("globp nil\n");
	for(i=0;;) {
		if(sys->read(sys->fildes(0), s[i:], 1) <= 0)
			return lastc = EOF;
		i++;
		(r, nil, status) = sys->byte2char(s, 0);
		if (status > 0)
			break;
		
	}
	lastc = r;
	return lastc;
}

gety(): int
{
	c: int;
	gf: int;
	p: int;

	p = 0;
	gf = !globp.isnil;
	for(;;) {
		c = getchr();
		if(c == '\n') {
			linebuf[p] = 0;
			return 0;
		}
		if(c == EOF) {
			if(gf)
				peekc = c;
			return c;
		}
		if(c == 0)
			continue;
		linebuf[p++] = c;
		if(p >= len linebuf)
			error(Q);
	}
	return 0;
}

gettty(): int
{
	rc: int;

	rc = gety();
	if(rc)
		return rc;
	if(linebuf[0] == '.' && linebuf[1] == 0)
		return EOF;
	return 0;
}

getfile(): int
{
	c: int;
	lp: int;

	lp = 0;
	do {
		c = iobuf.getc();
		if(c < 0) {
			if(lp > 0) {
				putst("'\\n' appended");
				c = '\n';
			} else
				return EOF;
		}
		if(lp >= len linebuf) {
			lastc = '\n';
			error(Q);
		}
		linebuf[lp++] = c;
		count++;
	} while(c != '\n');
	linebuf[lp - 1] = 0;
#debug(sys->sprint("getline read %d\n", lp));
	return 0;
}

putfile()
{
	a1: int;
	lp: int;
	c: int;

	a1 = addr1;
	do {
		lp = getline(zero[a1++]);
		for(;;) {
			count++;
			c = linebuf[lp++];
			if(c == 0) {
				if (iobuf.putc('\n') < 0)
					error(Q);
				break;
			}
			if (iobuf.putc(c) < 0)
				error(Q);
		}
	} while(a1 <= addr2);
	if(iobuf.flush() < 0)
		error(Q);
}

append(f: int, a: int): int
{
	a1, a2, rdot, nline, _tl: int;
	rv: int;

	nline = 0;
	dot = a;
	for (;;) {
		case f {
		APPEND_GETTTY => rv = gettty();
		APPEND_GETSUB => rv = getsub();
		APPEND_GETCOPY => rv = getcopy();
		APPEND_GETFILE => rv = getfile();
		}
		if (rv != 0)
			break;
		if(dol >= nlall) {
			nlall += 512;
			newzero := array [nlall + 5] of int;
			if(newzero == nil) {
				error("MEM?");
				rescue();
			}
			newzero[0:] = zero;
			zero = newzero;
		}
		_tl = putline();
		nline++;
		a1 = ++dol;
		a2 = a1+1;
		rdot = ++dot;
		zero[rdot:] = zero[rdot - 1: a1];
		zero[rdot] = _tl;
	}
#debug(sys->sprint("end of append - dot %d\n", dot));
	return nline;
}

add(i: int)
{
	if(i && (given || dol > 0)) {
		addr1--;
		addr2--;
	}
	squeeze(0);
	newline();
	append(APPEND_GETTTY, addr2);
}

bformat, bnum: int;

browse()
{
	forward, n: int;

	forward = 1;
	peekc = getchr();
	if(peekc != '\n'){
		if(peekc == '-' || peekc == '+') {
			if(peekc == '-')
				forward = 0;
			getchr();
		}
		n = getnum();
		if(n > 0)
			bpagesize = n;
	}
	newline();
	if(pflag) {
		bformat = listf;
		bnum = listn;
	} else {
		listf = bformat;
		listn = bnum;
	}
	if(forward) {
		addr1 = addr2;
		addr2 += bpagesize;
		if(addr2 > dol)
			addr2 = dol;
	} else {
		addr1 = addr2-bpagesize;
		if(addr1 <= 0)
			addr1 = 0+1;
	}
	printcom();
}

callunix()
{
	buf: string;
	c: int;

	if (sh == nil)
		sh = load Sh Sh->PATH;
	if (sh == nil) {
		putst("can't load shell");
		return;
	}
	setnoaddr();
	while((c=getchr()) != EOF && c != '\n')
		buf[len buf] = c;
	sh->system(drawctxt, buf);
 	if(vflag)
 		putst("!");
}

quit()
{
	if(vflag && fchange && dol!=0) {
		fchange = 0;
		error(Q);
	}
	sys->remove(tfname);
	exit;
}

onquit(nil: int)
{
	quit();
}

rdelete(ad1, ad2: int)
{
	a1, a2, a3: int;

	a1 = ad1;
	a2 = ad2+1;
	a3 = dol;
	dol -= a2 - a1;
	do {
		zero[a1++] = zero[a2++];
	} while (a2 <= a3);
	a1 = ad1;
	if(a1 > dol)
		a1 = dol;
	dot = a1;
	fchange = 1;
}

gdelete()
{
	a1, a2, a3: int;

	a3 = dol;
	for(a1=0; (zero[a1]&8r01)==0; a1++)
		if(a1>=a3)
			return;
	for(a2=a1+1; a2<=a3;) {
		if(zero[a2] & 8r01) {
			a2++;
			dot = a1;
		} else
			zero[a1++] = zero[a2++];
	}
	dol = a1-1;
	if(dot > dol)
		dot = dol;
	fchange = 1;
}

getline(_tl: int): int
{
	lp, bp: int;
	nl: int;
	block: array of int;
#debug(sys->sprint("getline %d\n", _tl));
	lp = 0;
	(block, bp) = getblock(_tl, Sys->OREAD);
	nl = len block - bp;
	_tl &= ~(RunesPerBlock - 1);
	while(linebuf[lp++] = block[bp++]) {
		nl--;
		if(nl == 0) {
			(block, bp) = getblock(_tl += RunesPerBlock, Sys->OREAD);
			nl = len block;
		}
	}
	return 0;
}

putline(): int
{
	lp, bp: int;
	nl, _tl: int;
	block: array of int;
	fchange = 1;
	lp = 0;
	_tl = tline;
	(block, bp) = getblock(_tl, Sys->OWRITE);
	nl = len block - bp;
	_tl &= ~(RunesPerBlock-1);		# _tl is now at the beginning of the block
	while(block[bp] = linebuf[lp++]) {
		if(block[bp++] == '\n') {
			block[bp-1] = 0;
			linebp = lp;
			break;
		}
		nl--;
		if(nl == 0) {
			_tl += RunesPerBlock;
			(block, bp) = getblock(_tl, Sys->OWRITE);
			nl = len block;
		}
	}
	nl = tline;
	tline += ((lp) + 8r03) & 8r077776;
	return nl;
}

tbuf := array [BLKSIZE] of byte;

getrune(buf: array of byte): int
{
	return int buf[0] + (int buf[1] << 8);
}

putrune(buf: array of byte, v: int)
{
	buf[0] = byte (v);
	buf[1] = byte (v >> 8);
}

blkio(b: int, buf: array of int, writefunc: int)
{
	sys->seek(tfile, big b * big BLKSIZE, Sys->SEEKSTART);
	if (writefunc) {
		# flatten buf into tbuf
		for (x := 0; x < RunesPerBlock; x++)
			putrune(tbuf[x * BytesPerRune:], buf[x]);
		if (sys->write(tfile, tbuf, BLKSIZE) != len tbuf) {
			error(T);
		}
	}
	else {
		if (sys->read(tfile, tbuf, len tbuf) != len tbuf) {
			error(T);
		}
		for (x := 0; x < RunesPerBlock; x++)
			buf[x] = getrune(tbuf[x * BytesPerRune:]);
	}
}

ibuff := array [RunesPerBlock] of int;
obuff := array [RunesPerBlock] of int;

getblock(atl, iof: int): (array of int, int)
{
	bno, off: int;
	
	bno = atl / RunesPerBlock;
	off = (atl * BytesPerRune) & (BLKSIZE-1) & ~8r03;
	if(bno >= NBLK) {
		lastc = '\n';
		error(T);
	}
	off /= BytesPerRune;
	if(bno == iblock) {
		ichanged |= iof;
#debug(sys->sprint("getblock(%d, %d): returns ibuff offset %d\n", atl, iof, off));
		return (ibuff, off);
	}
	if(bno == oblock) {
#debug(sys->sprint("getblock(%d, %d): returns obuff offset %d\n", atl, iof, off));
		return (obuff, off);
	}
	if(iof == Sys->OREAD) {
		if(ichanged)
			blkio(iblock, ibuff, 1);
		ichanged = 0;
		iblock = bno;
		blkio(bno, ibuff, 0);
#debug(sys->sprint("getblock(%d, %d): returns ibuff offset %d\n", atl, iof, off));
		return (ibuff, off);
	}
	if(oblock >= 0)
		blkio(oblock, obuff, 1);
	oblock = bno;
#debug(sys->sprint("getblock(%d, %d): returns offset %d\n", atl, iof, off));
	return (obuff, off);
}

_init()
{
	markp: int;

	tfile = nil;
	tline = RunesPerBlock;
	for(markp = 0; markp < len names; markp++)
		names[markp] = 0;
	subnewa = 0;
	anymarks = 0;
	iblock = -1;
	oblock = -1;
	ichanged = 0;
	if((tfile = sys->create(tfname, Sys->ORDWR, 8r0600)) == nil){
		error1(T);
		exit;
	}
	dot = dol = 0;
}

global(k: int)
{
	globuf: string;
	c, a1: int;

	if(!globp.isnil)
		error(Q);
	setwide();
	squeeze(dol > 0);
	c = getchr();
	if(c == '\n')
		error(Q);
	compile(c);
	globuf = nil;
	while((c=getchr()) != '\n') {
		if(c == EOF)
			error(Q);
		if(c == '\\') {
			c = getchr();
			if(c != '\n')
				globuf[len globuf] = '\\';
		}
		globuf[len globuf] = c;
	}
	if(globuf == nil)
		globuf = "p";
	globuf[len globuf] = '\n';
	for(a1=0; a1<=dol; a1++) {
		zero[a1] &= ~8r01;
		if(a1 >= addr1 && a1 <= addr2 && match(a1) == k)
			zero[a1] |= 8r01;
	}

	#
	# Special case: g/.../d (avoid n^2 algorithm)
	 
	if(globuf == "d\n") {
		gdelete();
		return;
	}
	for(a1=0; a1<=dol; a1++) {
		if(zero[a1] & 8r01) {
			zero[a1] &= ~8r01;
			dot = a1;
			globp = (globuf, 0);
			commands();
			a1 = 0;
		}
	}
}

join()
{
	gp, lp: int;
	a1: int;

	nonzero();
	gp = 0;
	for(a1=addr1; a1<=addr2; a1++) {
		lp = getline(zero[a1]);
		while(genbuf[gp] = linebuf[lp++])
			if(gp++ >= LBSIZE-2)
				error(Q);
	}
	lp = 0;
	gp = 0;
	while(linebuf[lp++] = genbuf[gp++])
		;
	zero[addr1] = putline();
	if(addr1 < addr2)
		rdelete(addr1+1, addr2);
	dot = addr1;
}

substitute(inglob: int)
{
	mp, a1, nl, gsubf, n: int;

	n = getnum();	# OK even if n==0 
	gsubf = compsub();
	for(a1 = addr1; a1 <= addr2; a1++) {
		if(match(a1)){
			m := n;

			do {
				span := loc2-loc1;

				if(--m <= 0) {
					dosub();
					if(!gsubf)
						break;
					if(span == 0) {	# null RE match 
						if(zero[loc2] == 0)
							break;
						loc2++;
					}
				}
			} while(match(-1));
			if(m <= 0) {
				inglob |= 8r01;
				subnewa = putline();
				zero[a1] &= ~8r01;
				if(anymarks) {
					for(mp=0; mp<len names; mp++)
						if(names[mp] == zero[a1])
							names[mp] = subnewa;
				}
				subolda = zero[a1];
				zero[a1] = subnewa;
#debug(sys->sprint("append-getsub linebp = %d\n", linebp));
				nl = append(APPEND_GETSUB, a1);
				addr2 += nl;
			}
		}
	}
	if(inglob == 0)
		error(Q);
}

compsub(): int
{
	seof, c: int;
	p: int;

	seof = getchr();
	if(seof == '\n' || seof == ' ')
		error(Q);
	compile(seof);
	p = 0;
	for(;;) {
		c = getchr();
		if(c == '\\') {
			c = getchr();
			rhsbuf[p++] = ESCFLG;
			if(p >= LBSIZE / 2)
				error(Q);
		} else
		if(c == '\n' && (globp.isnil || globp.s == nil)) {
			peekc = c;
			pflag++;
			break;
		} else
		if(c == seof)
			break;
		rhsbuf[p++] = c;
		if(p >= LBSIZE / 2)
			error(Q);
	}
	rhsbuf[p] = 0;
	peekc = getchr();
	if(peekc == 'g') {
		peekc = 0;
		newline();
		return 1;
	}
	newline();
	return 0;
}

getsub(): int
{
	p1, p2: int;

	p1 = 0;
	if((p2 = linebp) == -1)
		return EOF;
	while(linebuf[p1++] = linebuf[p2++])
		;
	linebp = -1;
	return 0;
}

dosub()
{
	lp, sp, rp: int;
	c, n: int;

#	lp = linebuf;
#	sp = genbuf;
#	rp = rhsbuf;
	lp = 0;	
	sp = 0;
	rp = 0;
	while(lp < loc1)
		genbuf[sp++] = linebuf[lp++];
	while(c = rhsbuf[rp++]) {
		if(c == '&'){
			sp = place(sp, loc1, loc2);
			continue;
		}
		if(c == ESCFLG && (c = rhsbuf[rp++]) >= '1' && c < MAXSUB+'0') {
			n = c-'0';
			if(n < len subexp && subexp[n].rsp >= 0 && subexp[n].rep >= 0) {
				sp = place(sp, subexp[n].rsp, subexp[n].rep);
				continue;
			}
			error(Q);
		}
		genbuf[sp++] = c;
		if(sp >= LBSIZE)
			error(Q);
	}
	lp = loc2;
	loc2 = sp;
	while(genbuf[sp++] = linebuf[lp++])
		if(sp >= LBSIZE)
			error(Q);
	linebuf[0:] = genbuf[0: sp];
}

place(sp: int, l1: int, l2: int): int
{

	while(l1 < l2) {
		genbuf[sp++] = linebuf[l1++];
		if(sp >= LBSIZE)
			error(Q);
	}
	return sp;
}

move(cflag: int)
{
	_adt, ad1, ad2: int;

	nonzero();
	if((_adt = address()) < 0)	# address() guarantees addr is in range 
		error(Q);
	newline();
	if(cflag) {
		ad1 = dol;
		append(APPEND_GETCOPY, ad1++);
		ad2 = dol;
	} else {
		ad2 = addr2;
		for(ad1 = addr1; ad1 <= ad2;)
			zero[ad1++] &= ~8r01;
		ad1 = addr1;
	}
	ad2++;
	if(_adt<ad1) {
		dot = _adt + (ad2-ad1);
		if((++_adt)==ad1)
			return;
		reverse(_adt, ad1);
		reverse(ad1, ad2);
		reverse(_adt, ad2);
	} else
	if(_adt >= ad2) {
		dot = _adt++;
		reverse(ad1, ad2);
		reverse(ad2, _adt);
		reverse(ad1, _adt);
	} else
		error(Q);
	fchange = 1;
}

reverse(a1, a2: int)
{
	t: int;

	for(;;) {
		t = zero[--a2];
		if(a2 <= a1)
			return;
		zero[a2] = zero[a1];
		zero[a1++] = t;
	}
}

getcopy(): int
{
	if(addr1 > addr2)
		return EOF;
	getline(zero[addr1++]);
	return 0;
}

compile(eof: int)
{
	c: int;

	if((c = getchr()) == '\n') {
		peekc = c;
		c = eof;
	}
	if(c == eof) {
		if(pattern == nil)
			error(Q);
		return;
	}
	pattern = nil;
	program := "";
	do {
		
		if(c == '\\') {
			program[len program] = '\\';
			if((c = getchr()) == '\n') {
				error(Q);
				return;
			}
		}
		program[len program] = c;
	} while((c = getchr()) != eof && c != '\n');
	if(c == '\n')
		peekc = c;
	diag: string;
#debug("program " + program + "\n");
	(pattern, diag) = regex->compile(program, 1);
#if (diag != nil)
#	debug("diag " + diag + "\n");
	if (diag != nil)
		pattern = nil;
}

mkstring(a: array of int): string
{
	s: string;
	for (x := 0; x < len a; x++) {
		if (a[x] == 0)
			break;
		s[x] = a[x];
	}
	return s;
}

match(addr: int): int
{
	rsp: int;
	if(pattern == nil)
		return 0;
	if(addr >= 0){
		if(addr == 0)
			return 0;
		rsp = getline(zero[addr]);
	} else
		rsp = loc2;
	s := mkstring(linebuf);
	subexp = regex->executese(pattern, s, (rsp, len s), rsp == 0, 1);
	if(subexp != nil) {
		(loc1, loc2) = subexp[0];
		return 1;
	}
	loc1 = loc2 = -1;
	return 0;
}

putd()
{
	r: int;

	r = count%10;
	count /= 10;
	if(count)
		putd();
	putchr(r + '0');
}

putst(s: string)
{
	col = 0;
	for(x := 0; x < len s; x++)
		putchr(s[x]);
	putchr('\n');
}

putshst(sp: int)
{
	col = 0;
	while(linebuf[sp]) {
		putchr(linebuf[sp++]);
	}
	putchr('\n');
}

putchr(ac: int)
{
	lp: int;
	c: int;
	rune: int;
	lp = linp;
	c = ac;
	if(listf) {
		if(c == '\n') {
			if(linp != 0 && line[linp - 1] == byte ' ') {
				line[lp++] = byte '\\';
				line[lp++] = byte 'n';
			}
		} else {
			if(col > (72-6-2)) {
				col = 8;
				line[lp++] = byte '\\';
				line[lp++] = byte '\n';
				line[lp++] = byte '\t';
			}
			col++;
			if(c=='\b' || c=='\t' || c=='\\') {
				line[lp++] = byte '\\';
				if(c == '\b')
					c = 'b';
				else
				if(c == '\t')
					c = 't';
				col++;
			} else
			if(c<' ' || c>=8r0177) {
				line[lp++] = byte '\\';
				line[lp++] = byte 'x';
				line[lp++] = byte hex[c>>12];
				line[lp++] = byte hex[c>>8&16rF];
				line[lp++] = byte hex[c>>4&16rF];
				c     =  hex[c&16rF];
				col += 5;
			}
		}
	}

	rune = c;
	lp += sys->char2byte(rune, line, lp);

	if(c == '\n' || lp >= len line - 5) {
		linp = 0;
		if (oflag)
			sys->write(sys->fildes(2), line, lp);
		else
			sys->write(sys->fildes(1), line, lp);
		return;
	}
	linp = lp;
}

stringfromint(i: int): string
{
	s: string;
	s[0] = i;
	return s;
}

mktemp(as: string): string
{
	pid: int;
	s: string;

	s = nil;
	pid = sys->pctl(0, nil);
	for (x := len as - 1; x >= 0; x--)
		if (as[x] == 'X') {
			s = stringfromint('0' + pid % 10) + s;
			pid /= 10;
		}
		else
			s = stringfromint(as[x]) + s;
	s[len s] = 'a';
	for (;;) {
		(rv, nil) := sys->stat(s);
		if (rv < 0)
			break;
		if (s[len s - 1] == 'z')
			return "/";
		s[len s - 1]++;
	}
	return s;
}
