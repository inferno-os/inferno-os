implement Endpointsrv;
include "sys.m";
	sys: Sys;
include "draw.m";

Endpointsrv: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if(len argv != 3)
		fatal("usage: endpointsrv addr [dir]");
	addr := hd tl argv;
	dir := hd tl tl argv;
	if(sys->bind("#s", dir, Sys->MREPL) == -1)
		fatal(sys->sprint("cannot bind #s onto %q: %r", dir));

	fio := sys->file2chan(dir, "clone");
	spawn endpointproc(addr, dir, fio);
}

endpointproc(addr, dir: string, fio: ref Sys->FileIO)
{
	n := 0;
	for(;;) alt {
	(offset, nil, nil, rc) := <-fio.read =>
		if(rc != nil){
			if(offset > 0)
				rc <-= (nil, nil);
			else{
				mkpipe(dir, string n);
				rc <-= (array of byte (addr+" "+string n++), nil);
			}
		}
	(nil, nil, nil, wc) := <-fio.write =>
		if(wc != nil)
			wc <-= (0, "cannot write");
	}
}

mkpipe(dir: string, p: string)
{
	sys->bind("#|", "/tmp", Sys->MREPL);
	d := Sys->nulldir;
	d.name = p;
	sys->wstat("/tmp/data", d);
	d.name = p + ".in";
	sys->wstat("/tmp/data1", d);
	sys->bind("/tmp", dir, Sys->MBEFORE);
}

fatal(e: string)
{
	sys->fprint(sys->fildes(2), "endpointsrv: %s\n", e);
	raise "fail:error";
}
