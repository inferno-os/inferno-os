implement AgentLib;

#
# agentlib - Shared agent library for Veltro
#
# Extracted from veltro.b and repl.b: LLM session management, prompt building,
# response parsing, tool execution, and utility functions. Each function uses
# the best version from whichever file had it (see plan audit table).
#

include "sys.m";
	sys: Sys;

include "string.m";
	str: String;

include "agentlib.m";

SCRATCH_PATH: con "/tmp/veltro/scratch";

verbose := 0;
stderr: ref Sys->FD;

init()
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	str = load String String->PATH;
}

setverbose(v: int)
{
	verbose = v;
}

#
# ==================== LLM Session Management ====================
#

# Create LLM session using clone pattern
# Returns session ID (e.g., "0") or empty string on error
# (from veltro.b — has verbose logging on failure)
createsession(): string
{
	fd := sys->open("/n/llm/new", Sys->OREAD);
	if(fd == nil) {
		if(verbose)
			sys->fprint(stderr, "agentlib: cannot open /n/llm/new: %r\n");
		return "";
	}
	buf := array[32] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "";
	# Trim newline if present
	id := string buf[:n];
	if(len id > 0 && id[len id - 1] == '\n')
		id = id[:len id - 1];
	return id;
}

# Set prefill on session-specific path
# (from veltro.b — has verbose logging on failure)
setprefillpath(path, prefill: string)
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil) {
		if(verbose)
			sys->fprint(stderr, "agentlib: cannot open %s: %r\n", path);
		return;
	}
	data := array of byte prefill;
	sys->write(fd, data, len data);
}

# Query LLM using persistent fd for conversation history
# The same fd must be used across all steps to maintain session isolation
# (from veltro.b — has verbose logging on write failure)
queryllmfd(fd: ref Sys->FD, prompt: string): string
{
	data := array of byte prompt;
	if(verbose)
		sys->fprint(stderr, "agentlib: queryllmfd: write %d bytes\n", len data);

	# Retry on transient write failures with exponential backoff
	delays := array[] of {100, 500, 2000};
	ok := 0;
	for(attempt := 0; attempt <= len delays; attempt++) {
		n := sys->write(fd, data, len data);
		if(n == len data) {
			ok = 1;
			break;
		}
		if(verbose)
			sys->fprint(stderr, "agentlib: write attempt %d failed: %r\n", attempt + 1);
		if(attempt < len delays)
			sys->sleep(delays[attempt]);
	}
	if(!ok)
		return "";

	if(verbose)
		sys->fprint(stderr, "agentlib: queryllmfd: write done, reading response\n");

	# Read response using pread from offset 0
	result := "";
	buf := array[8192] of byte;
	offset := big 0;
	for(;;) {
		n := sys->pread(fd, buf, len buf, offset);
		if(n <= 0)
			break;
		result += string buf[0:n];
		offset += big n;
	}
	if(verbose)
		sys->fprint(stderr, "agentlib: queryllmfd: response %d bytes\n", len array of byte result);
	return result;
}

# Write system prompt to session path
# (from repl.b — only repl had this)
setsystemprompt(path, prompt: string)
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil) {
		sys->fprint(stderr, "agentlib: cannot open %s: %r\n", path);
		return;
	}
	data := array of byte prompt;
	n := sys->write(fd, data, len data);
	if(n != len data)
		sys->fprint(stderr, "agentlib: system prompt write: %d/%d bytes: %r\n", n, len data);
	else if(verbose)
		sys->fprint(stderr, "agentlib: system prompt set: %d bytes\n", n);
}

#
# ==================== Prompt Building ====================
#

