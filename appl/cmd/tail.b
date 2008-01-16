implement Tail;

include "sys.m";
sys: Sys;

include "draw.m";

include "bufio.m";
bufmod : Bufio;
Iobuf : import bufmod;

include "string.m";
	str : String;

count, anycount, follow : int;
file : ref sys->FD;
bout : ref Iobuf;
BSize : con 8*1024;

BEG, END, CHARS, LINES , FWD, REV : con iota;
 
origin := END;
units := LINES;
dir := FWD;


Tail: module
{
	init:	fn(nil: ref Draw->Context, argv: list of string);
};


init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	bufmod = load Bufio Bufio->PATH;
	seekable : int;
	bout = bufmod->fopen(sys->fildes(1),bufmod->OWRITE);
	argv=parse(tl argv);
	if(dir==REV && (units==CHARS || follow || origin==BEG))
		fail("incompatible options");
	if(!anycount){
		if (dir==REV)
			count= 16r7fffffff;
		else
			count = 10;
	}
	if(origin==BEG && units==LINES && count>0)
		count--;
	if(len argv > 1)
		usage();
	if(argv == nil || hd argv == "-") {
		file = sys->fildes(0);
		seekable = 0;
	}
	else {
		if((file=sys->open(hd argv,sys->OREAD)) == nil )
			fatal(hd argv);
		(nil, stat) := sys->fstat(file);
		seekable = sys->seek(file,big 0,sys->SEEKSTART) == big 0 && stat.length > big 0;
	}

	if(!seekable && origin==END)
		keep();
	else if(!seekable && origin==BEG)
		skip();
	else if(units==CHARS && origin==END){
		tseek(big -count, Sys->SEEKEND);
		copy();
	}
	else if(units==CHARS && origin==BEG){
		tseek(big count, Sys->SEEKSTART);
		copy();
	}
	else if(units==LINES && origin==END)
		reverse();
	else if(units==LINES && origin==BEG)
		skip();
	if(follow){
		if(seekable){
			d : sys->Dir;
			d.length=big -1;
			for(;;){
				d=trunc(d.length);
				copy();
				sys->sleep(5000);
			}
		}else{
			for(;;){
				copy();
				sys->sleep(5000);
			}
		}
	}
	exit;
}


trunc(length : big) : sys->Dir
{
	(nil,d):=sys->fstat(file);
	if(d.length < length)
		d.length = tseek(big 0, sys->SEEKSTART);
	return d;
}


skip()	# read past head of the file to find tail 
{
	n : int;
	buf := array[BSize] of byte;
	if(units == CHARS) {
		for( ; count>0; count -=n) {
			if (count<BSize) 
				n=count;
			else
				n=BSize;
			n = tread(buf, n);
			if(n == 0)
				return;
		}
	} else { # units == LINES
		i:=0;
		n=0;
		while(count > 0) {
			n = tread(buf, BSize);
			if(n == 0)
				return;
			for(i=0; i<n && count>0; i++)
				if(buf[i]==byte '\n')
					count--;
		}
		twrite(buf[i:n]);
	}
	copy();
}


copy()
{
	buf := array[BSize] of byte;
	while((n := tread(buf, BSize)) > 0){
		twrite(buf[0:n]);
	}
	bout.flush();	
}


keep()	# read whole file, keeping the tail 
{	# complexity=length(file)*length(tail).  could be linear
	j, k : int;
	length:=0;
	buf : array of byte;
	tbuf : array of byte;
	bufsize := 0;
	for(n:=1; n;) {
		if(length+BSize > bufsize ) {
			bufsize += 2*BSize;
			tbuf = array[bufsize+1] of byte;
			tbuf[0:]=buf[0:];
			buf = tbuf;
		}
		for( ; n && length<bufsize; length+=n)
			n = tread(buf[length:], bufsize-length);
		if(count >= length)
			continue;
		if(units == CHARS)
			j = length - count;
		else{ # units == LINES 
			if (int buf[length-1]=='\n')
				j =  length-1;
			else
				j=length;
			for(k=0; j>0; j--)
				if(int buf[j-1] == '\n')
					if(++k >= count)
						break;
		}
		length-=j;
		buf[0:]=buf[j:j+length];
	}
	if(dir == REV) {
		if(length>0 && buf[length-1]!= byte '\n')
			buf[length++] = byte '\n';
		for(j=length-1 ; j>0; j--)
			if(buf[j-1] == byte '\n') {
				twrite(buf[j:length]);
				if(--count <= 0)
					return;
				length = j;
			}
	}
	if(count > 0 && length > 0)
		twrite(buf[0:length]);
	bout.flush();
}

