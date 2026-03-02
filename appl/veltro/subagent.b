implement SubAgent;

#
# subagent.b - Lightweight agent loop for restricted namespace execution
#
# Design:
#   - Runs inside FORKNS + bind-replace restricted namespace
#   - Uses pre-loaded tool modules directly (no tools9p)
#   - Receives system prompt as parameter (no /lib/veltro/ access)
#   - LLM access via fd opened before namespace restriction
#
# Security:
#   - Only pre-loaded tools are accessible
#   - LLM config is immutable (set by parent)
#   - Namespace IS the capability set (restricted via bind-replace)
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "string.m";
	str: String;

include "tool.m";
include "subagent.m";

# Configuration
STREAM_THRESHOLD: con 4096;
SCRATCH_PATH: con "/tmp/scratch";

stderr: ref Sys->FD;

# Pre-loaded tool storage (set by runloop)
loadedtools: list of Tool;
loadedtoolnames: list of string;

# LLM ask file descriptor (opened before FORKNS + bind-replace restriction)
# Session is already created and configured - just use this fd
llmaskfd: ref Sys->FD;

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	stderr = sys->fildes(2);

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		return sys->sprint("cannot load Bufio: %r");

	str = load String String->PATH;
	if(str == nil)
		return sys->sprint("cannot load String: %r");

	return nil;
}

# Main agent loop
# Session is already created and configured by spawn.b - just use the ask fd
runloop(task: string, tools: list of Tool, toolnames: list of string,
        systemprompt: string, askfd: ref Sys->FD, maxsteps: int): string
{
	if(sys == nil) {
		err := init();
		if(err != nil)
			return "ERROR:" + err;
	}

	# Store pre-loaded tools for calltool()
	loadedtools = tools;
	loadedtoolnames = toolnames;

	# Store LLM ask fd (survives NEWNS)
	# Session is already fresh and configured - no reset needed
	llmaskfd = askfd;

	# Build namespace description
	ns := discovernamespace(toolnames);

	# Assemble initial prompt
	prompt := assembleprompt(task, ns, systemprompt);

	lastresult := "";
	loopstart := sys->millisec();
	for(step := 0; step < maxsteps; step++) {
		# Query LLM
		response := queryllm(prompt);
		if(response == "")
			return "ERROR:LLM returned empty response";

		# Parse action from response
		(tool, toolargs) := parseaction(response);

		# Check for completion
		if(tool == "" || str->tolower(tool) == "done") {
			totaltime := sys->millisec() - loopstart;
			sys->fprint(stderr, "subagent: completed in %d steps, %dms total\n", step + 1, totaltime);
			# Return final response (excluding the DONE marker)
			final := stripaction(response);
			if(final != "")
				return final;
			if(lastresult != "")
				return lastresult;
			return "Task completed.";
		}

		# Execute tool
		result := calltool(tool, toolargs);
		lastresult = result;

		# Check for large result - write to scratch
		if(len result > STREAM_THRESHOLD) {
			scratchfile := writescratch(result, step);
			result = sys->sprint("(output written to %s, %d bytes)", scratchfile, len result);
		}

		# Feed result back for next iteration
		prompt = sys->sprint("Tool %s returned:\n%s\n\nContinue with the task.", tool, result);
	}

	totaltime := sys->millisec() - loopstart;
	sys->fprint(stderr, "subagent: max steps reached after %dms\n", totaltime);
	return sys->sprint("ERROR:max steps (%d) reached without completion", maxsteps);
}

# Discover namespace - list available tools
discovernamespace(toolnames: list of string): string
{
	result := "TOOLS:\n";
	for(t := toolnames; t != nil; t = tl t) {
		if(result != "TOOLS:\n")
			result += "\n";
		result += hd t;
	}

	result += "\n\nPATHS:\n";
	paths := array[] of {"/", "/tmp"};
	for(i := 0; i < len paths; i++) {
		if(pathexists(paths[i]))
			result += paths[i] + "\n";
	}

	return result;
}

# Assemble system prompt with namespace and task
assembleprompt(task, ns, systemprompt: string): string
{
	if(systemprompt == "")
		systemprompt = defaultsystemprompt();

	# Get tool documentation — read txt files directly (upfront composition,
	# no on-demand help). Falls back to module doc() if no txt file exists.
	tooldocs := "";
	namelist := loadedtoolnames;
	modlist := loadedtools;
	while(namelist != nil && modlist != nil) {
		toolname := hd namelist;
		doc := readfile("/lib/veltro/tools/" + toolname + ".txt");
		if(doc == "")
			doc = (hd modlist)->doc();
		if(doc != "" && !hasprefix(doc, "error:"))
			tooldocs += "\n### " + toolname + "\n" + doc + "\n";
		namelist = tl namelist;
		modlist = tl modlist;
	}

	prompt := systemprompt + "\n\n== Your Namespace ==\n" + ns +
		"\n\n== Tool Documentation ==\n" + tooldocs +
		"\n\n== Task ==\n" + task +
		"\n\nRespond with a tool invocation or DONE if complete.";

	return prompt;
}