# Discover namespace — read /tool/tools and list accessible paths
discovernamespace(): string
{
	result := "TOOLS:\n";

	# Read available tools
	tools := readfile("/tool/tools");
	if(tools != "")
		result += tools;
	else
		result += "(none)";

	# List accessible paths
	result += "\n\nPATHS:\n";
	paths := array[] of {"/", "/tool", "/n", "/tmp"};
	for(i := 0; i < len paths; i++) {
		if(pathexists(paths[i]))
			result += paths[i] + "\n";
	}

	return result;
}

# Build system prompt with namespace, reminders, and modular tool docs.
# Does NOT append mode-specific suffix — callers add their own.
# (from repl.b — has MAXPROMPT 8KB guard against 9P write limit)
buildsystemprompt(ns: string): string
{
	# NOTE: The system prompt may be written to /n/llm/{id}/system via a single
	# 9P Twrite. llm9p's MaxMessageSize is 8192 bytes, and each write
	# REPLACES the content (offset is ignored). If the prompt exceeds ~8KB,
	# the kernel splits into multiple Twrites and only the LAST survives.
	MAXPROMPT: con 8000;

	# Read base system prompt (behavioral policies only — no tool API docs)
	base := readfile("/lib/veltro/system.txt");
	if(base == "")
		base = defaultsystemprompt();

	(nil, toollist) := sys->tokenize(readfile("/tool/tools"), "\n");

	# Load context-specific reminders based on available tools (priority order)
	reminders := loadreminders(toollist);

	# Load modular tool docs for non-obvious tools.
	# exec.txt: Inferno sh differs from POSIX (single quotes, no &&, for-loop syntax)
	# spawn.txt: complex multi-section parallel subagent syntax
	tooldocs := loadtooldocs(toollist);

	prompt := base + "\n\n== Your Namespace ==\n" + ns;

	if(reminders != "")
		prompt += "\n\n== Reminders ==\n" + reminders;

	if(tooldocs != "")
		prompt += "\n\n== Tool Documentation ==\n" + tooldocs;

	# Guard against exceeding 9P write limit
	data := array of byte prompt;
	if(len data > MAXPROMPT) {
		sys->fprint(stderr, "agentlib: WARNING: system prompt %d bytes exceeds %d limit, truncating\n",
			len data, MAXPROMPT);
		prompt = string data[0:MAXPROMPT];
	}

	return prompt;
}

# Load modular tool documentation for tools with non-obvious behavior.
# Sourced from lib/veltro/tools/*.txt — composed upfront, no on-demand help.
# Tools covered: exec (Inferno sh ≠ POSIX), spawn (unique syntax),
#                grep (Plan 9 ERE), todo (MANDATORY workflow).
loadtooldocs(toollist: list of string): string
{
	has_exec := 0;
	has_spawn := 0;
	has_grep := 0;
	has_todo := 0;

	for(t := toollist; t != nil; t = tl t) {
		case hd t {
		"exec"  => has_exec = 1;
		"spawn" => has_spawn = 1;
		"grep"  => has_grep = 1;
		"todo"  => has_todo = 1;
		}
	}

	docs := "";
	# Priority order: exec (shell basics), grep (ERE warning),
	# todo (MANDATORY workflow), spawn (parallel subagent syntax)
	if(has_exec) {
		doc := readfile("/lib/veltro/tools/exec.txt");
		if(doc != "")
			docs += doc;
	}
	if(has_grep) {
		doc := readfile("/lib/veltro/tools/grep.txt");
		if(doc != "") {
			if(docs != "")
				docs += "\n\n";
			docs += doc;
		}
	}
	if(has_todo) {
		doc := readfile("/lib/veltro/tools/todo.txt");
		if(doc != "") {
			if(docs != "")
				docs += "\n\n";
			docs += doc;
		}
	}
	if(has_spawn) {
		doc := readfile("/lib/veltro/tools/spawn.txt");
		if(doc != "") {
			if(docs != "")
				docs += "\n\n";
			docs += doc;
		}
	}
	return docs;
}

