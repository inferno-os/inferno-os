implement ToolXenith;

#
# xenith - Xenith UI control tool for Veltro agent
#
# Provides AI control over Xenith's Acme-style windowing system.
# Windows are exposed via the file server at /chan/.
#
# SECURITY (namespace-based):
# Body reads use the process namespace as the access boundary.
# The window's file path (from its tag) is stat'd against the
# current (restricted) namespace. If stat fails, the file is
# outside the agent's namespace and the body read is denied.
# Windows created by this agent are always readable.
# Mutations (write, append, ctl, etc.) require ownership.
# Tag reads and list are always allowed for discovery.
#
# Commands:
#   create [name]              - Create new window, returns ID
#   write <id> body <text>     - Write text to window body (owned only)
#   write <id> tag <text>      - Write text to window tag (owned only)
#   read <id> [body|tag]       - Read window content (body: namespace check)
#   append <id> <text>         - Append text to body (owned only)
#   ctl <id> <commands>        - Send control commands (owned only)
#   colors <id> <settings>     - Set window colors (owned only)
#   delete <id>                - Delete window (owned only)
#   list                       - List all windows (always allowed)
#   status <id> <state>        - Set visual status (owned only)
#
# Status colors (for AI feedback):
#   ok    - Green tag (success)
#   warn  - Yellow tag (warning)
#   error - Red tag (error)
#   info  - Blue tag (information)
#   reset - Default colors
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolXenith: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

XENITH_ROOT: con "/chan";

# Windows created by this agent — only these can be read/written/modified
owned: list of string;

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";
	owned = nil;
	return nil;
}

name(): string
{
	return "xenith";
}

doc(): string
{
	return "Xenith - AI control for Xenith windowing system\n\n" +
		"Commands:\n" +
		"  create [name]              Create new window, returns ID\n" +
		"  write <id> body <text>     Write text to window body\n" +
		"  write <id> tag <text>      Write text to window tag  \n" +
		"  read <id> [body|tag]       Read window content (body: namespace check)\n" +
		"  append <id> <text>         Append text to body\n" +
		"  ctl <id> <commands>        Send control commands\n" +
		"  colors <id> <settings>     Set window colors\n" +
		"  delete <id>                Delete window\n" +
		"  list                       List all windows (tag names visible)\n" +
		"  status <id> <state>        Set visual status indicator\n\n" +
		"Body reads use namespace-based access control: the window's file\n" +
		"path must be accessible in the agent's namespace. Modifications\n" +
		"are restricted to windows created by this agent.\n\n" +
		"Status states: ok (green), warn (yellow), error (red), info (blue), reset\n\n" +
		"Control commands (for ctl):\n" +
		"  name <string>    Set window name/title\n" +
		"  clean            Mark as unmodified\n" +
		"  show             Scroll to cursor position\n" +
		"  grow             Moderate growth in column\n" +
		"  growmax          Maximum size in column\n" +
		"  growfull         Full column height\n" +
		"  moveto <y>       Move to Y position\n" +
		"  tocol <n> [y]    Move to column n\n" +
		"  noscroll         Disable auto-scroll on write\n" +
		"  scroll           Enable auto-scroll\n\n" +
		"Examples:\n" +
		"  xenith create output        Create window named 'output'\n" +
		"  xenith write 3 body Hello   Write 'Hello' to window 3 body\n" +
		"  xenith status 3 ok          Set green status on window 3\n" +
		"  xenith ctl 3 growmax        Maximize window 3\n";
}

# Check if window was created by this agent
isowned(winid: string): int
{
	for(w := owned; w != nil; w = tl w)
		if(hd w == winid)
			return 1;
	return 0;
}

# Namespace-based access check for body reads.
# The window's file path (first token in tag) is stat'd against
# the process's restricted namespace. If the path (or its parent
# directory for synthetic windows like +Errors) is accessible,
# the body read is allowed. Windows created by this agent are
# always accessible.
checkbodyaccess(winid: string): string
{
	# Agent's own windows are always readable
	if(isowned(winid))
		return nil;

	# Read the window's tag to determine what file it shows
	tagpath := sys->sprint("%s/%s/tag", XENITH_ROOT, winid);
	fd := sys->open(tagpath, Sys->OREAD);
	if(fd == nil)
		return sys->sprint("error: cannot read window %s", winid);

	buf := array[4096] of byte;
	n := sys->read(fd, buf, len buf);
	fd = nil;
	if(n <= 0)
		return sys->sprint("error: cannot read window %s tag", winid);

	tag := string buf[0:n];

	# Extract the window name/path (first token in tag)
	(wpath, nil) := splitfirst(tag);
	if(wpath == "")
		return sys->sprint("error: access denied — window %s has no path", winid);

	# Check if the path is accessible in our namespace
	(ok, nil) := sys->stat(wpath);
	if(ok >= 0)
		return nil;  # path accessible — allow body read

	# For synthetic windows (+Errors, +Veltro, etc.), check parent dir
	parent := dirname(wpath);
	if(parent != wpath) {
		(ok2, nil) := sys->stat(parent);
		if(ok2 >= 0)
			return nil;  # parent dir accessible — allow body read
	}

	return sys->sprint("error: access denied — %s is outside agent namespace", wpath);
}

