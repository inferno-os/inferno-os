# To be removed...
# functionality has been moved to appl/cmd/memfs.b
# some progs still refer to lib/memfs so it remains for the time being

implement MemFS;

include "sys.m";
	sys: Sys;
include "draw.m";
include "memfs.m";

Cmd: module {
	PATH: con "/dis/memfs.dis";
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

cmd: Cmd;

init(): string
{
	sys = load Sys Sys->PATH;
	cmd = load Cmd Cmd->PATH;
	if (cmd == nil)
		return sys->sprint("lib/memfs cannot load %s: %r\n", Cmd->PATH);
	return nil;
}

newfs(maxsz: int): ref Sys->FD
{
	p := array [2] of ref Sys->FD;
	if (sys->pipe(p) == -1)
		return nil;
	sync := chan of int;
	spawn run(p[1].fd, maxsz, sync);
	<- sync;
	return p[0];
}

run(fd: int, sz: int, sync: chan of int)
{
	sys->pctl(Sys->FORKFD, nil);
	sys->dup(fd, 0);
	sys->pctl(Sys->NEWFD, 0::1::2::nil);
	sync <-= 1;
	cmd->init(nil, Cmd->PATH :: "-s" :: "-m" :: string sz :: nil);
}
