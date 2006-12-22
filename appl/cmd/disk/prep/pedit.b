implement Pedit;

#
# disk partition editor
#

include "sys.m";
	sys: Sys;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "disks.m";
	disks: Disks;
	Disk: import disks;
	readn: import disks;

include "draw.m";
include "calc.tab.m";
	calc: Calc;

include "pedit.m";

Cmd: adt {
	c: int;
	f:	ref fn(e: ref Edit, a: array of string): string;
};

cmds: array of Cmd;

bin: ref Iobuf;

init()
{
	sys = load Sys Sys->PATH;
	calc = load Calc "/dis/disk/calc.tab.dis";
	bufio = load Bufio Bufio->PATH;
	disks = load Disks Disks->PATH;
	disks->init();

	bin = bufio->fopen(sys->fildes(0), Bufio->OREAD);
	cmds = array[] of {
		('.',	editdot),
		('a',	editadd),
		('d',	editdel),
		('?',	edithelp),
		('h',	edithelp),
		('P',	editctlprint),
		('p',	editprint),
		('w',	editwrite),
		('q',	editquit),
	};
}

Edit.mk(unit: string): ref Edit
{
	e := ref Edit;
	e.unit = unit;
	e.dot = big 0;
	e.end = big 0;
	e.changed = 0;
	e.warned = 0;
	e.lastcmd = 0;
	return e;
}

Edit.getline(edit: self ref Edit): string
{
	p := bin.gets('\n');
	if(p == nil){
		if(edit.changed)
			sys->fprint(sys->fildes(2), "?warning: changes not written\n");
		exit;
	}
	for(i := 0; i < len p; i++)
		if(!isspace(p[i]))
			break;
	if(i)
		return p[i:];
	return p;
}

Edit.findpart(edit: self ref Edit, name: string): ref Part
{
	for(i:=0; i<len edit.part; i++)
		if(edit.part[i].name == name)
			return edit.part[i];
	return nil;
}

okname(edit: ref Edit, name: string): string
{
	if(name[0] == '\0')
		return "partition has no name";

	for(i:=0; i<len edit.part; i++) {
		if(name == edit.part[i].name)
			return sys->sprint("already have partition with name '%s'", name);
	}
	return nil;
}

Edit.addpart(edit: self ref Edit, p: ref Part): string
{
	if((err := okname(edit, p.name)) != nil)
		return err;

	for(i:=0; i<len edit.part; i++) {
		if(p.start < edit.part[i].end && edit.part[i].start < p.end) {
			msg := sys->sprint("\"%s\" %bd-%bd overlaps with \"%s\" %bd-%bd",
				p.name, p.start, p.end,
				edit.part[i].name, edit.part[i].start, edit.part[i].end);
		#	return msg;
		}
	}

	if(len edit.part >= Maxpart)
		return "too many partitions";

	pa := array[i+1] of ref Part;
	pa[0:] = edit.part;
	edit.part = pa;

	edit.part[i] = p;
	for(; i > 0 && p.start < edit.part[i-1].start; i--) {
		edit.part[i] = edit.part[i-1];
		edit.part[i-1] = p;
	}

	if(p.changed)
		edit.changed = 1;
	return nil;
}

Edit.delpart(edit: self ref Edit, p: ref Part): string
{
	n := len edit.part;
	for(i:=0; i<n; i++)
		if(edit.part[i] == p)
			break;
	if(i >= n)
		raise "internal error: Part not found";
	n--;
	pa := array[n] of ref Part;
	if(n){
		pa[0:] = edit.part[0:i];
		if(i != n)
			pa[i:] = edit.part[i+1:];
	}
	edit.part = pa;
	edit.changed = 1;
	return nil;
}

editdot(edit: ref Edit, argv: array of string): string
{
	if(len argv == 1) {
		sys->print("\t. %bd\n", edit.dot);
		return nil;
	}

	if(len argv > 2)
		return "args";

	(ndot, err) := calc->parseexpr(argv[1], edit.dot, edit.end, edit.end);
	if(err != nil)
		return err;

	edit.dot = ndot;
	return nil;
}