# Load context-specific reminders based on available tools.
# Loads in fixed priority order so safety-critical reminders (git, security)
# are included before xenith.txt which is large and lower priority.
loadreminders(toollist: list of string): string
{
	# Determine which reminders are applicable
	has_git := 0;
	has_xenith := 0;
	has_spawn := 0;

	for(t := toollist; t != nil; t = tl t) {
		case hd t {
		"git" =>    has_git = 1;
		"xenith" => has_xenith = 1;
		"spawn" =>  has_spawn = 1;
		}
	}

	# Priority order: safety-critical reminders first.
	# Omitted: inferno-shell.txt (covered by exec.txt in == Tool Documentation ==)
	#          file-modified.txt (covered by <read_before_modify> in system.txt)
	paths := array[3] of string;
	n := 0;
	if(has_git)    { paths[n] = "/lib/veltro/reminders/git.txt"; n++; }
	if(has_spawn)  { paths[n] = "/lib/veltro/reminders/security.txt"; n++; }
	if(has_xenith) { paths[n] = "/lib/veltro/reminders/xenith.txt"; n++; }

	reminders := "";
	for(i := 0; i < n; i++) {
		content := readfile(paths[i]);
		if(content != "" && !contains(reminders, content)) {
			if(reminders != "")
				reminders += "\n\n";
			reminders += content;
		}
	}

	return reminders;
}

# Default system prompt if /lib/veltro/system.txt is not found.
# Tool invocation format is NOT described here — that is handled by native
# tool_use protocol (the model uses its training, not text instructions).
defaultsystemprompt(): string
{
	return "You are a Veltro agent running in Inferno OS.\n\n" +
		"<core_principle>\n" +
		"Your namespace IS your capability set. If a tool isn't available, it doesn't exist.\n" +
		"</core_principle>\n\n" +
		"<read_before_modify>\n" +
		"Always read a file before modifying it. Never guess at file contents.\n" +
		"</read_before_modify>\n\n" +
		"<task_completion>\n" +
		"Work systematically. Use your todo tool to track progress on complex tasks.\n" +
		"When all tasks are complete and no further tool calls are needed, stop.\n" +
		"</task_completion>";
}

#
# ==================== Response Parsing ====================
#

# Parse tool invocation from LLM response
# Supports heredoc syntax for multi-line content and collectsaytext for say
# (from repl.b — has collectsaytext for multi-line say)
parseaction(response: string): (string, string)
{
	# Split into lines
	(nil, lines) := sys->tokenize(response, "\n");

	# Get available tools for matching
	(nil, toollist) := sys->tokenize(readfile("/tool/tools"), "\n");

	# Look for tool invocation
	for(; lines != nil; lines = tl lines) {
		line := hd lines;

		# Skip empty lines
		line = str->drop(line, " \t");
		if(line == "")
			continue;

		# Strip [Veltro] prefix if present (from prefill)
		if(hasprefix(line, "[Veltro]"))
			line = line[8:];
		line = str->drop(line, " \t");
		if(line == "")
			continue;

		# Check for DONE (strip markdown formatting first)
		stripped := str->drop(str->tolower(line), "*#`- ");
		if(stripped == "done" || hasprefix(stripped, "done"))
			return ("DONE", "");

		# Check if line starts with a known tool name
		(first, rest) := splitfirst(line);
		tool := str->tolower(first);

		# Match against discovered tools
		for(t := toollist; t != nil; t = tl t) {
			if(tool == hd t) {
				args := str->drop(rest, " \t");
				# say collects all remaining lines as text
				if(tool == "say")
					args = collectsaytext(args, tl lines);
				else
					(args, lines) = parseheredoc(args, tl lines);
				return (first, args);
			}
		}

		# Not a tool — skip preamble and keep scanning.
		# LLMs often emit conversational text before the tool invocation.
	}

	return ("", "");
}

