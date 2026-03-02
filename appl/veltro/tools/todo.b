implement ToolTodo;

#
# todo - Agent task list tool for Veltro
#
# Provides a lightweight ordered task list for agent working memory.
# Items are stored in the active session directory when VELTRO_SESSION is set,
# otherwise in /tmp/veltro/todo.txt.  Format: n|status|text per line.
#
# Usage:
#   todo add <text>    # Add a pending item
#   todo list          # Show all items with status
#   todo done <n>      # Mark item N as done
#   todo delete <n>    # Remove item N
#   todo clear         # Remove all items
#   todo status        # One-line summary (n pending, m done)
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolTodo: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

TODO_DEFAULT: con "/tmp/veltro/todo.txt";

# Resolved at init time from VELTRO_SESSION env, or TODO_DEFAULT
todofile: string;

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";
	todofile = gettodofile();
	return nil;
}

# Determine todo file path from VELTRO_SESSION environment variable.
# Falls back to TODO_DEFAULT when the env var is absent or empty.
gettodofile(): string
{
	fd := sys->open("/env/VELTRO_SESSION", Sys->OREAD);
	if(fd == nil)
		return TODO_DEFAULT;
	buf := array[512] of byte;
	n := sys->read(fd, buf, len buf);
	fd = nil;
	if(n <= 0)
		return TODO_DEFAULT;
	sdir := string buf[0:n];
	# Trim trailing whitespace
	j := len sdir;
	while(j > 0 && (sdir[j-1] == ' ' || sdir[j-1] == '\n' || sdir[j-1] == '\r'))
		j--;
	sdir = sdir[0:j];
	if(sdir == "")
		return TODO_DEFAULT;
	return sdir + "/todo.txt";
}

# Return the directory containing todofile
tododir(): string
{
	f := todofile;
	for(i := len f - 1; i > 0; i--) {
		if(f[i] == '/')
			return f[0:i];
	}
	return "/tmp/veltro";
}

name(): string
{
	return "todo";
}

doc(): string
{
	return "Todo - Agent task list\n\n" +
		"Usage:\n" +
		"  todo add <text>    # Add a pending item\n" +
		"  todo list          # Show all items with status\n" +
		"  todo done <n>      # Mark item N as done\n" +
		"  todo delete <n>    # Remove item N\n" +
		"  todo clear         # Remove all items\n" +
		"  todo status        # One-line summary\n\n" +
		"List format:\n" +
		"  1 [pending] Explore the codebase\n" +
		"  2 [done]    Read the relevant files\n\n" +
		"Items persist in the session directory (or /tmp/veltro) across tool calls.\n" +
		"Use todo to decompose complex tasks into tracked steps.";
}

exec(args: string): string
{
	if(sys == nil)
		init();
	if(todofile == "")
		todofile = gettodofile();

	args = strip(args);
	if(args == "")
		return "error: usage: todo <add|list|done|delete|clear|status> [args...]";

	(cmd, rest) := splitfirst(args);
	cmd = str->tolower(cmd);

	case cmd {
	"add" =>
		return doadd(rest);
	"list" =>
		return dolist();
	"done" =>
		return dodone(rest);
	"delete" =>
		return dodelete(rest);
	"clear" =>
		return doclear();
	"status" =>
		return dostatus();
	* =>
		return "error: unknown command: " + cmd;
	}
}

# Add a new pending item
doadd(text: string): string
{
	text = strip(text);
	if(text == "")
		return "error: usage: todo add <text>";

	items := loaditems();

	# Find the highest existing ID
	maxid := 0;
	for(l := items; l != nil; l = tl l) {
		(idstr, nil) := spliton(hd l, '|');
		id := int(idstr);
		if(id > maxid)
			maxid = id;
	}

	newid := maxid + 1;
	newitem := string newid + "|pending|" + text;
	newitems := appenditem(items, newitem);

	err := writeitems(newitems);
	if(err != nil)
		return "error: " + err;

	return sys->sprint("added item %d: %s", newid, text);
}

# List all items
dolist(): string
{
	items := loaditems();
	if(items == nil)
		return "(no items)";

	npending := 0;
	ndone := 0;
	l: list of string;
	for(l = items; l != nil; l = tl l) {
		(nil, rest) := spliton(hd l, '|');
		(status, nil) := spliton(rest, '|');
		if(status == "done")
			ndone++;
		else
			npending++;
	}

	n := npending + ndone;
	sfx := "s";
	if(n == 1)
		sfx = "";
	result := sys->sprint("%d item%s (%d pending, %d done):\n",
		n, sfx, npending, ndone);

	for(l = items; l != nil; l = tl l) {
		item := hd l;
		(idstr, rest) := spliton(item, '|');
		(status, text) := spliton(rest, '|');
		result += sys->sprint("%s [%s] %s\n", idstr, status, text);
	}

	# Strip trailing newline
	if(len result > 0 && result[len result - 1] == '\n')
		result = result[0:len result - 1];

	return result;
}

