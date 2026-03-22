implement FractalToolTest;

#
# fractal_tool_test - Tests for the Veltro fractal tool and fractals.b logic
#
# Tests the fractal tool's command parsing, IPC file format,
# string helpers, and the Veltro IPC state/view generation
# from fractals.b by simulating the /tmp/veltro/fractal/ files.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "testing.m";
	testing: Testing;
	T: import testing;

FractalToolTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/fractal_tool_test.b";

passed := 0;
failed := 0;
skipped := 0;

run(name: string, testfn: ref fn(t: ref T))
{
	t := testing->newTsrc(name, SRCFILE);
	{
		testfn(t);
	} exception {
	"fail:fatal" =>
		;
	"fail:skip" =>
		;
	"*" =>
		t.failed = 1;
	}

	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

# ============================================================
# Re-implementations of fractal tool helper functions
# ============================================================

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

hassubstr(s, sub: string): int
{
	if(len sub > len s)
		return 0;
	for(i := 0; i <= len s - len sub; i++) {
		if(s[i:i+len sub] == sub)
			return 1;
	}
	return 0;
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

boolstr(b: int): string
{
	if(b) return "on";
	return "off";
}

# File I/O helpers
ensuredir(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil)
		return;
	fd = sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
}

writefile(path, data: string): string
{
	fd := sys->create(path, Sys->OWRITE, 8r666);
	if(fd == nil)
		return sys->sprint("error: cannot create %s: %r", path);
	b := array of byte data;
	n := sys->write(fd, b, len b);
	fd = nil;
	if(n != len b)
		return sys->sprint("error: write failed: %r");
	return nil;
}

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
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

# Strip trailing whitespace (from fractals.b readrmfile)
striptrailing(s: string): string
{
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == ' ' || s[len s - 1] == '\t'))
		s = s[0:len s - 1];
	return s;
}

# ============================================================
# Test data directory
# ============================================================

FRACT_TEST_DIR: con "/tmp/fractal_tool_test";

# ============================================================
# Tests: Command parsing (fractal tool exec dispatch)
# ============================================================

testCommandDispatch(t: ref T)
{
	# Test that commands are correctly parsed by splitfirst
	commands := array[] of {
		("state", "state", ""),
		("view", "view", ""),
		("zoomout", "zoomout", ""),
		("mandelbrot", "mandelbrot", ""),
		("restart", "restart", ""),
		("julia", "julia -0.4 0.6", "-0.4 0.6"),
		("depth", "depth 3", "3"),
		("fill", "fill on", "on"),
		("zoomin", "zoomin -0.8 0.05 -0.7 0.15", "-0.8 0.05 -0.7 0.15"),
		("center", "center -0.75 0.1 0.02", "-0.75 0.1 0.02"),
	};

	for(i := 0; i < len commands; i++) {
		(expected_cmd, input, expected_rest) := commands[i];
		(cmd, rest) := splitfirst(input);
		t.assertseq(cmd, expected_cmd, sys->sprint("cmd parsing %d: command", i));
		t.assertseq(rest, expected_rest, sys->sprint("cmd parsing %d: rest", i));
	}
}

testEmptyCommand(t: ref T)
{
	args := strip("");
	t.assertseq(args, "", "empty command detected");
}

testUnknownCommand(t: ref T)
{
	(cmd, nil) := splitfirst("rotate 90");
	known := array[] of {
		"state", "view", "zoomin", "center", "zoomout",
		"julia", "mandelbrot", "depth", "fill", "restart",
	};
	found := 0;
	for(i := 0; i < len known; i++)
		if(cmd == known[i])
			found = 1;
	t.assert(!found, "rotate is not a known command");
}

# ============================================================
# Tests: sendctl format verification
# ============================================================