reverse()	# count backward and print tail of file 
{
	length := 0;
	n := 0;
	buf : array of byte;
	pos := tseek(big 0, sys->SEEKEND);
	bufsize := 0;
	for(first:=1; pos>big 0 && count>0; first=0) {
		if (pos>big BSize)
			n = BSize;
		else
			n = int pos;
		pos -= big n;
		if(length+2*n > bufsize) {
			bufsize += BSize*((length+2*n-bufsize+BSize-1)/BSize);
			tbuf := array[bufsize+1] of byte;
			tbuf[0:] = buf;
			buf = tbuf;
		}
		length += n;
		abuf := array[length] of byte;
		abuf[0:] = buf[0:length];
		buf[n:] = abuf;
		tseek(pos, sys->SEEKSTART);
		if(tread(buf, n) != n)
			fatal("length error");
		if(first && buf[length-1]!= byte '\n')
			buf[length++] = byte '\n';
		for(n=length-1 ; n>0 && count>0; n--)
			if(buf[n-1] == byte '\n') {
				count--;
				if(dir == REV){
					twrite(buf[n:length]);
					bout.flush();
				}
				length = n;
			}
	}
	if(dir == FWD) {
		if (n==0)
			tseek(big 0 , sys->SEEKSTART);
		else
			tseek(pos+big n+big 1, sys->SEEKSTART);
			
		copy();
	} else if(count > 0)
		twrite(buf[0:length]);
	bout.flush();
}


tseek(o : big, p: int) : big
{
	o = sys->seek(file, o, p);
	if(o == big -1)
		fatal("");
	return o;
}


tread(buf: array of byte, n: int): int
{
	r := sys->read(file, buf, n);
	if(r == -1)
		fatal("");
	return r;
}


twrite(buf:array of byte)
{
	str1:= string buf;
	if(bout.puts(str1)!=len str1)
		fatal("");
}


		
fatal(s : string)
{
	sys->fprint(sys->fildes(2), "tail: %s: %r\n", s);
	exit;
}

fail(s : string)
{
	sys->fprint(sys->fildes(2), "tail: %s\n", s);
	exit;
}


usage()
{
	sys->fprint(sys->fildes(2), "usage: tail [-n N] [-c N] [-f] [-r] [+-N[bc][fr]] [file]\n");
	exit;
}


getnumber(s: string) : int
{
	i:=0;
	if (len s == 0) return 0;
	if(s[i]=='-' || s[i]=='+') {
		if (len s == 1)
			return 0;
		i++;
	}
	if(!(s[i]>='0' && s[i]<='9'))
		return 0;
	if(s[0] == '+')
		origin = BEG;
	if(anycount++)
		fail("excess option");
	if (s[0]=='-')
		s=s[1:];
	(count,nil) = str->toint(s,10);
	if(count < 0){	# protect int args (read, fwrite) 
		fail("too big");
	}
	return 1;
}
	
parse(args : list of string) : list of string 
{
	for(; args!=nil ; args = tl args ) {
		hdarg := hd args;
		if(getnumber(hdarg))
			suffix(hdarg);
		else if(len hdarg > 1 && hdarg[0] == '-')
			case (hdarg[1]) {
			 'c' or 'n'=>
				if (hdarg[1]=='c')
					units = CHARS;
				if(len hdarg>2 && getnumber(hdarg[2:]))
					;
				else if(tl args != nil && getnumber(hd tl args)) {
					args = tl args;
				} else
					usage();
			 'r' =>
				dir = REV;
			 'f' =>
				follow++;
			 '-' =>
				args = tl args;
			}
		else
			break;
	}
	return args;
}


suffix(s : string)
{
	i:=0;
	while(i < len s && str->in(s[i],"0123456789+-"))
		i++;
	if (i==len s)
		return;
	if (s[i]=='b')
		if((count*=1024) < 0)
			fail("too big");
	if (s[i]=='c' || s[i]=='b')
		units = CHARS;
	if (s[i]=='l' || s[i]=='c' || s[i]=='b')
		i++;
	if (i<len s){
		case s[i] {
		 'r'=>
			dir = REV;
			return;
		 'f'=>
			follow++;
			return;
		}
	}
	i++;
	if (i<len s)
		usage();
}
