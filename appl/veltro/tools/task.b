implement ToolTask;

#
# task - Task delegation tool for Veltro meta-agent
#
# Creates, monitors, and manages delegated AI tasks.
# Each task gets its own activity, tools9p, and lucibridge.
#
# Commands:
#   create label=<name> [tools=<csv>] [paths=<csv>] [urgency=<0-2>]
#   status <id>
#   list
#   close <id>
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolTask: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

UI_MOUNT: con "/n/ui";

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
	return "task";
}

doc(): string
{
	return "task - Create and manage delegated AI tasks\n\n" +
		"Commands:\n" +
		"  create label=<name> [tools=<csv>] [paths=<csv>] [urgency=<0-2>]\n" +
		"      Create new task with isolated tools and conversation.\n" +
		"      Tools validated against delegation budget.\n" +
		"  status <id>     Show task status and urgency\n" +
		"  list            List all active tasks\n" +
		"  close <id>      Archive a completed task\n\n" +
		"Each task gets its own conversation, tools, and filesystem overlay.\n" +
		"Use for work that should happen in parallel or needs isolation.\n\n" +
		"Examples:\n" +
		"  task create label=Review tools=read,list,find,grep\n" +
		"  task list\n" +
		"  task status 2\n" +
		"  task close 2";
}

exec(args: string): string
{
	if(sys == nil)
		return "error: not initialized";
	args = strip(args);
	if(args == "")
		return "error: no command. Use: create, status, list, close";

	(cmd, rest) := splitfirst(args);
	cmd = str->tolower(cmd);

	case cmd {
	"create" =>
		return docreate(rest);
	"status" =>
		return dostatus(rest);
	"list" =>
		return dolist();
	"close" =>
		return doclose(rest);
	* =>
		return sys->sprint("error: unknown command '%s'. Use: create, status, list, close", cmd);
	}
}

# Parse key=value attributes from argument string
parseattrs(s: string): list of (string, string)
{
	result: list of (string, string);
	i := 0;
	for(;;) {
		# skip whitespace
		while(i < len s && (s[i] == ' ' || s[i] == '\t'))
			i++;
		if(i >= len s)
			break;
		# find key
		kstart := i;
		while(i < len s && s[i] != '=' && s[i] != ' ')
			i++;
		if(i >= len s || s[i] != '=') {
			# bare word — skip
			while(i < len s && s[i] != ' ')
				i++;
			continue;
		}
		key := s[kstart:i];
		i++;	# skip =
		# find value
		vstart := i;
		while(i < len s && s[i] != ' ')
			i++;
		val := s[vstart:i];
		result = (key, val) :: result;
	}
	return result;
}

getattr(attrs: list of (string, string), key: string): string
{
	for(; attrs != nil; attrs = tl attrs) {
		(k, v) := hd attrs;
		if(k == key)
			return v;
	}
	return "";
}

docreate(args: string): string
{
	attrs := parseattrs(args);
	label := getattr(attrs, "label");
	if(label == "")
		return "error: label required. Usage: create label=<name> [tools=<csv>]";

	toolsarg := getattr(attrs, "tools");
	urgstr := getattr(attrs, "urgency");

	# Validate tools against budget
	if(toolsarg != "") {
		budgetstr := readfile("/tool/budget");
		if(budgetstr != nil) {
			budgetstr = strip(budgetstr);
			(reqtoks, nil) := sys->tokenize(toolsarg, ",");
			for(; reqtoks != nil; reqtoks = tl reqtoks) {
				t := hd reqtoks;
				if(!contains(budgetstr, t))
					return sys->sprint("error: tool '%s' not in delegation budget", t);
			}
		}
	}

	# Create activity via /n/ui/ctl
	ctlpath := UI_MOUNT + "/ctl";
	err := writefile(ctlpath, "activity create " + label);
	if(err != nil)
		return "error: " + err;

	# Read back the new activity id (last activity in list)
	info := readfile(UI_MOUNT + "/info");
	if(info == nil)
		return "error: cannot read /n/ui/info after create";

	# Parse "activities: id1 id2 ... idN" — idN is the newest
	newid := -1;
	lines := splitlines(strip(info));
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		if(hasprefix(line, "activities:")) {
			rest := strip(line[len "activities:":]);
			(toks, nil) := sys->tokenize(rest, " ");
			lastid := "";
			for(; toks != nil; toks = tl toks)
				lastid = hd toks;
			if(lastid != "")
				(newid, nil) = str->toint(lastid, 10);
		}
	}

	if(newid < 0)
		return "error: could not determine new activity id";

	# Set urgency if specified
	if(urgstr != "") {
		writefile(sys->sprint("%s/activity/%d/urgency", UI_MOUNT, newid), urgstr);
	}

	# Spawn tools9p + lucibridge for the new activity
	spawn provisiontask(newid, toolsarg, getattr(attrs, "paths"));

	return sys->sprint("created activity %d: %s", newid, label);
}

