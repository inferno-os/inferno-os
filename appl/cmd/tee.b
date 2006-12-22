implement Tee;

include "sys.m";
	sys: Sys;

include "draw.m";

include "arg.m";

Tee: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

File: adt
{
	fd:	ref Sys->FD;
	name:	string;
};

usage()
{
	sys->fprint(sys->fildes(2), "Usage: tee [-a] [file ...]\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	if(arg == nil)
		err(sys->sprint("can't load %s: %r", Arg->PATH));

	append := 0;
	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	append = 1;
		* =>		usage();
		}
	names := arg->argv();
	arg = nil;

	fd0 := sys->fildes(0);
	if(fd0 == nil)
		err("no standard input");
	nf := 0;
	files := array[len names + 1] of ref File;
	for(; names != nil; names = tl names){
		f := hd names;
		fd: ref Sys->FD;
		if(append){
			fd = sys->open(f, Sys->OWRITE);
			if(fd != nil)
				sys->seek(fd, big 0, 2);
			else
				fd = sys->create(f, Sys->OWRITE, 8r666);
		}else
			fd = sys->create(f, Sys->OWRITE, 8r666 );
		if(fd == nil)
			err(sys->sprint("cannot open %s: %r", f));
		files[nf++] = ref File(fd, f);
	}
	files[nf++] = ref File(sys->fildes(1), "standard output");
	buf := array[Sys->ATOMICIO] of byte;
	while((n := sys->read(fd0, buf, len buf)) > 0){
		for(i := 0; i < nf; i++)
			if(sys->write(files[i].fd, buf, n) != n)
				err(sys->sprint("error writing %s: %r", files[i].name));
	}
	if(n < 0)
		err(sys->sprint("read error: %r"));
}

err(s: string)
{
	sys->fprint(sys->fildes(2), "tee: %s\n", s);
	raise "fail:error";
}
