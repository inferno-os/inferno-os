implement ToolEdit;

#
# edit - Edit file contents tool for Veltro agent
#
# Performs find/replace operations on file contents.
# Similar to sed s/old/new/ but safer - fails if old text not found or ambiguous.
#
# Usage:
#   Edit <path> <old> <new>       # Replace first occurrence
#   Edit <path> <old> <new> all   # Replace all occurrences
#
# Arguments must be quoted if they contain spaces.
# Use \n for newlines, \t for tabs.
#
# Examples:
#   Edit /tmp/test.txt "hello" "goodbye"
#   Edit /appl/veltro/veltro.b "MAX_STEPS: con 50" "MAX_STEPS: con 100"
#   Edit /tmp/test.txt "foo" "bar" all
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "string.m";
	str: String;

include "../tool.m";

ToolEdit: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		return "cannot load Bufio";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";
	return nil;
}

name(): string
{
	return "edit";
}

doc(): string
{
	return "Edit - Edit file contents (find/replace)\n\n" +
		"Usage:\n" +
		"  Edit <path> <old> <new>       # Replace first occurrence\n" +
		"  Edit <path> <old> <new> all   # Replace all occurrences\n\n" +
		"Arguments:\n" +
		"  path - File to edit\n" +
		"  old  - Text to find (use quotes if contains spaces)\n" +
		"  new  - Replacement text (use quotes if contains spaces)\n" +
		"  all  - Optional: replace all occurrences\n\n" +
		"Use \\n for newlines, \\t for tabs.\n\n" +
		"Examples:\n" +
		"  Edit /tmp/test.txt \"hello\" \"goodbye\"\n" +
		"  Edit /appl/veltro/veltro.b \"MAX: con 50\" \"MAX: con 100\"\n" +
		"  Edit /tmp/test.txt \"foo\" \"bar\" all\n\n" +
		"Fails if old text not found. Without 'all', fails if multiple matches.";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	# Parse arguments
	(path, old, new, all) := parseargs(args);
	if(path == "")
		return "error: usage: Edit <path> <old> <new> [all]";
	if(old == "")
		return "error: no search text specified";

	# Process escape sequences
	old = unescape(old);
	new = unescape(new);

	# Read file
	content := readfile(path);
	if(content == nil)
		return sys->sprint("error: cannot read %s: %r", path);

	text := string content;

	# Count occurrences
	count := countoccur(text, old);
	if(count == 0)
		return sys->sprint("error: '%s' not found in %s", escape(old), path);

	if(count > 1 && !all)
		return sys->sprint("error: '%s' found %d times in %s (use 'all' to replace all)", escape(old), count, path);

	# Perform replacement
	newtext: string;
	replaced := 0;
	if(all) {
		newtext = replaceall(text, old, new);
		replaced = count;
	} else {
		newtext = replacefirst(text, old, new);
		replaced = 1;
	}

	# Write back
	fd := sys->create(path, Sys->OWRITE, 8r644);
	if(fd == nil)
		return sys->sprint("error: cannot write %s: %r", path);

	data := array of byte newtext;
	n := sys->write(fd, data, len data);
	if(n != len data)
		return sys->sprint("error: partial write to %s", path);

	return sys->sprint("replaced %d occurrence(s) in %s", replaced, path);
}

# Parse edit arguments: path, old, new, all flag
parseargs(s: string): (string, string, string, int)
{
	path := "";
	old := "";
	new := "";
	all := 0;

	# Parse path
	(path, s) = parseone(s);
	if(path == "")
		return ("", "", "", 0);

	# Parse old text
	(old, s) = parseone(s);
	if(old == "")
		return (path, "", "", 0);

	# Parse new text
	(new, s) = parseone(s);

	# Check for 'all' flag
	(flag, nil) := parseone(s);
	if(flag == "all")
		all = 1;

	return (path, old, new, all);
}

# Parse one argument, handling quotes
parseone(s: string): (string, string)
{
	# Skip leading whitespace
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;

	if(i >= len s)
		return ("", "");

	# Check for quoted string
	if(s[i] == '"' || s[i] == '\'') {
		quote := s[i];
		i++;
		start := i;
		# Handle escaped quotes
		result := "";
		while(i < len s) {
			if(s[i] == '\\' && i + 1 < len s && s[i+1] == quote) {
				result += s[start:i];
				result[len result] = quote;
				i += 2;
				start = i;
				continue;
			}
			if(s[i] == quote)
				break;
			i++;
		}
		result += s[start:i];
		if(i < len s)
			i++;
		return (result, s[i:]);
	}

	# Unquoted argument
	start := i;
	while(i < len s && s[i] != ' ' && s[i] != '\t')
		i++;
	return (s[start:i], s[i:]);
}

# Process escape sequences
unescape(s: string): string
{
	result := "";
	i := 0;
	while(i < len s) {
		if(s[i] == '\\' && i + 1 < len s) {
			case s[i+1] {
			'n' =>
				result[len result] = '\n';
			't' =>
				result[len result] = '\t';
			'r' =>
				result[len result] = '\r';
			'\\' =>
				result[len result] = '\\';
			'"' =>
				result[len result] = '"';
			'\'' =>
				result[len result] = '\'';
			* =>
				result[len result] = s[i+1];
			}
			i += 2;
		} else {
			result[len result] = s[i];
			i++;
		}
	}
	return result;
}

# Escape string for display
escape(s: string): string
{
	result := "";
	for(i := 0; i < len s; i++) {
		c := s[i];
		case c {
		'\n' =>
			result += "\\n";
		'\t' =>
			result += "\\t";
		'\r' =>
			result += "\\r";
		* =>
			result[len result] = c;
		}
	}
	return result;
}

# Count occurrences of needle in haystack
countoccur(haystack, needle: string): int
{
	count := 0;
	i := 0;
	while(i <= len haystack - len needle) {
		if(haystack[i:i+len needle] == needle) {
			count++;
			i += len needle;
		} else {
			i++;
		}
	}
	return count;
}

# Replace first occurrence
replacefirst(text, old, new: string): string
{
	i := 0;
	while(i <= len text - len old) {
		if(text[i:i+len old] == old)
			return text[0:i] + new + text[i+len old:];
		i++;
	}
	return text;
}

# Replace all occurrences
replaceall(text, old, new: string): string
{
	result := "";
	i := 0;
	while(i < len text) {
		if(i <= len text - len old && text[i:i+len old] == old) {
			result += new;
			i += len old;
		} else {
			result[len result] = text[i];
			i++;
		}
	}
	return result;
}

# Read entire file
readfile(path: string): array of byte
{
	(ok, d) := sys->stat(path);
	if(ok < 0)
		return nil;

	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;

	data := array[int d.length] of byte;
	n := sys->read(fd, data, len data);
	if(n < 0)
		return nil;

	return data[0:n];
}
