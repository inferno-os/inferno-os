implement ToolExec;

#
# exec - Execute shell command tool for Veltro agent
#
# Runs a shell command and returns output.
# Commands are executed via Inferno's sh(1).
#
# IMPORTANT: Inferno shell syntax differs from POSIX/bash:
#   - Use SINGLE quotes for strings: echo 'hello world'
#   - Double quotes do NOT work like bash
#   - Use {braces} for command grouping, not (parens)
#   - Use ; to separate commands (no && or ||)
#   - Semicolon needs space before it: cmd ; cmd2
#
# Usage:
#   Exec <command>
#
# Examples:
#   Exec cat /dev/sysname
#   Exec ls /appl
#   Exec echo 'hello world'
#   Exec wc -l /appl/cmd/cat.b
#
# Note: Double-quoted strings are auto-converted to single quotes.
# Security note: Commands run with agent's namespace/capabilities.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "sh.m";
	sh: Sh;

include "../tool.m";

ToolExec: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

# Limits
DEFAULT_TIMEOUT: con 5000;   # 5 seconds
MAX_TIMEOUT: con 30000;      # 30 seconds
MAX_OUTPUT: con 16384;       # 16KB max output

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	sh = load Sh Sh->PATH;
	if(sh == nil)
		return "cannot load shell module (sh.dis not accessible)";
	return nil;
}

name(): string
{
	return "exec";
}

doc(): string
{
	return "Exec - Execute shell command\n\n" +
		"Usage:\n" +
		"  Exec <command>\n\n" +
		"IMPORTANT: Inferno shell syntax differs from POSIX/bash:\n" +
		"  - Use SINGLE quotes for strings: echo 'hello world'\n" +
		"  - Double quotes are auto-converted to single quotes\n" +
		"  - Use ; to separate commands (no && or ||)\n\n" +
		"Examples:\n" +
		"  Exec cat /dev/sysname\n" +
		"  Exec ls /appl\n" +
		"  Exec echo 'hello world'\n" +
		"  Exec wc -l /appl/cmd/cat.b\n\n" +
		"Returns command output, or error message.\n" +
		"Default timeout: 5 seconds (max 30s).";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	if(sh == nil)
		return "error: cannot load shell module";

	# Parse command
	cmd := args;

	# Strip leading/trailing whitespace
	while(len cmd > 0 && (cmd[0] == ' ' || cmd[0] == '\t'))
		cmd = cmd[1:];
	while(len cmd > 0 && (cmd[len cmd - 1] == ' ' || cmd[len cmd - 1] == '\t' || cmd[len cmd - 1] == '\n'))
		cmd = cmd[0:len cmd - 1];

	# Handle quoted command (strip outer quotes if present)
	if(len cmd >= 2) {
		if((cmd[0] == '"' && cmd[len cmd - 1] == '"') ||
		   (cmd[0] == '\'' && cmd[len cmd - 1] == '\''))
			cmd = cmd[1:len cmd - 1];
	}

	if(cmd == "")
		return "error: usage: Exec <command>";

	# Convert double quotes to single quotes for Inferno shell compatibility
	# Inferno's sh uses single quotes for literal strings, not double quotes
	cmd = convertquotes(cmd);

	# Create pipe for capturing output
	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0)
		return sys->sprint("error: cannot create pipe: %r");

	# Spawn command execution
	result := chan of string;
	spawn runcommand(cmd, fds[1], result);
	fds[1] = nil;

	# Read output with timeout
	output := "";
	done := 0;

	timeout := chan of int;
	spawn timer(timeout, DEFAULT_TIMEOUT);

	reader := chan of string;
	spawn readoutput(fds[0], reader);

	while(!done) {
		alt {
		s := <-reader =>
			if(s == nil) {
				done = 1;
			} else {
				output += s;
				if(len output > MAX_OUTPUT) {
					output = output[0:MAX_OUTPUT] + "\n... (output truncated)";
					done = 1;
				}
			}
		<-timeout =>
			output += "\n... (timeout after 5 seconds)";
			done = 1;
		}
	}

	# Wait for result
	err := "";
	alt {
	e := <-result =>
		err = e;
	* =>
		;  # Already done
	}

	if(output == "" && err != "")
		return "error: " + err;

	if(err != "")
		output += "\n(exit: " + err + ")";

	if(output == "")
		return "(no output)";

	return output;
}

# Run command in separate thread
runcommand(cmd: string, outfd: ref Sys->FD, result: chan of string)
{
	# Redirect stdout/stderr to pipe
	sys->dup(outfd.fd, 1);
	sys->dup(outfd.fd, 2);
	outfd = nil;

	err := sh->system(nil, cmd);
	result <-= err;
}

# Timer thread
timer(ch: chan of int, ms: int)
{
	sys->sleep(ms);
	ch <-= 1;
}

# Read output from fd
readoutput(fd: ref Sys->FD, ch: chan of string)
{
	buf := array[4096] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0) {
			ch <-= nil;
			return;
		}
		ch <-= string buf[0:n];
	}
}

# Convert double quotes to single quotes for Inferno shell compatibility
# Handles: echo "hello world" -> echo 'hello world'
# Also handles escaped quotes and nested cases
convertquotes(s: string): string
{
	result := "";
	i := 0;

	while(i < len s) {
		if(s[i] == '"') {
			# Found double quote - convert to single quote
			# But first check if it's escaped
			if(i > 0 && s[i-1] == '\\') {
				# Escaped quote - keep as literal (remove backslash, keep quote)
				result = result[0:len result - 1] + "'";
				i++;
				continue;
			}

			# Start of double-quoted string - find matching close
			result[len result] = '\'';
			i++;

			# Copy contents until closing double quote
			while(i < len s && s[i] != '"') {
				# Handle single quotes inside - they need escaping in sh
				if(s[i] == '\'') {
					# End single quote, add escaped quote, restart single quote
					result += "'\\''";
				} else {
					result[len result] = s[i];
				}
				i++;
			}

			# Add closing single quote
			if(i < len s && s[i] == '"') {
				result[len result] = '\'';
				i++;
			}
		} else {
			result[len result] = s[i];
			i++;
		}
	}

	return result;
}
