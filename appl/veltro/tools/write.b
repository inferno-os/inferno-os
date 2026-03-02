implement ToolWrite;

#
# write - Write file contents tool for Veltro agent
#
# Creates or overwrites a file with specified content.
# For safety, creates parent directories as needed.
#
# Usage:
#   Write <path> <content>
#
# The content can span multiple lines and should be quoted if it contains spaces.
# Use \n for explicit newlines within the content.
#
# Examples:
#   Write /tmp/veltro/scratch/test.txt "Hello World"
#   Write /tmp/veltro/scratch/script.sh "#!/bin/sh\necho hello"
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "../tool.m";

ToolWrite: module {
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
	return nil;
}

name(): string
{
	return "write";
}

doc(): string
{
	return "Write - Write file contents\n\n" +
		"Usage:\n" +
		"  Write <path> <content>\n\n" +
		"Arguments:\n" +
		"  path    - File path to write (use /tmp/veltro/scratch/ for temp files)\n" +
		"  content - Content to write (use quotes for spaces, \\n for newlines)\n\n" +
		"Examples:\n" +
		"  Write /tmp/veltro/scratch/test.txt \"Hello World\"\n" +
		"  Write /tmp/veltro/scratch/script.sh \"#!/bin/sh\\necho hello\"\n\n" +
		"Returns confirmation with bytes written, or error message.";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	# Parse path and content
	(path, content) := parseargs(args);
	if(path == "")
		return "error: usage: Write <path> <content>";
	if(content == "")
		return "error: no content specified";

	# Process escape sequences in content
	content = unescape(content);

	# Ensure parent directory exists
	ensureparent(path);

	# Write file
	fd := sys->create(path, Sys->OWRITE, 8r644);
	if(fd == nil)
		return sys->sprint("error: cannot create %s: %r", path);

	data := array of byte content;
	n := sys->write(fd, data, len data);
	if(n < 0)
		return sys->sprint("error: write failed: %r");

	if(n != len data)
		return sys->sprint("error: partial write (%d of %d bytes)", n, len data);

	return sys->sprint("wrote %d bytes to %s", n, path);
}

# Parse path and content from args
parseargs(s: string): (string, string)
{
	# Skip leading whitespace
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;

	if(i >= len s)
		return ("", "");

	# Parse path (first argument)
	path := "";
	if(s[i] == '"' || s[i] == '\'') {
		# Quoted path
		quote := s[i];
		i++;
		start := i;
		while(i < len s && s[i] != quote)
			i++;
		path = s[start:i];
		if(i < len s)
			i++;
	} else {
		# Unquoted path
		start := i;
		while(i < len s && s[i] != ' ' && s[i] != '\t')
			i++;
		path = s[start:i];
	}

	# Skip whitespace
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;

	if(i >= len s)
		return (path, "");

	# Rest is content
	content := "";
	if(s[i] == '"' || s[i] == '\'') {
		# Quoted content
		quote := s[i];
		i++;
		start := i;
		# Find matching quote, handling escaped quotes
		while(i < len s) {
			if(s[i] == '\\' && i + 1 < len s) {
				i += 2;
				continue;
			}
			if(s[i] == quote)
				break;
			i++;
		}
		content = s[start:i];
	} else {
		# Unquoted content (rest of string)
		content = s[i:];
	}

	return (path, content);
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

# Ensure parent directory exists
ensureparent(path: string)
{
	# Find last /
	last := -1;
	for(i := 0; i < len path; i++) {
		if(path[i] == '/')
			last = i;
	}

	if(last <= 0)
		return;

	parent := path[0:last];
	ensuredir(parent);
}

# Recursively ensure directory exists
ensuredir(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil)
		return;

	# Ensure parent exists
	for(i := len path - 1; i > 0; i--) {
		if(path[i] == '/') {
			ensuredir(path[0:i]);
			break;
		}
	}

	# Create this directory
	sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
}
