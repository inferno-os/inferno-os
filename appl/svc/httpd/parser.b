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
	Range, Etag, Entity, Private_info: import Httpd;
	Internal, TempFail, Unimp, UnkVers, BadCont, BadReq, Syntax, 
	BadSearch, NotFound, NoSearch , OnlySearch, Unauth, OK : import Httpd;	
include "parser.m";
include "date.m";
	date : Date;
include "alarms.m";
	alarms: Alarms;
	Alarm: import alarms;
include "encoding.m";
	enc: Encoding;
include "rand.m";
	rand: Rand;

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

latin1 := array[] of {
	'¡',
	'¢',
	'£',
	'¤',
	'¥',
	'¦',
	'§',
	'¨',
	'©',
	'ª',
	'«',
	'¬',
	'­',
	'®',
	'¯',
	'°',
	'±',
	'²',
	'³',
	'´',
	'µ',
	'¶',
	'·',
	'¸',
	'¹',
	'º',
	'»',
	'¼',
	'½',
	'¾',
	'¿',
	'À',
	'Á',
	'Â',
	'Ã',
	'Ä',
	'Å',
	'Æ',
	'Ç',
	'È',
	'É',
	'Ê',
	'Ë',
	'Ì',
	'Í',
	'Î',
	'Ï',
	'Ð',
	'Ñ',
	'Ò',
	'Ó',
	'Ô',
	'Õ',
	'Ö',
	'×',
	'Ø',
	'Ù',
	'Ú',
	'Û',
	'Ü',
	'Ý',
	'Þ',
	'ß',
	'à',
	'á',
	'â',
	'ã',
	'ä',
	'å',
	'æ',
	'ç',
	'è',
	'é',
	'ê',
	'ë',
	'ì',
	'í',
	'î',
	'ï',
	'ð',
	'ñ',
	'ò',
	'ó',
	'ô',
	'õ',
	'ö',
	'÷',
	'ø',
	'ù',
	'ú',
	'û',
	'ü',
	'ý',
	'þ',
	'ÿ',
	0,
};