editadd(edit: ref Edit, argv: array of string): string
{
	if(len argv < 2)
		return "args";

	name := argv[1];
	if((err := okname(edit, name)) != nil || edit.okname != nil && (err = edit.okname(edit, name)) != nil)
		return err;

	if(len argv >= 3)
		q := argv[2];
	else {
		sys->fprint(sys->fildes(2), "start %s: ", edit.unit);
		q = edit.getline();
	}
	start: big;
	(start, err) = calc->parseexpr(q, edit.dot, edit.end, edit.end);
	if(err != nil)
		return err;

	if(start < big 0 || start >= edit.end)
		return "start out of range";

	for(i:=0; i < len edit.part; i++) {
		if(edit.part[i].start <= start && start < edit.part[i].end)
			return sys->sprint("start %s in partition '%s'", edit.unit, edit.part[i].name);
	}

	maxend := edit.end;
	for(i=0; i < len edit.part; i++)
		if(start < edit.part[i].start && edit.part[i].start < maxend)
			maxend = edit.part[i].start;

	if(len argv >= 4)
		q = argv[3];
	else {
		sys->fprint(sys->fildes(2), "end [%bd..%bd] ", start, maxend);
		q = edit.getline();
	}
	end: big;
	(end, err) = calc->parseexpr(q, edit.dot, maxend, edit.end);
	if(err != nil)
		return err;

	if(start == end)
		return "size zero partition";

	if(end <= start || end > maxend)
		return "end out of range";

	if(len argv > 4)
		return "args";

	if((err = edit.add(edit, name, start, end)) != nil)
		return err;

	edit.dot = end;
	return nil;
}

editdel(edit: ref Edit, argv: array of string): string
{
	if(len argv != 2)
		return "args";

	if((p := edit.findpart(argv[1])) == nil)
		return "no such partition";

	return edit.del(edit, p);
}

helptext :=
	". [newdot] - display or set value of dot\n"+
	"a name [start [end]] - add partition\n"+
	"d name - delete partition\n"+
	"h - sys->print help message\n"+
	"p - sys->print partition table\n"+
	"P - sys->print commands to update sd(3) device\n"+
	"w - write partition table\n"+
	"q - quit\n";

edithelp(edit: ref Edit, nil: array of string): string
{
	sys->print("%s", helptext);
	if(edit.help != nil)
		return edit.help(edit);
	return nil;
}

editprint(edit: ref Edit, argv: array of string): string
{
	if(len argv != 1)
		return "args";

	lastend := big 0;
	part := edit.part;
	for(i:=0; i<len edit.part; i++) {
		if(lastend < part[i].start)
			edit.sum(edit, nil, lastend, part[i].start);
		edit.sum(edit, part[i], part[i].start, part[i].end);
		lastend = part[i].end;
	}
	if(lastend < edit.end)
		edit.sum(edit, nil, lastend, edit.end);
	return nil;
}

editwrite(edit: ref Edit, argv: array of string): string
{
	if(len argv != 1)
		return "args";

	if(edit.disk.rdonly)
		return "read only";

	err := edit.write(edit);
	if(err != nil)
		return err;
	for(i:=0; i<len edit.part; i++)
		edit.part[i].changed = 0;
	edit.changed = 0;
	return nil;
}

editquit(edit: ref Edit, argv: array of string): string
{
	if(len argv != 1) {
		edit.warned = 0;
		return "args";
	}

	if(edit.changed && (!edit.warned || edit.lastcmd != 'q')) {
		edit.warned = 1;
		return "changes unwritten";
	}

	exit;
}

editctlprint(edit: ref Edit, argv: array of string): string
{
	if(len argv != 1)
		return "args";

	if(edit.printctl != nil)
		edit.printctl(edit, sys->fildes(1));
	else
		edit.ctldiff(sys->fildes(1));
	return nil;
}

Edit.runcmd(edit: self ref Edit, cmd: string)
{
	(nf, fl) := sys->tokenize(cmd, " \t\n\r");
	if(nf < 1)
		return;
	f := array[nf] of string;
	for(nf = 0; fl != nil; fl = tl fl)
		f[nf++] = hd fl;
	if(len f[0] != 1) {
		sys->fprint(sys->fildes(2), "?\n");
		return;
	}

	err := "";
	for(i:=0; i<len cmds; i++) {
		if(cmds[i].c == f[0][0]) {
			op := cmds[i].f;
			err = op(edit, f);
			break;
		}
	}
	if(i == len cmds){
		if(edit.ext != nil)
			err = edit.ext(edit, f);
		else
			err = "unknown command";
	}
	if(err != nil) 
		sys->fprint(sys->fildes(2), "?%s\n", err);
	edit.lastcmd = f[0][0];
}

