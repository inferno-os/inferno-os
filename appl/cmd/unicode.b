implement Unicode;

include "sys.m";
sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;


Unicode: module
{
	init: fn(c: ref Draw->Context, v: list of string);
};

usage: con "unicode { [-t] hex hex ... | hexmin-hexmax ... | [-n] char ... }";
hex: con "0123456789abcdefABCDEF";
numout:= 0;
text:= 0;
out: ref Bufio->Iobuf;
stderr: ref sys->FD;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	bufio = load Bufio Bufio->PATH;

	stderr = sys->fildes(2);

	if(str==nil || bufio==nil){
		sys->fprint(stderr, "unicode: can't load String or Bufio module: %r\n");
		return;
	}

	if(argv == nil){
		sys->fprint(stderr, "usage: %s\n", usage);
		return;
	}
	argv = tl argv;
	while(argv != nil) {
		s := hd argv;
		if(s != nil && s[0] != '-')
			break;
		case s{
		"-n" =>
			numout = 1;
		"-t" =>
			text = 1;
		}
		argv = tl argv;
	}
	if(argv == nil){
		sys->fprint(stderr, "usage: %s\n", usage);
		return;
	}

	out = bufio->fopen(sys->fildes(1), Bufio->OWRITE);

	if(!numout && oneof(hd argv, '-'))
		range(argv);
	else if(numout || oneof(hex, (hd argv)[0]) == 0)
		nums(argv);
	else
		chars(argv);
	out.flush();
}

oneof(s: string, c: int): int
{
	for(i:=0; i<len s; i++)
		if(s[i] == c)
			return 1;
	return 0;
}

badrange(q: string)
{
	sys->fprint(stderr, "unicode: bad range %s\n", q);
}

range(argv: list of string)
{
	min, max: int;

	while(argv != nil){
		q := hd argv;
		if(oneof(hex, q[0]) == 0){
			badrange(q);
			return;
		}
		(min, q) = str->toint(q,16);
		if(min<0 || min>16rFFFF || len q==0 || q[0]!='-'){
			badrange(hd argv);
			return;
		}
		q = q[1:];
		if(oneof(hex, q[0]) == 0){
			badrange(hd argv);
			return;
		}
		(max, q) = str->toint(q,16);
		if(max<0 || max>16rFFFF || max<min || len q>0){
			badrange(hd argv);
			return;
		}
		i := 0;
		do{
			out.puts(sys->sprint("%.4x %c", min, min));
			i++;
			if(min==max || (i&7)==0)
				out.puts("\n");
			else
				out.puts("\t");
			min++;
		}while(min<=max);
		argv = tl argv;
	}
}


nums(argv: list of string)
{
	while(argv != nil){
		q := hd argv;
		for(i:=0; i<len q; i++)
			out.puts(sys->sprint("%.4x\n", q[i]));
		argv = tl argv;
	}
}

badvalue(s: string)
{
	sys->fprint(stderr, "unicode: bad unicode value %s\n", s);
}

chars(argv: list of string)
{
	m: int;

	while(argv != nil){
		q := hd argv;
		if(oneof(hex, q[0]) == 0){
			badvalue(hd argv);
			return;
		}
		(m, q) = str->toint(q, 16);
		if(m<0 || m>16rFFFF || len q>0){
			badvalue(hd argv);
			return;
		}
		out.puts(sys->sprint("%c", m));
		if(!text)
			out.puts("\n");
		argv = tl argv;
	}
}
