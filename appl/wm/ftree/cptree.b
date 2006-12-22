implement Cptree;

include "sys.m";
	sys: Sys;
include "draw.m";
include "readdir.m";
	readdir: Readdir;
include "cptree.m";

init()
{
	sys = load Sys Sys->PATH;
	readdir = load Readdir Readdir->PATH;
}

Context: adt {
	progressch: chan of string;
	warningch: chan of (string, chan of int);
	finishedch: chan of string;
};

# recursively copy file/directory f into directory d;
# the name remains the same.
copyproc(f, d: string, progressch: chan of string,
		warningch: chan of (string, chan of int),
		finishedch: chan of string)
{
	ctxt := ref Context(progressch, warningch, finishedch);
	(fok, fstat) := sys->stat(f);
	if (fok == -1)
		error(ctxt, sys->sprint("cannot stat '%s': %r", f));
	(dok, dstat) := sys->stat(d);
	if (dok == -1)
		error(ctxt, sys->sprint("cannot stat '%s': %r", d));
	if ((dstat.mode & Sys->DMDIR) == 0)
		error(ctxt, sys->sprint("'%s' is not a directory", d));
	if (fstat.qid.path == dstat.qid.path)
		error(ctxt, sys->sprint("'%s' and '%s' are identical", f, d));

	c := d + "/" + fname(f);
	(cok, cstat) := sys->stat(c);
	if (cok == 0)
		error(ctxt, sys->sprint("'%s' already exists", c));
	rcopy(ctxt, f, ref fstat, c);
	finishedch <-= nil;
}

rcopy(ctxt: ref Context, src: string, srcstat: ref Sys->Dir, dst: string)
{
	omode := Sys->OWRITE;
	perm := srcstat.mode;
	if (perm & Sys->DMDIR) {
		omode = Sys->OREAD;
		perm |= 8r300;
	}

	dstfd := sys->create(dst, omode, perm);
	if (dstfd == nil) {
		warning(ctxt, sys->sprint("cannot create '%s': %r", dst));
		return;
	}
	if (srcstat.mode & Sys->DMDIR) {
		(entries, n) := readdir->init(src, Readdir->NAME | Readdir->COMPACT);
		if (n == -1)
			warning(ctxt, sys->sprint("cannot read dir '%s': %r", src));
		for (i := 0; i < len entries; i++) {
			e := entries[i];
			rcopy(ctxt, src + "/" + e.name, e, dst + "/" + e.name);
		}
		if (perm != srcstat.mode) {
			(ok, nil) := sys->fstat(dstfd);
			if (ok != -1) {
				dststat := sys->nulldir;
				dststat.mode = srcstat.mode;
				sys->fwstat(dstfd, dststat);
			}
		}
	} else {
		srcfd := sys->open(src, Sys->OREAD);
		if (srcfd == nil) {
			sys->remove(dst);
			warning(ctxt, sys->sprint("cannot open '%s': %r", src));
			return;
		}
		ctxt.progressch <-= "copying " + src;
		buf := array[Sys->ATOMICIO] of byte;
		while ((n := sys->read(srcfd, buf, len buf)) > 0) {
			if (sys->write(dstfd, buf, n) != n) {
				sys->remove(dst);
				warning(ctxt, sys->sprint("error writing '%s': %r", dst));
				return;
			}
		}
		if (n == -1) {
			sys->remove(dst);
			warning(ctxt, sys->sprint("error reading '%s': %r", src));
			return;
		}
	}
}

warning(ctxt: ref Context, msg: string)
{
	r := chan of int;
	ctxt.warningch <-= (msg, r);
	if (!<-r)
		exit;
}

error(ctxt: ref Context, msg: string)
{
	ctxt.finishedch <-= msg;
	exit;
}

fname(f: string): string
{
	f = cleanname(f);
	for (i := len f - 1; i >= 0; i--)
		if (f[i] == '/')
			break;
	return f[i+1:];
}

cleanname(s: string): string
{
	t := "";
	i := 0;
	while (i < len s)
		if ((t[len t] = s[i++]) == '/')
			while (i < len s && s[i] == '/')
				i++;
	if (len t > 1 && t[len t - 1] == '/')
		t = t[0:len t - 1];
	return t;
}
