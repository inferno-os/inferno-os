implement ToolSearch;

#
# search - Search file contents for pattern for Veltro agent
#
# Recursively searches file contents for matching text or regex.
#
# Usage:
#   Search <pattern>              # Search from current directory
#   Search <pattern> <path>       # Search in specified path
#
# The pattern is a regular expression. For literal search, escape special chars.
#
# Examples:
#   Search "func init" /appl
#   Search "include.*sys.m" /appl/veltro
#   Search TODO
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "regex.m";
	regex: Regex;
	Re: import regex;

include "string.m";
	str: String;

include "../tool.m";

ToolSearch: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

# Limits
MAX_RESULTS: con 20;
MAX_DEPTH: con 20;
MAX_LINE_LEN: con 200;
OPEN_TIMEOUT: con 3000;	# ms — skip directories that block longer than this

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	bufio = load Bufio Bufio->PATH;
	regex = load Regex Regex->PATH;
	str = load String String->PATH;
	return nil;
}

name(): string
{
	return "search";
}

doc(): string
{
	return "Search - Search file contents for pattern\n\n" +
		"Usage:\n" +
		"  Search <pattern>              # Search from current directory\n" +
		"  Search <pattern> <path>       # Search in specified path\n\n" +
		"The pattern is a regular expression.\n\n" +
		"Examples:\n" +
		"  Search \"func init\" /appl\n" +
		"  Search \"include.*sys.m\" /appl/veltro\n" +
		"  Search TODO\n\n" +
		"Returns matching lines with file:line:content (max 20 results).";
}

# Match result
Match: adt {
	file:   string;
	lineno: int;
	line:   string;
};

exec(args: string): string
{
	if(sys == nil)
		init();

	if(regex == nil)
		return "error: cannot load regex module";

	# Parse arguments - handle quoted strings
	(pattern, rest) := parsearg(args);
	if(pattern == "")
		return "error: usage: Search <pattern> [path]";

	basepath := ".";
	(p, nil) := parsearg(rest);
	if(p != "")
		basepath = p;

	# Compile regex
	(re, err) := regex->compile(pattern, 0);
	if(re == nil)
		return "error: invalid pattern: " + err;

	# Collect results
	results: list of ref Match;
	count := 0;
	truncated := 0;

	# Search recursively
	(results, count, truncated) = searchdir(basepath, re, 0);

	if(count == 0)
		return "no matches found";

	# Build result string (reverse to get original order)
	revresults: list of ref Match;
	for(; results != nil; results = tl results)
		revresults = hd results :: revresults;

	result := "";
	for(r := revresults; r != nil; r = tl r) {
		m := hd r;
		if(result != "")
			result += "\n";
		result += sys->sprint("%s:%d: %s", m.file, m.lineno, m.line);
	}

	if(truncated)
		result += sys->sprint("\n... (truncated at %d results)", MAX_RESULTS);

	return sys->sprint("%d matches:\n%s", count, result);
}

# Parse a single argument, handling quotes
parsearg(s: string): (string, string)
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
		while(i < len s && s[i] != quote)
			i++;
		arg := s[start:i];
		if(i < len s)
			i++;  # Skip closing quote
		return (arg, s[i:]);
	}

	# Unquoted argument
	start := i;
	while(i < len s && s[i] != ' ' && s[i] != '\t')
		i++;
	return (s[start:i], s[i:]);
}

# Check if file is likely text (not binary)
istext(path: string): int
{
	# Check file extension
	if(len path > 2) {
		ext := path[len path - 2:];
		if(ext == ".b" || ext == ".m" || ext == ".h" || ext == ".c")
			return 1;
	}
	if(len path > 4) {
		ext := path[len path - 4:];
		if(ext == ".txt" || ext == ".doc")
			return 1;
	}
	if(len path > 3) {
		ext := path[len path - 3:];
		if(ext == ".sh" || ext == ".rc" || ext == ".py")
			return 1;
	}

	# Check for known text files
	for(i := len path - 1; i >= 0; i--) {
		if(path[i] == '/') {
			name := path[i+1:];
			if(name == "mkfile" || name == "README" || name == "LICENSE")
				return 1;
			break;
		}
	}

	# Try to read first bytes and check for binary content
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return 0;

	buf := array[512] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return 0;

	# Check for null bytes (binary indicator)
	for(j := 0; j < n; j++) {
		if(int buf[j] == 0)
			return 0;
	}

	return 1;
}