# Parse all consecutive tool invocations from LLM response.
# Returns list of (tool, args) in order, or nil if nothing found.
# Returns ("DONE", "") :: nil when DONE is first recognizable token.
# Multiple tool lines execute in parallel (independent operations).
parseactions(response: string): list of (string, string)
{
	(nil, lines) := sys->tokenize(response, "\n");
	(nil, toollist) := sys->tokenize(readfile("/tool/tools"), "\n");

	result: list of (string, string);
	found_first := 0;

	for(; lines != nil; ) {
		line := hd lines;
		lines = tl lines;

		# Skip empty lines
		trimmed := str->drop(line, " \t");
		if(trimmed == "")
			continue;

		# Strip [Veltro] prefix if present
		if(hasprefix(trimmed, "[Veltro]"))
			trimmed = trimmed[8:];
		trimmed = str->drop(trimmed, " \t");
		if(trimmed == "")
			continue;

		# Check for DONE
		lower := str->drop(str->tolower(trimmed), "*#`- ");
		if(lower == "done" || hasprefix(lower, "done")) {
			if(!found_first)
				result = ("DONE", "") :: nil;
			break;
		}

		# Check if line starts with a known tool name
		(first, rest) := splitfirst(trimmed);
		tool := str->tolower(first);

		matched := 0;
		for(t := toollist; t != nil; t = tl t) {
			if(tool == hd t) {
				args := str->drop(rest, " \t");
				if(tool == "say") {
					# say consumes all remaining lines — it is terminal
					args = collectsaytext(args, lines);
					result = (first, args) :: result;
					found_first = 1;
					lines = nil;	# consumed
				} else {
					(args, lines) = parseheredoc(args, lines);
					result = (first, args) :: result;
					found_first = 1;
				}
				matched = 1;
				break;
			}
		}

		# Non-tool, non-blank line after finding first tool — stop
		if(!matched && found_first)
			break;
		# Non-tool line before any tool — skip (preamble)
	}

	if(result == nil)
		return nil;

	# Reverse to restore original order (list was built by prepending)
	rev: list of (string, string);
	for(l := result; l != nil; l = tl l)
		rev = (hd l) :: rev;
	return rev;
}

# Parse heredoc content if present in args
# Returns (processed_args, remaining_lines)
# Heredoc format: <<DELIM ... DELIM (DELIM defaults to EOF)
parseheredoc(args: string, lines: list of string): (string, list of string)
{
	# Find heredoc marker <<
	markerpos := findheredoc(args);
	if(markerpos < 0)
		return (args, lines);

	# Extract delimiter (word after <<)
	aftermarker := args[markerpos + 2:];
	aftermarker = str->drop(aftermarker, " \t");
	(delim, nil) := splitfirst(aftermarker);
	if(delim == "")
		delim = "EOF";

	# Args before the heredoc marker
	argsbefore := "";
	if(markerpos > 0)
		argsbefore = strip(args[0:markerpos]);

	# Collect heredoc content from remaining lines
	content := "";
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		# Check for end delimiter (must be alone on line, stripped)
		if(strip(line) == delim) {
			lines = tl lines;
			break;
		}
		if(content != "")
			content += "\n";
		content += line;
	}

	# Combine: args_before + heredoc_content
	result := argsbefore;
	if(result != "" && content != "")
		result += " ";
	result += content;

	return (result, lines);
}

# Collect all remaining lines as say text, stopping at DONE
# Strips markdown formatting for cleaner speech
# (from repl.b — only repl had this)
collectsaytext(first: string, lines: list of string): string
{
	text := first;
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		cleaned := str->drop(line, " \t");
		if(hasprefix(cleaned, "[Veltro]"))
			cleaned = cleaned[8:];
		cleaned = str->drop(cleaned, " \t");
		lower := str->tolower(cleaned);
		if(lower == "done" || hasprefix(lower, "done"))
			break;
		if(cleaned == "")
			text += " ";  # Preserve paragraph breaks as space
		else
			text += " " + stripmarkdown(cleaned);
	}
	return text;
}

