# ns - display the construction of the current namespace (loosely based on plan 9's ns)
implement Ns;

include "sys.m";
	sys: Sys;

include "draw.m";

include "arg.m";

Ns: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

SHELLMETA: con "' \t\\$#";

usage()
{
	sys->fprint(sys->fildes(2), "usage: ns [-r] [pid]\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	arg := load Arg Arg->PATH;
	if(arg == nil){
		sys->fprint(sys->fildes(2), "ns: can't load %s: %r\n", Arg->PATH);
		raise "fail:load";
	}
	arg->init(args);
	pid := sys->pctl(0, nil);
	raw := 0;
	while((o := arg->opt()) != 0)
		case o {
		'r' =>
			raw = 1;
		* =>
			usage();
		}
	args = arg->argv();
	arg = nil;

	if(len args > 1)
		usage();
	if(len args > 0)
		pid = int hd args;

	nsname := sys->sprint("/prog/%d/ns", pid);
	nsfd := sys->open(nsname, Sys->OREAD);
	if(nsfd == nil) {
		sys->fprint(sys->fildes(2), "ns: can't open %s: %r\n", nsname);
		raise "fail:open";
	}

	buf := array[2048] of byte;
	while((l := sys->read(nsfd, buf, len buf)) > 0){
		(nstr, lstr) := sys->tokenize(string buf[0:l], " \n");
		if(nstr < 2)
			continue;
		cmd := hd lstr;
		lstr = tl lstr;
		if(cmd == "cd" && lstr != nil){
			sys->print("%s %s\n", cmd, quoted(hd lstr));
			continue;
		}

		sflag := "";
		if((hd lstr)[0] == '-') {
			sflag = hd lstr + " ";
			lstr = tl lstr;
		}
		if(len lstr < 2)
			continue;

		src := hd lstr;
		lstr = tl lstr;
		if(len src >= 3 && (src[0:2] == "#/" || src[0:2] == "#U")) # remove unnecesary #/'s and #U's
			src = src[2:];

		# remove "#." from beginning of destination path
		dest := hd lstr;
		if(dest == "#M") {
			dest = dest[2:];
			if(dest == "")
				dest = "/";
		}

		if(cmd == "mount" && !raw)
			src = netaddr(src);	# optionally rewrite network files to network address

		# quote arguments if "#" found
		sys->print("%s %s%s %s\n", cmd, sflag, quoted(src), quoted(dest));
	} 
	if(l < 0)
		sys->fprint(sys->fildes(2), "ns: error reading %s: %r\n", nsname);
}

netaddr(f: string): string
{
	if(len f < 1 || f[0] != '/')
		return f;
	(nf, flds) := sys->tokenize(f, "/");	# expect /net[.alt]/proto/2/data
	if(nf < 4)
		return f;
	netdir := hd flds;
	if(netdir != "net" && netdir != "net.alt")
		return f;
	proto := hd tl flds;
	d := hd tl tl flds;
	if(hd tl tl tl flds != "data")
		return f;
	fd := sys->open(sys->sprint("/%s/%s/%s/remote", hd flds, proto, d), Sys->OREAD);
	if(fd == nil)
		return f;
	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return f;
	if(buf[n-1] == byte '\n')
		n--;
	if(netdir != "net")
		proto = "/"+netdir+"/"+proto;
	return sys->sprint("%s!%s", proto, string buf[0:n]);
}

any(c: int, t: string): int
{
	for(j := 0; j < len t; j++)
		if(c == t[j])
			return 1;
	return 0;
}

contains(s: string, t: string): int
{
	for(i := 0; i<len s; i++)
		if(any(s[i], t))
			return 1;
	return 0;
}

quoted(s: string): string
{
	if(!contains(s, SHELLMETA))
		return s;
	r := "'";
	for(i := 0; i < len s; i++){
		if(s[i] == '\'')
			r[len r] = '\'';
		r[len r] = s[i];
	}
	r[len r] = '\'';
	return r;
}
