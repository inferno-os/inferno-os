implement ToolGap;

#
# gap - Context zone gap management tool for Veltro agent
#
# Manages knowledge gaps in the Lucifer context zone via /n/ui/.
# The AI uses this to surface blind spots and signal missing information.
#
# Commands:
#   add "desc" [relevance]   - Add or update a gap (upsert by desc, idempotent)
#   resolve "desc"           - Remove a gap by description match
#
# Relevance levels: high | medium (default) | low
#
# Examples:
#   gap add "No test coverage data" high
#   gap add "API rate limits unknown"
#   gap resolve "No test coverage data"
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolGap: module {
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
	return "gap";
}

doc(): string
{
	return "Gap - Manage context zone knowledge gaps\n\n" +
		"Commands:\n" +
		"  add \"desc\" [relevance]  Add or update a gap (upsert by description)\n" +
		"  resolve \"desc\"          Remove a gap by description\n" +
		"  list                   List all current gaps\n\n" +
		"Relevance levels: high | medium (default) | low\n\n" +
		"The add command is idempotent: same description updates relevance\n" +
		"rather than creating a duplicate entry.\n\n" +
		"Examples:\n" +
		"  gap add \"No test coverage data\" high\n" +
		"  gap add \"API rate limits unknown\"\n" +
		"  gap resolve \"No test coverage data\"\n" +
		"  gap list";
}

currentactid(): int
{
	s := readfile(UI_MOUNT + "/activity/current");
	if(s == nil)
		return -1;
	s = strip(s);
	(n, nil) := str->toint(s, 10);
	return n;
}

exec(args: string): string
{
	if(sys == nil)
		init();

	args = strip(args);
	if(args == "")
		return "error: no command. Use: add, resolve, list";

	(cmd, rest) := splitfirst(args);
	cmd = str->tolower(cmd);

	case cmd {
	"add" =>
		return doadd(rest);
	"resolve" =>
		return doresolve(rest);
	"list" =>
		return dolist();
	* =>
		return sys->sprint("error: unknown command '%s'. Use: add, resolve, list", cmd);
	}
}

# Add (or update via upsert) a gap.
# Parses: "desc" [high|medium|low]
# The last word is treated as relevance if it matches high/medium/low.
doadd(args: string): string
{
	args = strip(args);
	if(args == "")
		return "error: usage: add \"desc\" [high|medium|low]";

	# Determine relevance from last word (if it's a level keyword)
	relevance := "medium";
	desc := args;
	lastsp := -1;
	for(i := len args - 1; i >= 0; i--) {
		if(args[i] == ' ' || args[i] == '\t') {
			lastsp = i;
			break;
		}
	}
	if(lastsp >= 0) {
		lastword := strip(args[lastsp:]);
		if(lastword == "high" || lastword == "medium" || lastword == "low") {
			relevance = lastword;
			desc = strip(args[0:lastsp]);
		}
	}

	# Strip surrounding double-quotes from desc
	if(len desc >= 2 && desc[0] == '"' && desc[len desc - 1] == '"')
		desc = desc[1:len desc - 1];
	desc = strip(desc);

	if(desc == "")
		return "error: gap description required";

	actid := currentactid();
	if(actid < 0)
		return "error: no active activity (is luciuisrv running?)";

	ctxctl := sys->sprint("%s/activity/%d/context/ctl", UI_MOUNT, actid);
	cmd := "gap upsert desc=" + desc + " relevance=" + relevance;
	err := writefile(ctxctl, cmd);
	if(err != nil)
		return "error: " + err;

	return sys->sprint("gap '%s' [%s]", desc, relevance);
}

# Remove a gap by description.
doresolve(args: string): string
{
	desc := strip(args);
	# Strip surrounding double-quotes
	if(len desc >= 2 && desc[0] == '"' && desc[len desc - 1] == '"')
		desc = desc[1:len desc - 1];
	desc = strip(desc);

	if(desc == "")
		return "error: usage: resolve \"desc\"";

	actid := currentactid();
	if(actid < 0)
		return "error: no active activity";

	ctxctl := sys->sprint("%s/activity/%d/context/ctl", UI_MOUNT, actid);
	cmd := "gap resolve desc=" + desc;
	err := writefile(ctxctl, cmd);
	if(err != nil)
		return "error: " + err;

	return sys->sprint("resolved gap '%s'", desc);
}

# List all current gaps for the active activity.
dolist(): string
{
	actid := currentactid();
	if(actid < 0)
		return "error: no active activity (is luciuisrv running?)";

	gapbase := sys->sprint("%s/activity/%d/context/gaps", UI_MOUNT, actid);
	result := "";
	n := 0;
	for(i := 0; ; i++) {
		s := readfile(gapbase + "/" + string i);
		if(s == nil)
			break;
		s = strip(s);
		if(s == "")
			continue;
		# Parse "desc=... relevance=..." — relevance= is the last field.
		# splitstrr(s, sep) returns (s[0:n+len(sep)], s[n+len(sep):])
		# where n is the start of the last occurrence of sep.
		# So: before ends with sep, after is the value.
		desc := s;
		relevance := "medium";
		revsep := " relevance=";
		(before, after) := str->splitstrr(s, revsep);
		if(before != "") {
			relevance = strip(after);
			# before ends with revsep — strip it to get the desc portion
			desc = before[0:len before - len revsep];
		}
		if(len desc > 5 && desc[0:5] == "desc=")
			desc = desc[5:];
		desc = strip(desc);
		if(result != "")
			result += "\n";
		result += "[" + relevance + "] " + desc;
		n++;
	}
	if(n == 0)
		return "no gaps";
	return result;
}

# --- Helpers ---

writefile(path, data: string): string
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("cannot open %s: %r", path);
	b := array of byte data;
	n := sys->write(fd, b, len b);
	if(n < 0)
		return sys->sprint("write to %s failed: %r", path);
	return nil;
}

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
