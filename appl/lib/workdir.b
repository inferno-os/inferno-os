implement Workdir;

include "sys.m";

include "workdir.m";

init(): string
{
	sys := load Sys Sys->PATH;
	fd := sys->open(".", Sys->OREAD);
	if(fd == nil)
		return nil;
	return sys->fd2path(fd);
}
