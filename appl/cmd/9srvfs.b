implement P9srvfs;

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "sh.m";
	sh: Sh;

include "arg.m";

P9srvfs: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	if(str == nil)
		nomod(String->PATH);

	perm := 8r600;
	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	arg->init(args);
	arg->setusage("9srvfs [-p perm] name path|{command}");
	while((o := arg->opt()) != 0)
		case o {
		'p' =>
			s := arg->earg();
			if(s == nil)
				arg->usage();
			(perm, s) = str->toint(s, 8);
			if(s != nil)
				arg->usage();
		* =>
			arg->usage();
		}
	args = arg->argv();
	if(len args != 2)
		arg->usage();
	arg = nil;

	srvname := hd args;
	args = tl args;
	dest := hd args;
	if(dest == nil)
		dest = ".";
	iscmd := dest[0] == '{' && dest[len dest-1] == '}';
	if(!iscmd){		# quick check before creating service file
		(ok, d) := sys->stat(dest);
		if(ok < 0)
			error(sys->sprint("can't stat %s: %r", dest));
		if((d.mode & Sys->DMDIR) == 0)
			error(sys->sprint("%s: not a directory", dest));
	}else{
		sh = load Sh Sh->PATH;
		if(sh == nil)
			nomod(Sh->PATH);
	}
	srvfd := sys->create("/srv/"+srvname, Sys->ORDWR, perm);
	if(srvfd == nil)
		error(sys->sprint("can't create /srv/%s: %r", srvname));
	if(iscmd){
		sync := chan of int;
		spawn runcmd(sh, ctxt, dest :: nil, srvfd, sync);
		<-sync;
	}else{
		if(sys->export(srvfd, dest, Sys->EXPWAIT) < 0)
			error(sys->sprint("export failed: %r"));
	}
}

error(msg: string)
{
	sys->fprint(sys->fildes(2), "9srvfs: %s\n", msg);
	raise "fail:error";
}

nomod(mod: string)
{
	error(sys->sprint("can't load %s: %r", mod));
}

runcmd(sh: Sh, ctxt: ref Draw->Context, argv: list of string, stdin: ref Sys->FD, sync: chan of int)
{
	sys->pctl(Sys->FORKFD, nil);
	sys->dup(stdin.fd, 0);
	stdin = nil;
	sync <-= 0;
	sh->run(ctxt, argv);
}
