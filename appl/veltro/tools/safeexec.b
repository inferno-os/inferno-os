implement ToolSafeExec;

#
# safeexec - Safe execution tool for Veltro agents without shell access
#
# This tool runs whitelisted .dis files directly without shell interpretation.
# Unlike the exec tool which uses the shell, safeexec:
#
# 1. Parses the tool name and arguments directly
# 2. Loads the .dis module from /dis/veltro/tools/
# 3. Calls the tool's exec function with arguments
#
# This prevents shell metacharacter injection attacks:
#   exec("cat /etc/passwd; rm -rf /")  <- shell interprets ; as command separator
#   safeexec("cat /etc/passwd; rm -rf /")  <- "cat" is the tool, rest is args
#
# For agents without shellcmds, spawn.b uses safeexec instead of exec.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolSafeExec: module {
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

# Whitelist of allowed tools (tools that exist in /dis/veltro/tools/)
# This is populated dynamically by reading /tool/tools
allowedtools: list of string;

init()
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
}

name(): string
{
	return "safeexec";
}

doc(): string
{
	return "SafeExec - Execute tools without shell interpretation\n\n" +
		"Usage:\n" +
		"  SafeExec <tool> [args...]\n\n" +
		"Arguments:\n" +
		"  tool - Name of the tool to execute (must be in /dis/veltro/tools/)\n" +
		"  args - Arguments to pass to the tool\n\n" +
		"Examples:\n" +
		"  SafeExec read /appl/veltro/veltro.b\n" +
		"  SafeExec list /appl\n" +
		"  SafeExec search pattern /appl\n\n" +
		"Security:\n" +
		"  - No shell interpretation (prevents injection attacks)\n" +
		"  - Only tools in /dis/veltro/tools/ can be executed\n" +
		"  - Tool name parsed directly from first argument\n";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	# Strip leading/trailing whitespace
	args = strip(args);
	if(args == "")
		return "error: no tool specified";

	# Parse first word as tool name
	(toolname, toolargs) := splitfirst(args);
	if(toolname == "")
		return "error: no tool specified";

	# Normalize tool name to lowercase
	ltool := str->tolower(toolname);

	# Security: Validate tool name has no path components
	# This prevents attacks like "../../malicious"
	for(i := 0; i < len ltool; i++) {
		c := ltool[i];
		if(c == '/' || c == '\\' || c == '.')
			return sys->sprint("error: invalid tool name: %s", toolname);
	}

	# Load tool directly from whitelist location
	toolpath := "/dis/veltro/tools/" + ltool + ".dis";

	# Verify tool exists before loading
	(ok, nil) := sys->stat(toolpath);
	if(ok < 0)
		return sys->sprint("error: tool not found: %s", toolname);

	# Load the tool module
	tool := load Tool toolpath;
	if(tool == nil)
		return sys->sprint("error: cannot load tool %s: %r", toolname);

	# Execute with arguments
	return tool->exec(toolargs);
}

# Strip leading/trailing whitespace
strip(s: string): string
{
	if(s == nil)
		return "";
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

# Split on first whitespace
splitfirst(s: string): (string, string)
{
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t')
			return (s[0:i], strip(s[i:]));
	}
	return (s, "");
}