entities :=array[] of {
		Entity( "&#161;",	'¡' ),
		Entity( "&#162;",	'¢' ),
		Entity( "&#163;",	'£' ),
		Entity( "&#164;",	'¤' ),
		Entity( "&#165;",	'¥' ),
		Entity( "&#166;",	'¦' ),
		Entity( "&#167;",	'§' ),
		Entity( "&#168;",	'¨' ),
		Entity( "&#169;",	'©' ),
		Entity( "&#170;",	'ª' ),
		Entity( "&#171;",	'«' ),
		Entity( "&#172;",	'¬' ),
		Entity( "&#173;",	'­' ),
		Entity( "&#174;",	'®' ),
		Entity( "&#175;",	'¯' ),
		Entity( "&#176;",	'°' ),
		Entity( "&#177;",	'±' ),
		Entity( "&#178;",	'²' ),
		Entity( "&#179;",	'³' ),
		Entity( "&#180;",	'´' ),
		Entity( "&#181;",	'µ' ),
		Entity( "&#182;",	'¶' ),
		Entity( "&#183;",	'·' ),
		Entity( "&#184;",	'¸' ),
		Entity( "&#185;",	'¹' ),
		Entity( "&#186;",	'º' ),
		Entity( "&#187;",	'»' ),
		Entity( "&#188;",	'¼' ),
		Entity( "&#189;",	'½' ),
		Entity( "&#190;",	'¾' ),
		Entity( "&#191;",	'¿' ),
		Entity( "&Agrave;",	'À' ),
		Entity( "&Aacute;",	'Á' ),
		Entity( "&Acirc;",	'Â' ),
		Entity( "&Atilde;",	'Ã' ),
		Entity( "&Auml;",	'Ä' ),
		Entity( "&Aring;",	'Å' ),
		Entity( "&AElig;",	'Æ' ),
		Entity( "&Ccedil;",	'Ç' ),
		Entity( "&Egrave;",	'È' ),
		Entity( "&Eacute;",	'É' ),
		Entity( "&Ecirc;",	'Ê' ),
		Entity( "&Euml;",	'Ë' ),
		Entity( "&Igrave;",	'Ì' ),
		Entity( "&Iacute;",	'Í' ),
		Entity( "&Icirc;",	'Î' ),
		Entity( "&Iuml;",	'Ï' ),
		Entity( "&ETH;",	'Ð' ),
		Entity( "&Ntilde;",	'Ñ' ),
		Entity( "&Ograve;",	'Ò' ),
		Entity( "&Oacute;",	'Ó' ),
		Entity( "&Ocirc;",	'Ô' ),
		Entity( "&Otilde;",	'Õ' ),
		Entity( "&Ouml;",	'Ö' ),
		Entity( "&215;",	'×' ),
		Entity( "&Oslash;",	'Ø' ),
		Entity( "&Ugrave;",	'Ù' ),
		Entity( "&Uacute;",	'Ú' ),
		Entity( "&Ucirc;",	'Û' ),
		Entity( "&Uuml;",	'Ü' ),
		Entity( "&Yacute;",	'Ý' ),
		Entity( "&THORN;",	'Þ' ),
		Entity( "&szlig;",	'ß' ),
		Entity( "&agrave;",	'à' ),
		Entity( "&aacute;",	'á' ),
		Entity( "&acirc;",	'â' ),
		Entity( "&atilde;",	'ã' ),
		Entity( "&auml;",	'ä' ),
		Entity( "&aring;",	'å' ),
		Entity( "&aelig;",	'æ' ),
		Entity( "&ccedil;",	'ç' ),
		Entity( "&egrave;",	'è' ),
		Entity( "&eacute;",	'é' ),
		Entity( "&ecirc;",	'ê' ),
		Entity( "&euml;",	'ë' ),
		Entity( "&igrave;",	'ì' ),
		Entity( "&iacute;",	'í' ),
		Entity( "&icirc;",	'î' ),
		Entity( "&iuml;",	'ï' ),
		Entity( "&eth;",	'ð' ),
		Entity( "&ntilde;",	'ñ' ),
		Entity( "&ograve;",	'ò' ),
		Entity( "&oacute;",	'ó' ),
		Entity( "&ocirc;",	'ô' ),
		Entity( "&otilde;",	'õ' ),
		Entity( "&ouml;",	'ö' ),
		Entity( "&247;",	'÷' ),
		Entity( "&oslash;",	'ø' ),
		Entity( "&ugrave;",	'ù' ),
		Entity( "&uacute;",	'ú' ),
		Entity( "&ucirc;",	'û' ),
		Entity( "&uuml;",	'ü' ),
		Entity( "&yacute;",	'ý' ),
		Entity( "&thorn;",	'þ' ),
		Entity( "&yuml;",	'ÿ' ),

		Entity( "&#SPACE;",	' ' ),
		Entity( "&#RS;",	'\n' ),
		Entity( "&#RE;",	'\r' ),
		Entity( "&quot;",	'"' ),
		Entity( "&amp;",	'&' ),
		Entity( "&lt;",	'<' ),
		Entity( "&gt;",	'>' ),

		Entity( "CAP-DELTA",	'Δ' ),
		Entity( "ALPHA",	'α' ),
		Entity( "BETA",	'β' ),
		Entity( "DELTA",	'δ' ),
		Entity( "EPSILON",	'ε' ),
		Entity( "THETA",	'θ' ),
		Entity( "MU",		'μ' ),
		Entity( "PI",		'π' ),
		Entity( "TAU",	'τ' ),
		Entity( "CHI",	'χ' ),

		Entity( "<-",		'←' ),
		Entity( "^",		'↑' ),
		Entity( "->",		'→' ),
		Entity( "v",		'↓' ),
		Entity( "!=",		'≠' ),
		Entity( "<=",		'≤' ),
		Entity( nil, 0 ),
	};


initarray() : array of Entity
{
	return entities;
}

badmodule(p: string)
{
	sys->fprint(sys->fildes(2), "parse: cannot load %s: %r", p);
	raise "fail:bad module";
}

lockch: chan of int;

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

	enc = load Encoding Encoding->BASE64PATH;
	if(enc == nil) badmodule(Encoding->BASE64PATH);

	rand = load Rand Rand->PATH;
	if(rand == nil) badmodule(Rand->PATH);

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


MAXHEADERS: con 100;	# Maximum number of HTTP headers to accept
MAXHDRVAL: con 8192;	# Maximum header value size (8KB)

