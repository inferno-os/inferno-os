implement Writestrokes;

#
# write structures to classifier files
#

include "sys.m";
	sys: Sys;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "strokes.m";
	strokes: Strokes;
	Penpoint, Stroke: import strokes;

init(s: Strokes)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	strokes = s;
}

write_examples(fd: ref Sys->FD, names: array of string, examples: array of list of ref Stroke): string
{
	fp := bufio->fopen(fd, Bufio->OWRITE);
	nclass := len names;
	fp.puts(sys->sprint("%d\n", nclass));
	for(i := 0; i < nclass; i++){
		exl := examples[i];
		fp.puts(sys->sprint("%d %s\n", len exl, names[i]));
		for(; exl != nil; exl = tl exl){
			putpoints(fp, hd exl);
			fp.putc('\n');
		}
	}
	if(fp.flush() == Bufio->ERROR)
		return sys->sprint("write error: %r");
	fp.close();
	return nil;
}

write_digest(fd: ref Sys->FD, cnames: array of string, dompts: array of ref Stroke): string
{
	fp := bufio->fopen(fd, Bufio->OWRITE);
	n := len cnames;
	for(i := 0; i < n; i++){
		d := dompts[i];
		npts := d.npts;
		fp.puts(cnames[i]);
		putpoints(fp, d);
		fp.putc('\n');
	}
	if(fp.flush() == Bufio->ERROR)
		return sys->sprint("write error: %r");
	fp.close();
	return nil;
}

putpoints(fp: ref Iobuf, d: ref Stroke)
{
	fp.puts(sys->sprint(" %d", d.npts));
	for(j := 0; j < d.npts; j++){
		p := d.pts[j];
		fp.puts(sys->sprint(" %d %d", p.x, p.y));
	}
}