# Search file for pattern
searchfile(path: string, re: Re): list of ref Match
{
	results: list of ref Match;

	if(!istext(path))
		return nil;

	f := bufio->open(path, Sys->OREAD);
	if(f == nil)
		return nil;

	lineno := 0;
	while((line := f.gets('\n')) != nil) {
		lineno++;

		# Strip trailing newline
		if(len line > 0 && line[len line - 1] == '\n')
			line = line[0:len line - 1];

		# Check for match
		match := regex->execute(re, line);
		if(match != nil) {
			# Truncate long lines
			if(len line > MAX_LINE_LEN)
				line = line[0:MAX_LINE_LEN] + "...";
			results = ref Match(path, lineno, line) :: results;
		}
	}

	f.close();
	return results;
}

# Recursively search directory for matches
searchdir(path: string, re: Re, depth: int): (list of ref Match, int, int)
{
	results: list of ref Match;
	count := 0;
	truncated := 0;

	if(depth > MAX_DEPTH)
		return (nil, 0, 0);

	# Check if path is a file or directory (with timeout for blocked paths)
	isdir := isdirtimeout(path, OPEN_TIMEOUT);
	if(isdir < 0)
		return (nil, 0, 0);

	if(isdir == 0) {
		# It's a file, search it
		matches := searchfile(path, re);
		for(; matches != nil; matches = tl matches) {
			if(count >= MAX_RESULTS)
				return (results, count, 1);
			results = hd matches :: results;
			count++;
		}
		return (results, count, 0);
	}

	# It's a directory, enumerate contents (with timeout)
	fd := opentimeout(path, Sys->OREAD, OPEN_TIMEOUT);
	if(fd == nil)
		return (nil, 0, 0);

	for(;;) {
		(nread, dir) := sys->dirread(fd);
		if(nread <= 0)
			break;

		for(i := 0; i < nread; i++) {
			ent := dir[i];
			name := ent.name;

			# Skip . and ..
			if(name == "." || name == "..")
				continue;

			# Skip hidden files and common non-text directories
			if(len name > 0 && name[0] == '.')
				continue;
			if(name == "dis" || name == "bin" || name == "obj")
				continue;

			fullpath := path + "/" + name;
			if(len path > 0 && path[len path - 1] == '/')
				fullpath = path + name;

			if(ent.mode & Sys->DMDIR) {
				# Recurse into directory
				(subresults, subcount, subtrunc) := searchdir(fullpath, re, depth + 1);
				for(; subresults != nil; subresults = tl subresults) {
					if(count >= MAX_RESULTS) {
						truncated = 1;
						return (results, count, truncated);
					}
					results = hd subresults :: results;
					count++;
				}
				if(subtrunc)
					truncated = 1;
			} else {
				# Search file
				matches := searchfile(fullpath, re);
				for(; matches != nil; matches = tl matches) {
					if(count >= MAX_RESULTS) {
						truncated = 1;
						return (results, count, truncated);
					}
					results = hd matches :: results;
					count++;
				}
			}

			if(count >= MAX_RESULTS) {
				truncated = 1;
				return (results, count, truncated);
			}
		}
	}

	return (results, count, truncated);
}

# Check if path is a directory, with timeout to skip blocked paths.
# Returns: 1=directory, 0=file, -1=error/timeout.
isdirtimeout(path: string, ms: int): int
{
	result := chan[1] of int;
	spawn statcheck(path, result);

	timeout := chan of int;
	spawn sleeptimer(timeout, ms);

	alt {
		v := <-result =>
			return v;
		<-timeout =>
			sys->fprint(sys->fildes(2), "search: timeout stat %s (skipping)\n", path);
			return -1;
	}
}

statcheck(path: string, result: chan of int)
{
	(ok, d) := sys->stat(path);
	if(ok < 0)
		result <-= -1;
	else if(d.mode & Sys->DMDIR)
		result <-= 1;
	else
		result <-= 0;
}

# Open a file with timeout to skip blocked paths.
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
			sys->fprint(sys->fildes(2), "search: timeout open %s (skipping)\n", path);
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
