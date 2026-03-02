implement ToolMemory;

#
# memory - Agent memory/persistence tool for Veltro agent
#
# Provides persistent key-value storage for agent context.
# Data persists across sessions in /tmp/veltro/memory/{agentid}/
#
# Usage:
#   memory save <key> <value>     # Store a value
#   memory load <key>             # Retrieve a value
#   memory delete <key>           # Delete a key
#   memory list                   # List all keys
#   memory clear                  # Clear all keys
#
# Examples:
#   memory save project_path /home/user/myproject
#   memory load project_path
#   memory save context "Working on authentication module"
#   memory list
#
# Keys are alphanumeric with underscores. Values are stored as-is.
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

ToolMemory: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

# Memory storage base path
# Agent ID is determined from sandbox path or generated
MEMORY_BASE: con "/tmp/veltro/memory";
DEFAULT_AGENT: con "default";

# Current agent ID (set on first use)
agentid: string;

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

	# Try to determine agent ID from environment or sandbox
	agentid = getagentid();

	return nil;
}

name(): string
{
	return "memory";
}

doc(): string
{
	return "Memory - Persistent key-value storage\n\n" +
		"Usage:\n" +
		"  memory save <key> <value>  # Store a value\n" +
		"  memory load <key>          # Retrieve a value\n" +
		"  memory delete <key>        # Delete a key\n" +
		"  memory list                # List all keys\n" +
		"  memory clear               # Clear all keys\n" +
		"  memory append <key> <val>  # Append to existing value\n\n" +
		"Arguments:\n" +
		"  key   - Alphanumeric key (a-z, 0-9, _)\n" +
		"  value - Any string value\n\n" +
		"Examples:\n" +
		"  memory save project /home/user/myproject\n" +
		"  memory load project\n" +
		"  memory save notes \"Working on auth\"\n" +
		"  memory append notes \" - added login\"\n" +
		"  memory list\n\n" +
		"Data persists across agent sessions.";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	args = strip(args);
	if(args == "")
		return "error: usage: memory <save|load|delete|list|clear|append> [args...]";

	# Parse command
	(cmd, rest) := splitfirst(args);
	cmd = str->tolower(cmd);

	case cmd {
	"save" =>
		return dosave(rest);
	"load" =>
		return doload(rest);
	"delete" =>
		return dodelete(rest);
	"list" =>
		return dolist();
	"clear" =>
		return doclear();
	"append" =>
		return doappend(rest);
	* =>
		return "error: unknown command: " + cmd;
	}
}

# Save a key-value pair
dosave(args: string): string
{
	(key, value) := splitfirst(args);
	if(key == "")
		return "error: usage: memory save <key> <value>";

	if(!validkey(key))
		return "error: invalid key (use alphanumeric and underscore only)";

	value = stripquotes(value);

	# Ensure memory directory exists
	err := ensuredir(memorypath());
	if(err != nil)
		return "error: " + err;

	# Write value to file
	path := keypath(key);
	fd := sys->create(path, Sys->OWRITE, 8r600);
	if(fd == nil)
		return sys->sprint("error: cannot create %s: %r", path);

	data := array of byte value;
	if(sys->write(fd, data, len data) < 0) {
		fd = nil;
		return sys->sprint("error: write failed: %r");
	}
	fd = nil;

	return sys->sprint("saved '%s' (%d bytes)", key, len value);
}

# Load a value by key
doload(args: string): string
{
	key := strip(args);
	if(key == "")
		return "error: usage: memory load <key>";

	if(!validkey(key))
		return "error: invalid key";

	path := keypath(key);
	(value, err) := readfile(path);
	if(err != nil)
		return "error: key not found: " + key;

	return value;
}

# Delete a key
dodelete(args: string): string
{
	key := strip(args);
	if(key == "")
		return "error: usage: memory delete <key>";

	if(!validkey(key))
		return "error: invalid key";

	path := keypath(key);
	if(sys->remove(path) < 0)
		return "error: key not found: " + key;

	return "deleted '" + key + "'";
}