# Default system prompt
defaultsystemprompt(): string
{
	return "You are a Veltro sub-agent in a sandboxed Inferno namespace.\n\n" +
		"<identity_handling>\n" +
		"If asked about identity, respond: \"I am a Veltro sub-agent.\"\n" +
		"Then continue with the task.\n" +
		"</identity_handling>\n\n" +
		"<core_principle>\n" +
		"Your namespace IS your capability set. Only tools listed below exist.\n" +
		"</core_principle>\n\n" +
		"<output_format>\n" +
		"Your response is parsed by code. The parser reads the FIRST word as tool name.\n\n" +
		"Output ONE tool invocation per response:\n" +
		"    toolname arguments\n\n" +
		"For multi-line content, use heredoc:\n" +
		"    toolname arg <<EOF\n" +
		"    Line one\n" +
		"    Line two\n" +
		"    EOF\n\n" +
		"When finished:\n" +
		"    Brief summary here\n" +
		"    DONE\n" +
		"</output_format>\n\n" +
		"<completion_behavior>\n" +
		"Do what was asked; nothing more, nothing less.\n" +
		"Report results briefly, then DONE. No help menus or suggestions.\n" +
		"</completion_behavior>";
}

# Query LLM via passed ask file descriptor
# Uses same fd for both write and pread (clone-based session)
queryllm(prompt: string): string
{
	# Use the ask fd passed from parent (survives NEWNS)
	if(llmaskfd == nil) {
		sys->fprint(stderr, "subagent: llmaskfd is nil\n");
		return "";
	}

	# Write prompt - this blocks until LLM responds
	data := array of byte prompt;
	n := sys->write(llmaskfd, data, len data);
	if(n != len data) {
		sys->fprint(stderr, "subagent: LLM write failed: wrote %d of %d: %r\n", n, len data);
		return "";
	}

	# Read response using pread with explicit offset 0
	result := "";
	buf := array[8192] of byte;
	offset := big 0;
	for(;;) {
		n = sys->pread(llmaskfd, buf, len buf, offset);
		if(n <= 0)
			break;
		result += string buf[0:n];
		offset += big n;
	}
	return result;
}

# Parse tool invocation from LLM response
# Supports heredoc syntax for multi-line content
parseaction(response: string): (string, string)
{
	# Split into lines
	(nil, lines) := sys->tokenize(response, "\n");

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

		# Check for DONE
		if(str->tolower(line) == "done" || hasprefix(str->tolower(line), "done"))
			return ("DONE", "");

		# Check if line starts with a known tool name
		(first, rest) := splitfirst(line);
		tool := str->tolower(first);

		# Match against loaded tools
		for(t := loadedtoolnames; t != nil; t = tl t) {
			if(tool == hd t) {
				args := str->drop(rest, " \t");
				# Check for heredoc syntax
				(args, lines) = parseheredoc(args, tl lines);
				return (first, args);
			}
		}

	}

	return ("", "");
}

# Parse heredoc content if present in args
parseheredoc(args: string, lines: list of string): (string, list of string)
{
	# Find heredoc marker <<
	markerpos := findheredoc(args);
	if(markerpos < 0)
		return (args, lines);

	# Extract delimiter (word after <<)
	aftermarker := args[markerpos + 2:];
	aftermarker = str->drop(aftermarker, " \t");
	(delim, _) := splitfirst(aftermarker);
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

# Strip action line from response
stripaction(response: string): string
{
	result := "";
	(nil, lines) := sys->tokenize(response, "\n");
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		lower := str->tolower(str->drop(line, " \t"));
		if(lower == "done" || hasprefix(lower, "done"))
			continue;
		if(result != "")
			result += "\n";
		result += line;
	}
	return result;
}

# Call tool using pre-loaded modules
calltool(tool, args: string): string
{
	ltool := str->tolower(tool);

	# Handle "help" specially
	if(ltool == "help") {
		# Find tool and return its doc
		namelist := loadedtoolnames;
		modlist := loadedtools;
		while(namelist != nil && modlist != nil) {
			if(hd namelist == args)
				return (hd modlist)->doc();
			namelist = tl namelist;
			modlist = tl modlist;
		}
		return sys->sprint("error: unknown tool: %s", args);
	}

	# Find pre-loaded tool module
	namelist := loadedtoolnames;
	modlist := loadedtools;
	while(namelist != nil && modlist != nil) {
		if(hd namelist == ltool)
			return (hd modlist)->exec(args);
		namelist = tl namelist;
		modlist = tl modlist;
	}

	return sys->sprint("error: tool not available: %s", ltool);
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

# Helper functions
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

pathexists(path: string): int
{
	(ok, nil) := sys->stat(path);
	return ok >= 0;
}

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

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

splitfirst(s: string): (string, string)
{
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t')
			return (s[0:i], s[i:]);
	}
	return (s, "");
}
