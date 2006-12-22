implement Cmp;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;

include "arg.m";

BUF: con 65536;
stderr: ref Sys->FD;

Cmp: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	lflag := Lflag := sflag := 0;
	buf1 := array[BUF] of byte;
	buf2 := array[BUF] of byte;

	stderr = sys->fildes(2);

	arg := load Arg Arg->PATH;	
	if(arg == nil){
		sys->fprint(stderr, "cmp: cannot load %s: %r\n", Arg->PATH);
		raise "fail:load";
	}
	arg->init(args);
	while((op := arg->opt()) != 0)
		case op {
		'l' =>		lflag = 1;
		'L' =>	Lflag = 1;
		's' =>		sflag = 1;
		* =>		usage();
		}
	args = arg->argv();
	arg = nil;
	if(args == nil)
		usage();

	if(len args < 2)
		usage();
	name1 := hd args;
	args = tl args;

	if((f1 := sys->open(name1, Sys->OREAD)) == nil){
		sys->fprint(stderr, "cmp: can't open %s: %r\n",name1);
		raise "fail:open";
	}
	name2 := hd args;
	args = tl args;

	if((f2 := sys->open(name2, Sys->OREAD)) == nil){
		sys->fprint(stderr, "cmp: can't open %s: %r\n",name2);
		raise "fail:open";
	}

	if(args != nil){
		o := big hd args;
		if(sys->seek(f1, o, 0) < big 0){
			sys->fprint(stderr, "cmp: seek by offset1 failed: %r\n");
			raise "fail:seek 1";
		}
		args = tl args;
	}

	if(args != nil){
		o := big hd args;
		if(sys->seek(f2, o, 0) < big 0){
			sys->fprint(stderr, "cmp: seek by offset2 failed: %r");
			raise "fail:seek 2";
		}
		args = tl args;
	}
	if(args != nil)
		usage();
	nc := big 1;
	l := big 1;
	diff := 0;
	b1, b2: array of byte;
	for(;;){
		if(len b1 == 0){
			nr := sys->read(f1, buf1, BUF);
			if(nr < 0){
				if(!sflag)
					sys->print("error on %s after %bd bytes\n", name1, nc-big 1);
				raise "fail:read error";
			}
			b1 = buf1[0: nr];
		}
		if(len b2 == 0){
			nr := sys->read(f2, buf2, BUF);
			if(nr < 0){
				if(!sflag)
					sys->print("error on %s after %bd bytes\n", name2, nc-big 1);
				raise "fail:read error";
			}
			b2 = buf2[0: nr];
		}
		n := len b2;
		if(n > len b1)
			n = len b1;
		if(n == 0)
			break;
		for(i:=0; i<n; i++){
			if(Lflag && b1[i]== byte '\n')
				l++;
			if(b1[i] != b2[i]){
				if(!lflag){
					if(!sflag){
						sys->print("%s %s differ: char %bd", name1, name2, nc+big i);
						if(Lflag)
							sys->print(" line %bd\n", l);
						else
							sys->print("\n");
					}
					raise "fail:differ";
				}
				sys->print("%6bd 0x%.2x 0x%.2x\n", nc+big i, int b1[i], int b2[i]);
				diff = 1;
			}
		}
		nc += big n;
		b1 = b1[n:];
		b2 = b2[n:];
	}
	if(len b1 != len b2) {
		nc--;
		if(len b1 > len b2)
			sys->print("EOF on %s after %bd bytes\n", name2, nc);
		else 
			sys->print("EOF on %s after %bd bytes\n", name1, nc);
		raise "fail:EOF";
	}
	if(diff)
		raise "fail:differ";
	exit;
}


usage() 
{
	sys->fprint(stderr, "Usage: cmp [-lsL] file1 file2 [offset1 [offset2] ]\n");
	raise "fail:usage";
}
