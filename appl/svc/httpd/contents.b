implement Contents;

include "sys.m";
	sys: Sys;
	dbg_log : ref Sys->FD;
include "draw.m";

include "bufio.m";
	bufio: Bufio;
Iobuf : import bufio;
	
include "contents.m";

include "cache.m";

include "httpd.m";

include "string.m";
	str : String;

Suffix: adt{
	suffix : string;
	generic : string;
	specific : string;
	encoding : string;
};

suffixes: list of Suffix;

#internal functions...
parsesuffix : fn(nil:string): (int,Suffix);

mkcontent(generic,specific : string): ref Content
{
	c:= ref Content; 	
	c.generic = generic;
	c.specific = specific;
	c.q = real 1;
	return c;
}

badmod(m: string)
{
	sys->fprint(stderr(), "contents: cannot load %s: %r\n", m);
	raise "fail:bad module";
}

contentinit(log: ref Sys->FD)
{
	if(suffixes != nil)
		return;

	sys = load Sys Sys->PATH;

	bufio = load Bufio Bufio->PATH;
	if (bufio == nil) badmod(Bufio->PATH);

	str = load String String->PATH;
	if (str == nil) badmod(String->PATH);

	iob := bufio->open(Httpd->HTTP_SUFF, bufio->OREAD);
	if (iob==nil) {
		sys->fprint(stderr(), "contents: cannot open %s: %r\n", Httpd->HTTP_SUFF);
		raise "fail:no suffix file";;
	}
	while((s := iob.gets('\n'))!=nil) {
		(i, su) := parsesuffix(s);
		if (i != 0)
			suffixes =  su :: suffixes;
	}
	dbg_log = log;
}

# classify by file name extensions

uriclass(name : string): (ref Content, ref Content)
{
	s : Suffix;
	typ, enc: ref Content;
	p : string;
	lis := suffixes;
	typ=nil;
	enc=nil;
	uri:=name;
	(nil,p) = str->splitr(name,"/");
	if (p!=nil) name=p;

	if(str->in('.',name)){
		(nil,p) = str->splitl(name,".");
		for(s = hd lis; lis!=nil; lis = tl lis){
			if(p == s.suffix){	
				if(s.generic != nil && typ==nil)
					typ = mkcontent(s.generic, s.specific);
				if(s.encoding != nil && enc==nil)
					enc = mkcontent(s.encoding, "");
			}
		s = hd lis;
		}
	}
	if(typ == nil && enc == nil){
		buff := array[64] of byte;
		fd := sys->open(uri, sys->OREAD);
		n := sys->read(fd, buff, len buff);
		if(n > 0){
			tmp := string buff[0:n];
			(typ, enc) = dataclass(tmp);
		}
	}
	return (typ, enc);
}


parsesuffix(line: string): (int, Suffix)
{
	s : Suffix;	
	if (str->in('#',line))
		(line,nil) = str->splitl(line, "#");
	if (line!=nil){
		(n,slist):=sys->tokenize(line,"\n\t ");
		if (n!=4 && n!=0){
			if (dbg_log!=nil)
				sys->fprint(dbg_log,"Error in suffixes file!, n=%d\n",n);
			sys->print("Error in suffixes file!, n=%d\n",n);
			exit;
		}
		s.suffix = hd slist;
		slist = tl slist;
		s.generic = hd slist;
		if (s.generic == "-") s.generic="";	
		slist = tl slist;
		s.specific = hd slist;
		if (s.specific == "-") s.specific="";	
		slist = tl slist;
		s.encoding = hd slist;
		if (s.encoding == "-") s.encoding="";
		
	}
	if (((s.generic ==  "")||(s.specific ==  "")) && s.encoding=="")
		return (0,s);
	return (1,s);
}

#classify by initial contents of file
dataclass(buf : string): (ref Content,ref Content)
{
	c,n : int;
	c=0;
	n = len buf;
	for(; n > 0; n --){		
		if(buf[c] < 16r80)
			if(buf[c] < 32 && buf[c] != '\n' && buf[c] != '\r' 
					&& buf[c] != '\t' && buf[c] != '\v')
				return (nil,nil);
		c++;		
	}
	return (mkcontent("text", "plain"),nil);
}

checkcontent(me: ref Content,oks :list of ref Content, clist : string): int
{
	ok:=oks;
	try : ref Content;
	if(oks == nil || me == nil)
		return 1;
	for(; ok != nil; ok = tl ok){
		try = hd ok;
		if((try.generic==me.generic || try.generic=="*")
		&& (try.specific==me.specific || try.specific=="*")){
			return 1;
		}
	}

	sys->fprint(dbg_log,"%s/%s not found", 
				me.generic, me.specific);
	logcontent(clist, oks);
	return 1;
}

logcontent(name : string, c : list of ref Content)
{
	buf : string;
	if (dbg_log!=nil){
		for(; c!=nil; c = tl c)
			buf+=sys->sprint("%s/%s ", (hd c).generic,(hd c).specific);
		sys->fprint(dbg_log,"%s: %s: %s", "client", name, buf);
	}
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}
