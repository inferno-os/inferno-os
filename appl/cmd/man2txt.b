implement Man2txt;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "man.m";

Man2txt: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

W: adt {
	textwidth: fn(w: self ref W, text: Parseman->Text): int;
};

output: ref Iobuf;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->print("cannot load Bufio module: %r\n");
		raise "fail:init";
	}

	stdout := sys->fildes(1);
	output = bufio->fopen(stdout, Sys->OWRITE);

	parser := load Parseman Parseman->PATH;
	parser->init();

	argv = tl argv;
	for (; argv != nil ; argv = tl argv) {
		fname := hd argv;
		fd := sys->open(fname, Sys->OREAD);
		if (fd == nil) {
			sys->print("cannot open %s: %r\n", fname);
			continue;
		}
		m := Parseman->Metrics(65, 1, 1, 1, 1, 5, 2);
		
		datachan := chan of list of (int, Parseman->Text);
		w: ref W;
		spawn parser->parseman(fd, m, 1, w, datachan);
		for (;;) {
			line := <- datachan;
			if (line == nil)
				break;
			setline(line);
		}
		output.flush();
	}
	output.close();
}

W.textwidth(nil: self ref W, text: Parseman->Text): int
{
	return len text.text;
}

setline(line: list of (int, Parseman->Text))
{
#return;
	offset := 0;
	for (; line != nil; line = tl line) {
		(indent, txt) := hd line;
		while (offset < indent) {
			output.putc(' ');
			offset++;
		}
		output.puts(txt.text);
		offset += len txt.text;
	}
	output.putc('\n');
}
