implement Env;

#
# Copyright © 2000 Vita Nuova Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
include "readdir.m";
include "env.m";

ENVDIR : con "/env/";

setenv(var: string, val: string): int
{
	init();
	if (var == nil || !nameok(var)) {
		sys->werrstr("bad variable name");
		return -1;
	}
	if (val == nil) {
		sys->remove(ENVDIR+var);
		return 0;
	}
	fd := sys->create(ENVDIR+var, Sys->OWRITE, 8r600);
	if (fd == nil)
		return -1;
	valb := array of byte val;
	if (sys->write(fd, valb, len valb) != len valb)
		return -1;
	return 0;
}

getenv(var: string): string
{
	init();
	if (var == nil || !nameok(var))
		return nil;
	fd := sys->open(ENVDIR+var, Sys->OREAD);
	if (fd == nil)
		return nil;
	(ok, stat) := sys->fstat(fd);
	if (ok == -1)
		return nil;
	buf := array[int stat.length] of byte;
	n := sys->read(fd, buf, len buf);
	if (n < 0)
		return nil;
	return string buf[0:n];
}

getall(): list of (string, string)
{
	readdir := load Readdir Readdir->PATH;
	if (readdir == nil)
		return nil;
	(a, n) := readdir->init(ENVDIR,
			Readdir->NONE | Readdir->COMPACT | Readdir->DESCENDING);
	vl: list of (string, string);
	for (i := 0; i < len a; i++)
		vl = (a[i].name, getenv(a[i].name)) :: vl;
	return vl;
}

# clone the current environment
clone(): int
{
	init();
	return sys->pctl(sys->FORKENV, nil);
}

new(): int
{
	init();
	return sys->pctl(sys->NEWENV, nil);
}

init()
{
	if (sys == nil)
		sys = load Sys Sys->PATH;
}

nameok(var: string): int
{
	for(i:=0; i<len var; i++) 
		if (var[i] == '/') return 0;
	return 1;
}