# List all keys
dolist(): string
{
	path := memorypath();
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return "(no stored keys)";

	result := "";
	count := 0;

	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			name := dirs[i].name;
			if(name == "." || name == "..")
				continue;
			if(result != "")
				result += "\n";
			result += name;
			count++;
		}
	}
	fd = nil;

	if(count == 0)
		return "(no stored keys)";

	return sys->sprint("%d keys:\n%s", count, result);
}

# Clear all keys
doclear(): string
{
	path := memorypath();
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return "(memory already empty)";

	count := 0;
	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			name := dirs[i].name;
			if(name == "." || name == "..")
				continue;
			sys->remove(path + "/" + name);
			count++;
		}
	}
	fd = nil;

	return sys->sprint("cleared %d keys", count);
}

# Append to existing value
doappend(args: string): string
{
	(key, value) := splitfirst(args);
	if(key == "")
		return "error: usage: memory append <key> <value>";

	if(!validkey(key))
		return "error: invalid key";

	value = stripquotes(value);

	# Load existing value
	path := keypath(key);
	(existing, nil) := readfile(path);

	# Append new value
	newvalue := existing + value;

	# Ensure directory exists
	err := ensuredir(memorypath());
	if(err != nil)
		return "error: " + err;

	# Write combined value
	fd := sys->create(path, Sys->OWRITE, 8r600);
	if(fd == nil)
		return sys->sprint("error: cannot create %s: %r", path);

	data := array of byte newvalue;
	if(sys->write(fd, data, len data) < 0) {
		fd = nil;
		return sys->sprint("error: write failed: %r");
	}
	fd = nil;

	return sys->sprint("appended to '%s' (now %d bytes)", key, len newvalue);
}

# Get agent ID from environment or generate default
getagentid(): string
{
	# Try to read from sandbox context
	# For now, use default
	return DEFAULT_AGENT;
}

# Get memory directory path for current agent
memorypath(): string
{
	return MEMORY_BASE + "/" + agentid;
}

# Get path for a specific key
keypath(key: string): string
{
	return memorypath() + "/" + key;
}

# Validate key (alphanumeric + underscore)
validkey(key: string): int
{
	if(key == "")
		return 0;
	if(len key > 64)
		return 0;

	for(i := 0; i < len key; i++) {
		c := key[i];
		if(!((c >= 'a' && c <= 'z') ||
		     (c >= 'A' && c <= 'Z') ||
		     (c >= '0' && c <= '9') ||
		     c == '_' || c == '-'))
			return 0;
	}

	# Don't allow special names
	if(key == "." || key == "..")
		return 0;

	return 1;
}

# Ensure directory exists (creates parents)
ensuredir(path: string): string
{
	# Check if exists
	(ok, nil) := sys->stat(path);
	if(ok >= 0)
		return nil;

	# Create parent first
	parent := "";
	for(i := len path - 1; i > 0; i--) {
		if(path[i] == '/') {
			parent = path[0:i];
			break;
		}
	}
	if(parent != "" && parent != "/") {
		err := ensuredir(parent);
		if(err != nil)
			return err;
	}

	# Create directory
	fd := sys->create(path, Sys->OREAD, 8r700 | Sys->DMDIR);
	if(fd == nil)
		return sys->sprint("cannot create %s: %r", path);
	fd = nil;
	return nil;
}

# Read entire file contents
readfile(path: string): (string, string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return ("", sys->sprint("cannot open %s: %r", path));

	content := "";
	buf := array[8192] of byte;
	while((n := sys->read(fd, buf, len buf)) > 0)
		content += string buf[0:n];

	fd = nil;
	return (content, nil);
}

# Strip whitespace
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

# Strip surrounding quotes
stripquotes(s: string): string
{
	s = strip(s);
	if(len s < 2)
		return s;
	if((s[0] == '"' && s[len s - 1] == '"') ||
	   (s[0] == '\'' && s[len s - 1] == '\''))
		return s[1:len s - 1];
	return s;
}

# Split on first whitespace
splitfirst(s: string): (string, string)
{
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t')
			return (s[0:i], strip(s[i:]));
	}
	return (s, "");
}