provisiontask(id: int, toolsarg, pathsarg: string)
{
	# Build tools9p command
	cmd := "tools9p -m /tool." + string id;
	if(pathsarg != "") {
		(ptoks, nil) := sys->tokenize(pathsarg, ",");
		for(; ptoks != nil; ptoks = tl ptoks)
			cmd += " -p " + hd ptoks;
	}
	# Add tool names
	if(toolsarg != "") {
		(ttoks, nil) := sys->tokenize(toolsarg, ",");
		for(; ttoks != nil; ttoks = tl ttoks)
			cmd += " " + hd ttoks;
	} else {
		# Default: delegate all budget tools
		bstr := readfile("/tool/budget");
		if(bstr != nil) {
			bstr = strip(bstr);
			(btoks, nil) := sys->tokenize(bstr, "\n");
			for(; btoks != nil; btoks = tl btoks)
				cmd += " " + hd btoks;
		}
	}

	# Run tools9p in background via sh
	shfd := sys->open("/dev/null", Sys->OREAD);
	sys->fprint(sys->fildes(2), "task: provisioning activity %d: %s\n", id, cmd);

	# Use sh to run the tools9p and lucibridge pipeline
	shcmd := cmd + " ; sleep 1 ; lucibridge -a " + string id + " -s";
	spawn runsh(shcmd);
}

runsh(cmd: string)
{
	fd := sys->open("/dev/null", Sys->OREAD);
	sh := load Command "/dis/sh.dis";
	if(sh == nil) {
		sys->fprint(sys->fildes(2), "task: cannot load sh: %r\n");
		return;
	}
	sh->init(nil, "sh" :: "-c" :: cmd :: nil);
}

dostatus(args: string): string
{
	args = strip(args);
	if(args == "")
		return "error: activity id required";
	(id, nil) := str->toint(args, 10);
	if(id < 0)
		return "error: invalid activity id";

	label := readfile(sys->sprint("%s/activity/%d/label", UI_MOUNT, id));
	status := readfile(sys->sprint("%s/activity/%d/status", UI_MOUNT, id));
	urgstr := readfile(sys->sprint("%s/activity/%d/urgency", UI_MOUNT, id));
	if(label == nil)
		return sys->sprint("error: activity %d not found", id);

	label = strip(label);
	if(status != nil) status = strip(status); else status = "unknown";
	if(urgstr != nil) urgstr = strip(urgstr); else urgstr = "0";

	return sys->sprint("activity %d: %s [%s] urgency=%s", id, label, status, urgstr);
}

dolist(): string
{
	info := readfile(UI_MOUNT + "/info");
	if(info == nil)
		return "no activities";

	result := "";
	lines := splitlines(strip(info));
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		if(hasprefix(line, "activities:")) {
			rest := strip(line[len "activities:":]);
			(toks, nil) := sys->tokenize(rest, " ");
			for(; toks != nil; toks = tl toks) {
				(id, nil) := str->toint(hd toks, 10);
				if(id < 0) continue;
				label := readfile(sys->sprint("%s/activity/%d/label", UI_MOUNT, id));
				status := readfile(sys->sprint("%s/activity/%d/status", UI_MOUNT, id));
				if(label != nil) label = strip(label); else label = "?";
				if(status != nil) status = strip(status); else status = "?";
				if(status == "hidden") continue;
				if(result != "")
					result += "\n";
				result += sys->sprint("%d: %s [%s]", id, label, status);
			}
		}
	}
	if(result == "")
		return "no active tasks";
	return result;
}

doclose(args: string): string
{
	args = strip(args);
	if(args == "")
		return "error: activity id required";
	(id, nil) := str->toint(args, 10);
	if(id < 0)
		return "error: invalid activity id";
	if(id == 0)
		return "error: cannot close the meta-agent activity";

	err := writefile(UI_MOUNT + "/ctl", "activity delete " + string id);
	if(err != nil)
		return "error: " + err;

	return sys->sprint("activity %d archived", id);
}

# --- Utility functions ---

Command: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}

writefile(path, data: string): string
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("cannot open %s: %r", path);
	b := array of byte data;
	if(sys->write(fd, b, len b) != len b)
		return sys->sprint("write %s: %r", path);
	return nil;
}

strip(s: string): string
{
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == ' ' || s[len s - 1] == '\t'))
		s = s[0:len s - 1];
	return s;
}

hasprefix(s, pfx: string): int
{
	return len s >= len pfx && s[0:len pfx] == pfx;
}

splitfirst(s: string): (string, string)
{
	for(i := 0; i < len s; i++)
		if(s[i] == ' ' || s[i] == '\t')
			return (s[0:i], strip(s[i+1:]));
	return (s, "");
}

splitlines(s: string): list of string
{
	result: list of string;
	start := 0;
	for(i := 0; i < len s; i++) {
		if(s[i] == '\n') {
			if(i > start)
				result = s[start:i] :: result;
			start = i + 1;
		}
	}
	if(start < len s)
		result = s[start:] :: result;
	rev: list of string;
	for(; result != nil; result = tl result)
		rev = hd result :: rev;
	return rev;
}

contains(haystack, needle: string): int
{
	nlen := len needle;
	for(i := 0; i <= len haystack - nlen; i++) {
		if(haystack[i:i+nlen] == needle) {
			# Check word boundary
			if(i > 0 && haystack[i-1] != '\n' && haystack[i-1] != ' ' && haystack[i-1] != ',')
				continue;
			end := i + nlen;
			if(end < len haystack && haystack[end] != '\n' && haystack[end] != ' ' && haystack[end] != ',')
				continue;
			return 1;
		}
	}
	return 0;
}
