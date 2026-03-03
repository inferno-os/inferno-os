implement ToolPresent;

#
# present - Presentation zone tool for Veltro agent
#
# Manages artifacts in the Lucifer presentation zone via /n/ui/.
# The AI uses this to display documents, tables, summaries, and code
# in the center zone of the Lucifer UI.
#
# Commands:
#   create <id> [type=markdown|text|table|code] [label=<text>]
#                            - Create a new presentation artifact
#   write <id> <content>     - Write content to artifact (\\n for newlines)
#   center <id>              - Make artifact the active/focused view
#   list                     - List artifacts in current activity
#   status                   - Show current activity and centered artifact
#
# Examples:
#   present create summary type=markdown label="Session Summary"
#   present write summary "# Summary\n\nKey findings:\n- Item 1\n- Item 2"
#   present center summary
#   present create data type=table label="Results"
#   present write data "| Name | Value |\n|------|-------|\n| Foo | 42 |"
#   present list
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolPresent: module {
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
	return "present";
}

doc(): string
{
	return "Present - Manage Lucifer presentation zone\n\n" +
		"Commands:\n" +
		"  create <id> [type=markdown|text|table|code] [label=<text>]\n" +
		"                          Create a presentation artifact\n" +
		"  write <id> <content>    Write content (use \\\\n for newlines)\n" +
		"  center <id>             Make artifact the active/focused view\n" +
		"  list                    List artifacts in current activity\n" +
		"  status                  Show current activity and centered artifact\n\n" +
		"Artifact types:\n" +
		"  markdown  Rich text with headings, bold, code, tables (default)\n" +
		"  text      Plain wrapped text\n" +
		"  table     Pipe-delimited table (| Col | Col | format)\n" +
		"  code      Monospace code listing\n\n" +
		"Examples:\n" +
		"  present create summary type=markdown label=\"Session Summary\"\n" +
		"  present write summary \"# Summary\\n\\n- Key finding 1\\n- Key finding 2\"\n" +
		"  present center summary\n" +
		"  present list";
}

# Read current activity ID from namespace
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
		return "error: no command. Use: create, write, center, list, status";

	(cmd, rest) := splitfirst(args);
	cmd = str->tolower(cmd);

	case cmd {
	"create" =>
		return docreate(rest);
	"write" =>
		return dowrite(rest);
	"append" =>
		return doappend(rest);
	"center" =>
		return docenter(rest);
	"list" =>
		return dolist();
	"status" =>
		return dostatus();
	* =>
		return sys->sprint("error: unknown command '%s'. Use: create, write, append, center, list, status", cmd);
	}
}

# Create a new artifact
docreate(args: string): string
{
	# Parse: <id> [type=...] [label=...]
	args = strip(args);
	if(args == "")
		return "error: usage: create <id> [type=markdown] [label=<text>]";

	(id, rest) := splitfirst(args);
	if(id == "")
		return "error: artifact id required";

	# Parse optional attributes
	attrs := parseattrs(rest);
	atype := getattr(attrs, "type");
	label := getattr(attrs, "label");

	if(atype == nil || atype == "")
		atype = "markdown";
	if(label == nil || label == "")
		label = id;

	actid := currentactid();
	if(actid < 0)
		return "error: no active activity (is luciuisrv running?)";

	pctl := sys->sprint("%s/activity/%d/presentation/ctl", UI_MOUNT, actid);
	cmd := sys->sprint("create id=%s type=%s label=%s", id, atype, label);
	err := writefile(pctl, cmd);
	if(err != nil)
		return "error: " + err;

	return sys->sprint("created artifact '%s' (type=%s)", id, atype);
}