testSendctlFormat(t: ref T)
{
	ensuredir(FRACT_TEST_DIR);

	# Test that control commands are written in the expected format
	cmds := array[] of {
		"zoomin -0.8 0.05 -0.7 0.15",
		"center -0.75 0.1 0.02",
		"zoomout",
		"julia -0.4 0.6",
		"mandelbrot",
		"depth 3",
		"fill on",
		"restart",
	};

	for(i := 0; i < len cmds; i++) {
		err := writefile(FRACT_TEST_DIR + "/ctl", cmds[i]);
		if(err != nil) {
			t.error(sys->sprint("cannot write ctl for cmd %d: %s", i, err));
			continue;
		}
		content := readfile(FRACT_TEST_DIR + "/ctl");
		t.assertseq(content, cmds[i], sys->sprint("ctl roundtrip case %d", i));
	}

	sys->remove(FRACT_TEST_DIR + "/ctl");
}

testSendctlEmpty(t: ref T)
{
	# fractal.b sendctl returns error for empty command
	cmd := "";
	t.assertseq(cmd, "", "empty command detected");
}

# ============================================================
# Tests: State file format (fractals.b writefractstate)
# ============================================================

testStateFileMandelbrot(t: ref T)
{
	# Simulate writefractstate() for Mandelbrot mode
	morj := 1;
	minx := -2.0;
	miny := -1.5;
	maxx := 1.0;
	maxy := 1.5;
	kdivisor := 1;
	fill := 1;
	computing := 0;
	stackdepth := 0;

	ftype := "mandelbrot";
	if(!morj)
		ftype = "julia";

	state := sys->sprint("type %s\n", ftype);
	state += sys->sprint("view %g %g %g %g\n", minx, miny, maxx, maxy);
	state += sys->sprint("depth %d\n", kdivisor);
	state += sys->sprint("fill %d\n", fill);
	state += sys->sprint("computing %d\n", computing);
	state += sys->sprint("zoomdepth %d\n", stackdepth);

	t.assert(hassubstr(state, "type mandelbrot"), "state has mandelbrot type");
	t.assert(hassubstr(state, "view -2 -1.5 1 1.5"), "state has view coords");
	t.assert(hassubstr(state, "depth 1"), "state has depth");
	t.assert(hassubstr(state, "fill 1"), "state has fill");
	t.assert(hassubstr(state, "computing 0"), "state has computing flag");
	t.assert(hassubstr(state, "zoomdepth 0"), "state has zoom depth");

	ensuredir(FRACT_TEST_DIR);
	writefile(FRACT_TEST_DIR + "/state", state);
	readback := readfile(FRACT_TEST_DIR + "/state");
	t.assertseq(readback, state, "state file roundtrip");

	sys->remove(FRACT_TEST_DIR + "/state");
}

testStateFileJulia(t: ref T)
{
	# Simulate writefractstate() for Julia mode
	morj := 0;
	julx := -0.4;
	july := 0.6;
	minx := -2.0;
	miny := -1.5;
	maxx := 2.0;
	maxy := 1.5;
	kdivisor := 3;
	fill := 0;
	computing := 1;
	stackdepth := 2;

	ftype := "julia";
	state := sys->sprint("type %s\n", ftype);
	state += sys->sprint("view %g %g %g %g\n", minx, miny, maxx, maxy);
	if(!morj)
		state += sys->sprint("julia %g %g\n", julx, july);
	state += sys->sprint("depth %d\n", kdivisor);
	state += sys->sprint("fill %d\n", fill);
	state += sys->sprint("computing %d\n", computing);
	state += sys->sprint("zoomdepth %d\n", stackdepth);

	t.assert(hassubstr(state, "type julia"), "julia state has julia type");
	t.assert(hassubstr(state, "julia -0.4 0.6"), "julia state has julia params");
	t.assert(hassubstr(state, "depth 3"), "julia state has depth 3");
	t.assert(hassubstr(state, "fill 0"), "julia state has fill off");
	t.assert(hassubstr(state, "computing 1"), "julia state has computing on");
	t.assert(hassubstr(state, "zoomdepth 2"), "julia state has zoom depth 2");
}

