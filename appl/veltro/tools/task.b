implement ToolTask;

#
# task - Task delegation tool for Veltro meta-agent
#
# Creates, monitors, and manages delegated AI tasks.
# Each task gets its own activity, tools9p, and lucibridge.
#
# Commands:
#   create label=<name> [tools=<csv>] [paths=<csv>] [urgency=<0-2>] [instructions=<text>] [category=<text>]
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
		"  create label=<name> [tools=<csv>] [paths=<csv>] [urgency=<0-2>] [instructions=<text>]\n" +
		"      Create new task with isolated tools and conversation.\n" +
		"      Tools validated against delegation budget.\n" +
		"      instructions= sets structured directives injected into the TA system prompt.\n" +
		"  status <id>     Show task status and urgency\n" +
		"  list            List all active tasks\n" +
		"  close <id>      Archive a completed task\n\n" +
		"Each task gets its own conversation, tools, and filesystem overlay.\n" +
		"Use for work that should happen in parallel or needs isolation.\n\n" +
		"Examples:\n" +
		"  task create label=Review tools=read,list,find,grep\n" +
		"  task create label=Editor instructions=\"Open /lib/veltro/system.txt and edit it\"\n" +
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
# Handles quoted values: label="Write poetry" tools=read,list
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
		# find value — handle quoted strings
		val := "";
		if(i < len s && (s[i] == '"' || s[i] == '\'')) {
			q := s[i];
			i++;	# skip opening quote
			vstart := i;
			while(i < len s && s[i] != q)
				i++;
			val = s[vstart:i];
			if(i < len s)
				i++;	# skip closing quote
		} else {
			vstart := i;
			while(i < len s && s[i] != ' ')
				i++;
			val = s[vstart:i];
		}
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
			(nil, reqtoks) := sys->tokenize(toolsarg, ",");
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
	info := readfile(UI_MOUNT + "/ctl");
	if(info == nil)
		return "error: cannot read /n/ui/ctl after create";

	# Parse "activities: id1 id2 ... idN" — idN is the newest
	newid := -1;
	lines := splitlines(strip(info));
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		if(hasprefix(line, "activities:")) {
			rest := strip(line[len "activities:":]);
			(nil, toks) := sys->tokenize(rest, " ");
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

	# Write task brief to a file that lucibridge reads at startup.
	# This goes into the LLM system prompt only — no visible chat message.
	brief := getattr(attrs, "brief");
	if(brief == "")
		brief = "You have been assigned to: " + label + ". Greet the user and ask how you can help with this task.";
	briefpath := sys->sprint("/tmp/veltro/brief.%d", newid);
	bfd := sys->create(briefpath, Sys->OWRITE, 8r644);
	if(bfd != nil) {
		bb := array of byte brief;
		sys->write(bfd, bb, len bb);
		bfd = nil;
	}

	# Write structured instructions if provided
	instructions := getattr(attrs, "instructions");
	if(instructions != "") {
		instrpath := sys->sprint("/tmp/veltro/instructions.%d", newid);
		ifd := sys->create(instrpath, Sys->OWRITE, 8r644);
		if(ifd != nil) {
			ib := array of byte instructions;
			sys->write(ifd, ib, len ib);
			ifd = nil;
		}
	}

	# Push metadata to dashboard if available
	dashctl := "/n/dashboard/ctl";
	dfd := sys->open(dashctl, Sys->OWRITE);
	if(dfd != nil) {
		dfd = nil;
		writefile(dashctl, "synopsis " + string newid + " " + label);
		category := getattr(attrs, "category");
		if(category != "")
			writefile(dashctl, "categorize " + string newid + " " + category);
		if(instructions != "")
			writefile(dashctl, "instructions " + string newid + " " + instructions);
	}

	# Delegate provisioning to the unrestricted parent serveloop.
	# We cannot spawn tools9p/lucibridge from here because asyncexec()
	# restricts our namespace — /dis is hidden.  Writing to /tool/ctl
	# routes to the serveloop which runs in the full namespace.
	provcmd := "provision " + string newid;
	if(toolsarg != "")
		provcmd += " tools=" + toolsarg;
	if(getattr(attrs, "paths") != "")
		provcmd += " paths=" + getattr(attrs, "paths");
	perr := writefile("/tool/ctl", provcmd);
	if(perr != nil)
		sys->fprint(sys->fildes(2), "task: provision warning: %s\n", perr);

	return sys->sprint("created activity %d: %s", newid, label);
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
	info := readfile(UI_MOUNT + "/ctl");
	if(info == nil)
		return "no activities";

	result := "";
	lines := splitlines(strip(info));
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		if(hasprefix(line, "activities:")) {
			rest := strip(line[len "activities:":]);
			(nil, toks) := sys->tokenize(rest, " ");
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
