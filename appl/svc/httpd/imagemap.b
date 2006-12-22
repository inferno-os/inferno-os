implement imagemap;

include "sys.m";
	sys : Sys;

include "bufio.m";
	bufio: Bufio;
	Iobuf: 	import bufio;

include "draw.m";
	draw: Draw;

include "cache.m";
include "contents.m";

include "httpd.m";
	Private_info: import Httpd;
	OnlySearch, BadSearch, NotFound: import Httpd;
	g : ref Private_info;

include "parser.m";
	parser : Parser;

include "daytime.m";
	daytime: Daytime;

include "string.m";
	str : String;

imagemap : module
{
	init: fn(g : ref Private_info, req: Httpd->Request);
};

Point : adt {
	x,y : int;
};

me : string;

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "imagemap: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init(k : ref Private_info, req: Httpd->Request)
{
	dest, s : string;
	sys = load Sys "$Sys";
	draw = load Draw "$Draw";

	daytime = load Daytime Daytime->PATH;
	if(daytime == nil) badmod(Daytime->PATH);

	parser = load Parser Parser->PATH;
	if(parser == nil) badmod(Parser->PATH);

	str = load String String->PATH;
	if (str == nil) badmod(String->PATH);

	me = "imagemap";

	g=k;
	bufio=g.bufio;
	parser->init();
	parser->httpheaders(g,req.version);
	dest = translate(req.uri, req.search);
	if(dest == nil){
		if(req.version!= ""){
			parser->okheaders(g);
			g.bout.puts(sys->sprint("Date: %s\r\n", daytime->time()));
			g.bout.puts("Content-type: text/html\r\n");
			g.bout.puts("\r\n");
		}
		g.bout.puts("<head><title>Nothing Found</title></head><body>\n");
		g.bout.puts("Nothing satisfying your search request could be found.\n</body>\n");
		return;
	}

	g.bout.puts(sys->sprint("%s 301 Moved Permanently\r\n", g.version));
	g.bout.puts(sys->sprint("Date: %s\r\n", daytime->time()));
	g.bout.puts("Server: Charon\r\n");
	g.bout.puts("MIME-version: 1.0\r\n");
	g.bout.puts("Content-type: text/html\r\n");
	(s,nil)=str->splitl(dest, ":");
	if(s!=nil){
		g.bout.puts(sys->sprint("URI: <%s>\r\n", parser->urlconv(dest)));
		g.bout.puts(sys->sprint("Location: %s\r\n", parser->urlconv(dest)));
	}else if(dest[0] == '/'){
		g.bout.puts(sys->sprint("URI: <%s>\r\n",parser->urlconv(dest)));
		g.bout.puts(sys->sprint("Location: http://%s%s\r\n", parser->urlconv(g.mydomain), parser->urlconv(dest)));
	} else {
		(req.uri,s) = str->splitr(req.uri, "/");
		g.bout.puts(sys->sprint("URI: <%s/%s>\r\n", parser->urlconv(req.uri), parser->urlconv(dest)));
		g.bout.puts(sys->sprint("Location: http://%s%s/%s\r\n", parser->urlconv(g.mydomain), parser->urlconv(req.uri), parser->urlconv(dest)));
	}
	g.bout.puts("\r\n");
	g.bout.puts("<head><title>Object Moved</title></head>\r\n");
	g.bout.puts("<body><h1>Object Moved</h1></body>\r\n");
	if(dest[0] == '/')
		g.bout.puts(sys->sprint("Your selection mapped to <a href=\"%s\"> here</a>.<p>\r\n", parser->urlconv(dest)));
	else
		g.bout.puts(sys->sprint("Your selection mapped to <a href=\"%s/%s\"> here</a>.<p>\r\n", parser->urlconv(req.uri), parser->urlconv(dest)));
}


translate(uri, search : string) : string
{
	b : ref Iobuf;
	p, c, q, start : Point;
	close, d : real;
	line, To, def, s : string;
	ok, n, inside, r : int;
	(pth,nil):=str->splitr(uri,"/");
	# sys->print("pth is %s",pth);
	if(search == nil)
		parser->fail(g,OnlySearch, me);
	(p, ok) = pt(search);
	if(!ok)
		parser->fail(g,BadSearch, me);

	b = bufio->open(uri, bufio->OREAD);
	if(b == nil){
		sys->fprint(sys->fildes(2), "imagemap: cannot open %s: %r\n", uri);
		parser->fail(g, NotFound, uri);
	}
	To = "";
	def = "";
	close = 0.;
	while((line = b.gets('\n'))!=nil){
		line=line[0:len line-1];

		(s, line) = getfield(line);
		if(s== "rect"){
			(s, line) = getfield(line);
			(q, ok) = pt(s);
			if(!ok || q.x > p.x || q.y > p.y)
				continue;
			(s, line) = getfield(line);
			(q, ok) = pt(s);
			if(!ok || q.x < p.x || q.y < p.y)
				continue;
			(s, nil) = getfield(line);
			return pth+s;
		}else if(s== "circle"){
			(s, line) = getfield(line);
			(c, ok) = pt(s);
			if(!ok)
				continue;
			(s, line) = getfield(line);
			(r,nil) = str->toint(s,10);
			(s, line) = getfield(line);
			d = real (r * r);
			if(d >= dist(p, c))
				return pth+s;
		}else if(s=="poly"){
			(s, line) = getfield(line);
			(start, ok) = pt(s);
			if(!ok)
				continue;
			inside = 0;
			c = start;
			for(n = 1; ; n++){
				(s, line) = getfield(line);
				(q, ok) = pt(s);
				if(!ok)
					break;
				inside = polytest(inside, p, c, q);
				c = q;
			}
			inside = polytest(inside, p, c, start);
			if(n >= 3 && inside)
				return pth+s;
		}else if(s== "point"){
			(s, line) = getfield(line);
			(q, ok) = pt(s);
			if(!ok)
				continue;
			d = dist(p, q);
			(s, line) = getfield(line);
			if(d == 0.)
				return pth+s;
			if(close == 0. || d < close){
				close = d;
				To = s;
			}
		}else if(s ==  "default"){
			(def, line) = getfield(line);
		}
	}
	if(To == nil)
		To = def;
	return pth+To;
}


polytest(inside : int,p, b, a : Point) : int{
	pa, ba : Point;

	if(b.y>a.y){
		pa=sub(p, a);
		ba=sub(b, a);
	}else{
		pa=sub(p, b);
		ba=sub(a, b);
	}
	if(0<=pa.y && pa.y<ba.y && pa.y*ba.x<=pa.x*ba.y)
		inside = !inside;
	return inside;
}


sub(p, q : Point) : Point {
	return (Point)(p.x-q.x, p.y-q.y);
}


dist(p, q : Point) : real {
	p.x -= q.x;
	p.y -= q.y;
	return real (p.x * p.x + p.y *p.y);
}


pt(s : string) : (Point, int) {
	p : Point;
	x, y : string;

	if(s[0] == '(')
		s=s[1:];
	(s,nil)=str->splitl(s, ")");
	p = Point(0, 0);
	(x,y) = str->splitl(s, ",");
	if(x == s)
		return (p, 0);
	(p.x,nil) = str->toint(x,10);
	if(y==nil)
		return (p, 0);
	y=y[1:];
	(p.y,nil) = str->toint(y, 10);
	return (p, 1);
}


getfield(s : string) : (string,string) {
	i:=0;
	while(s[i] == '\t' || s[i] == ' ')
		i++;
	return str->splitl(s[i:],"\t ");
}
