implement Parser;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
include "bufio.m";
include "string.m";
	str: String;
include "daytime.m";
	daytime: Daytime;
include "contents.m";
	contents : Contents;
	Content: import contents;
include "cache.m";
include "httpd.m";
	Private_info: import Httpd;
	Internal, TempFail, Unimp, UnkVers, BadCont, BadReq, Syntax, 
	BadSearch, NotFound, NoSearch , OnlySearch, Unauth, OK : import Httpd;	
include "parser.m";
include "date.m";
	date : Date;
include "alarms.m";
	alarms: Alarms;
	Alarm: import alarms;
include "lock.m";
	locks: Lock;
	Semaphore: import locks;

Error: adt {
	num : string;
	concise: string;
	verbose: string;
};

errormsg := array[] of {
	Internal => Error("500 Internal Error", "Internal Error",
		"This server could not process your request due to an interal error."),
	TempFail =>	Error("500 Internal Error", "Temporary Failure",
		"The object %s is currently inaccessible.<p>Please try again later."),
	Unimp =>	Error("501 Not implemented", "Command not implemented",
		"This server does not implement the %s command."),
	UnkVers =>	Error("501 Not Implemented", "Unknown http version",
		"This server does not know how to respond to http version %s."),
	BadCont =>	Error("501 Not Implemented", "Impossible format",
		"This server cannot produce %s in any of the formats your client accepts."),
	BadReq =>	Error("400 Bad Request", "Strange Request",
		"Your client sent a query that this server could not understand."),
	Syntax =>	Error("400 Bad Request", "Garbled Syntax",
		"Your client sent a query with incoherent syntax."),
	BadSearch =>Error("400 Bad Request", "Inapplicable Search",
		"Your client sent a search that cannot be applied to %s."),
	NotFound =>Error("404 Not Found", "Object not found",
		"The object %s does not exist on this server."),
	NoSearch =>	Error("403 Forbidden", "Search not supported",
		"The object %s does not support the search command."),
	OnlySearch =>Error("403 Forbidden", "Searching Only",
		"The object %s only supports the searching methods."),
	Unauth =>	Error("401 Unauthorized", "Unauthorized",
		"You are not authorized to see the object %s."),
	OK =>	Error("200 OK", "everything is fine","Groovy man"),
};	

badmodule(p: string)
{
	sys->fprint(sys->fildes(2), "parse: cannot load %s: %r", p);
	raise "fail:bad module";
}

lock: ref Semaphore;

init()
{
	sys = load Sys Sys->PATH;

	date = load Date Date->PATH;
	if (date==nil) badmodule(Date->PATH);

	daytime = load Daytime Daytime->PATH;
	if(daytime == nil) badmodule(Daytime->PATH);

	contents = load Contents Contents->PATH;
	if(contents == nil) badmodule(Contents->PATH);

	str = load String String->PATH;
	if(str == nil) badmodule(String->PATH);

	alarms = load Alarms Alarms->PATH;
	if(alarms == nil) badmodule(Alarms->PATH);

	locks = load Lock Lock->PATH;
	if(locks == nil) badmodule(Lock->PATH);
	locks->init();
	lock = Semaphore.new();
	date->init();
}

atexit(g: ref Private_info)
{
	if (g.dbg_log!=nil){
		sys->fprint(g.dbg_log,"At exit from parse, closing fds. \n");
	}
	if (g.bin!=nil)
		g.bufio->g.bin.close();
	if (g.bout!=nil)
		g.bufio->g.bout.close();
	g.bin=nil;
	g.bout=nil;
	exit;
}


httpheaders(g: ref Private_info,vers : string)
{
	if(vers == "")
		return;
	g.tok = '\n';
	# 15 minutes to get request line
	a := Alarm.alarm(15*1000*60); 
	while(lex(g) != '\n'){
		if(g.tok == Word && lex(g) == ':'){
			if (g.dbg_log!=nil)
				sys->fprint(g.dbg_log,"hitting parsejump. wordval is %s\n",
										g.wordval);
			parsejump(g,g.wordval);
		}
		while(g.tok != '\n')
			lex(g);
	}
	a.stop();
}