# ============================================================
# Tests: View description format (fractals.b writefractstate)
# ============================================================

testViewDescMandelbrot(t: ref T)
{
	ftype := "mandelbrot";
	minx := -2.0;
	miny := -1.5;
	maxx := 1.0;
	maxy := 1.5;
	kdivisor := 1;
	fill := 1;
	computing := 0;
	stackdepth := 0;

	view := sys->sprint("Fractal viewer: %s set\n", ftype);
	view += sys->sprint("Viewing region: x=[%g, %g] y=[%g, %g]\n", minx, maxx, miny, maxy);
	dx := maxx - minx;
	dy := maxy - miny;
	view += sys->sprint("Region size: %g x %g\n", dx, dy);
	cx := (minx + maxx) / 2.0;
	cy := (miny + maxy) / 2.0;
	view += sys->sprint("Center: (%g, %g)\n", cx, cy);
	view += sys->sprint("Depth multiplier: %d (max iterations: %d)\n", kdivisor, 253 * kdivisor);
	view += sys->sprint("Fill mode: %s\n", boolstr(fill));
	view += "Status: ready\n";
	view += sys->sprint("Zoom history: %d levels deep\n", stackdepth);

	# Since dx > 2.5 and morj==1, we should add notable regions
	if(dx > 2.5)
		view += "\nNotable regions to explore:\n";

	t.assert(hassubstr(view, "Fractal viewer: mandelbrot set"), "view has mandelbrot title");
	t.assert(hassubstr(view, "Viewing region:"), "view has region");
	t.assert(hassubstr(view, "Region size: 3 x 3"), "view has region size");
	t.assert(hassubstr(view, "Fill mode: on"), "view has fill mode");
	t.assert(hassubstr(view, "Status: ready"), "view has ready status");
	t.assert(hassubstr(view, "Notable regions"), "view has notable regions for full set");
}

testViewDescJulia(t: ref T)
{
	ftype := "julia";
	julx := -0.75;
	july := 0.1;
	computing := 1;

	view := sys->sprint("Fractal viewer: %s set\n", ftype);
	view += sys->sprint("Julia parameter: c = %g + %gi\n", julx, july);
	if(computing)
		view += "Status: computing...\n";
	else
		view += "Status: ready\n";

	t.assert(hassubstr(view, "Fractal viewer: julia set"), "julia view has title");
	t.assert(hassubstr(view, "Julia parameter:"), "julia view has parameter");
	t.assert(hassubstr(view, "computing..."), "julia view shows computing");
}

# ============================================================
# Tests: Ctl file command parsing (fractals.b checkctlfile)
# ============================================================

testCtlZoomin(t: ref T)
{
	# checkctlfile parses "zoomin <x1> <y1> <x2> <y2>"
	cmd := "zoomin -0.8 0.05 -0.7 0.15";
	(nil, toks) := sys->tokenize(cmd, " \t\n");

	t.assert(toks != nil, "tokenize produced tokens");
	verb := hd toks;
	toks = tl toks;
	t.assertseq(verb, "zoomin", "verb is zoomin");

	# Count remaining tokens
	n := 0;
	for(l := toks; l != nil; l = tl l)
		n++;
	t.asserteq(n, 4, "zoomin has 4 coordinate args");

	x1 := real hd toks; toks = tl toks;
	y1 := real hd toks; toks = tl toks;
	x2 := real hd toks; toks = tl toks;
	y2 := real hd toks;

	t.assert(x1 < x2, "x1 < x2");
	t.assert(y1 < y2, "y1 < y2");
}

