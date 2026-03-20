implement ToolMan;

#
# man - Veltro tool for controlling the wm/man page viewer
#
# Provides AI control over the manual page viewer via real-file IPC
# at /tmp/veltro/man/. The viewer must be running (launch man).
#
# Commands:
#   open [section] title       Open a man page by title
#   open /path/to/file         Open a man page by file path
#   view                       Read visible content
#   state                      Read viewer state
#   scroll up|down|top|bottom  Scroll the view
#   scroll <n>                 Scroll to line number
#   find <text>                Search for text
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "../tool.m";

ToolMan: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

MAN_ROOT: con "/tmp/veltro/man";

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	return nil;
}

name(): string
{
	return "man";
}

doc(): string
{
	return "Man - AI control for the manual page viewer\n\n" +
		"Commands:\n" +
		"  open [section] title       Open a man page (e.g. open 1 ls)\n" +
		"  open /man/1/ls             Open a man page by path\n" +
		"  view                       Read visible page content\n" +
		"  state                      Read viewer state\n" +
		"  scroll up|down|top|bottom  Scroll the view\n" +
		"  scroll <n>                 Scroll to line number\n" +
		"  find <text>                Search for text in the page\n\n" +
		"The man viewer must be running. Use 'launch man' to start it.\n\n" +
		"Examples:\n" +
		"  man open ls                Open the ls(1) man page\n" +
		"  man open 2 sys             Open sys in section 2\n" +
		"  man view                   See what's on screen\n" +
		"  man scroll down            Scroll down one page\n" +
		"  man find SYNOPSIS          Jump to SYNOPSIS section\n";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	args = strip(args);
	if(args == "")
		return "error: no command. Use: open, view, state, scroll, find";

	(cmd, rest) := splitfirst(args);

	case cmd {
	"state" =>
		return readfile(MAN_ROOT + "/state");
	"view" =>
		return readfile(MAN_ROOT + "/view");
	"open" =>
		if(rest == "")
			return "error: open requires a title or path";
		return sendctl("open " + rest);
	"scroll" =>
		if(rest == "")
			return "error: scroll requires direction (up, down, top, bottom) or line number";
		return sendctl("scroll " + rest);
	"find" =>
		if(rest == "")
			return "error: find requires search text";
		return sendctl("find " + rest);
	* =>
		return sys->sprint("error: unknown command '%s'. Use: open, view, state, scroll, find", cmd);
	}
}

sendctl(cmd: string): string
{
	if(cmd == "")
		return "error: empty command";
	err := writefile(MAN_ROOT + "/ctl", cmd);
	if(err != nil)
		return err;
	return "ok";
}

# --- I/O helpers ---

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %%r (is wm/man running?)", path);

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
		return sys->sprint("error: cannot create %s: %%r (is wm/man running?)", path);

	b := array of byte data;
	n := sys->write(fd, b, len b);
	fd = nil;

	if(n != len b)
		return sys->sprint("error: write failed: %%r");

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
