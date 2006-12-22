implement Agrep;

include "sys.m";
include "draw.m";
include "sh.m";

Agrep : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

init(ctxt : ref Draw->Context, argl : list of string)
{
	sys := load Sys Sys->PATH;
	stderr := sys->fildes(2);
	cmd := "grep";
	file := cmd + ".dis";
	c := load Command file;
	if(c == nil) {
		err := sys->sprint("%r");
		if(file[0]!='/' && file[0:2]!="./"){
			c = load Command "/dis/"+file;
			if(c == nil)
				err = sys->sprint("%r");
		}
		if(c == nil){
			sys->fprint(stderr, "%s: %s\n", cmd, err);
			return;
		}
	}
	argl = tl argl;
	argl = rev(argl);
	argl = "/dev/null" :: argl;
	argl = rev(argl);
	argl = "-n" :: argl;
	argl = cmd :: argl;
	c->init(ctxt, argl);
}

rev(a : list of string) : list of string
{
	b : list of string;

	for ( ; a != nil; a = tl a)
		b = hd a :: b;
	return b;
}
