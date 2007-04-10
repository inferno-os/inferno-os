implement Look;

#
#	Copyright © 2002 Lucent Technologies Inc.
#	transliteration of the Plan 9 command; subject to the Lucent Public License 1.02
#	-r option added by Caerwyn Jones to print a range
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "arg.m";

Look: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

filename := "/lib/words";
dfile: ref Iobuf;
bout: ref Iobuf;
debug := 0;
fold, direc, exact, iflag, range: int;
rev := 1;	# -1 for reverse-ordered file, not implemented
compare: ref fn(a, b: string): int;
tab := '\t';
entry: string;
word: string;
key: string;
latin_fold_tab := array[64] of {
	# 	Table to fold latin 1 characters to ASCII equivalents
	# 	based at Rune value 0xc0
	# 
	#	 À    Á    Â    Ã    Ä    Å    Æ    Ç
	#	 È    É    Ê    Ë    Ì    Í    Î    Ï
	#	 Ð    Ñ    Ò    Ó    Ô    Õ    Ö    ×
	#	 Ø    Ù    Ú    Û    Ü    Ý    Þ    ß
	#	 à    á    â    ã    ä    å    æ    ç
	#	 è    é    ê    ë    ì    í    î    ï
	#	 ð    ñ    ò    ó    ô    õ    ö    ÷
	#	 ø    ù    ú    û    ü    ý    þ    ÿ
	# 
	'a',	'a',	'a',	'a',	'a',	'a',	'a',	'c',	
	'e',	'e',	'e',	'e',	'i',	'i',	'i',	'i',
	'd',	'n',	'o',	'o',	'o',	'o',	'o',	0,
	'o',	'u',	'u',	'u',	'u',	'y',	0,	0,
	'a',	'a',	'a',	'a',	'a',	'a',	'a',	'c',
	'e',	'e',	'e',	'e',	'i',	'i',	'i',	'i',
	'd',	'n',	'o',	'o',	'o',	'o',	'o',	0,
	'o',	'u',	'u',	'u',	'u',	'y',	0,	'y',
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	arg := load Arg Arg->PATH;

	lastkey: string;

	arg->init(args);
	arg->setusage("look -[dfinx] [-r lastkey] [-t c] [string] [file]");
	compare = acomp;
	while((c := arg->opt()) != 0)
		case c {
		'D' =>
			debug = 1;
		'd' =>
			direc++;
		'f' =>
			fold++;
		'i' =>
			iflag++;
		'n' =>
			compare = ncomp;
		't' =>
			tab = (arg->earg())[0];
		'x' =>
			exact++;
		'r' =>
			range++;
			lastkey = rcanon(arg->earg());
		* =>
			arg->usage();
		}
	args = arg->argv();
	arg = nil;

	bin := bufio->fopen(sys->fildes(0), Sys->OREAD); 
	bout = bufio->fopen(sys->fildes(1), Sys->OWRITE);
	orig: string;
	if(!iflag){
		if(args != nil){
			orig = hd args;
			args = tl args;
		}else
			iflag++;
	}
	if(args == nil){
		direc++;
		fold++;
	}else
		filename = hd args;
	if(!iflag)
		key = rcanon(orig);
	if(debug)
		sys->fprint(sys->fildes(2), "orig %s key %s %s\n", orig, key, filename);
	dfile = bufio->open(filename, Sys->OREAD);
	if(dfile == nil){
		sys->fprint(sys->fildes(2), "look: can't open %s\n", filename);
		raise "fail:no dictionary";
	}
	if(!iflag) 
		if(!locate() && !range)
			raise "fail:not found";
	do{
		if(iflag){
			bout.flush();
			if((orig = bin.gets('\n')) == nil)
				exit;
			key = rcanon(orig);
			if(!locate())
				continue;
		}
		if(range){
			if(compare(key, word) <= 0 && compare(word, lastkey) <= 0)
				bout.puts(entry);
		}else if(!exact || acomp(word, orig) == 0)
			bout.puts(entry);
	Matches:
		while((entry = dfile.gets('\n')) != nil){
			word = rcanon(entry);
			if(range)
				n := compare(word, lastkey);
			else
				n = compare(key, word);
			if(debug)
				sys->print("compare %d %q\n", n, word);
			case n {
			-2 =>
				if(!range)
					break Matches;
				bout.puts(entry);
			-1 =>
				if(exact)
					break Matches;
				bout.puts(entry);
			0 =>
				if(!exact || acomp(word, orig) == 0)
					bout.puts(entry);
			* =>
				break Matches;
			}
		}
	}while(iflag);
	bout.flush();
}

