implement ToolLuciedit;

#
# luciedit - Veltro tool for controlling the Luciedit text editor
#
# Provides AI control over the Luciedit editor via its 9P filesystem
# interface at /edit/. Supports reading/writing document body, cursor
# positioning, search, and file operations.
#
# Commands:
#   read [body|addr]           Read document body or cursor address
#   write <text>               Replace document body
#   append <text>              Append text to body
#   save                       Save current file
#   open <path>                Open file in editor
#   goto <line>                Move cursor to line
#   find <string>              Search for text
#   addr                       Get cursor position
#   insert <line> <col> <text> Insert text at position
#   delete <sl> <sc> <el> <ec> Delete range
#   name <path>                Set file path
#   close                      Close editor
#   status                     Show editor status
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolLuciedit: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

EDIT_ROOT: con "/edit";

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
	return "luciedit";
}

doc(): string
{
	return "Luciedit - AI control for the Luciedit text editor\n\n" +
		"Commands:\n" +
		"  read [body]              Read document body text\n" +
		"  read addr                Read cursor position (line col)\n" +
		"  write <text>             Replace entire document body\n" +
		"  append <text>            Append text to body\n" +
		"  save                     Save current file\n" +
		"  open <path>              Open file in editor\n" +
		"  goto <line>              Move cursor to line number\n" +
		"  find <string>            Search for text in document\n" +
		"  addr                     Get cursor position (line col)\n" +
		"  insert <ln> <col> <text> Insert text at position\n" +
		"  delete <sl> <sc> <el> <ec>  Delete range\n" +
		"  name <path>              Set file path without loading\n" +
		"  close                    Close editor (quit)\n" +
		"  status                   Show document info\n\n" +
		"The editor must be running for commands to work.\n" +
		"Use 'launch luciedit' to start it, or 'open <path>'\n" +
		"which sends the open command to an already-running editor.\n\n" +
		"Examples:\n" +
		"  luciedit open /usr/me/file.b    Open a file\n" +
		"  luciedit read                   Read the document\n" +
		"  luciedit write Hello world      Replace body\n" +
		"  luciedit goto 42                Jump to line 42\n" +
		"  luciedit find TODO              Search for TODO\n" +
		"  luciedit save                   Save to disk\n";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	args = strip(args);
	if(args == "")
		return "error: no command. Use: read, write, append, save, open, goto, find, addr, insert, delete, name, close, status";

	(cmd, rest) := splitfirst(args);
	cmd = str->tolower(cmd);

	case cmd {
	"read" =>
		return doread(rest);
	"write" =>
		return dowrite(rest);
	"append" =>
		return doappend(rest);
	"save" =>
		return dosave();
	"open" =>
		return doopen(rest);
	"goto" =>
		return dogoto(rest);
	"find" =>
		return dofind(rest);
	"addr" =>
		return doaddr();
	"insert" =>
		return doinsert(rest);
	"delete" =>
		return dodelete(rest);
	"name" =>
		return doname(rest);
	"close" =>
		return doclose();
	"status" =>
		return dostatus();
	* =>
		return sys->sprint("error: unknown command '%s'", cmd);
	}
}

doread(args: string): string
{
	target := strip(args);
	if(target == "" || target == "body") {
		return readfile(sys->sprint("%s/1/body", EDIT_ROOT));
	}
	if(target == "addr") {
		return doaddr();
	}
	return "error: read target must be 'body' or 'addr'";
}

dowrite(text: string): string
{
	if(text == "")
		return "error: usage: write <text>";
	return writefile(sys->sprint("%s/1/body", EDIT_ROOT), text);
}

doappend(text: string): string
{
	if(text == "")
		return "error: usage: append <text>";
	# Read current body, append, write back
	body := readfile(sys->sprint("%s/1/body", EDIT_ROOT));
	if(len body >= 6 && body[0:6] == "error:")
		return body;
	newbody := body + text;
	return writefile(sys->sprint("%s/1/body", EDIT_ROOT), newbody);
}

dosave(): string
{
	return writefile(sys->sprint("%s/1/ctl", EDIT_ROOT), "save");
}

doopen(path: string): string
{
	path = strip(path);
	if(path == "")
		return "error: usage: open <path>";
	return writefile(sys->sprint("%s/ctl", EDIT_ROOT), "open " + path);
}

dogoto(args: string): string
{
	args = strip(args);
	if(args == "")
		return "error: usage: goto <line>";
	return writefile(sys->sprint("%s/1/ctl", EDIT_ROOT), "goto " + args);
}

dofind(args: string): string
{
	if(args == "")
		return "error: usage: find <string>";
	return writefile(sys->sprint("%s/1/ctl", EDIT_ROOT), "find " + args);
}

doaddr(): string
{
	return readfile(sys->sprint("%s/1/addr", EDIT_ROOT));
}

doinsert(args: string): string
{
	if(args == "")
		return "error: usage: insert <line> <col> <text>";
	return writefile(sys->sprint("%s/1/ctl", EDIT_ROOT), "insert " + args);
}

dodelete(args: string): string
{
	if(args == "")
		return "error: usage: delete <startline> <startcol> <endline> <endcol>";
	return writefile(sys->sprint("%s/1/ctl", EDIT_ROOT), "delete " + args);
}

doname(args: string): string
{
	args = strip(args);
	if(args == "")
		return "error: usage: name <path>";
	return writefile(sys->sprint("%s/1/ctl", EDIT_ROOT), "name " + args);
}

doclose(): string
{
	return writefile(sys->sprint("%s/ctl", EDIT_ROOT), "quit");
}

dostatus(): string
{
	return readfile(sys->sprint("%s/index", EDIT_ROOT));
}

# --- I/O helpers ---

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r (is luciedit running?)", path);

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
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r (is luciedit running?)", path);

	b := array of byte data;
	n := sys->write(fd, b, len b);
	fd = nil;

	if(n != len b)
		return sys->sprint("error: write failed: %r");

	return "ok";
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
