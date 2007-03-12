implement Plumb;

include "sys.m";
	sys: Sys;

include "draw.m";

include "arg.m";

include "plumbmsg.m";
	plumbmsg: Plumbmsg;
	Msg, Attr: import plumbmsg;

include "workdir.m";
	workdir: Workdir;

Plumb: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	plumbmsg = load Plumbmsg Plumbmsg->PATH;
	if(plumbmsg == nil)
		nomod(Plumbmsg->PATH);
	workdir = load Workdir Workdir->PATH;
	if(workdir == nil)
		nomod(Workdir->PATH);

	if(plumbmsg->init(1, nil, 0) < 0)
		err(sys->sprint("can't connect to plumb: %r"));

	attrs: list of ref Attr;
	input := 0;
	m := ref Msg("plumb", nil, workdir->init(), "text", nil, nil);
	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("plumb [-s src] [-d dest] [-w wdir] [-t type] [-a name val] -i | ... data ...");
	while((c := arg->opt()) != 0)
		case c {
		's' =>
			m.src = arg->earg();
		'd' =>
			m.dst = arg->earg();
		'w' or 'D' =>
			m.dir = arg->earg();
		'i' =>
			input++;
		't' or 'k'=>
			m.kind = arg->arg();
		'a' =>
			name := arg->earg();
			val := arg->earg();
			attrs = tack(attrs, ref Attr(name, val));
		* =>
			arg->usage();
		}
	args = arg->argv();
	if(input && args != nil || !input && args == nil)
		arg->usage();
	arg = nil;

	if(input){
		m.data = gather(sys->fildes(0));
		(notfound, nil) := plumbmsg->lookup(plumbmsg->string2attrs(m.attr), "action");
		if(notfound)
			tack(attrs, ref Attr("action", "showdata"));
		m.attr = plumbmsg->attrs2string(attrs);
		if(m.send() < 0)
			err(sys->sprint("can't send message: %r"));
		exit;
	}
	
	nb := 0;
	for(a := args; a != nil; a = tl a)
		nb += len array of byte hd a;
	nb += len args;
	buf := array[nb] of byte;
	nb = 0;
	for(a = args; a != nil; a = tl a){
		b := array of byte hd a;
		buf[nb++] = byte ' ';
		buf[nb:] = b;
		nb += len b;
	}
	m.data = buf[1:];
	m.attr = plumbmsg->attrs2string(attrs);
	if(m.send() < 0)
		err(sys->sprint("can't plumb message: %r"));
}

gather(fd: ref Sys->FD): array of byte
{
	Chunk: con 8192;	# arbitrary
	ndata := 0;
	buf := array[Chunk] of byte;
	while((n := sys->read(fd, buf[ndata:], len buf - ndata)) > 0){
		ndata += n;
		if(len buf - ndata < Chunk){
			t := array[len buf+Chunk] of byte;
			t[0:] = buf[0: ndata];
			buf = t;
		}
	}
	if(n < 0)
		err(sys->sprint("error reading input: %r"));
	return buf[0: ndata];
}

tack(l: list of ref Attr, v: ref Attr): list of ref Attr
{
	if(l == nil)
		return v :: nil;
	return hd l :: tack(tl l, v);
}

nomod(m: string)
{
	err(sys->sprint("can't load %s: %r", m));
}

err(s: string)
{
	sys->fprint(sys->fildes(2), "plumb: %s\n", s);
	raise "fail:error";
}
