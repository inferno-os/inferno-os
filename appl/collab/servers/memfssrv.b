implement Service;

include "sys.m";
include "../service.m";
include "memfs.m";

init(nil : list of string) : (string, string, ref Sys->FD)
{
	sys := load Sys Sys->PATH;
	memfs := load MemFS MemFS->PATH;
	if (memfs == nil) {
		err := sys->sprint("cannot load %s: %r", MemFS->PATH);
		return (err, nil, nil);
	}
	err := memfs->init();
	if (err != nil)
		return (err, nil, nil);
	fd := memfs->newfs(1024 * 512);
	return (nil, "/", fd);
}