httpheaders(g: ref Private_info,vers : string)
{
	if(vers == "")
		return;
	g.tok = '\n';
	g.parse_eol = 0;
	g.parse_eoh = 0;
	nhdr := 0;
	# 15 minutes to get request line
	a := Alarm.alarm(15*1000*60);
	while(lex(g) != '\n'){
		nhdr++;
		if(nhdr > MAXHEADERS) {
			a.stop();
			fail(g, BadReq, "too many headers");
		}
		if(g.tok == Word && lex(g) == ':'){
			if (g.dbg_log!=nil)
				sys->fprint(g.dbg_log,"hitting parsejump. wordval is %s\n",
										g.wordval);
			parsejump(g,g.wordval);
		}
		while(g.tok != '\n')
			lex(g);
		g.parse_eol = g.parse_eoh;
	}
	a.stop();
	# check whether http1.1 and Host has been set, else error
}

mimeparams(g: ref Private_info): list of (string, string)
{
	l : list of (string, string);
	for(;;){
		if(lex(g) != Word)
			break;
		s := g.wordval;
		if(lex(g) != Word)
			break;
		l = (s, g.wordval) :: l;
	}
	return l;
}

mimefields(g: ref Private_info): list of (string, list of (string, string))
{
	f: list of (string, list of (string, string));

	loop: for(;;){
		while(lex(g) != Word)
			if(g.tok != ',')
				break loop;
		if(lex(g) == ';')
			f = (g.wordval, mimeparams(g)) :: f;
		else
			f = (g.wordval, nil) :: f;
		if(g.tok != ',')
			break;
	}
	return f;
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

http11(g: ref Private_info): int
{
	return g.vermaj > 1 || g.vermaj == 1 && g.vermin > 0;
}

mimeboundary(nil: ref Private_info): string
{
	# Seed from /dev/random for better entropy; fall back to time+pid
	seed := 0;
	rfd := sys->open("/dev/random", sys->OREAD);
	if(rfd != nil) {
		buf := array[4] of byte;
		if(sys->read(rfd, buf, 4) == 4)
			seed = (int buf[0] << 24) | (int buf[1] << 16) |
				(int buf[2] << 8) | int buf[3];
		rfd = nil;
	}
	if(seed == 0)
		seed = daytime->now() << 16 | sys->pctl(0, nil);
	rand->init(seed);
	s := "upas-";
	for(i:=5; i < 32; i++)
		s[i] = 'a' + rand->rand(26);
	return s;
}

mimeconnection(g: ref Private_info, nil: string)
{
	loop: for(;;){
		while(lex(g) != Word)
			if(g.tok != ',')
				break loop;

		if(g.wordval == "keep-alive")
			g.persist = 1;
		else if(g.wordval == "close")
			g.closeit = 1;	
		else if(!http11(g))
			; 

		if(lex(g) != ',')
			break;
	}
}

mimeaccept(g: ref Private_info,name : string)
{
	g.oktype = mimeok(g,name, 1, g.oktype);
}

mimeacceptchar(g: ref Private_info, name: string)
{
	g.okchar = mimeok(g, name, 0, g.okchar);
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
	g.ifmodsince = date->date2sec(g.wordval);
	if (g.dbg_log!=nil){
		sys->fprint(g.dbg_log,"modtime %d\n",g.ifmodsince);
	}
	if(g.ifmodsince == 0)
		logit(g,sys->sprint("%s: %s", name, g.wordval));
}

mimeunmodified(g: ref Private_info, nil: string)
{
	lexhead(g);
	g.ifunmodsince = date->date2sec(g.wordval);
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

mimematch(g: ref Private_info, nil: string)
{
	g.ifmatch = mimeetag(g, g.ifmatch);
}

mimenomatch(g: ref Private_info, nil: string)
{
	g.ifnomatch = mimeetag(g, g.ifnomatch);
}

mimeifrange(g: ref Private_info, nil: string)
{
	et := 0;
	c := getc(g);
	while(c == ' ' || c == '\t')
		c = getc(g);
	if(c == '"')
		et = 1;
	else if(c == 'W'){
		d := getc(g);
		if(d == '/')
			et = 1;
		ungetc(g);
	}
	ungetc(g);
	if(et){
		g.ifrangeetag = mimeetag(g, g.ifrangeetag);
	}else{
		lexhead(g);
		g.ifrangedate = date->date2sec(g.wordval);
	}
}

mimeauthorization(g: ref Private_info, nil: string)
{
	if(lex(g) != Word || g.wordval != "basic")
		return;
	n := lexbase64(g);
	if(n == 0)
		return;
	s := string enc->dec(g.wordval);
	(p, q) := str->splitl(s, ":");
	if(q != nil)
		(g.authuser, g.authpass) = (p, q[1:]);
}

mimerange(g: ref Private_info, nil: string)
{
	g.range = mimeranges(g, g.range);
}

mimeetag(g: ref Private_info, head: list of Etag): list of Etag
{
	for(;;){
		while(lex(g) != Word)
			if(g.tok != ',')
				return head;
	
		weak := 0;
		if(g.tok == Word && g.wordval != "*"){
			if(g.wordval != "W")
				return head;
			if(lex(g) != '/' || lex(g) != Word)
				return head;
			weak = 1;
		}

		e := Etag(g.wordval, weak);
		head = e :: head;
		if(lex(g) != ',')
			return head;
	}
	return head;
}

mimeranges(g: ref Private_info, head: list of Range): list of Range
{
	r: Range;
	if(lex(g) != Word || g.wordval != "bytes" || lex(g) != '=')
		return head;
	loop: for(;;) {
		while(lex(g) != Word){
			if(g.tok != ','){
				if(g.tok == '\n')
					break loop;
				return head;
			}
		}
		w := g.wordval;
		start := 0;
		suf := 1;
		if(w[0] != '-'){
			suf = 0;
			(start, w) = str->toint(w, 10);
			if(w != nil && w[0] != '-')
				return head;
		}
		w = w[1:];
		stop := ~0;
		if(w != nil){
			(stop, w) = str->toint(w, 10);
			if(w != nil)
				return head;
			if(!suf && stop < start)
				return head;
		}
		r = Range(suf, start, stop);
		if(lex(g) != ','){
			if(g.tok == '\n')
				break;
			return head;
		}
	}
	return r :: head;
}

mimetransenc(g: ref Private_info, nil: string)
{
	g.transenc = mimefields(g);
}

mimeexpect(g: ref Private_info, nil: string)
{
	if(lex(g) != Word || g.wordval != "100-continue" || lex(g) != '\n')
		g.expectother = 1;
	g.expectcont = 1;
}

mimefresh(g: ref Private_info, nil: string)
{
	lex(g);
	s := str->drop(g.wordval, " \t");
	if(s == "pathstat/")
		(g.fresh_thresh, nil) = str->toint(s[9:], 10);
	else if(s == "have/")
		(g.fresh_have, nil) = str->toint(s[5:], 10);
}

parsejump(g: ref Private_info,k : string)
{
	case k { 
	"accept" =>		
		mimeaccept(g,k);
	"accept-charset" =>
		mimeacceptchar(g, k);
	"accept-encoding" =>	
		mimeacceptenc(g,k);
	"accept-language" =>	
		mimeacceptlang(g,k);
	"authorization" =>
		mimeauthorization(g, k);
	"connection" =>
		mimeconnection(g, k);
	"content-length" =>
		mimeclength(g,k);
	"content-type" =>
		mimectype(g,k);
	"expect" =>
		mimeexpect(g, k);
	"fresh" =>
		mimefresh(g, k);
	"from" =>		
		mimefrom(g,k);
	"host" =>		
		mimehost(g,k);
	"if-match" =>
		mimematch(g, k);
	"if-none-match" =>
		mimenomatch(g, k);
	"if-modified-since" =>	
		mimemodified(g,k);
	"if-unmodified-since" =>
		mimeunmodified(g,k);
	"if-range" =>
		mimeifrange(g, k);
	"user-agent" =>		
		mimeagent(g,k);
	"range" =>
		mimerange(g, k);
	"referer" =>		
		mimereferer(g,k);
	"transfer-encoding" =>
		mimetransenc(g, k);
	"chargeto" or "forwarded" or
	"pragma" or "proxy-agent" or "proxy-connection" or
	"x-afs-tokens" or "x-serial-number" =>	
		mimeignore(g,k);
	* =>				
		mimeunknown(g,k);
	};	
}


lexbase64(g: ref Private_info): int
{
	n := 0;
	lex1(g, 1);
	s : string;
	while((c := getc(g)) >= 0){
		if(!(c >= 'A' && c <= 'Z'
		|| c >= 'a' && c <= 'z'
		|| c >= '0' && c <= '9'
		|| c == '+' || c == '/')){
			ungetc(g);
			break;
		}
		s[n++] = c;
	}
	g.wordval = s;
	return n;
}

lex(g: ref Private_info): int
{
	g.tok = lex1(g, 0);
	return g.tok;
}


# rfc 822/rfc 1521 lexical analyzer
lex1(g: ref Private_info, skipwhite: int): int
{
	level, c : int;
	if(g.parse_eol)
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
					g.parse_eol = 1;
					g.parse_eoh = 1;
					return '\n';
				}
				c = getc(g);
				if(c == Bufio->EOF){
					g.parse_eol = 1;
					return '\n';
				}
				if(c != ' ' && c != '\t'){
					ungetc(g);
					g.parse_eol = 1;
					return '\n';
				}
			')' or '<' or '>' or '[' or ']' or '@' or '/' or ',' 
			or ';' or ':' or '?' or '=' =>
				if(skipwhite){
					ungetc(g);
					return c;
				}
				return c;

	 		'"' =>
				if(skipwhite){
					ungetc(g);
					return c;
				}
				word(g,"\"");
				getc(g);		# skip the closing quote 
				return Word;

	 		* =>
				ungetc(g);
				if(skipwhite)
					return c;
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
		if(n >= MAXHDRVAL) {
			# Discard remaining header value to prevent memory exhaustion
			while((c = getc(g)) != Bufio->EOF && c != '\n')
				;
			break;
		}
		g.wordval[n++] = c;
	}
	g.tok = '\n';
	g.parse_eol = 1;
	g.wordval= g.wordval[0:n];
}