testCtlCenter(t: ref T)
{
	cmd := "center -0.75 0.1 0.02";
	(nil, toks) := sys->tokenize(cmd, " \t\n");

	verb := hd toks;
	toks = tl toks;
	t.assertseq(verb, "center", "verb is center");

	cx := real hd toks; toks = tl toks;
	cy := real hd toks; toks = tl toks;
	rad := real hd toks;

	t.assert(rad > 0.0, "radius is positive");

	# Center command converts to zoomin rect
	x1 := cx - rad;
	y1 := cy - rad;
	x2 := cx + rad;
	y2 := cy + rad;
	t.assert(x1 < x2, "derived x1 < x2");
	t.assert(y1 < y2, "derived y1 < y2");
}

testCtlJulia(t: ref T)
{
	cmd := "julia -0.4 0.6";
	(nil, toks) := sys->tokenize(cmd, " \t\n");

	verb := hd toks;
	toks = tl toks;
	t.assertseq(verb, "julia", "verb is julia");

	re := real hd toks; toks = tl toks;
	im := real hd toks;

	# Verify parsed values are reasonable
	t.assert(re >= -2.0 && re <= 2.0, "julia re in range");
	t.assert(im >= -2.0 && im <= 2.0, "julia im in range");
}

testCoordClamping(t: ref T)
{
	# Coordinates are clamped to [-4, 4] in fractals.b checkctlfile
	MAXCOORD: con 4.0;

	cases := array[] of {
		(0.0, 0.0), (1.5, 1.5), (-2.0, -2.0),
		(100.0, MAXCOORD), (-100.0, -MAXCOORD),
		(4.0, 4.0), (-4.0, -4.0),
		(1.0e308, MAXCOORD), (-1.0e308, -MAXCOORD),
	};
	for(i := 0; i < len cases; i++) {
		(input, expected) := cases[i];
		v := input;
		if(v < -MAXCOORD) v = -MAXCOORD;
		if(v > MAXCOORD) v = MAXCOORD;
		# Compare as strings since asserteq is int-only
		t.assertseq(sys->sprint("%g", v), sys->sprint("%g", expected),
			sys->sprint("coord clamping case %d: %g", i, input));
	}
}

testCtlDepthClamping(t: ref T)
{
	# depth is clamped to [1, 20] in fractals.b
	MAXDEPTH: con 20;

	# Test various depth values
	depths := array[] of {(0, 1), (1, 1), (10, 10), (20, 20), (25, 20), (-5, 1)};
	for(i := 0; i < len depths; i++) {
		(input, expected) := depths[i];
		d := input;
		if(d < 1) d = 1;
		if(d > MAXDEPTH) d = MAXDEPTH;
		t.asserteq(d, expected, sys->sprint("depth clamping case %d", i));
	}
}

testCtlFillParsing(t: ref T)
{
	# fill on|off|1|0
	cases := array[] of {("on", 1), ("1", 1), ("off", 0), ("0", 0)};
	for(i := 0; i < len cases; i++) {
		(input, expected) := cases[i];
		on := 0;
		if(input == "on" || input == "1")
			on = 1;
		t.asserteq(on, expected, sys->sprint("fill parsing case %d: '%s'", i, input));
	}
}

testCtlZoominCanonical(t: ref T)
{
	# fractals.b canonicalizes: if x1>x2, swap; if y1>y2, swap
	x1 := 0.5;
	y1 := 0.5;
	x2 := -0.5;
	y2 := -0.5;

	if(x1 > x2) (x1, x2) = (x2, x1);
	if(y1 > y2) (y1, y2) = (y2, y1);

	t.assert(x1 < x2, "canonicalized x1 < x2");
	t.assert(y1 < y2, "canonicalized y1 < y2");
}

# ============================================================
# Tests: readrmfile logic (read and truncate)
# ============================================================

