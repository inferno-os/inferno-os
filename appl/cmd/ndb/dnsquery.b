implement Dnsquery;

#
# Copyright © 2003 Vita Nuova Holdings LImited.  All rights reserved.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "arg.m";

Dnsquery: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

usage()
{
	sys->fprint(sys->fildes(2), "usage: dnsquery [-x /net] [-s server] [address ...]\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		cantload(Bufio->PATH);

	net := "/net";
	server: string;
	arg := load Arg Arg->PATH;
	if(arg == nil)
		cantload(Arg->PATH);
	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		'x' =>
			net = arg->arg();
			if(net == nil)
				usage();
		's' =>
			server = arg->arg();
			if(server == nil)
				usage();
		* =>
			usage();
		}
	args = arg->argv();
	arg = nil;

	if(server == nil)
		server = net+"/dns";
	if(args != nil){
		for(; args != nil; args = tl args)
			dnsquery(server, hd args);
	}else{
		f := bufio->fopen(sys->fildes(0), Sys->OREAD);
		if(f == nil)
			exit;
		for(;;){
			sys->print("> ");
			s := f.gets('\n');
			if(s == nil)
				break;
			dnsquery(server, s[0:len s-1]);
		}
	}
}

cantload(s: string)
{
	sys->fprint(sys->fildes(2), "dnsquery: can't load %s: %r\n", s);
	raise "fail:load";
}

dnsquery(server: string, query: string)
{
	dns := sys->open(server, Sys->ORDWR);
	if(dns == nil){
		sys->fprint(sys->fildes(2), "dnsquery: can't open %s: %r\n", server);
		raise "fail:open";
	}
	stdout := sys->fildes(1);
	for(i := len query; --i >= 0 && query[i] != ' ';)
		{}
	if(i < 0){
		i = len query;
		case dbattr(query) {
		"ip" =>
			query += " ptr";
		* =>
			query += " ip";
		}
	}
	if(query[i+1:] == "ptr"){
		while(i > 0 && query[i-1] == ' ')
			i--;
		if(!hastail(query[0:i], ".in-addr.arpa") && !hastail(query[0:i], ".IN-ADDR.ARPA"))
			query = addr2arpa(query[0:i])+" ptr";
	}
	b := array of byte query;
	if(sys->write(dns, b, len b) > 0){
		sys->seek(dns, big 0, Sys->SEEKSTART);
		buf := array[256] of byte;
		while((n := sys->read(dns, buf, len buf)) > 0)
			sys->print("%s\n", string buf[0:n]);
		if(n == 0)
			return;
	}
	sys->print("!%r\n");
}

hastail(s: string, t: string): int
{
	if(len s >= len t && s[len s - len t:] == t)
		return 1;
	return 0;
}

addr2arpa(a: string): string
{
	(nf, flds) := sys->tokenize(a, ".");
	rl: list of string;
	for(; flds != nil; flds = tl flds)
		rl = hd flds :: rl;
	addr: string;
	for(; rl != nil; rl = tl rl){
		if(addr != nil)
			addr[len addr] = '.';
		addr += hd rl;
	}
	return addr+".in-addr.arpa";
}

dbattr(s: string): string
{
	digit := 0;
	dot := 0;
	alpha := 0;
	hex := 0;
	colon := 0;
	for(i := 0; i < len s; i++){
		case c := s[i] {
		'0' to '9' =>
			digit = 1;
		'a' to 'f' or 'A' to 'F' =>
			hex = 1;
		'.' =>
			dot = 1;
		':' =>
			colon = 1;
		* =>
			if(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '-' || c == '&')
				alpha = 1;
		}
	}
	if(alpha){
		if(dot)
			return "dom";
		return "sys";
	}
	if(colon)
		return "ip";
	if(dot){
		if(!hex)
			return "ip";
		return "dom";
	}
	return "sys";
}
