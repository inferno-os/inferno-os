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
MAX_DEPTH:   con 20;
MAX_DIRS:    con 2000;   # max directories opened per search — safety valve for huge trees
OPEN_TIMEOUT: con 500;  # ms — skip directories that block longer than this

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	filepat = load Filepat Filepat->PATH;
	if(filepat == nil)
		return "cannot load Filepat";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";
	return nil;
}

name(): string
{
	return "find";
}

doc(): string
{
	return "Find - Find files by glob pattern\n\n" +
		"Accepts both native and Unix-style syntax:\n" +
		"  Find <pattern> [path]            # native: pattern first\n" +
		"  Find [path] -name <pattern>      # Unix: path then -name pattern\n\n" +
		"Patterns:\n" +
		"  *     - Match any characters\n" +
		"  ?     - Match single character\n" +
		"  [abc] - Match character class\n\n" +
		"Examples:\n" +
		"  Find *.dis /dis/wm\n" +
		"  Find /dis/wm -name *.dis\n" +
		"  Find / -name *tetris*\n" +
		"  Find *_test.b /tests\n\n" +
		"Returns list of matching file paths (max 100 results, max 2000 directories).";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	if(filepat == nil)
		return "error: cannot load filepat module";

	# Parse arguments — accept two calling conventions:
	#   Tool-native:  Find <pattern> [path]       e.g. Find *tetris* /dis
	#   Unix-compat:  Find [path] -name <pattern>  e.g. Find /dis -name *tetris*
	(n, argv) := sys->tokenize(args, " \t");
	if(n < 1)
		return "error: usage: Find <pattern> [path]";

	pattern := "";
	basepath := ".";

	# Detect Unix-style: scan for -name flag
	nameflag := 0;
	patharg := "";
	patarg := "";
	for(a := argv; a != nil; a = tl a) {
		tok := hd a;
		if(nameflag) {
			patarg = tok;
			nameflag = 0;
		} else if(tok == "-name" || tok == "-iname") {
			nameflag = 1;
		} else if(len tok > 0 && tok[0] != '-') {
			patharg = tok;
		}
	}
	if(patarg != "") {
		# Unix-style found
		pattern = patarg;
		if(patharg != "")
			basepath = patharg;
	} else {
		# Tool-native: pattern first, optional path second
		pattern = hd argv;
		argv = tl argv;
		if(argv != nil)
			basepath = hd argv;
	}

	# Strip shell-style quotes that LLMs sometimes add around patterns.
	# e.g. -name "*.pdf" tokenizes as `"*.pdf"` (with literal quotes).
	if(len pattern >= 2 &&
	   ((pattern[0] == '"' && pattern[len pattern - 1] == '"') ||
	    (pattern[0] == '\'' && pattern[len pattern - 1] == '\'')))
		pattern = pattern[1:len pattern - 1];

	# dirc[0] tracks directories opened across the entire recursive search.
	# Passed by reference (array) so all recursive calls share one counter.
	dirc := array[1] of {* => 0};

	# Collect results
	results: list of string;
	count := 0;
	truncated := 0;

	# Search recursively
	(results, count, truncated) = searchdir(basepath, pattern, 0, dirc);

	if(count == 0) {
		if(truncated)
			return sys->sprint("no matches found (search stopped after %d directories)", dirc[0]);
		return "no matches found";
	}

	# Build result string
	result := "";
	for(r := results; r != nil; r = tl r) {
		if(result != "")
			result += "\n";
		result += hd r;
	}

	if(truncated)
		result += sys->sprint("\n... (truncated at %d results, %d directories searched)", MAX_RESULTS, dirc[0]);

	return sys->sprint("%d matches:\n%s", count, result);
}

# Recursively search directory for matching files.
# dirc is a single-element array used as a shared directory counter.
#
# Files at the current level are matched BEFORE recursing into any
# subdirectory.  This guarantees that a file sitting at /foo/bar.pdf is
# found even when the very first subdirectory of /foo exhausts MAX_DIRS.
# (Previous DFS approach: recurse into subdir immediately → MAX_DIRS hit →
# early return → root-level files never checked.)
searchdir(path, pattern: string, depth: int, dirc: array of int): (list of string, int, int)
{
	results: list of string;
	count := 0;
	truncated := 0;

	if(depth > MAX_DEPTH)
		return (nil, 0, 0);

	if(dirc[0] >= MAX_DIRS)
		return (nil, 0, 1);

	fd := opentimeout(path, Sys->OREAD, OPEN_TIMEOUT);
	if(fd == nil)
		return (nil, 0, 0);
	dirc[0]++;

	# Pass 1: read all entries, match files immediately, collect subdir paths.
	# Subdirs are deferred so ALL files at this level are checked first.
	subdirs: list of string;
	done := 0;
	for(;;) {
		if(done)
			break;
		(nread, dir) := sys->dirread(fd);
		if(nread <= 0)
			break;

		for(i := 0; i < nread && !done; i++) {
			d := dir[i];
			name := d.name;

			if(name == "." || name == "..")
				continue;

			fullpath := path + "/" + name;
			if(path == "." || path == "/")
				fullpath = path + name;
			if(path == "/" && name[0] != '/')
				fullpath = "/" + name;
			if(len path > 0 && path[len path - 1] == '/')
				fullpath = path + name;

			# Match all entries (files AND dirs) against pattern
			if(filepat->match(pattern, name)) {
				if(count >= MAX_RESULTS) {
					done = 1;
					truncated = 1;
					continue;
				}
				results = fullpath :: results;
				count++;
			}

			# Collect non-hidden subdirs for later recursion.
			# Skip hidden dirs (.git, .cache, .npm, etc.) which can be
			# enormous and are rarely where user files live.
			if((d.mode & Sys->DMDIR) && name[0] != '.')
				subdirs = fullpath :: subdirs;
		}
	}

	# Pass 2: recurse into collected subdirs (only after all files matched above)
	for(s := subdirs; s != nil && !truncated; s = tl s) {
		if(dirc[0] >= MAX_DIRS) {
			truncated = 1;
			break;
		}
		(subresults, subcount, subtrunc) := searchdir(hd s, pattern, depth + 1, dirc);
		for(; subresults != nil; subresults = tl subresults)
			results = hd subresults :: results;
		count += subcount;
		if(subtrunc)
			truncated = 1;
		if(count >= MAX_RESULTS)
			truncated = 1;
	}

	return (results, count, truncated);
}

# Open a file with timeout to skip blocked paths (e.g. macOS TCC).
# IMPORTANT: timeout MUST be chan[1] (buffered) so sleeptimer() can exit
# after sending even when nobody is receiving.  An unbuffered channel
# causes sleeptimer() to block forever — a goroutine leak that accumulates
# one leaked goroutine per directory visited and eventually exhausts memory.
opentimeout(path: string, mode: int, ms: int): ref Sys->FD
{
	result := chan[1] of ref Sys->FD;
	spawn tryopen(path, mode, result);

	timeout := chan[1] of int;  # buffered: sleeptimer exits after send
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
