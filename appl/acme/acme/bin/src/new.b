implement New;

include "sys.m";
include "draw.m";
include "sh.m";
include "workdir.m";

New : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

sys : Sys;

init(ctxt : ref Draw->Context, argl : list of string)
{
	sys = load Sys Sys->PATH;
	workdir := load Workdir Workdir->PATH;
	if (len argl <= 1)
		return;
	ncfd := sys->open("/mnt/acme/new/ctl", Sys->OREAD);
	if (ncfd == nil)
		return;
	b := array[128] of byte;
	n := sys->read(ncfd, b, len b);
	id := string int string b[0:n];
	buf := "/mnt/acme/" + id + "/ctl";
	icfd := sys->open(buf, Sys->OWRITE);
	if (icfd == nil)
		return;
	base := hd tl argl;
	for (i := len base - 1; i >= 0; --i)
		if (base[i] == '/') {
			base = base[i+1:];
			break;
	}
	buf = "name " + workdir->init() + "/-" + base + "\n";
	b = array of byte buf;
	sys->write(icfd, b, len b);
	buf = "/mnt/acme/" + id + "/body";
	bfd := sys->open(buf, Sys->OWRITE);
	if (bfd == nil)
		return;
	sys->dup(bfd.fd, 1);
	sys->dup(1, 2);
	spawn exec(hd tl argl, tl argl, ctxt);
	b = array of byte "clean\n";
	sys->write(icfd, b, len b);
}

exec(cmd : string, argl : list of string, ctxt : ref Draw->Context)
{
	file := cmd;
	if(len file<4 || file[len file-4:]!=".dis")
		file += ".dis";
	c := load Command file;
	if(c == nil) {
		err := sys->sprint("%r");
		if(file[0]!='/' && file[0:2]!="./"){
			c = load Command "/dis/"+file;
			if(c == nil)
				err = sys->sprint("%r");
		}
		if(c == nil){
			sys->fprint(sys->fildes(2), "%s: %s\n", cmd, err);
			return;
		}
	}
	c->init(ctxt, argl);
	exit;
}