locate(): int
{
	bot := big 0;
	top := dfile.seek(big 0, 2);
	mid: big;
Search:
	for(;;){
		mid = (top+bot)/big 2;
		if(debug)
			sys->fprint(sys->fildes(2), "locate %bd %bd %bd\n", top, mid, bot);
		dfile.seek(mid, 0);
		c: int;
		do
			c = dfile.getc();
		while(c >= 0 && c != '\n');
		mid = dfile.offset();
		if((entry = dfile.gets('\n')) == nil)
			break;
		word = rcanon(entry);
		if(debug)
			sys->fprint(sys->fildes(2), "mid %bd key: %s entry: %s\n", mid, key, word);
		n := compare(key, word);
		if(debug)
			sys->fprint(sys->fildes(2), "compare: %d\n", n);
		case n {
		-2 or -1 or 0 =>
			if(top <= mid)
				break Search;
			top = mid;
		1 or 2 =>
			bot = mid;
		}
	}
	if(debug)
		sys->fprint(sys->fildes(2), "locate %bd %bd %bd\n", top, mid, bot);
	bot = dfile.seek(big bot, 0);
	while((entry = dfile.gets('\n')) != nil){
		word = rcanon(entry);
		if(debug)
			sys->fprint(sys->fildes(2), "seekbot %bd key: %s entry: %s\n", bot, key, word);
		n := compare(key, word);
		if(debug)
			sys->fprint(sys->fildes(2), "compare: %d\n", n);
		case n {
		-2 =>
			return 0;
		-1 =>
			return !exact;
		0 =>
			return 1;
		1 or 2 =>
			;
		}
	}
	return 0;
}

#
#	acomp(s, t) returns:
#		-2 if s strictly precedes t
#		-1 if s is a prefix of t
#		0 if s is the same as t
#		1 if t is a prefix of s
#		2 if t strictly precedes s
#  
acomp(s, t: string): int
{
	if(s == t)
		return 0;
	l := len s;
	if(l > len t)
		l = len t;
	cs, ct: int;
	for(i := 0; i < l; i++) {
		cs = s[i];
		ct = t[i];
		if(cs != ct)
			break;
	}
	if(i == len s)
		return -1;
	if(i == len t)
		return 1;
	if(cs < ct)
		return -2;
	return 2;
}

rcanon(s: string): string
{
	if(s != nil && s[len s - 1] == '\n')
		s = s[0: len s - 1];
	o := 0;
	for(i := 0; i < len s && (r := s[i]) != tab; i++){
		if(islatin1(r) && (mr := latin_fold_tab[r-16rc0]) != 0)
			r = mr;
		if(direc)
			if(!(isalnum(r) || r == ' ' || r == '\t'))
				continue;
		if(fold)
			if(isupper(r))
				r = tolower(r);
		if(r != s[o])	# avoid copying s unless necessary
			s[o] = r;
		o++;
	}
	if(o != i)
		return s[0:o];
	return s;
}

sgn(v: int): int
{
	if(v < 0)
		return -1;
	if(v > 0)
		return 1;
	return 0;
}

ncomp(s: string, t: string): int
{
	while(len s > 0 && isspace(s[0]))
		s = s[1:];
	while(len t > 0 && isspace(t[0]))
		t = t[1:];
	ssgn := tsgn := -2*rev;
	if(s != nil && s[0] == '-'){
		s = s[1: ];
		ssgn = -ssgn;
	}
	if(t != nil && t[0] == '-'){
		t = t[1:];
		tsgn = -tsgn;
	}
	for(i := 0; i < len s && isdigit(s[i]); i++)
		;
	is := s[0:i];
	js := s[i:];
	for(i = 0; i < len t && isdigit(t[i]); i++)
		;
	it := t[0:i];
	jt := t[i:];
	a := 0;
	i = len is;
	j := len it;
	if(ssgn == tsgn){
		while(j > 0 && i > 0)
			if((b := it[--j] - is[--i]) != 0)
				a = b;
	}
	while(i > 0)
		if(is[--i] != '0')
			return -ssgn;
	while(j > 0)
		if(it[--i] != '0')
			return tsgn;
	if(a)
		return sgn(a)*ssgn;
	s = js;
	if(len s > 0 && s[0] == '.')
		s = s[1: ];
	t = jt;
	if(len t > 0 && t[0] == '.')
		t = t[1: ];
	if(ssgn == tsgn)
		while((len s > 0 && isdigit(s[0])) && (len t > 0 && isdigit(t[0]))){
			if(a = t[0] - s[0])
				return sgn(a)*ssgn;
			s = s[1:];
			t = t[1:];
		}
	for(; len s > 0 && isdigit(s[0]); s = s[1:])
		if(s[0] != '0')
			return -ssgn;
	for(; len t > 0 && isdigit(t[0]); t = t[1:])
		if(t[0] != '0')
			return tsgn;
	return 0;
}

isupper(c: int): int
{
	return c >= 'A' && c <= 'Z';
}

islower(c: int): int
{
	return c >= 'a' && c <= 'z';
}

isalpha(c: int): int
{
	return islower(c) || isupper(c);
}

islatin1(c: int): int
{
	return c >= 16rC0 && c <= 16rFF;
}

isdigit(c: int): int
{
	return c >= '0' && c <= '9';
}

isalnum(c: int): int
{
	return isdigit(c) || islower(c) || isupper(c);
}

isspace(c: int): int
{
	return c == ' ' || c == '\t' || c >= 16r0A && c <= 16r0D;
}

tolower(c: int): int
{
	return c-'A'+'a';
}
