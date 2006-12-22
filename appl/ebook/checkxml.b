implement Checkxml;

# simple minded xml checker - checks for basic nestedness, and
# prints out more informative context on the error messages than
# the usual xml parser.

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
include "xml.m";
	xml: Xml;
	Parser, Item, Locator: import xml;

stderr: ref Sys->FD;
Checkxml: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	xml = load Xml Xml->PATH;
	if (xml == nil) {
		sys->fprint(stderr, "checkxml: cannot load %s: %r\n", Xml->PATH);
		raise "fail:bad module";
	}
	xml->init();
	if (len argv < 2) {
		sys->fprint(stderr, "usage: checkxml file...\n");
		raise "fail:usage";
	}
	err := 0;
	for (argv = tl argv; argv != nil; argv = tl argv) {
		err = check(hd argv) || err;
	}
	if (err)
		raise "fail:errors";
}

warningproc(warningch: chan of (Locator, string), finch: chan of int, tagstackch: chan of ref Item.Tag)
{
	nw := 0;
	stack: list of ref Item.Tag;
	for (;;) {
		alt {
		(loc, w) := <-warningch =>
			if (w == nil) {
				finch <-= nw;
				exit;
			}
			printerror(loc, w, stack);
			nw++;
		item := <-tagstackch =>
			if (item != nil)
				stack = item :: stack;
			else
				stack = tl stack;
		}
	}
}

printerror(loc: Locator, e: string, tagstack: list of ref Item.Tag)
{
	if (tagstack != nil) {
		sys->print("%s:%d: %s\n", loc.systemid, loc.line, e);
		for (il := tagstack; il != nil; il = tl il)
			sys->print("\t%s:%s: <%s>\n", loc.systemid, o2l(loc.systemid, (hd il).fileoffset), (hd il).name);
	}
}

# convert file offset to line number... not very efficient, but we don't really care.
o2l(f: string, o: int): string
{
	fd := sys->open(f, Sys->OREAD);
	if (fd == nil)
		return "#" + string o;
	buf := array[o] of byte;
	n := sys->read(fd, buf, len buf);
	if (n < o)
		return "#" + string o;
	nl := 1;
	for (i := 0; i < len buf; i++)
		if (buf[i] == byte '\n')
			nl++;
	return string nl;
}

check(f: string): int
{
	spawn warningproc(
			warningch := chan of (Locator, string),
			finch := chan of int,
			tagstackch := chan of ref Item.Tag
	);
	(x, e) := xml->open(f, warningch, nil);
	if (x == nil) {
		sys->fprint(stderr, "%s: %s\n", f, e);
		return -1;
	}
	{
		parse(x, tagstackch, warningch);
		warningch <-= (*ref Locator, nil);
		return <-finch;
	} exception ex {
	"error" =>
		warningch <-= (*ref Locator, nil);
		<-finch;
		return -1;
	}
}

parse(x: ref Xml->Parser, tagstackch: chan of ref Item.Tag, warningch: chan of (Locator, string))
{
	for (;;) {
		item := x.next();
		if (item == nil)
			return;
		pick i := item {
		Error =>
			warningch <-= (i.loc, i.msg);
			raise "error";
		Tag =>
			tagstackch <-= i;
			x.down();
			parse(x, tagstackch, warningch);
			x.up();
			tagstackch <-= nil;
		}
	}
}
