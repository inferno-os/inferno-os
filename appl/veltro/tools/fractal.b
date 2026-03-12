implement ToolFractal;

#
# fractal - Veltro tool for controlling the Mandelbrot/Julia viewer
#
# Provides AI control over the fractal viewer via real-file IPC
# at /tmp/veltro/fractal/. The viewer must be running (launch fractals).
#
# Commands:
#   state                          Read fractal state (type, coords, depth)
#   view                           Read view description (AI-friendly)
#   zoomin <x1> <y1> <x2> <y2>    Zoom to fractal coordinate region
#   center <re> <im> <radius>     Zoom to center point with radius
#   zoomout                        Go back one zoom level
#   julia <re> <im>               Show Julia set for c = re + im*i
#   mandelbrot                     Switch back to Mandelbrot set
#   depth <n>                      Set depth multiplier (1=default)
#   fill on|off                    Toggle boundary-trace fill mode
#   restart                        Restart current computation
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "../tool.m";

ToolFractal: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

FRACT_ROOT: con "/tmp/veltro/fractal";

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	return nil;
}

name(): string
{
	return "fractal";
}

doc(): string
{
	return "Fractal - AI control for the Mandelbrot/Julia fractal viewer\n\n" +
		"Commands:\n" +
		"  state                          Read fractal state\n" +
		"  view                           Read AI-friendly view description\n" +
		"  zoomin <x1> <y1> <x2> <y2>    Zoom to fractal coordinates\n" +
		"  center <re> <im> <radius>     Zoom centered on point\n" +
		"  zoomout                        Go back one zoom level\n" +
		"  julia <re> <im>               Show Julia set for c\n" +
		"  mandelbrot                     Return to Mandelbrot set\n" +
		"  depth <n>                      Set depth multiplier\n" +
		"  fill on|off                    Toggle fill mode\n" +
		"  restart                        Restart computation\n\n" +
		"The fractal viewer must be running. Use 'launch fractals' to start it.\n\n" +
		"Coordinates are in the complex plane:\n" +
		"  Full Mandelbrot: x=[-2, 1] y=[-1.5, 1.5]\n" +
		"  Interesting spots:\n" +
		"    Seahorse valley: center -0.75 0.1 0.05\n" +
		"    Elephant valley: center 0.28 0.008 0.01\n" +
		"    Mini-Mandelbrot: center -1.768 0.002 0.01\n\n" +
		"Examples:\n" +
		"  fractal view                            See current state\n" +
		"  fractal zoomin -0.8 0.05 -0.7 0.15      Zoom into seahorse valley\n" +
		"  fractal center -0.75 0.1 0.02           Zoom centered on point\n" +
		"  fractal julia -0.4 0.6                  Show Julia set\n" +
		"  fractal depth 3                          Increase detail\n" +
		"  fractal zoomout                          Go back\n";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	args = strip(args);
	if(args == "")
		return "error: no command. Use: state, view, zoomin, center, zoomout, julia, mandelbrot, depth, fill, restart";

	(cmd, rest) := splitfirst(args);

	case cmd {
	"state" =>
		return readfile(FRACT_ROOT + "/state");
	"view" =>
		return readfile(FRACT_ROOT + "/view");
	"zoomin" =>
		return sendctl("zoomin " + rest);
	"center" =>
		return sendctl("center " + rest);
	"zoomout" =>
		return sendctl("zoomout");
	"julia" =>
		return sendctl("julia " + rest);
	"mandelbrot" =>
		return sendctl("mandelbrot");
	"depth" =>
		return sendctl("depth " + rest);
	"fill" =>
		return sendctl("fill " + rest);
	"restart" =>
		return sendctl("restart");
	* =>
		return sys->sprint("error: unknown command '%s'", cmd);
	}
}

sendctl(cmd: string): string
{
	if(cmd == "")
		return "error: empty command";
	err := writefile(FRACT_ROOT + "/ctl", cmd);
	if(err != nil)
		return err;
	return "ok";
}

# --- I/O helpers ---

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r (is fractals running?)", path);

	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	fd = nil;
	return result;
}

writefile(path, data: string): string
{
	fd := sys->create(path, Sys->OWRITE, 8r666);
	if(fd == nil)
		return sys->sprint("error: cannot create %s: %r (is fractals running?)", path);

	b := array of byte data;
	n := sys->write(fd, b, len b);
	fd = nil;

	if(n != len b)
		return sys->sprint("error: write failed: %r");

	return nil;
}

# --- String helpers ---

strip(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n'))
		j--;
	if(i >= j)
		return "";
	return s[i:j];
}

splitfirst(s: string): (string, string)
{
	s = strip(s);
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t')
			return (s[0:i], strip(s[i:]));
	}
	return (s, "");
}