# Strip common markdown formatting for speech
# (from repl.b — only repl had this)
stripmarkdown(s: string): string
{
	result := "";
	for(i := 0; i < len s; i++) {
		c := s[i];
		# Skip ** and * (bold/italic markers)
		if(c == '*')
			continue;
		# Skip # at start of line (headers)
		if(c == '#' && (i == 0 || s[i-1] == '\n'))
			continue;
		# Skip ` (code markers)
		if(c == '`')
			continue;
		result[len result] = c;
	}
	return result;
}

# Strip action line from response
# (from repl.b — strips [Veltro] prefix and empty lines)
stripaction(response: string): string
{
	result := "";
	(nil, lines) := sys->tokenize(response, "\n");
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		lower := str->drop(str->tolower(str->drop(line, " \t")), "*#`- ");
		if(lower == "done" || hasprefix(lower, "done"))
			continue;
		cleaned := str->drop(line, " \t");
		if(hasprefix(cleaned, "[Veltro]"))
			cleaned = cleaned[8:];
		cleaned = str->drop(cleaned, " \t");
		if(cleaned == "")
			continue;
		if(result != "")
			result += "\n";
		result += cleaned;
	}
	return result;
}

#
# ==================== Tool Execution ====================
#

# Call tool via /tool filesystem
calltool(tool, args: string): string
{
	path := "/tool/" + str->tolower(tool);

	# Open tool file
	fd := sys->open(path, Sys->ORDWR);
	if(fd == nil)
		return sys->sprint("error: tool not found: %s", tool);

	# Write arguments
	if(args != "") {
		data := array of byte args;
		n := sys->write(fd, data, len data);
		if(n < 0)
			return sys->sprint("error: write to %s failed: %r", tool);
	}

	# Seek back to start
	sys->seek(fd, big 0, Sys->SEEKSTART);

	# Read result
	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}

	return result;
}

# Write large result to scratch file
writescratch(content: string, step: int): string
{
	ensuredir(SCRATCH_PATH);
	path := sys->sprint("%s/step%d.txt", SCRATCH_PATH, step);

	fd := sys->create(path, Sys->OWRITE, 8r644);
	if(fd == nil)
		return "(cannot create scratch file)";

	data := array of byte content;
	sys->write(fd, data, len data);
	return path;
}

#
# ==================== Utilities ====================
#

# Read entire file contents
readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return "";

	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	return result;
}

# Check if path exists
pathexists(path: string): int
{
	(ok, nil) := sys->stat(path);
	return ok >= 0;
}

# Ensure directory exists (recursive)
ensuredir(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil)
		return;

	# Ensure parent
	for(i := len path - 1; i > 0; i--) {
		if(path[i] == '/') {
			ensuredir(path[0:i]);
			break;
		}
	}

	sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
}

# Strip leading/trailing whitespace
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

# Check if string contains substring
contains(s, sub: string): int
{
	if(len sub > len s)
		return 0;
	for(i := 0; i <= len s - len sub; i++) {
		match := 1;
		for(j := 0; j < len sub; j++) {
			if(s[i+j] != sub[j]) {
				match = 0;
				break;
			}
		}
		if(match)
			return 1;
	}
	return 0;
}

# Check string prefix
hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

# Split string at first whitespace
splitfirst(s: string): (string, string)
{
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t')
			return (s[0:i], s[i:]);
	}
	return (s, "");
}

# Truncate string with ellipsis
truncate(s: string, max: int): string
{
	if(len s <= max)
		return s;
	return s[0:max] + "...";
}

# Find heredoc marker << in string, returns position or -1
findheredoc(s: string): int
{
	for(i := 0; i < len s - 1; i++) {
		if(s[i] == '<' && s[i+1] == '<') {
			# Make sure it's not <<< (which would be different)
			if(i + 2 >= len s || s[i+2] != '<')
				return i;
		}
	}
	return -1;
}

