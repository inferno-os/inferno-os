implement Fs;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "readdir.m";
include "fslib.m";
	fslib: Fslib;
	Report, Value, type2s: import fslib;
	Fschan, Fsdata, Entrychan, Entry,
	Quit: import Fslib;

# fs distribution:

# {filter -d {not {match -r '\.(dis|sbl)$'}} {filter {path /module/fslib.m /module/bundle.m /module/unbundle.m /appl/cmd/fs.b /appl/cmd/fs /appl/lib/fslib.b} /}}

Fs: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

badmod(path: string)
{
	sys->fprint(stderr(), "fs: cannot load %s: %r\n", path);
	raise "fail:bad module";
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	fslib = load Fslib Fslib->PATH;
	if(fslib == nil)
		badmod(Fslib->PATH);
	fslib->init();
	argv = tl argv;

	if(argv == nil)
		usage();
	report := Report.new();
	s := hd argv;
	if(tl argv == nil && s != nil && s[0] == '{' && s[len s - 1] == '}')
		s = "void " + hd argv;
	else {
		s = "void {" + hd argv;
		for(argv = tl argv; argv != nil; argv = tl argv){
			a := hd argv;
			if(a == nil || a[0] != '{')		# }
				s += sys->sprint(" %q", a);
			else
				s += " " + hd argv;
		}
		s += "}";
	}
	m := load Fsmodule "/dis/fs/eval.dis";
	if(m == nil)
		badmod("/dis/fs/eval.dis");
	if(!fslib->typecompat("as", m->types())){
		sys->fprint(stderr(), "fs: eval module implements incompatible type (usage: %s)\n",
				fslib->cmdusage("eval", m->types()));
		raise "fail:bad eval module";
	}
	m->init();
	v := m->run(ctxt, report, nil, ref Value.S(s) :: nil);
	fail: string;
	if(v == nil)
		fail = "error";
	else{
		sync := v.v().i;
		sync <-= 1;
	}
	report.enable();
	while((e := <-report.reportc) != nil)
		sys->fprint(stderr(), "fs: %s\n", e);
	if(fail != nil)
		raise "fail:" +fail;
}

usage()
{
	fd := stderr();
	sys->fprint(fd, "usage: fs expression\n");
	sys->fprint(fd, "verbs are:\n");
	if((readdir := load Readdir Readdir->PATH) == nil){
		sys->fprint(fd, "fs: cannot load %s: %r\n", Readdir->PATH);
	}else{
		(a, nil) := readdir->init("/dis/fs", Readdir->NAME|Readdir->COMPACT);
		for(i := 0; i < len a; i++){
			f := a[i].name;
			if(len f < 4 || f[len f - 4:] != ".dis")
				continue;
			m := load Fsmodule "/dis/fs/" + f;
			if(m == nil)
				sys->fprint(fd, "\t(%s: cannot load: %r)\n", f[0:len f - 4]);
			else
				sys->fprint(fd, "\t%s\n", fslib->cmdusage(f[0:len f - 4], m->types()));
		}
	}
	sys->fprint(fd, "automatic conversions:\n");
	sys->fprint(fd, "\tstring -> fs {walk string}\n");
	sys->fprint(fd, "\tfs -> entries {entries fs}\n");
	sys->fprint(fd, "\tstring -> gate {match string}\n");
	sys->fprint(fd, "\tentries -> void {print entries}\n");
	sys->fprint(fd, "\tcommand -> string {run command}\n");
	raise "fail:usage";
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}