# Mark item N as done
dodone(nstr: string): string
{
	nstr = strip(nstr);
	if(nstr == "")
		return "error: usage: todo done <n>";

	n := int(nstr);
	if(n <= 0)
		return "error: invalid item number: " + nstr;

	items := loaditems();
	found := 0;
	foundtext := "";
	acc: list of string;

	for(l := items; l != nil; l = tl l) {
		item := hd l;
		(idstr, rest) := spliton(item, '|');
		if(int(idstr) == n) {
			(nil, text) := spliton(rest, '|');
			acc = (idstr + "|done|" + text) :: acc;
			found = 1;
			foundtext = text;
		} else {
			acc = item :: acc;
		}
	}

	if(!found)
		return sys->sprint("error: item %d not found", n);

	err := writeitems(reverselist(acc));
	if(err != nil)
		return "error: " + err;

	return sys->sprint("item %d done: %s", n, foundtext);
}

# Delete item N
dodelete(nstr: string): string
{
	nstr = strip(nstr);
	if(nstr == "")
		return "error: usage: todo delete <n>";

	n := int(nstr);
	if(n <= 0)
		return "error: invalid item number: " + nstr;

	items := loaditems();
	found := 0;
	foundtext := "";
	acc: list of string;

	for(l := items; l != nil; l = tl l) {
		item := hd l;
		(idstr, rest) := spliton(item, '|');
		if(int(idstr) == n) {
			(nil, text) := spliton(rest, '|');
			found = 1;
			foundtext = text;
			# Omit from acc — this deletes the item
		} else {
			acc = item :: acc;
		}
	}

	if(!found)
		return sys->sprint("error: item %d not found", n);

	err := writeitems(reverselist(acc));
	if(err != nil)
		return "error: " + err;

	return sys->sprint("deleted item %d: %s", n, foundtext);
}

# Remove all items
doclear(): string
{
	items := loaditems();
	n := listlen(items);
	if(n == 0)
		return "cleared 0 items";

	sys->remove(todofile);

	sfx := "s";
	if(n == 1)
		sfx = "";
	return sys->sprint("cleared %d item%s", n, sfx);
}

# One-line status summary
dostatus(): string
{
	items := loaditems();
	if(items == nil)
		return "0 items: 0 pending, 0 done";

	npending := 0;
	ndone := 0;
	for(l := items; l != nil; l = tl l) {
		(nil, rest) := spliton(hd l, '|');
		(status, nil) := spliton(rest, '|');
		if(status == "done")
			ndone++;
		else
			npending++;
	}

	n := npending + ndone;
	sfx := "s";
	if(n == 1)
		sfx = "";
	return sys->sprint("%d item%s: %d pending, %d done",
		n, sfx, npending, ndone);
}

# Load items from file; returns list of "n|status|text" strings in order
loaditems(): list of string
{
	(content, err) := readfile(todofile);
	if(err != nil)
		return nil;

	items: list of string;
	nc := len content;
	i := 0;
	while(i <= nc) {
		# Find end of line
		j := i;
		while(j < nc && content[j] != '\n')
			j++;
		line := strip(content[i:j]);
		if(line != "")
			items = line :: items;
		i = j + 1;
	}
	return reverselist(items);
}

# Write items list back to file; nil list removes the file
writeitems(items: list of string): string
{
	err := ensuredir(tododir());
	if(err != nil)
		return err;

	if(items == nil) {
		sys->remove(todofile);
		return nil;
	}

	content := "";
	for(l := items; l != nil; l = tl l) {
		if(content != "")
			content += "\n";
		content += hd l;
	}

	fd := sys->create(todofile, Sys->OWRITE, 8r600);
	if(fd == nil)
		return sys->sprint("cannot create %s: %r", todofile);

	data := array of byte content;
	if(sys->write(fd, data, len data) < 0) {
		fd = nil;
		return sys->sprint("write failed: %r");
	}
	fd = nil;
	return nil;
}

# Append item to end of list (recursive)
appenditem(items: list of string, item: string): list of string
{
	if(items == nil)
		return item :: nil;
	return hd items :: appenditem(tl items, item);
}

# Reverse a list of strings
reverselist(l: list of string): list of string
{
	rev: list of string;
	for(; l != nil; l = tl l)
		rev = hd l :: rev;
	return rev;
}

# Count list length
listlen(l: list of string): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

# Split s on first occurrence of character c
# Returns (before, after) where after does not include c
spliton(s: string, c: int): (string, string)
{
	for(i := 0; i < len s; i++) {
		if(s[i] == c)
			return (s[0:i], s[i+1:]);
	}
	return (s, "");
}

# Ensure directory exists, creating parents as needed
ensuredir(path: string): string
{
	(ok, nil) := sys->stat(path);
	if(ok >= 0)
		return nil;

	parent := "";
	for(i := len path - 1; i > 0; i--) {
		if(path[i] == '/') {
			parent = path[0:i];
			break;
		}
	}
	if(parent != "" && parent != "/") {
		err := ensuredir(parent);
		if(err != nil)
			return err;
	}

	fd := sys->create(path, Sys->OREAD, 8r700 | Sys->DMDIR);
	if(fd == nil)
		return sys->sprint("cannot create %s: %r", path);
	fd = nil;
	return nil;
}

# Read entire file contents; returns ("", error) on failure
readfile(path: string): (string, string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return ("", sys->sprint("cannot open %s: %r", path));

	content := "";
	buf := array[8192] of byte;
	while((n := sys->read(fd, buf, len buf)) > 0)
		content += string buf[0:n];

	fd = nil;
	return (content, nil);
}

# Strip leading and trailing whitespace
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

# Split on first whitespace; strips leading whitespace from the second part
splitfirst(s: string): (string, string)
{
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t')
			return (s[0:i], strip(s[i:]));
	}
	return (s, "");
}