# Extract parent directory from path
dirname(path: string): string
{
	for(i := len path - 1; i > 0; i--)
		if(path[i] == '/')
			return path[0:i];
	return "/";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	args = strip(args);
	if(args == "")
		return "error: no command specified. Use: create, write, read, append, ctl, colors, delete, list, status";

	# Parse command
	(cmd, rest) := splitfirst(args);
	cmd = str->tolower(cmd);

	case cmd {
	"create" =>
		return docreate(rest);
	"write" =>
		return dowrite(rest);
	"read" =>
		return doread(rest);
	"append" =>
		return doappend(rest);
	"ctl" =>
		return doctl(rest);
	"colors" =>
		return docolors(rest);
	"delete" =>
		return dodelete(rest);
	"list" =>
		return dolist();
	"status" =>
		return dostatus(rest);
	* =>
		return sys->sprint("error: unknown command '%s'", cmd);
	}
}

# Create a new window
docreate(args: string): string
{
	winname := strip(args);

	# Create window by writing to new/ctl
	newctl := XENITH_ROOT + "/new/ctl";
	fd := sys->open(newctl, Sys->ORDWR);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r (is Xenith running?)", newctl);

	# Write empty string to create, read back ID
	sys->write(fd, array[0] of byte, 0);

	buf := array[64] of byte;
	n := sys->read(fd, buf, len buf);
	fd = nil;

	if(n <= 0)
		return "error: failed to create window";

	# ctl returns "id  tag  body  ..." — extract just the window ID (first token)
	(winid, nil) := splitfirst(string buf[0:n]);

	# Track ownership
	owned = winid :: owned;

	# Set name if provided
	if(winname != "") {
		ctlpath := sys->sprint("%s/%s/ctl", XENITH_ROOT, winid);
		ctlfd := sys->open(ctlpath, Sys->OWRITE);
		if(ctlfd != nil) {
			namecmd := sys->sprint("name %s\n", winname);
			sys->write(ctlfd, array of byte namecmd, len namecmd);
			ctlfd = nil;
		}
	}

	return winid;
}

# Write to window body or tag
dowrite(args: string): string
{
	(winid, rest) := splitfirst(args);
	if(winid == "")
		return "error: usage: write <id> body|tag <text>";

	if(!isowned(winid))
		return sys->sprint("error: permission denied — window %s not owned by agent", winid);

	(target, text) := splitfirst(rest);
	target = str->tolower(target);

	if(target == "ctl")
		return "error: use 'xenith ctl <id> <command>' instead of write";
	if(target != "body" && target != "tag")
		return "error: target must be 'body' or 'tag'. Use 'xenith ctl' for control, 'xenith delete' to close";

	filepath := sys->sprint("%s/%s/%s", XENITH_ROOT, winid, target);
	fd := sys->open(filepath, Sys->OWRITE | Sys->OTRUNC);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r", filepath);

	data := array of byte text;
	n := sys->write(fd, data, len data);
	fd = nil;

	if(n != len data)
		return sys->sprint("error: write failed: %r");

	return sys->sprint("wrote %d bytes to %s/%s", n, winid, target);
}

