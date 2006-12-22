implement Stats;

include "sys.m";
	sys : Sys;

include "bufio.m";
	bufio: Bufio;
	Iobuf: 	import bufio;

include "draw.m";
	draw: Draw;

include "contents.m";
include "cache.m";
	cache : Cache;

include "httpd.m";
	Private_info: import Httpd;

include "date.m";
	date : Date;

include "parser.m";
	pars : Parser;

include "daytime.m";
	daytime: Daytime;

Stats: module
{
	init: fn(g : ref Private_info, req: Httpd->Request);
};

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "stats: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init(k : ref Private_info, req: Httpd->Request)
{	
	sys = load Sys "$Sys";
	draw = load Draw "$Draw";
	
	daytime = load Daytime Daytime->PATH;
	if(daytime == nil) badmod(Daytime->PATH);

	pars = load Parser Parser->PATH;
	if(pars == nil) badmod(Parser->PATH);

	date = load Date Date->PATH;
	if(date == nil) badmod(Date->PATH);

	date->init();
	bufio=k.bufio;
	send(k, req.method, req.version, req.uri, req.search);
}

send(g: ref Private_info, meth, vers, uri, search : string)
{
	if(meth=="");
	if(uri=="");
	if(search=="");
	if(vers != ""){
		if (g.version == nil)
			sys->print("stats: version is unknown.\n");
		g.bout.puts(sys->sprint("%s 200 OK\r\n", g.version));
		g.bout.puts("Server: Charon\r\n");
		g.bout.puts("MIME-version: 1.0\r\n");
		g.bout.puts(sys->sprint("Date: %s\r\n", date->dateconv(daytime->now())));
		g.bout.puts("Content-type: text/html\r\n");
		g.bout.puts(sys->sprint("Expires: %s\r\n", date->dateconv(daytime->now())));
		g.bout.puts("\r\n");
	}
	g.bout.puts("<head><title>Cache Information</title></head>\r\n");
	g.bout.puts("<body><h1>Cache Information</h1>\r\n");
	g.bout.puts("These are the pages stored in the server cache:<p>\r\n");
	lis:=(g.cache)->dump();
	while (lis!=nil){
		(a,b,d):=hd lis;
		g.bout.puts(sys->sprint("<a href=\"%s\"> %s</a> \t size %d \t tag %d.<p>\r\n",a,a,b,d));
		lis = tl lis;
	}
	g.bout.flush();
}
