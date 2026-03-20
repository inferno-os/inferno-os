implement Man2txt;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw : Draw;
	Font: import draw;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "env.m";
	env: Env;
include "man.m";
include "arg.m";
	arg: Arg;

Man2txt: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

W: adt {
	textwidth: fn(w: self ref W, text: Parseman->Text): int;
};

R: adt {
	textwidth: fn(w: self ref R, text: Parseman->Text): int;
};

output: ref Iobuf;
ROMAN: con "/fonts/lucidasans/euro.8.font";
rfont : ref Font;
rflag := 0;
pagew := 80;

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	env = load Env Env->PATH;
	bufio = load Bufio Bufio->PATH;
	arg = load Arg Arg->PATH;
	if (bufio == nil) {
		sys->print("man2txt: cannot load Bufio: %r\n");
		raise "fail:init";
	}
	if (arg == nil) {
		sys->print("man2txt: cannot load Arg: %r\n");
		raise "fail:init";
	}

	stdout := sys->fildes(1);
	output = bufio->fopen(stdout, Sys->OWRITE);

	parser := load Parseman Parseman->PATH;
	if (parser == nil) {
		sys->print("man2txt: cannot load Parseman: %r\n");
		raise "fail:init";
	}
	err := parser->init();
	if (err != nil) {
		sys->print("man2txt: %s\n", err);
		raise "fail:init";
	}
	arg->init(argv);
	while((c := arg->opt()))
		case c {
		'r' =>
			rflag = 1;
		'p' =>
			s := arg->arg();
			if(s != nil) {
				(v, nil) := str2int(s);
				if(v > 0)
					pagew = v;
			}
		}


	argv = arg->argv();
	for (; argv != nil ; argv = tl argv) {
		fname := hd argv;
		fd := sys->open(fname, Sys->OREAD);
		if (fd == nil) {
			sys->print("man2txt: cannot open %s: %r\n", fname);
			continue;
		}
		font := ROMAN;
		if(env != nil) {
			efont := env->getenv("font");
			if(efont != nil)
				font = efont;
		}
		m: Parseman->Metrics;
		datachan := chan of list of (int, Parseman->Text);
		if(ctxt != nil && ctxt.display != nil && !rflag){
			rfont = Font.open(ctxt.display, font);
			if(rfont == nil)
				rfont = Font.open(ctxt.display, "*default*");
			if(rfont != nil) {
				em := rfont.width("m");
				en := rfont.width("n");
				m = Parseman->Metrics(490, 80, em, en, 14, 40, 20);
				spawn parser->parseman(fd, m, 1, ref W, datachan);
			} else {
				# Font open failed; fall back to text mode
				m = Parseman->Metrics(pagew, 10, 1, 1, 1, 3, 3);
				spawn parser->parseman(fd, m, 1, ref R, datachan);
			}
		}else{
			m = Parseman->Metrics(pagew, 10, 1, 1, 1, 3, 3);
			spawn parser->parseman(fd, m, 1, ref R, datachan);
		}
		for (;;) {
			line := <- datachan;
			if (line == nil)
				break;
			if(rfont != nil && ctxt != nil && !rflag)
				setline(line);
			else
				osetline(line);
		}
		output.flush();
	}
	output.close();
}

str2int(s: string): (int, string)
{
	n := 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c < '0' || c > '9')
			return (n, s[i:]);
		n = n * 10 + (c - '0');
	}
	return (n, nil);
}

W.textwidth(nil: self ref W, text: Parseman->Text): int
{
	return rfont.width(text.text);
}

R.textwidth(nil: self ref R, text: Parseman->Text): int
{
	return len text.text;
}

setline(line: list of (int, Parseman->Text))
{
	offset := 0;
	spacew := rfont.width(" ");
	if(spacew < 1)
		spacew = 1;
	for (; line != nil; line = tl line) {
		(indent, txt) := hd line;
		# indent is in dots
		indent = indent / spacew;
		while (offset < indent) {
			output.putc(' ');
			offset++;
		}
		output.puts(txt.text);
		offset += (rfont.width(txt.text) / spacew);
	}
	output.putc('\n');
}

osetline(line: list of (int, Parseman->Text))
{
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
