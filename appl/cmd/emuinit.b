implement Emuinit;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "arg.m";
	arg: Arg;

Emuinit: module
{
	init: fn();
};

init()
{
	sys = load Sys Sys->PATH;
	sys->bind("#e", "/env", sys->MREPL|sys->MCREATE);	# if #e not configured, that's fine
	args := getenv("emuargs");
	arg = load Arg Arg->PATH;
	if (arg == nil)
		sys->fprint(sys->fildes(2), "emuinit: cannot load %s: %r\n", Arg->PATH);
	else{
		arg->init(args);
		while((c := arg->opt()) != 0)
			case c {
			'g' or 'c' or 'C' or 'm' or 'p' or 'f' or 'r' or 'd' =>
				arg->arg();
	                  }
		args = arg->argv();
	}
	mod: Command;
	(mod, args) = loadmod(args);
	mod->init(nil, args);
}

loadmod(args: list of string): (Command, list of string)
{
	path := Command->PATH;
	if(args != nil)
		path = hd args;
	else
		args = "-l" :: nil;	# add startup option

	# try loading the module directly.
	mod: Command;
	if (path != nil && path[0] == '/')
		mod = load Command path;
	else {
		mod = load Command "/dis/"+path;
		if (mod == nil)
			mod = load Command "/"+path;
	}
	if(mod != nil)
		return (mod, args);

	# if we can't load the module directly, try getting the shell to run it.
	err := sys->sprint("%r");
	mod = load Command Command->PATH;
	if(mod == nil){
		sys->fprint(sys->fildes(2), "emuinit: unable to load %s: %s\n", path, err);
		raise "fail:error";
	}
	return (mod, "sh" :: "-c" :: "$*" :: args);
}

getenv(v: string): list of string
{
	fd := sys->open("#e/"+v, Sys->OREAD);
	if (fd == nil)
		return nil;
	(ok, d) := sys->fstat(fd);
	if(ok == -1)
		return nil;
	buf := array[int d.length] of byte;
	n := sys->read(fd, buf, len buf);
	if (n <= 0)
		return nil;
	return unquoted(string buf[0:n]);
}

unquoted(s: string): list of string
{
	args: list of string;
	word: string;
	inquote := 0;
	for(j := len s; j > 0;){
		c := s[j-1];
		if(c == ' ' || c == '\t' || c == '\n'){
			j--;
			continue;
		}
		for(i := j-1; i >= 0 && ((c = s[i]) != ' ' && c != '\t' && c != '\n' || inquote); i--){	# collect word
			if(c == '\''){
				word = s[i+1:j] + word;
				j = i;
				if(!inquote || i == 0 || s[i-1] != '\'')
					inquote = !inquote;
				else
					i--;
			}
		}
		args = (s[i+1:j]+word) :: args;
		word = nil;
		j = i;
	}
	# if quotes were unbalanced, balance them and try again.
	if(inquote)
		return unquoted(s + "'");
	return args;
}