# Write content to an artifact's data file
dowrite(args: string): string
{
	args = strip(args);
	if(args == "")
		return "error: usage: write <id> <content>";

	(id, content) := splitfirst(args);
	if(id == "")
		return "error: artifact id required";
	if(content == "")
		return "error: content required";

	# Process escape sequences
	content = unescape(content);

	actid := currentactid();
	if(actid < 0)
		return "error: no active activity";

	datapath := sys->sprint("%s/activity/%d/presentation/%s/data", UI_MOUNT, actid, id);
	fd := sys->open(datapath, Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r (artifact '%s' exists?)", datapath, id);

	# Truncate and write
	sys->seek(fd, big 0, Sys->SEEKSTART);
	data := array of byte content;
	n := sys->write(fd, data, len data);
	if(n < 0)
		return sys->sprint("error: write failed: %r");

	return sys->sprint("wrote %d bytes to artifact '%s'", n, id);
}

# Append a chunk to an artifact's data (for streaming / incremental updates).
doappend(args: string): string
{
	args = strip(args);
	if(args == "")
		return "error: usage: append <id> <content>";

	(id, content) := splitfirst(args);
	if(id == "")
		return "error: artifact id required";

	# Process escape sequences in content
	content = unescape(content);

	actid := currentactid();
	if(actid < 0)
		return "error: no active activity";

	pctl := sys->sprint("%s/activity/%d/presentation/ctl", UI_MOUNT, actid);
	cmd := sys->sprint("append id=%s data=%s", id, content);
	err := writefile(pctl, cmd);
	if(err != nil)
		return "error: " + err;

	return sys->sprint("appended %d bytes to artifact '%s'", len content, id);
}

# Center/activate an artifact
docenter(args: string): string
{
	id := strip(args);
	if(id == "")
		return "error: usage: center <id>";

	actid := currentactid();
	if(actid < 0)
		return "error: no active activity";

	pctl := sys->sprint("%s/activity/%d/presentation/ctl", UI_MOUNT, actid);
	cmd := "center id=" + id;
	err := writefile(pctl, cmd);
	if(err != nil)
		return "error: " + err;

	return sys->sprint("centered '%s'", id);
}

# List artifacts in current activity
dolist(): string
{
	actid := currentactid();
	if(actid < 0)
		return "error: no active activity";

	presdir := sys->sprint("%s/activity/%d/presentation", UI_MOUNT, actid);
	fd := sys->open(presdir, Sys->OREAD);
	if(fd == nil)
		return "error: cannot open presentation dir (is luciuisrv running?)";

	# Read currently centered artifact
	centered := readfile(presdir + "/current");
	if(centered != nil)
		centered = strip(centered);
	else
		centered = "";

	result := "";
	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(di := 0; di < n; di++) {
			nm := dirs[di].name;
			if(nm == "ctl" || nm == "current" || nm == ".." || nm == ".")
				continue;
			if(!(dirs[di].mode & Sys->DMDIR))
				continue;
			# Read type and label
			atype := readfile(presdir + "/" + nm + "/type");
			if(atype != nil) atype = strip(atype);
			else atype = "?";
			label := readfile(presdir + "/" + nm + "/label");
			if(label != nil) label = strip(label);
			else label = nm;
			marker := "";
			if(nm == centered)
				marker = " *";
			if(result != "")
				result += "\n";
			result += sys->sprint("  %-20s  type=%-8s  label=%s%s", nm, atype, label, marker);
		}
	}

	if(result == "")
		return "no artifacts";
	return "Artifacts (* = centered):\n" + result;
}

# Show current activity and artifact status
dostatus(): string
{
	actid := currentactid();
	if(actid < 0)
		return "error: no active activity";

	label := readfile(sys->sprint("%s/activity/%d/label", UI_MOUNT, actid));
	if(label != nil) label = strip(label);
	else label = "(no label)";

	status := readfile(sys->sprint("%s/activity/%d/status", UI_MOUNT, actid));
	if(status != nil) status = strip(status);
	else status = "?";

	centered := readfile(sys->sprint("%s/activity/%d/presentation/current", UI_MOUNT, actid));
	if(centered != nil) centered = strip(centered);
	else centered = "(none)";

	return sys->sprint("Activity %d: %s [%s]\nCentered: %s", actid, label, status, centered);
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

# Process escape sequences in content (\\n → newline, \\t → tab, etc.)
unescape(s: string): string
{
	result := "";
	i := 0;
	while(i < len s) {
		if(s[i] == '\\' && i + 1 < len s) {
			case s[i+1] {
			'n'  => result[len result] = '\n';
			't'  => result[len result] = '\t';
			'r'  => result[len result] = '\r';
			'\\' => result[len result] = '\\';
			'"'  => result[len result] = '"';
			'\'' => result[len result] = '\'';
			*    => result[len result] = s[i+1];
			}
			i += 2;
		} else {
			result[len result] = s[i];
			i++;
		}
	}
	return result;
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

# Parse "key=val key2=val2 ..." attribute string
Attr: adt {
	key: string;
	val: string;
};

parseattrs(s: string): list of ref Attr
{
	# Scan for key= positions
	kstarts := array[16] of int;
	eqposs := array[16] of int;
	nkp := 0;
	j := 0;
	while(j < len s) {
		if(s[j] == '=') {
			kstart := j - 1;
			while(kstart > 0 && s[kstart-1] != ' ' && s[kstart-1] != '\t')
				kstart--;
			if(kstart >= 0 && kstart < j) {
				if(nkp < len kstarts) {
					kstarts[nkp] = kstart;
					eqposs[nkp] = j;
					nkp++;
				}
			}
		}
		j++;
	}
	attrs: list of ref Attr;
	for(k := 0; k < nkp; k++) {
		key := s[kstarts[k]:eqposs[k]];
		vstart := eqposs[k] + 1;
		vend: int;
		if(k + 1 < nkp) {
			vend = kstarts[k+1];
			while(vend > vstart && (s[vend-1] == ' ' || s[vend-1] == '\t'))
				vend--;
		} else
			vend = len s;
		val := "";
		if(vstart < vend)
			val = s[vstart:vend];
		attrs = ref Attr(key, val) :: attrs;
	}
	rev: list of ref Attr;
	for(; attrs != nil; attrs = tl attrs)
		rev = hd attrs :: rev;
	return rev;
}

getattr(attrs: list of ref Attr, key: string): string
{
	for(; attrs != nil; attrs = tl attrs)
		if((hd attrs).key == key)
			return (hd attrs).val;
	return nil;
}