#
# ==================== Native Tool_Use Protocol ====================
#
# These functions support the Anthropic tool_use JSON protocol via llm9p.
# Tool definitions are written to /n/llm/{id}/tools before the first Ask.
# Responses arrive as STOP:/TOOL: formatted text (parsed from structured JSON
# by llm9p). Results are submitted back via TOOL_RESULTS wire format.
#

# Return a short human-readable description for a known tool name.
tooldesc(name: string): string
{
	case name {
	"read"   => return "Read the contents of a file";
	"write"  => return "Write content to a file";
	"exec"   => return "Execute a command in Inferno sh";
	"grep"   => return "Search files for a regular expression pattern";
	"find"   => return "Find files by name or pattern";
	"git"    => return "Run a git command";
	"say"    => return "Speak text aloud via text-to-speech";
	"xenith"   => return "Issue a command to the Xenith text editor";
	"present"  => return "Manage the Lucifer presentation zone: create <id> [type=markdown|text|table|code] [label=text], write <id> <content>, center <id>, list, status";
	"spawn"    => return "Spawn a parallel subagent with its own namespace";
	"todo"   => return "Manage a persistent task list";
	"http"   => return "Make an HTTP request";
	"ls"     => return "List directory contents";
	"mkdir"  => return "Create a directory";
	"rm"     => return "Remove a file or directory";
	"cp"     => return "Copy a file";
	"mv"     => return "Move or rename a file";
	"cat"    => return "Print file contents";
	"python" => return "Execute a Python expression or script";
	"curl"   => return "Transfer data from a URL";
	}
	return "Run the " + name + " tool with the given arguments";
}

# Escape a string for inclusion inside a JSON string value.
# Handles: " → \", \ → \\, newline → \n, CR → \r, tab → \t
jsonstr(s: string): string
{
	result := "";
	for(i := 0; i < len s; i++) {
		case s[i] {
		'"'  => result += "\\\"";
		'\\' => result += "\\\\";
		'\n' => result += "\\n";
		'\r' => result += "\\r";
		'\t' => result += "\\t";
		*    => result += s[i:i+1];
		}
	}
	return result;
}

# Build a JSON array of tool definitions for the native tool_use protocol.
# Each tool uses a single string "args" parameter — compatible with /tool/*.
# Returns a JSON string suitable for writing to /n/llm/{id}/tools.
buildtooldefs(toollist: list of string): string
{
	schema := "{\"type\":\"object\",\"properties\":{\"args\":{\"type\":\"string\"}},\"required\":[\"args\"]}";
	parts := "";
	first := 1;
	for(t := toollist; t != nil; t = tl t) {
		name := jsonstr(hd t);
		desc := jsonstr(tooldesc(hd t));
		entry := "{\"name\":\"" + name + "\",\"description\":\"" + desc + "\",\"input_schema\":" + schema + "}";
		if(!first)
			parts += ",";
		parts += entry;
		first = 0;
	}
	return "[" + parts + "]";
}

# Install tool definitions on an LLM session by writing to /n/llm/{id}/tools.
# This enables the native tool_use protocol for subsequent Ask calls.
# No-op if toollist is nil (leaves session in text-only mode).
initsessiontools(id: string, toollist: list of string)
{
	if(toollist == nil)
		return;

	path := "/n/llm/" + id + "/tools";
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil) {
		if(verbose)
			sys->fprint(stderr, "agentlib: cannot open %s: %r\n", path);
		return;
	}

	defs := buildtooldefs(toollist);
	data := array of byte defs;
	n := sys->write(fd, data, len data);
	if(n != len data) {
		sys->fprint(stderr, "agentlib: initsessiontools: write %d/%d bytes: %r\n",
			n, len data);
	} else if(verbose) {
		sys->fprint(stderr, "agentlib: initsessiontools: installed %d tools\n",
			len toollist);
	}
}