mimeok(g: ref Private_info,name : string,multipart : int,head : list of ref Content): list of ref Content
{

	generic, specific, s : string;
	v : real;

	while(lex(g) != Word)
		if(g.tok != ',')
			return head;

	generic = g.wordval;
	lex(g);
	if(g.tok == '/' || multipart){
		if(g.tok != '/')
			return head;
		if(lex(g) != Word)
			return head;
		specific = g.wordval;
		lex(g);
	}else
		specific = "*";
	tmp := contents->mkcontent(generic, specific);
	head = tmp::head;
	for(;;){
		case g.tok {
		';' =>
			if(lex(g) == Word){
				s = g.wordval;
				if(lex(g) != '=' || lex(g) != Word)
					return head;
				v = 3.14; # should be strtof(g.wordval, nil);
				if(s=="q")
					tmp.q = v;
				else
					logit(g,sys->sprint(
						"unknown %s param: %s %s",
						name, s, g.wordval));
			}
			break;
		',' =>
			return  mimeok(g,name, multipart,head);
		* =>
			return head;
		}
		lex(g);
	}
	return head;
}

mimeaccept(g: ref Private_info,name : string)
{
	g.oktype = mimeok(g,name, 1, g.oktype);
}

mimeacceptenc(g: ref Private_info,name : string)
{
	g.okencode = mimeok(g,name, 0, g.okencode);
}

mimeacceptlang(g: ref Private_info,name : string)
{
	g.oklang = mimeok(g,name, 0, g.oklang);
}

mimemodified(g: ref Private_info,name : string)
{
	lexhead(g);
	g.modtime = date->date2sec(g.wordval);
	if (g.dbg_log!=nil){
		sys->fprint(g.dbg_log,"modtime %d\n",g.modtime);
	}
	if(g.modtime == 0)
		logit(g,sys->sprint("%s: %s", name, g.wordval));
}


mimeagent(g: ref Private_info,nil : string)
{
	lexhead(g);
	g.client = g.wordval;
}

mimefrom(g: ref Private_info,nil : string)
{
	lexhead(g);
}


mimehost(g: ref Private_info,nil : string)
{
	h : string;
	lexhead(g);
	(nil,h)=str->splitr(g.wordval," \t");
	g.host = h;
}

mimereferer(g: ref Private_info,nil : string)
{
	h : string;
	lexhead(g);
	(nil,h)=str->splitr(g.wordval," \t");
	g.referer = h;
}

mimeclength(g: ref Private_info,nil : string)
{
	h : string;
	lexhead(g);
	(nil,h)=str->splitr(g.wordval," \t");
	g.clength = int h;
}

mimectype(g: ref Private_info,nil : string)
{
	h : string;
	lexhead(g);
	(nil,h)=str->splitr(g.wordval," \t");
	g.ctype = h;
}


mimeignore(g: ref Private_info,nil : string)
{
	lexhead(g);
}


mimeunknown(g: ref Private_info,name : string)
{
	lexhead(g);
	if(g.client!="")
		logit(g,sys->sprint("agent %s: ignoring header %s: %s ", 
			g.client, name, g.wordval));
	else
		logit(g,sys->sprint("ignoring header %s: %s", name, g.wordval));
}


parsejump(g: ref Private_info,k : string)
{
	case k { 

	"from" =>		
		mimefrom(g,k);
	"if-modified-since" =>	
		mimemodified(g,k);
	"accept" =>		
		mimeaccept(g,k);
	"accept-encoding" =>	
		mimeacceptenc(g,k);
	"accept-language" =>	
		mimeacceptlang(g,k);
	"user-agent" =>		
		mimeagent(g,k);
	"host" =>		
		mimehost(g,k);
	"referer" =>		
		mimereferer(g,k);
	"content-length" =>
		mimeclength(g,k);
	"content-type" =>
		mimectype(g,k);
	"authorization" or "chargeto" or "connection" or "forwarded" or
	"pragma" or "proxy-agent" or "proxy-connection" or
	"x-afs-tokens" or "x-serial-number" =>	
		mimeignore(g,k);
	* =>				
		mimeunknown(g,k);
	};	
}