MAXWORD: con 16384;  # Maximum word length to prevent DoS

word(g: ref Private_info,stop : string)
{
	c : int;
	n := 0;
	while((c = getc(g)) != Bufio->EOF){
		if(n >= MAXWORD){
			g.wordval = g.wordval[0:n];
			return;
		}
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
	if(g.parse_eoh)
		return -1;
	c := g.bufio->g.bin.getc();
	if(c == Bufio->EOF){
		g.parse_eol = 1;
		g.parse_eoh = 1;
		return c;
	}
	return c & 16r7f;
}

ungetc(g: ref Private_info) {
	if(g.parse_eoh)
		return;
	# this is a dirty hack, I am tacitly assuming that characters read
	# from stdin will be ASCII.....
	g.bufio->g.bin.ungetc();
}

# go from url with latin1 and escapes to utf 

urlunesc(s : string): string
{
	c, n : int;
	t : string;
	for(i := 0;i<len s ; i++){
		c = int s[i];
		if(c == '%'){
			if(i + 2 >= len s)
				break;
			n = int s[i+1];
			if(n >= '0' && n <= '9')
				n = n - '0';
			else if(n >= 'A' && n <= 'F')
				n = n - 'A' + 10;
			else if(n >= 'a' && n <= 'f')
				n = n - 'a' + 10;
			else
				break;
			c = n;
			n = int s[i+2];
			if(n >= '0' && n <= '9')
				n = n - '0';
			else if(n >= 'A' && n <= 'F')
				n = n - 'A' + 10;
			else if(n >= 'a' && n <= 'f')
				n = n - 'a' + 10;
			else
				break;
			i += 2;
			c = c * 16 + n;
		}
		else if( c == '+' )
			c = ' ';
		t[len t] = c;
	}
	return t;
}


#  go from http with latin1 escapes to utf,
# we assume that anything >= Runeself is already in utf

httpunesc(g: ref Private_info,s : array of byte): string
{
	t,v: string;
	c,i : int;
	# convert bytes to a string.
	v = string s;
	for(i=0; i < len v;i++){
		c = v[i];
		if(c == '&'){
			if(v[1] == '#' && v[2] && v[3] && v[4] && v[5] == ';'){
				c = 100*(v[2])+10*(v[3])+(v[4]);
				if(c < Runeself){
					t[len t] = c;
					i += 6;
					continue;
				}
				if(c < 256 && c >= 161){
					t[len t] = g.entity[c-161].value;
					i += 6;
					continue;
				}
			} else {
				for(j:= 0;g.entity[j].name != nil; j++)
					if(g.entity[j].name == v[i+1:])
				# problem here cvert array of byte to string?
						break;
				if(g.entity[j].name != nil){
					i += len g.entity[j].name;
					t[len t] = g.entity[j].value;
					continue;
				}
			}
		}
		t[len t] = c;
	}
	return t;
}


# Escape HTML special characters to prevent XSS
htmlescape(s: string): string
{
	t := "";
	for(i := 0; i < len s; i++) {
		case s[i] {
		'&' =>
			t += "&amp;";
		'<' =>
			t += "&lt;";
		'>' =>
			t += "&gt;";
		'"' =>
			t += "&quot;";
		'\'' =>
			t += "&#39;";
		* =>
			t[len t] = s[i];
		}
	}
	return t;
}

# write a failure message to the net and exit
fail(g: ref Private_info,reason : int, message : string)
{
	verb : string;
	escmsg := htmlescape(message);
	title:=sys->sprint("<head><title>%s</title></head>\n<body bgcolor=#ffffff>\n",
					errormsg[reason].concise);
	body1:=	"<h1> Error </h1>\n<P>" +
		"Sorry, Charon is unable to process your request. The webserver reports"+
		" the following error <P><b>";
	#concise error
	body2:="</b><p>for the URL\n<P><b>";
	#message (HTML-escaped)
	body3:="</b><P>with the following reason:\n<P><b>";
	#reason
	if (str->in('%',errormsg[reason].verbose)){
		(v1,v2):=str->splitl(errormsg[reason].verbose,"%");
		verb=v1+escmsg+v2[2:];
	}else
		verb=errormsg[reason].verbose;
	body4:="</b><hr> This Webserver powered by  DRIED DUNG<br>"+
		"For more information  <a href=\"http://caerwyn.com\"> caerwyn.com </a>\n"+
		"<hr><address>\n";
	dtime:=sys->sprint("This information processed at %s.\n",daytime->time());
	body5:="</address>\n</body>\n";
	strbuf:=title+body1+errormsg[reason].concise+body2+escmsg+body3+
		verb+body4+dtime+body5;
	if (g.bout!=nil && reason!=2){
		g.bufio->g.bout.puts(sys->sprint("%s %s\r\n", g.version, errormsg[reason].num));
		g.bufio->g.bout.puts(sys->sprint("Date: %s\r\n", daytime->time()));
		g.bufio->g.bout.puts("Server: Charon\r\n");
		g.bufio->g.bout.puts("MIME-version: 1.0\r\n");
		g.bufio->g.bout.puts("Content-Type: text/html\r\n");
		g.bufio->g.bout.puts(sys->sprint("Content-Length: %d\r\n", len strbuf));
		g.bufio->g.bout.puts("\r\n");
		g.bufio->g.bout.puts(strbuf);
		g.bufio->g.bout.flush();
	}
	logit(g,sys->sprint("failing: %s", errormsg[reason].num));
	clf(g, int errormsg[reason].num, 0);
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
	sys->fprint(g.logfile,"%s %s\n", g.remotesys, message);
}

urlconv(p : string): string
{
	c : int;
	t : string;
	for(i:=0;i<len p ;i++){
		c = p[i];
		if(c == 0)
			break;
		if(c <= ' ' || c == '%' || c >= Runeself){
			t += sys->sprint("%%%2.2x", c);
		} else {
			t[len t] = c;
		}
	}
	return t; 
}


month := array[] of {
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
};

# sample common log file format
# 127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /index.html HTTP/1.0" 200 2326

clf(g: ref Private_info, status, length: int)
{
	tm := daytime->local(daytime->now());
	t := sys->sprint("[%.2d/%s/%d:%.2d:%.2d:%.2d %.2d00]",
		tm.mday, month[tm.mon], tm.year+1900, tm.hour, tm.min, tm.sec, tm.tzoff/60/60);
	user := "-";
	if(g.authuser != nil)
		user = g.authuser;
	req := sys->sprint("%s %s HTTP/%d.%d", g.meth, g.requri, g.vermaj, g.vermin);
	sys->fprint(g.accesslog, "%s - %s %s \"%s\" %d %d\n", 
	g.remotesys, user, t, req, status, length);
}
