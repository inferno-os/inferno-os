implement Digest;

#
# read a classifier example file and write its digest
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "strokes.m";
	strokes: Strokes;
	Classifier, Penpoint, Stroke: import strokes;
	readstrokes: Readstrokes;
	writestrokes: Writestrokes;

include "arg.m";

Digest: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

usage()
{
	sys->fprint(sys->fildes(2), "Usage: digest [file.cl ...]\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	strokes = load Strokes Strokes->PATH;
	if(strokes == nil)
		nomod(Strokes->PATH);
	strokes->init();
	readstrokes = load Readstrokes Readstrokes->PATH;
	if(readstrokes == nil)
		nomod(Readstrokes->PATH);
	readstrokes->init(strokes);
	writestrokes = load Writestrokes Writestrokes->PATH;
	if(writestrokes == nil)
		nomod(Writestrokes->PATH);
	writestrokes->init(strokes);

	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	arg->init(args);
	while((opt := arg->opt()) != 0)
		case opt {
		* =>
			usage();
		}
	args = arg->argv();
	arg = nil;

	for(; args != nil; args = tl args){
		ofile := file := hd args;
		n := len file;
		if(n >= 3 && ofile[n-3:] == ".cl")
			ofile = ofile[0:n-3];
		ofile += ".clx";
		(err, rec) := readstrokes->read_classifier(hd args, 1, 0);
		if(err != nil)
			error(sys->sprint("error reading classifier from %s: %s", file, err));
		fd := sys->create(ofile, Sys->OWRITE, 8r666);
		if(fd == nil)
			error(sys->sprint("can't create %s: %r", file));
		err = writestrokes->write_digest(fd, rec.cnames, rec.dompts);
		if(err != nil)
			error(sys->sprint("error writing digest to %s: %s", file, err));
	}
}

nomod(s: string)
{
	error(sys->sprint("can't load %s: %r", s));
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "digest: %s\n", s);
	raise "fail:error";
}