lex(g: ref Private_info): int
{
	g.tok = lex1(g);
	return g.tok;
}


# rfc 822/rfc 1521 lexical analyzer
lex1(g: ref Private_info): int
{
	level, c : int;
	if(g.parse_eof)
		return '\n';

# top:
	for(;;){
		c = getc(g);
		case c {
			 '(' =>
				level = 1;
				while((c = getc(g)) != Bufio->EOF){
					if(c == '\\'){
						c = getc(g);
						if(c == Bufio->EOF)
							return '\n';
						continue;
					}
					if(c == '(')
						level++;
					else if(c == ')' && level == 1){
						level--;
						break;
					}
					else if(c == '\n'){
						c = getc(g);
						if(c == Bufio->EOF)
							return '\n';
							break;
						if(c != ' ' && c != '\t'){
							ungetc(g);
							return '\n';
						}
					}
				}
	 		' ' or '\t' or '\r' =>
				break;
	 		'\n' =>
				if(g.tok == '\n'){
					g.parse_eof = 1;
					return '\n';
				}
				c = getc(g);
				if(c == Bufio->EOF)
					return '\n';
				if(c != ' ' && c != '\t'){
					ungetc(g);
					return '\n';
				}
			')' or '<' or '>' or '[' or ']' or '@' or '/' or ',' 
			or ';' or ':' or '?' or '=' =>
				return c;

	 		'"' =>
				word(g,"\"");
				getc(g);		# skip the closing quote 
				return Word;

	 		* =>
				ungetc(g);
				word(g,"\"()<>@,;:/[]?=\r\n \t");
				return Word;
			}
	}
	return 0;	
}

# return the rest of an rfc 822, not including \r or \n
# do not map to lower case

lexhead(g: ref Private_info)
{
	c, n: int;
	n = 0;
	while((c = getc(g)) != Bufio->EOF){
		if(c == '\r')
			c = wordcr(g);
		else if(c == '\n')
			c = wordnl(g);
		if(c == '\n')
			break;
		if(c == '\\'){
			c = getc(g);
			if(c == Bufio->EOF)
				break;
		}
		g.wordval[n++] = c;
	}
	g.tok = '\n';
	g.wordval= g.wordval[0:n];
}

word(g: ref Private_info,stop : string)
{
	c : int;
	n := 0;
	while((c = getc(g)) != Bufio->EOF){
		if(c == '\r')
			c = wordcr(g);
		else if(c == '\n')
			c = wordnl(g);
		if(c == '\\'){
			c = getc(g);
			if(c == Bufio->EOF)
				break;
		}else if(str->in(c,stop)){
				ungetc(g);
				g.wordval = g.wordval[0:n];	
				return;
			}
		if(c >= 'A' && c <= 'Z')
			c += 'a' - 'A';
		g.wordval[n++] = c;
	}
	g.wordval = g.wordval[0:n];
	# sys->print("returning from word");
}


wordcr(g: ref Private_info): int
{
	c := getc(g);
	if(c == '\n')
		return wordnl(g);
	ungetc(g);
	return ' ';
}


wordnl(g: ref Private_info): int
{
	c := getc(g);
	if(c == ' ' || c == '\t')
		return c;
	ungetc(g);
	return '\n';
}


getc(g: ref Private_info): int
{
	c := g.bufio->g.bin.getc();
	if(c == Bufio->EOF){
		g.parse_eof = 1;
		return c;
	}
	return c & 16r7f;
}

ungetc(g: ref Private_info)
{
	# this is a dirty hack, I am tacitly assuming that characters read
	# from stdin will be ASCII.....
	g.bufio->g.bin.ungetc();
}

# go from url with ascii and %xx escapes to unicode, allowing for existing unencoded utf-8

urlunesc(s : string): string
{
	a := array[Sys->UTFmax*len s] of byte;
	o := 0;
	for(i := 0; i < len s; i++){
		c := int s[i];
		if(c < Runeself){
			if(c == '%' && i+2 < len s){
				d0 := hex(int s[i+1]);
				if(d0 >= 0){
					d1 := hex(int s[i+2]);
					if(d1 >= 0){
						i += 2;
						c = d0*16 + d1;
					}
				}
			} else if(c == '+'  || c == 0)
				c = ' ';
			a[o++] = byte c;
		}else
			o += sys->char2byte(c, a, o);
	}
	return string a[0: o];
}

