implement Styxaux;

include "sys.m";
	sys: Sys;
include "styx.m";
include "styxaux.m";

Tmsg : import Styx;

init()
{
}

msize(m: ref Tmsg): int
{
	pick fc := m {
		Version =>	return fc.msize;
	}
	error("bad styx msize", m);
	return 0;
}

version(m: ref Tmsg): string
{
	pick fc := m {
		Version =>	return fc.version;
	}
	error("bad styx version", m);
	return nil;
}

fid(m: ref Tmsg): int
{
	pick fc := m {
		Readerror =>	return 0;
		Version =>	return 0;
		Flush =>		return 0;
		Walk =>		return fc.fid;
		Open =>		return fc.fid;
		Create =>		return fc.fid;
		Read =>		return fc.fid;
		Write =>		return fc.fid;
		Clunk =>		return fc.fid;
		Remove =>	return fc.fid;
		Stat =>		return fc.fid;
		Wstat =>		return fc.fid;
		Attach =>		return fc.fid;
	}
	error("bad styx fid", m);
	return 0;
}

uname(m: ref Tmsg): string
{
	pick fc := m {
		Attach =>		return fc.uname;
	}
	error("bad styx uname", m);
	return nil;
}

aname(m: ref Tmsg): string
{
	pick fc := m {
		Attach =>		return fc.aname;
	}
	error("bad styx aname", m);
	return nil;
}

newfid(m: ref Tmsg): int
{
	pick fc := m {
		Walk =>		return fc.newfid;
	}
	error("bad styx newfd", m);
	return 0;
}

name(m: ref Tmsg): string
{
	pick fc := m {
		Create =>		return fc.name;
	}
	error("bad styx name", m);
	return nil;
}

names(m: ref Tmsg): array of string
{
	pick fc := m {
		Walk =>		return fc.names;
	}
	error("bad styx names", m);
	return nil;
}

mode(m: ref Tmsg): int
{
	pick fc := m {
		Open =>		return fc.mode;
	}
	error("bad styx mode", m);
	return 0;
}

setmode(m: ref Tmsg, mode: int)
{
	pick fc := m {
		Open =>		fc.mode = mode;
		* =>			error("bad styx setmode", m);
	}
}

offset(m: ref Tmsg): big
{
	pick fc := m {
		Read =>		return fc.offset;
		Write =>		return fc.offset;
	}
	error("bad styx offset", m);
	return big 0;
}

count(m: ref Tmsg): int
{
	pick fc := m {
		Read =>		return fc.count;
		Write =>		return len fc.data;
	}
	error("bad styx count", m);
	return 0;
}

setcount(m: ref Tmsg, count: int)
{
	pick fc := m {
		Read =>		fc.count = count;
		* =>			error("bad styx setcount", m);
	}
}

oldtag(m: ref Tmsg): int
{
	pick fc := m {
		Flush =>		return fc.oldtag;
	}
	error("bad styx oldtag", m);
	return 0;
}

data(m: ref Tmsg): array of byte
{
	pick fc := m {
		Write =>		return fc.data;
	}
	error("bad styx data", m);
	return nil;
}

setdata(m: ref Tmsg, data: array of byte)
{
	pick fc := m {
		Write =>		fc.data = data;
		* =>			error("bad styx setdata", m);
	}
}

error(s: string, m: ref Tmsg)
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	sys->fprint(sys->fildes(2), "%s %d\n", s, tagof m);
}