# Unescape \\n → newline and \\\\ → backslash in TOOL: line args.
# llm9p escapes newlines in args so each TOOL: fits on one line.
unescapenl(s: string): string
{
	result := "";
	i := 0;
	while(i < len s) {
		if(s[i] == '\\' && i + 1 < len s) {
			case s[i+1] {
			'n'  => result += "\n"; i += 2;
			'\\' => result += "\\"; i += 2;
			*    => result += s[i:i+1]; i++;
			}
		} else {
			result += s[i:i+1];
			i++;
		}
	}
	return result;
}

# Parse a tool line component "id:name:args" into (id, name, args).
# The id and name are split at the first two colons; args occupies the rest.
# Newline escapes in args are resolved via unescapenl().
parsetoolline(s: string): (string, string, string)
{
	# Find first colon → end of id
	i := 0;
	while(i < len s && s[i] != ':')
		i++;
	if(i >= len s)
		return (s, "", "");
	id := s[0:i];

	# Find second colon → end of name
	rest := s[i+1:];
	j := 0;
	while(j < len rest && rest[j] != ':')
		j++;
	if(j >= len rest)
		return (id, rest, "");

	name := rest[0:j];
	args := unescapenl(rest[j+1:]);
	return (id, name, args);
}

# Parse an LLM response in STOP:/TOOL: format into its components.
# Returns (stop_reason, tool_calls, text_content) where:
#   stop_reason: "end_turn", "tool_use", or "" (plain text / no tools defined)
#   tool_calls:  list of (tool_use_id, name, args) — non-nil when stop_reason=="tool_use"
#   text_content: any assistant text accompanying the response
#
# Response format (from llm9p):
#   STOP:tool_use
#   TOOL:<id>:<name>:<args-with-\n-escaped>
#   [more TOOL: lines...]
#   [optional text]
#
#   STOP:end_turn
#   [text content]
#
#   (no STOP: prefix → plain text, backward-compatible)
parsellmresponse(response: string): (string, list of (string, string, string), string)
{
	if(!hasprefix(response, "STOP:"))
		return ("", nil, response);

	(nil, lines) := sys->tokenize(response, "\n");
	if(lines == nil)
		return ("", nil, "");

	# First line: STOP:<reason>
	stopreason := "";
	stopline := hd lines;
	lines = tl lines;
	if(hasprefix(stopline, "STOP:"))
		stopreason = stopline[5:];

	# Collect TOOL: lines followed by any text lines
	tools: list of (string, string, string);
	textparts: list of string;
	intext := 0;
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		if(!intext && hasprefix(line, "TOOL:")) {
			(id, name, args) := parsetoolline(line[5:]);
			tools = (id, name, args) :: tools;
		} else {
			intext = 1;
			textparts = line :: textparts;
		}
	}

	# Reverse tool list (was built by prepending)
	rtools: list of (string, string, string);
	for(tl2 := tools; tl2 != nil; tl2 = tl tl2)
		rtools = (hd tl2) :: rtools;

	# Reverse and join text lines
	text := "";
	rtextparts: list of string;
	for(tp := textparts; tp != nil; tp = tl tp)
		rtextparts = (hd tp) :: rtextparts;
	for(tp2 := rtextparts; tp2 != nil; tp2 = tl tp2) {
		if(text != "")
			text += "\n";
		text += hd tp2;
	}

	return (stopreason, rtools, strip(text));
}

# Build the TOOL_RESULTS wire format for submitting tool execution results.
# results: list of (tool_use_id, content) pairs.
# The returned string is written to /n/llm/{id}/ask to trigger AskWithToolResults.
buildtoolresults(results: list of (string, string)): string
{
	text := "TOOL_RESULTS\n";
	for(r := results; r != nil; r = tl r) {
		(id, content) := hd r;
		text += id + "\n" + content + "\n---\n";
	}
	return text;
}
