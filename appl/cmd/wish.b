implement Test;

include "sys.m";
include "draw.m";
draw: Draw;
Screen, Display, Image: import draw;
include "tk.m";

Test: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

tk: Tk;
sys: Sys;

init(nil: ref Draw->Context, argv: list of string)
{
	cmd: string;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;

	display := Display.allocate(nil);
	if(display == nil) {
		sys->print("can't initialize display: %r\n");
		return;
	}

	disp := display.image;
	screen := Screen.allocate(disp, display.rgb(161, 195, 209), 1);
	if(screen == nil) {
		sys->print("can't allocate screen: %r\n");
		return;
	}
	fd := sys->open("/dev/pointer", sys->OREAD);
	if(fd == nil) {
		sys->print("open: %s: %r\n", "/dev/pointer");
		sys->print("run wm/wish instead\n");
		return;
	}

	t := tk->toplevel(display, "");
	spawn mouse(t, fd);
	spawn keyboard(t);
	disp.draw(disp.r, screen.fill, nil, disp.r.min);

	input := array[8192] of byte;
	stdin := sys->fildes(0);

	if(argv != nil)
		argv = tl argv;
	while(argv != nil) {
		exec(t, hd argv);
		argv = tl argv;
	}

	for(;;) {
		tk->cmd(t, "update");

		prompt := '%';
		if(cmd != nil)
			prompt = '>';
		sys->print("%c ", prompt);

		n := sys->read(stdin, input, len input);
		if(n <= 0)
			break;
		if(n == 1)
			continue;
		cmd += string input[0:n-1];
		if(cmd[len cmd-1] != '\\') {
			cmd = esc(cmd);
			s := tk->cmd(t, cmd);
			if(len s != 0)
				sys->print("%s\n", s);
			cmd = nil;
			continue;
		}
		cmd = cmd[0:len cmd-1];
	}
}

esc(s: string): string
{
	c: int;

	for(i := 0; i < len s; i++) {
		if(s[i] != '\\')
			continue;
		case s[i+1] {
		'n'=>	c = '\n';
		't'=>	c = '\t';
		'b'=>	c = '\b';
		'\\'=>	c = '\\';
		* =>	c = 0;
		}
		if(c != 0) {
			s[i] = c;
			s = s[0:i+1]+s[i+2:len s];
		}
	}
	return s;
}

exec(t: ref Tk->Toplevel, path: string)
{
	fd := sys->open(path, sys->OREAD);
	if(fd == nil) {
		sys->print("open: %s: %r\n", path);
		return;
	}
	(ok, d) := sys->fstat(fd);
	if(ok < 0) {
		sys->print("fstat: %s: %r\n", path);
		return;
	}
	buf := array[int d.length] of byte;
	if(sys->read(fd, buf, len buf) < 0) {
		sys->print("read: %s: %r\n", path);
		return;
	}
	(n, l) := sys->tokenize(string buf, "\n");
	buf = nil;
	n = -1;
	for(; l != nil; l = tl l) {
		n++;
		s := hd l;
		if(len s == 0 || s[0] == '#')
			continue;

		while(s[len s-1] == '\\') {
			s = s[0:len s-1];
			if(tl l != nil) {
				l = tl l;
				s = s + hd l;
			}
			else
				break;
		}

		s = tk->cmd(t, esc(s));

		if(len s != 0 && s[0] == '!') {
			sys->print("%s:%d %s\n", path, n, s);
			sys->print("%s:%d %s\n", path, n, hd l);
		}
	}
}

mouse(t: ref Tk->Toplevel, fd: ref Sys->FD)
{
	n := 0;
	buf := array[100] of byte;
	for(;;) {
		n = sys->read(fd, buf, len buf);
		if(n <= 0)
			break;

		if(int buf[0] == 'm' && n >= 1+3*12) {
			x := int(string buf[ 1:13]);
			y := int(string buf[12:25]);
			b := int(string buf[24:37]);
			tk->pointer(t, Draw->Pointer(b, Draw->Point(x, y), sys->millisec()));
		}
	}
}

keyboard(t: ref Tk->Toplevel)
{
	dfd := sys->open("/dev/keyboard", sys->OREAD);
	if(dfd == nil)
		return;

	b:= array[1] of byte;
	buf := array[10] of byte;
	i := 0;
	for(;;) {
		n := sys->read(dfd, buf[i:], len buf - i);
		if(n < 1)
			break;
		i += n;
		while(i >0 && (nutf := sys->utfbytes(buf, i)) > 0){
			s := string buf[0:nutf];
			tk->keyboard(t, int s[0]);
			buf[0:] = buf[nutf:i];
			i -= nutf;
		}
	}
}