hex(c: int): int
{
	if(c >= '0' && c <= '9')
		return c-'0';
	if(c >= 'a' && c <= 'f')
		return c-'a' + 10;
	if(c >= 'A' && c <= 'F')
		return c-'A' + 10;
	return -1;
}

# write a failure message to the net and exit
fail(g: ref Private_info,reason : int, message : string)
{
	verb : string;
	title:=sys->sprint("<head><title>%s</title></head>\n<body bgcolor=#ffffff>\n",
					errormsg[reason].concise);
	body1:=	"<h1> Error </h1>\n<P>" +
		"Sorry, Charon is unable to process your request. The webserver reports"+
		" the following error <P><b>";
	#concise error
	body2:="</b><p>for the URL\n<P><b>";
	#message
	body3:="</b><P>with the following reason:\n<P><b>";
	#reason
	if (str->in('%',errormsg[reason].verbose)){
		(v1,v2):=str->splitl(errormsg[reason].verbose,"%");
		verb=v1+message+v2[2:];
	}else
		verb=errormsg[reason].verbose;
	body4:="</b><hr> This Webserver powered by <img src=\"/inferno.gif\">. <P>"+
		"For more information click <a href=\"http://inferno.lucent.com\"> here </a>\n"+
		"<hr><address>\n";
	dtime:=sys->sprint("This information processed at %s.\n",daytime->time());
	body5:="</address>\n</body>\n";
	strbuf:=title+body1+errormsg[reason].concise+body2+message+body3+
		verb+body4+dtime+body5;
	if (g.bout!=nil && reason!=2){
		g.bufio->g.bout.puts(sys->sprint("%s %s\r\n", g.version, errormsg[reason].num));
		g.bufio->g.bout.puts(sys->sprint("Date: %s\r\n", daytime->time()));
		g.bufio->g.bout.puts(sys->sprint("Server: Charon\r\n"));
		g.bufio->g.bout.puts(sys->sprint("MIME-version: 1.0\r\n"));
		g.bufio->g.bout.puts(sys->sprint("Content-Type: text/html\r\n"));
		g.bufio->g.bout.puts(sys->sprint("Content-Length: %d\r\n", len strbuf));
		g.bufio->g.bout.puts(sys->sprint("\r\n"));
		g.bufio->g.bout.puts(strbuf);
		g.bufio->g.bout.flush();
	}
	logit(g,sys->sprint("failing: %s", errormsg[reason].num));
	atexit(g);
}


# write successful header
 
okheaders(g: ref Private_info)
{
	g.bufio->g.bout.puts(sys->sprint("%s 200 OK\r\n", g.version));
	g.bufio->g.bout.puts("Server: Charon\r\n");
	g.bufio->g.bout.puts("MIME-version: 1.0\r\n");
}

notmodified(g: ref Private_info)
{
	g.bufio->g.bout.puts(sys->sprint("%s 304 Not Modified\r\n", g.version));
	g.bufio->g.bout.puts("Server: Charon\r\n");
	g.bufio->g.bout.puts("MIME-version: 1.0\r\n\r\n");
	atexit(g);
}

logit(g: ref Private_info,message : string )
{
	lock.obtain();
	sys->fprint(g.logfile,"%s %s\n", g.remotesys, message);
	lock.release();
}

urlconv(p : string): string
{
	a := array[Sys->UTFmax] of byte;
	t := "";
	for(i := 0; i < len p; i++){
		c := p[i];
		if(c == 0)
			continue;	# ignore nul bytes
		if(c >= Runeself){	# convert to UTF-8
			n := sys->char2byte(c, a, 0);
			for(j := 0; j < n; j++)
				t += sys->sprint("%%%.2X", int a[j]);
		}else if(c <= ' ' || c == '%'){
			t += sys->sprint("%%%2.2X", c);
		} else {
			t[len t] = c;
		}
	}
	return t; 
}
