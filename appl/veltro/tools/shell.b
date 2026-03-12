implement ToolShell;

#
# shell - Veltro tool for observing the shell terminal
#
# Provides read-only access to the shell terminal via its file-based
# interface at /tmp/veltro/shell/.  For safety, Veltro can only read the
# shell transcript and current input line — it cannot send commands.
# Instead, Veltro should propose commands in Chat for the user to run.
#
# Commands:
#   read [body]     Read the shell transcript
#   read input      Read the current input line
#   tail [n]        Read the last n lines of transcript (default 30)
#   status          Show shell status
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolShell: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

SHELL_ROOT: con "/tmp/veltro/shell";

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";
	return nil;
}

name(): string
{
	return "shell";
}

doc(): string
{
	return "Shell - Read-only access to the shell terminal\n\n" +
		"Commands:\n" +
		"  read [body]     Read the full shell transcript\n" +
		"  read input      Read the current input line\n" +
		"  tail [n]        Read the last n lines (default 30)\n" +
		"  status          Check if shell is running\n\n" +
		"NOTE: This tool is READ-ONLY for safety.\n" +
		"You cannot send commands to the shell.\n" +
		"Instead, propose commands in Chat for the user to run.\n\n" +
		"The shell must be running for commands to work.\n" +
		"Use 'launch shell' to start it.\n\n" +
		"Examples:\n" +
		"  shell read              Read transcript\n" +
		"  shell tail              Last 30 lines\n" +
		"  shell tail 50           Last 50 lines\n" +
		"  shell read input        Current input line\n" +
		"  shell status            Check shell status\n";
}

exec(args: string): string
{
	if(sys == nil) {
		err := init();
		if(err != nil)
			return "error: " + err;
	}

	args = strip(args);
	if(args == "")
		return "error: no command. Use: read, tail, status";

	(cmd, rest) := splitfirst(args);
	cmd = str->tolower(cmd);

	case cmd {
	"read" =>
		return doread(rest);
	"tail" =>
		return dotail(rest);
	"status" =>
		return dostatus();
	* =>
		return sys->sprint("error: unknown command '%s'. Use: read, tail, status", cmd);
	}
}

doread(args: string): string
{
	target := strip(args);
	if(target == "" || target == "body") {
		return readfile(sys->sprint("%s/body", SHELL_ROOT));
	}
	if(target == "input") {
		return readfile(sys->sprint("%s/input", SHELL_ROOT));
	}
	return "error: read target must be 'body' or 'input'";
}

dotail(args: string): string
{
	n := 30;
	args = strip(args);
	if(args != "") {
		(v, nil) := str->toint(args, 10);
		if(v > 0)
			n = v;
	}

	body := readfile(sys->sprint("%s/body", SHELL_ROOT));
	if(len body >= 6 && body[0:6] == "error:")
		return body;

	# Split into lines and take last n
	alllines: list of string;
	count := 0;
	start := 0;
	for(i := 0; i < len body; i++) {
		if(body[i] == '\n') {
			alllines = body[start:i] :: alllines;
			count++;
			start = i + 1;
		}
	}
	if(start < len body) {
		alllines = body[start:] :: alllines;
		count++;
	}

	# alllines is in reverse order; take last n
	if(count <= n) {
		return body;
	}

	# Reverse and take
	result := "";
	taken := 0;
	for(; alllines != nil && taken < n; alllines = tl alllines) {
		if(taken > 0)
			result = hd alllines + "\n" + result;
		else
			result = hd alllines;
		taken++;
	}
	return result;
}

dostatus(): string
{
	body := readfile(sys->sprint("%s/body", SHELL_ROOT));
	if(len body >= 6 && body[0:6] == "error:")
		return "shell is not running (not started)";
	# Count lines
	count := 1;
	for(i := 0; i < len body; i++)
		if(body[i] == '\n')
			count++;
	input := readfile(sys->sprint("%s/input", SHELL_ROOT));
	return sys->sprint("shell is running\ntranscript: %d lines\ncurrent input: %s", count, input);
}

# --- I/O helpers ---

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r (is shell running?)", path);

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