# Read from window body or tag
doread(args: string): string
{
	(winid, rest) := splitfirst(args);
	if(winid == "")
		return "error: usage: read <id> [body|tag]";

	target := strip(rest);
	if(target == "")
		target = "body";
	target = str->tolower(target);

	if(target == "ctl")
		return "error: use 'xenith ctl <id> <command>' for control commands";
	if(target != "body" && target != "tag")
		return "error: target must be 'body' or 'tag'";

	# Body reads use namespace-based access control.
	# Tag reads always allowed for discovery.
	if(target == "body") {
		err := checkbodyaccess(winid);
		if(err != nil)
			return err;
	}

	filepath := sys->sprint("%s/%s/%s", XENITH_ROOT, winid, target);
	fd := sys->open(filepath, Sys->OREAD);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r", filepath);

	# Read all content
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

# Append to window body
doappend(args: string): string
{
	(winid, text) := splitfirst(args);
	if(winid == "" || text == "")
		return "error: usage: append <id> <text>";

	if(!isowned(winid))
		return sys->sprint("error: permission denied — window %s not owned by agent", winid);

	filepath := sys->sprint("%s/%s/body", XENITH_ROOT, winid);
	fd := sys->open(filepath, Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r", filepath);

	# Seek to end
	sys->seek(fd, big 0, Sys->SEEKEND);

	data := array of byte text;
	n := sys->write(fd, data, len data);
	fd = nil;

	if(n != len data)
		return sys->sprint("error: append failed: %r");

	return sys->sprint("appended %d bytes", n);
}

# Send control commands
doctl(args: string): string
{
	(winid, cmds) := splitfirst(args);
	if(winid == "" || cmds == "")
		return "error: usage: ctl <id> <commands>";

	if(!isowned(winid))
		return sys->sprint("error: permission denied — window %s not owned by agent", winid);

	filepath := sys->sprint("%s/%s/ctl", XENITH_ROOT, winid);
	fd := sys->open(filepath, Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r", filepath);

	# Ensure commands end with newline
	if(len cmds > 0 && cmds[len cmds - 1] != '\n')
		cmds += "\n";

	data := array of byte cmds;
	n := sys->write(fd, data, len data);
	fd = nil;

	if(n != len data)
		return sys->sprint("error: ctl write failed: %r");

	return "ok";
}

# Set window colors
docolors(args: string): string
{
	(winid, settings) := splitfirst(args);
	if(winid == "" || settings == "")
		return "error: usage: colors <id> <settings>";

	if(!isowned(winid))
		return sys->sprint("error: permission denied — window %s not owned by agent", winid);

	filepath := sys->sprint("%s/%s/colors", XENITH_ROOT, winid);
	fd := sys->open(filepath, Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r", filepath);

	# Ensure settings end with newline
	if(len settings > 0 && settings[len settings - 1] != '\n')
		settings += "\n";

	data := array of byte settings;
	n := sys->write(fd, data, len data);
	fd = nil;

	if(n != len data)
		return sys->sprint("error: colors write failed: %r");

	return "ok";
}

# Delete a window
dodelete(args: string): string
{
	winid := strip(args);
	if(winid == "")
		return "error: usage: delete <id>";

	if(!isowned(winid))
		return sys->sprint("error: permission denied — window %s not owned by agent", winid);

	filepath := sys->sprint("%s/%s/ctl", XENITH_ROOT, winid);
	fd := sys->open(filepath, Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r", filepath);

	data := array of byte "delete\n";
	sys->write(fd, data, len data);
	fd = nil;

	return "ok";
}

# List all windows — always allowed (shows tags, not bodies)
dolist(): string
{
	filepath := XENITH_ROOT + "/index";
	fd := sys->open(filepath, Sys->OREAD);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r (is Xenith running?)", filepath);

	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	fd = nil;

	if(result == "")
		return "(no windows)";
	return result;
}

# Set visual status indicator via colors
dostatus(args: string): string
{
	(winid, state) := splitfirst(args);
	if(winid == "" || state == "")
		return "error: usage: status <id> ok|warn|error|info|reset";

	if(!isowned(winid))
		return sys->sprint("error: permission denied — window %s not owned by agent", winid);

	state = str->tolower(strip(state));

	# Define status colors (Catppuccin-inspired)
	colorstr: string;
	case state {
	"ok" or "success" or "green" =>
		# Green tag for success
		colorstr = "tagbg #A6E3A1\ntagfg #1E1E2E\n";
	"warn" or "warning" or "yellow" =>
		# Yellow tag for warning
		colorstr = "tagbg #F9E2AF\ntagfg #1E1E2E\n";
	"error" or "fail" or "red" =>
		# Red tag for error
		colorstr = "tagbg #F38BA8\ntagfg #1E1E2E\n";
	"info" or "blue" =>
		# Blue tag for information
		colorstr = "tagbg #89B4FA\ntagfg #1E1E2E\n";
	"reset" or "default" =>
		colorstr = "reset\n";
	* =>
		return sys->sprint("error: unknown status '%s'. Use: ok, warn, error, info, reset", state);
	}

	filepath := sys->sprint("%s/%s/colors", XENITH_ROOT, winid);
	fd := sys->open(filepath, Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r", filepath);

	data := array of byte colorstr;
	n := sys->write(fd, data, len data);
	fd = nil;

	if(n != len data)
		return sys->sprint("error: status write failed: %r");

	return "ok";
}

# Helper: strip whitespace
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

# Helper: split on first whitespace
splitfirst(s: string): (string, string)
{
	s = strip(s);
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t')
			return (s[0:i], strip(s[i:]));
	}
	return (s, "");
}
