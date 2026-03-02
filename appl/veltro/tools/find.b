implement ToolFind;

#
# find - Find files by glob pattern for Veltro agent
#
# Recursively searches for files matching a glob pattern.
#
# Usage:
#   Find <pattern>              # Search from current directory
#   Find <pattern> <path>       # Search from specified path
#
# Patterns:
#   *     - Match any characters
#   ?     - Match single character
#   [abc] - Match character class
#
# Examples:
#   Find *.b /appl
#   Find mkfile
#   Find *_test.b /tests
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "filepat.m";
	filepat: Filepat;

include "string.m";
	str: String;

include "../tool.m";

ToolFind: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

# Limits
MAX_RESULTS: con 100;
MAX_DEPTH: con 20;
OPEN_TIMEOUT: con 3000;	# ms — skip directories that block longer than this

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	filepat = load Filepat Filepat->PATH;
	str = load String String->PATH;
	return nil;
}

name(): string
{
	return "find";
}

doc(): string
{
	return "Find - Find files by glob pattern\n\n" +
		"Usage:\n" +
		"  Find <pattern>              # Search from current directory\n" +
		"  Find <pattern> <path>       # Search from specified path\n\n" +
		"Patterns:\n" +
		"  *     - Match any characters\n" +
		"  ?     - Match single character\n" +
		"  [abc] - Match character class\n\n" +
		"Examples:\n" +
		"  Find *.b /appl\n" +
		"  Find mkfile\n" +
		"  Find *_test.b /tests\n\n" +
		"Returns list of matching file paths (max 100 results).";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	if(filepat == nil)
		return "error: cannot load filepat module";

	# Parse arguments
	(n, argv) := sys->tokenize(args, " \t");
	if(n < 1)
		return "error: usage: Find <pattern> [path]";

	pattern := hd argv;
	argv = tl argv;

	basepath := ".";
	if(argv != nil)
		basepath = hd argv;

	# Collect results
	results: list of string;
	count := 0;
	truncated := 0;

	# Search recursively
	(results, count, truncated) = searchdir(basepath, pattern, 0);

	if(count == 0)
		return "no matches found";

	# Build result string
	result := "";
	for(r := results; r != nil; r = tl r) {
		if(result != "")
			result += "\n";
		result += hd r;
	}

	if(truncated)
		result += sys->sprint("\n... (truncated at %d results)", MAX_RESULTS);

	return sys->sprint("%d matches:\n%s", count, result);
}

# Recursively search directory for matching files
searchdir(path, pattern: string, depth: int): (list of string, int, int)
{
	results: list of string;
	count := 0;
	truncated := 0;

	if(depth > MAX_DEPTH)
		return (nil, 0, 0);

	fd := opentimeout(path, Sys->OREAD, OPEN_TIMEOUT);
	if(fd == nil)
		return (nil, 0, 0);

	for(;;) {
		(nread, dir) := sys->dirread(fd);
		if(nread <= 0)
			break;

		for(i := 0; i < nread; i++) {
			d := dir[i];
			name := d.name;

			# Skip . and ..
			if(name == "." || name == "..")
				continue;

			fullpath := path + "/" + name;
			if(path == "." || path == "/")
				fullpath = path + name;
			if(path == "/" && name[0] != '/')
				fullpath = "/" + name;
			if(len path > 0 && path[len path - 1] == '/')
				fullpath = path + name;

			# Check if name matches pattern
			if(filepat->match(pattern, name)) {
				if(count >= MAX_RESULTS) {
					truncated = 1;
					return (results, count, truncated);
				}
				results = fullpath :: results;
				count++;
			}

			# Recurse into directories
			if(d.mode & Sys->DMDIR) {
				(subresults, subcount, subtrunc) := searchdir(fullpath, pattern, depth + 1);
				for(; subresults != nil; subresults = tl subresults)
					results = hd subresults :: results;
				count += subcount;
				if(subtrunc || count >= MAX_RESULTS) {
					truncated = 1;
					return (results, count, truncated);
				}
			}
		}
	}

	return (results, count, truncated);
}

# Open a file with timeout to skip blocked paths (e.g. macOS TCC).
opentimeout(path: string, mode: int, ms: int): ref Sys->FD
{
	result := chan[1] of ref Sys->FD;
	spawn tryopen(path, mode, result);

	timeout := chan of int;
	spawn sleeptimer(timeout, ms);

	alt {
		fd := <-result =>
			return fd;
		<-timeout =>
			sys->fprint(sys->fildes(2), "find: timeout open %s (skipping)\n", path);
			return nil;
	}
}

tryopen(path: string, mode: int, result: chan of ref Sys->FD)
{
	fd := sys->open(path, mode);
	result <-= fd;
}

sleeptimer(ch: chan of int, ms: int)
{
	sys->sleep(ms);
	ch <-= 1;
}