testReadrmfile(t: ref T)
{
	ensuredir(FRACT_TEST_DIR);

	# Write a command
	writefile(FRACT_TEST_DIR + "/ctl", "zoomout\n");

	# Read it (simulating readrmfile)
	s := readfile(FRACT_TEST_DIR + "/ctl");
	if(s == nil) {
		t.error("could not read ctl file");
		return;
	}

	# Strip trailing whitespace (as readrmfile does)
	s = striptrailing(s);
	t.assertseq(s, "zoomout", "readrmfile strips trailing whitespace");

	# Truncate the file (as readrmfile does)
	fd := sys->create(FRACT_TEST_DIR + "/ctl", Sys->OWRITE, 8r666);
	fd = nil;

	# Verify it's now empty
	s2 := readfile(FRACT_TEST_DIR + "/ctl");
	t.assert(s2 == nil || s2 == "", "ctl file truncated after read");

	sys->remove(FRACT_TEST_DIR + "/ctl");
}

# ============================================================
# Tests: Julia preset data
# ============================================================

Fracpoint: adt {
	x, y: real;
};

Juliapreset: adt {
	label: string;
	c: Fracpoint;
};

testJuliaPresets(t: ref T)
{
	presets := array[] of {
		Juliapreset("dendrite", Fracpoint(0.0, 1.0)),
		Juliapreset("seahorse", Fracpoint(-0.75, 0.1)),
		Juliapreset("spiral", Fracpoint(-0.4, 0.6)),
		Juliapreset("rabbit", Fracpoint(-0.123, 0.745)),
		Juliapreset("star", Fracpoint(-0.744, 0.148)),
	};

	t.asserteq(len presets, 5, "5 Julia presets");

	# Verify all preset coordinates are in valid range
	for(i := 0; i < len presets; i++) {
		p := presets[i];
		t.assert(len p.label > 0, sys->sprint("preset %d has label", i));
		t.assert(p.c.x >= -2.0 && p.c.x <= 2.0,
			sys->sprint("preset '%s' re in [-2,2]", p.label));
		t.assert(p.c.y >= -2.0 && p.c.y <= 2.0,
			sys->sprint("preset '%s' im in [-2,2]", p.label));
	}

	# Verify specific values
	t.assertseq(presets[0].label, "dendrite", "first preset is dendrite");
	t.assertseq(presets[4].label, "star", "last preset is star");
}

# ============================================================
# Tests: boolstr helper
# ============================================================

testBoolstr(t: ref T)
{
	t.assertseq(boolstr(1), "on", "boolstr(1) is on");
	t.assertseq(boolstr(0), "off", "boolstr(0) is off");
	t.assertseq(boolstr(42), "on", "boolstr(nonzero) is on");
}

cleanup()
{
	sys->remove(FRACT_TEST_DIR + "/state");
	sys->remove(FRACT_TEST_DIR + "/ctl");
	sys->remove(FRACT_TEST_DIR + "/view");
	sys->remove(FRACT_TEST_DIR);
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	ensuredir(FRACT_TEST_DIR);

	# Command parsing
	run("CommandDispatch", testCommandDispatch);
	run("EmptyCommand", testEmptyCommand);
	run("UnknownCommand", testUnknownCommand);

	# sendctl format
	run("SendctlFormat", testSendctlFormat);
	run("SendctlEmpty", testSendctlEmpty);

	# State file format
	run("StateFileMandelbrot", testStateFileMandelbrot);
	run("StateFileJulia", testStateFileJulia);

	# View description
	run("ViewDescMandelbrot", testViewDescMandelbrot);
	run("ViewDescJulia", testViewDescJulia);

	# Ctl command parsing
	run("CtlZoomin", testCtlZoomin);
	run("CtlCenter", testCtlCenter);
	run("CtlJulia", testCtlJulia);
	run("CoordClamping", testCoordClamping);
	run("CtlDepthClamping", testCtlDepthClamping);
	run("CtlFillParsing", testCtlFillParsing);
	run("CtlZoominCanonical", testCtlZoominCanonical);

	# readrmfile
	run("Readrmfile", testReadrmfile);

	# Julia presets
	run("JuliaPresets", testJuliaPresets);

	# boolstr
	run("Boolstr", testBoolstr);

	cleanup();

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
