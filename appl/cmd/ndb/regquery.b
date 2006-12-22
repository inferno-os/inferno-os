implement Regquery;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "string.m";
	str: String;

include "arg.m";

Regquery: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		cantload(Bufio->PATH);
	str = load String String->PATH;
	if(str == nil)
		cantload(String->PATH);

	mntpt := "/mnt/registry";
	arg := load Arg Arg->PATH;
	if(arg == nil)
		cantload(Arg->PATH);
	arg->init(args);
	arg->setusage("regquery [-m mntpt] [-n] [attr val attr val ...]");
	namesonly := 0;
	while((c := arg->opt()) != 0)
		case c {
		'm' =>	mntpt = arg->earg();
		'n' =>	namesonly = 1;
		* =>	arg->usage();
		}
	args = arg->argv();
	arg = nil;

	finder := mntpt+"/find";
	if(args != nil){
		s := "";
		for(; args != nil; args = tl args)
			s += sys->sprint(" %q", hd args);
		if(s != nil)
			s = s[1:];
		regquery(finder, s, namesonly);
	}else{
		f := bufio->fopen(sys->fildes(0), Sys->OREAD);
		if(f == nil)
			exit;
		for(;;){
			sys->print("> ");
			s := f.gets('\n');
			if(s == nil)
				break;
			regquery(finder, s[0:len s-1], namesonly);
		}
	}
}

cantload(s: string)
{
	sys->fprint(sys->fildes(2), "regquery: can't load %s: %r\n", s);
	raise "fail:load";
}

regquery(server: string, addr: string, namesonly: int)
{
	fd := sys->open(server, Sys->ORDWR);
	if(fd == nil){
		sys->fprint(sys->fildes(2), "regquery: can't open %s: %r\n", server);
		raise "fail:open";
	}
	stdout := sys->fildes(1);
	b := array of byte addr;
	if(sys->write(fd, b, len b) >= 0){
		sys->seek(fd, big 0, Sys->SEEKSTART);
		if(namesonly){
			bio := bufio->fopen(fd, Bufio->OREAD);
			while((s := bio.gets('\n')) != nil){
				l := str->unquoted(s);
				if(l != nil)
					sys->print("%s\n", hd l);
			}
			return;
		}else{
			buf := array[Sys->ATOMICIO] of byte;
			while((n := sys->read(fd, buf, len buf)) > 0)
				sys->print("%s", string buf[0:n]);
			if(n == 0)
				return;
		}
	}
	sys->fprint(sys->fildes(2), "regquery: %r\n");
}
