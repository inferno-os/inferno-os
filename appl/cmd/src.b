implement Src;

include "sys.m";
	sys: Sys;
include "draw.m";
include "dis.m";
	dis: Dis;

Src: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	dis = load Dis Dis->PATH;

	if(dis != nil){
		dis->init();
		for(argv = tl argv; argv != nil; argv = tl argv){
			s := src(hd argv);
			if(s == nil)
				s = "?";
			sys->print("%s:	%s\n", hd argv, s);
		}
	}
}

src(progname: string): string
{
	disfile := 0;
	if (len progname >= 4 && progname[len progname-4:] == ".dis")
		disfile = 1;
	pathlist: list of string;
	if (absolute(progname))
		pathlist = list of {""};
	else
		pathlist = list of {"/dis", "."};

	err := "";
	do {
		path: string;
		if (hd pathlist != "")
			path = hd pathlist + "/" + progname;
		else
			path = progname;

		npath := path;
		if (!disfile)
			npath += ".dis";
		src := dis->src(npath);
		if(src != nil)
			return src;
		err = sys->sprint("%r");
		if (nonexistent(err)) {
			# try and find it as a shell script
			if (!disfile) {
				(ok, info) := sys->stat(path);
				if (ok == 0 && (info.mode & Sys->DMDIR) == 0
						&& (info.mode & 8r111) != 0)
					return path;
				else
					err = sys->sprint("%r");
			}
		}
		pathlist = tl pathlist;
	} while (pathlist != nil && nonexistent(err));
	return nil;
}

absolute(p: string): int
{
	if (len p < 2)
		return 0;
	if (p[0] == '/' || p[0] == '#')
		return 1;
	if (len p < 3 || p[0] != '.')
		return 0;
	if (p[1] == '/')
		return 1;
	if (p[1] == '.' && p[2] == '/')
		return 1;
	return 0;
}

nonexistent(e: string): int
{
	errs := array[] of {"does not exist", "directory entry not found"};
	for (i := 0; i < len errs; i++){
		j := len errs[i];
		if (j <= len e && e[len e-j:] == errs[i])
			return 1;
	}
	return 0;
}
