implement Tr;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "arg.m";
	arg: Arg;

Tr: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Pcb: adt {	# Control block controlling specification parse
	spec: string;	# specification string
	end:	int;	# its length
	current:	int;	# current parse point
	last:	int;	# last Rune returned
	final:	int;	# final Rune in a span

	new:	fn(nil: string): ref Pcb;
	rewind:	fn(nil: self ref Pcb);
	getc:	fn(nil: self ref Pcb): int;
	canon:	fn(nil: self ref Pcb): int;
};

bits := array [] of { byte 1, byte 2, byte 4, byte 8, byte 16, byte 32, byte 64, byte 128 };

SETBIT(a: array of byte, c: int)
{
	a[c>>3] |= bits[c & 7];
}

CLEARBIT(a: array of byte, c: int)
{
	a[c>>3] &= ~bits[c & 7];
}

BITSET(a: array of byte, c: int): int
{
	return int (a[c>>3] & bits[c&7]);
}

MAXRUNE: con 16rFFFF;

f := array[(MAXRUNE+1)/8] of byte;
t := array[(MAXRUNE+1)/8] of byte;

pto, pfrom: ref Pcb;

cflag := 0;
dflag := 0;
sflag := 0;
stderr: ref Sys->FD;

ib: ref Iobuf;
ob: ref Iobuf;

usage()
{
	sys->fprint(stderr, "Usage: tr [-sdc] [from-set [to-set]]\n");
	raise "fail: usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	bufio = load Bufio Bufio->PATH;
	arg = load Arg Arg->PATH;
	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		's' => sflag = 1;
		'd' => dflag = 1;
		'c' => cflag = 1;
		* => usage();
	}
	args = arg->argv();
	argc := len args;
	if(args != nil){
		pfrom = Pcb.new(hd args);
		args = tl args;
	}
	if(args != nil){
		pto = Pcb.new(hd args);
		args = tl args;
	}
	if(args != nil)
		usage();
	ib = bufio->fopen(sys->fildes(0), Bufio->OREAD);
	ob = bufio->fopen(sys->fildes(1), Bufio->OWRITE);
	if(dflag) {
		if(sflag && argc != 2 || !sflag && argc != 1)
			usage();
		delete();
	} else {
		if(argc != 2)
			usage();
		if(cflag)
			complement();
		else
			translit();
	}
	if(ob.flush() == Bufio->ERROR)
		error(sys->sprint("write error: %r"));
}

delete()
{
	if (cflag) {
		for(i := 0; i < len f; i++)
			f[i] = byte 16rFF;
		while ((c := pfrom.canon()) >= 0)
			CLEARBIT(f, c);
	} else {
		while ((c := pfrom.canon()) >= 0)
			SETBIT(f, c);
	}
	if (sflag) {
		while ((c := pto.canon()) >= 0)
			SETBIT(t, c);
	}

	last := MAXRUNE+1;
	while ((c := ib.getc()) >= 0) {
		if(!BITSET(f, c) && (c != last || !BITSET(t,c))) {
			last = c;
			ob.putc(c);
		}
	}
}

complement()
{
	lastc := 0;
	high := 0;
	while ((from := pfrom.canon()) >= 0) {
		if (from > high)
			high = from;
		SETBIT(f, from);
	}
	while ((cto := pto.canon()) >= 0) {
		if (cto > high)
			high = cto;
		SETBIT(t,cto);
	}
	pto.rewind();
	p := array[high+1] of int;
	for (i := 0; i <= high; i++){
		if (!BITSET(f,i)) {
			if ((cto = pto.canon()) < 0)
				cto = lastc;
			else
				lastc = cto;
			p[i] = cto;
		} else
			p[i] = i;
	}
	if (sflag){
		lastc = MAXRUNE+1;
		while ((from = ib.getc()) >= 0) {
			if (from > high)
				from = cto;
			else
				from = p[from];
			if (from != lastc || !BITSET(t,from)) {
				lastc = from;
				ob.putc(from);
			}
		}
	} else {
		while ((from = ib.getc()) >= 0){
			if (from > high)
				from = cto;
			else
				from = p[from];
			ob.putc(from);
		}
	}
}

translit()
{
	lastc := 0;
	high := 0;
	while ((from := pfrom.canon()) >= 0)
		if (from > high)
			high = from;
	pfrom.rewind();
	p := array[high+1] of int;
	for (i := 0; i <= high; i++)
		p[i] = i;
	while ((from = pfrom.canon()) >= 0) {
		if ((cto := pto.canon()) < 0)
			cto = lastc;
		else
			lastc = cto;
		if (BITSET(f,from) && p[from] != cto)
			error("ambiguous translation");
		SETBIT(f,from);
		p[from] = cto;
		SETBIT(t,cto);
	}
	while ((cto := pto.canon()) >= 0)
		SETBIT(t,cto);
	if (sflag){
		lastc = MAXRUNE+1;
		while ((from = ib.getc()) >= 0) {
			if (from <= high)
				from = p[from];
			if (from != lastc || !BITSET(t,from)) {
				lastc = from;
				ob.putc(from);
			}
		}
				
	} else {
		while ((from = ib.getc()) >= 0) {
			if (from <= high)
				from = p[from];
			ob.putc(from);
		}
	}
}

Pcb.new(s: string): ref Pcb
{
	return ref Pcb(s, len s, 0, -1, -1);
}

Pcb.rewind(p: self ref Pcb)
{
	p.current = 0;
	p.last = p.final = -1;
}

Pcb.getc(p: self ref Pcb): int
{
	if(p.current >= p.end)
		return -1;
	s := p.current;
	r := p.spec[s++];
	if(r == '\\' && s < p.end){
		n := 0;
		if ((r = p.spec[s]) == 'x') {
			s++;
			for (i := 0; i < 6 && s < p.end; i++) {
				p.current = s;
				r = p.spec[s++];
				if ('0' <= r && r <= '9')
					n = 16*n + r - '0';
				else if ('a' <= r && r <= 'f')
					n = 16*n + r - 'a' + 10;
				else if ('A' <= r && r <= 'F')
					n = 16*n + r - 'A' + 10;
				else {
					if (i == 0)
						return 'x';
					return n;
				}
			}
			r = n;
		} else {
			for(i := 0; i < 3 && s < p.end; i++) {
				p.current = s;
				r = p.spec[s++];
				if('0' <= r && r <= '7')
					n = 8*n + r - '0';
				else {
					if (i == 0)
						return r;
					return n;
				}
			}
			if(n > 0377)
				error("char>0377");
			r = n;
		}
	}
	p.current = s;
	return r;
}

Pcb.canon(p: self ref Pcb): int
{
	if (p.final >= 0) {
		if (p.last < p.final)
			return ++p.last;
		p.final = -1;
	}
	if (p.current >= p.end)
		return -1;
	if(p.spec[p.current] == '-' && p.last >= 0 && p.current+1 < p.end){
		p.current++;
		r := p.getc();
		if (r < p.last)
			error ("Invalid range specification");
		if (r > p.last) {
			p.final = r;
			return ++p.last;
		}
	}
	r := p.getc();
	p.last = r;
	return p.last;
}

error(s: string)
{
	sys->fprint(stderr, "tr: %s\n", s);
	raise "fail: error";
}
