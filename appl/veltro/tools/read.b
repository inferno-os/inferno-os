implement ToolRead;

#
# read - Read file contents tool for Veltro agent
#
# Reads and returns file contents with optional offset and line limit.
#
# Usage:
#   Read <path>                    # Read entire file (default: 100 lines max)
#   Read <path> <offset>           # Start from line offset
#   Read <path> <offset> <limit>   # Read limit lines from offset
#
# Examples:
#   Read /appl/veltro/veltro.b
#   Read /appl/veltro/veltro.b 10
#   Read /appl/veltro/veltro.b 10 50
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

ToolRead: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

# Defaults and limits
DEFAULT_LIMIT: con 100;
MAX_LIMIT: con 1000;

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
	return "read";
}

doc(): string
{
	return "Read - Read file contents\n\n" +
		"Usage:\n" +
		"  Read <path>                    # Read file (default: 100 lines max)\n" +
		"  Read <path> <offset>           # Start from line offset\n" +
		"  Read <path> <offset> <limit>   # Read limit lines from offset\n\n" +
		"Arguments:\n" +
		"  path    - File path to read\n" +
		"  offset  - Starting line number (0-indexed, default: 0)\n" +
		"  limit   - Maximum lines to return (default: 100, max: 1000)\n\n" +
		"Examples:\n" +
		"  Read /appl/veltro/veltro.b\n" +
		"  Read /appl/veltro/veltro.b 10\n" +
		"  Read /appl/veltro/veltro.b 10 50\n\n" +
		"Returns file contents with line numbers, or error message.";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	# Parse arguments
	(n, argv) := sys->tokenize(args, " \t");
	if(n < 1)
		return "error: usage: Read <path> [offset] [limit]";

	path := hd argv;
	argv = tl argv;

	offset := 0;
	limit := DEFAULT_LIMIT;

	if(argv != nil) {
		offset = int hd argv;
		argv = tl argv;
		if(offset < 0)
			offset = 0;
	}

	if(argv != nil) {
		limit = int hd argv;
		if(limit < 1)
			limit = 1;
		if(limit > MAX_LIMIT)
			limit = MAX_LIMIT;
	}

	# Open file
	f := bufio->open(path, Sys->OREAD);
	if(f == nil)
		return sys->sprint("error: cannot open %s: %r", path);

	# Read lines
	result := "";
	lineno := 0;
	linesread := 0;
	truncated := 0;

	while((line := f.gets('\n')) != nil) {
		if(lineno >= offset) {
			if(linesread >= limit) {
				truncated = 1;
				break;
			}
			# Format with line number
			result += sys->sprint("%5d\t%s", lineno + 1, line);
			linesread++;
		}
		lineno++;
	}

	f.close();

	if(result == "")
		return sys->sprint("(empty file or offset %d beyond end)", offset);

	if(truncated)
		result += sys->sprint("\n... (truncated at %d lines, %d total)", limit, lineno);

	return result;
}
