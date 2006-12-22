implement Adiff;

include "sys.m";
include "draw.m";
include "sh.m";
include "workdir.m";
include "bufio.m";

Adiff : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

sys : Sys;

Context : import Draw;
OREAD, OWRITE, QTDIR, FD, FORKFD, open, read, write, sprint, fprint, stat, fildes, dup, pctl : import sys;

init(ctxt : ref Context, argl : list of string)
{
	sys = load Sys Sys->PATH;
	workdir := load Workdir Workdir->PATH;
	stderr := fildes(2);
	if (len argl != 3) {
		fprint(stderr, "usage: adiff file1 file2\n");
		return;
	}
	ncfd := open("/chan/new/ctl", OREAD);
	if (ncfd == nil) {
		fprint(stderr, "cannot open ctl file\n");
		return;
	}
	b := array[128] of byte;
	n := read(ncfd, b, len b);
	id := string int string b[0:n];
	f1 := hd tl argl;
	f2 := hd tl tl argl;
	(ok1, d1) := stat(f1);
	if (ok1 < 0) {
		fprint(stderr, "cannot stat %s\n", f1);
		return;
	}
	(ok2, d2) := stat(f2);
	if (ok2 < 0) {
		fprint(stderr, "cannot stat %s\n", f2);
		return;
	}
	if (d1.qid.qtype & QTDIR)
		f1 = f1 + "/" + basename(f2);
	else if (d2.qid.qtype & QTDIR)
		f2 = f2 + "/" + basename(f1);
	buf := "/chan/" + id + "/ctl";
	icfd := open(buf, OWRITE);
	if (icfd == nil) {
		fprint(stderr, "cannot open control file\n");
		return;
	}
	buf = "name " + workdir->init() + "/-diff-" + f1 + "\n";
	b = array of byte buf;
	write(icfd, b, len b);

	fds := array[2] of ref FD;
	if (sys->pipe(fds) < 0) {
		fprint(stderr, "can't pipe\n");
		return;
	}
	buf = "/chan/" + id + "/body";
	bfd := open(buf, OWRITE);
	if (bfd == nil) {
		fprint(stderr, "cannot open body file\n");
		return;
	}
	spawn diff(fds[1], f1, f2, ctxt);
	fds[1] = nil;
	awk(fds[0], bfd, f1, f2);
	b = array of byte "clean\n";
	write(icfd, b, len b);
}

strchr(s : string, c : int) : int
{
	for (i := 0; i < len s; i++)
		if (s[i] == c)
			return i;
	return -1;
}
	
strchrs(s, pat : string) : int
{
	for (i := 0; i < len s; i++)
		if (strchr(pat, s[i]) >= 0)
			return i;
	return -1;
}

awk(ifd, ofd : ref FD, f1, f2 : string)
{
	bufio := load Bufio Bufio->PATH;
	Iobuf : import bufio;
	b := bufio->fopen(ifd, OREAD);
	while ((s := b.gets('\n')) != nil) {
		if (s[0] >= '1' && s[0] <= '9') {
			if ((n := strchrs(s, "acd")) >= 0)
				s = f1 + ":" + s[0:n] + " " + s[n:n+1] + " " + f2 + ":" + s[n+1:];
		}
		fprint(ofd, "%s", s);
	}
}

diff(ofd : ref FD, f1, f2 : string, ctxt : ref Context)
{
	args : list of string;

	pctl(FORKFD, nil);
	fd := open("/dev/null", OREAD);
	dup(fd.fd, 0);
	fd = nil;
	dup(ofd.fd, 1);
	dup(1, 2);
	ofd = nil;
	args = nil;
	args = f2 :: args;
	args = f1 :: args;
	args = "diff" :: args;
	exec("diff", args, ctxt);
	exit;
}

exec(cmd : string, argl : list of string, ctxt : ref Context)
{
	file := cmd;
	if(len file<4 || file[len file-4:]!=".dis")
		file += ".dis";
	c := load Command file;
	if(c == nil) {
		err := sprint("%r");
		if(file[0]!='/' && file[0:2]!="./"){
			c = load Command "/dis/"+file;
			if(c == nil)
				err = sprint("%r");
		}
		if(c == nil){
			fprint(fildes(2), "%s: %s\n", cmd, err);
			return;
		}
	}
	c->init(ctxt, argl);
}

basename(s : string) : string
{
	for (i := len s -1; i >= 0; --i)
		if (s[i] == '/')
			return s[i+1:];
	return s;
}