isspace(c: int): int
{
	return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

ctlmkpart(name: string, start: big, end: big, changed: int): ref Part
{
	p := ref Part;
	p.name = name;
	p.ctlname = name;
	p.start = start;
	p.end = end;
	p.ctlstart = big 0;
	p.ctlend = big 0;
	p.changed = changed;
	return p;
}

rdctlpart(edit: ref Edit)
{
	disk := edit.disk;
	edit.ctlpart = array[0] of ref Part;
	sys->seek(disk.ctlfd, big 0, 0);
	buf := array[4096] of byte;
	if(readn(disk.ctlfd, buf, len buf) <= 0)
		return;
	for(i := 0; i < len buf; i++)
		if(buf[i] == byte 0)
			break;

	(nline, lines) := sys->tokenize(string buf[0:i], "\n\r");
	edit.ctlpart = array[nline] of ref Part;	# upper bound
	npart := 0;
	for(i=0; i<nline; i++){
		line := hd lines;
		lines = tl lines;
		if(len line < 5 || line[0:5] != "part ")
			continue;

		(nf, f) := sys->tokenize(line, " \t");
		if(nf != 4 || hd f != "part")
			break;

		a := big hd tl tl f;
		b := big hd tl tl tl f;

		if(a >= b)
			break;

		# only gather partitions contained in the disk partition we are editing
		if(a < disk.offset ||  disk.offset+disk.secs < b)
			continue;

		a -= disk.offset;
		b -= disk.offset;

		# the partition we are editing does not count
		if(hd tl f == disk.part)
			continue;

		edit.ctlpart[npart++] = ctlmkpart(hd tl f, a, b, 0);
	}
	if(npart != len edit.ctlpart)
		edit.ctlpart = edit.ctlpart[0:npart];
}

ctlstart(p: ref Part): big
{
	if(p.ctlstart != big 0)
		return p.ctlstart;
	return p.start;
}

ctlend(p: ref Part): big
{
	if(p.ctlend != big 0)
		return p.ctlend;
	return p.end;
}

areequiv(p: ref Part, q: ref Part): int
{
	if(p.ctlname == nil || q.ctlname == nil)
		return 0;
	return p.ctlname == q.ctlname &&
			ctlstart(p) == ctlstart(q) && ctlend(p) == ctlend(q);
}

unchange(edit: ref Edit, p: ref Part)
{
	for(i:=0; i<len edit.ctlpart; i++) {
		q := edit.ctlpart[i];
		if(p.start <= q.start && q.end <= p.end)
			q.changed = 0;
	}
	if(p.changed)
		raise "internal error: Part unchanged";
}

Edit.ctldiff(edit: self ref Edit, ctlfd: ref Sys->FD): int
{
	rdctlpart(edit);

	# everything is bogus until we prove otherwise
	for(i:=0; i<len edit.ctlpart; i++)
		edit.ctlpart[i].changed = 1;

	#
	# partitions with same info have not changed,
	# and neither have partitions inside them.
	#
	for(i=0; i<len edit.ctlpart; i++)
		for(j:=0; j<len edit.part; j++)
			if(areequiv(edit.ctlpart[i], edit.part[j])) {
				unchange(edit, edit.ctlpart[i]);
				break;
			}

	waserr := 0;
	#
	# delete all the changed partitions except data (we'll add them back if necessary) 
	#
	for(i=0; i<len edit.ctlpart; i++) {
		p := edit.ctlpart[i];
		if(p.changed)
		if(sys->fprint(ctlfd, "delpart %s\n", p.ctlname)<0) {
			sys->fprint(sys->fildes(2), "delpart failed: %s: %r\n", p.ctlname);
			waserr = -1;
		}
	}

	#
	# add all the partitions from the real list;
	# this is okay since adding a partition with
	# information identical to what is there is a no-op.
	#
	offset := edit.disk.offset;
	for(i=0; i<len edit.part; i++) {
		p := edit.part[i];
		if(p.ctlname != nil) {
			if(sys->fprint(ctlfd, "part %s %bd %bd\n", p.ctlname, offset+ctlstart(p), offset+ctlend(p)) < 0) {
				sys->fprint(sys->fildes(2), "adding part failed: %s: %r\n", p.ctlname);
				waserr = -1;
			}
		}
	}
	return waserr;
}
