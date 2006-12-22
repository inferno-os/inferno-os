implement Csquery;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "arg.m";

Csquery: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

usage()
{
	sys->fprint(sys->fildes(2), "usage: csquery [-x /net] [-s server] [address ...]\n");
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
		server = net+"/cs";
	if(args != nil){
		for(; args != nil; args = tl args)
			csquery(server, hd args);
	}else{
		f := bufio->fopen(sys->fildes(0), Sys->OREAD);
		if(f == nil)
			exit;
		for(;;){
			sys->print("> ");
			s := f.gets('\n');
			if(s == nil)
				break;
			csquery(server, s[0:len s-1]);
		}
	}
}

cantload(s: string)
{
	sys->fprint(sys->fildes(2), "csquery: can't load %s: %r\n", s);
	raise "fail:load";
}

csquery(server: string, addr: string)
{
	cs := sys->open(server, Sys->ORDWR);
	if(cs == nil){
		sys->fprint(sys->fildes(2), "csquery: can't open %s: %r\n", server);
		raise "fail:open";
	}
	stdout := sys->fildes(1);
	b := array of byte addr;
	if(sys->write(cs, b, len b) > 0){
		sys->seek(cs, big 0, Sys->SEEKSTART);
		buf := array[256] of byte;
		while((n := sys->read(cs, buf, len buf)) > 0)
			sys->print("%s\n", string buf[0:n]);
		if(n == 0)
			return;
	}
	sys->print("%s: %r\n", addr);
}
