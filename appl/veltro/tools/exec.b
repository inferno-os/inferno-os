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
	# sh.dis may not be visible at init() time if tools9p's namespace
	# restriction hasn't yet bound sh.dis (exec not in the caps.tools
	# passed to restrictns, or called before restriction applies).
	# exec() will retry the load lazily when actually invoked.
	return nil;
}

name(): string
{
	return "exec";
}

doc(): string
{
	return "Exec - Run a program in the Inferno namespace\n\n" +
		"For GUI/WM programs, Exec launches them in the presentation zone\n" +
		"automatically. All three forms work (no wm/wm wrapper, no & suffix):\n" +
		"  Exec wm/clock            (short name)\n" +
		"  Exec /dis/wm/clock       (absolute path, .dis optional)\n" +
		"  Exec /dis/wm/clock.dis   (full path)\n\n" +
		"Available draw-based GUI apps (these work):\n" +
		"  clock, bounce, coffee, colors, date, view, rt, lens\n\n" +
		"IMPORTANT GUI launch rules:\n" +
		"  - Do NOT wrap with 'wm/wm' (wrong: 'exec wm/wm wm/clock')\n" +
		"  - Do NOT add '&' — background launch is handled automatically\n\n" +
		"Apps that do NOT work (require Tk, which is not available):\n" +
		"  task, edit, about, tetris, sh, ftree — do not attempt these\n\n" +
		"For non-GUI programs:\n" +
		"  Exec /dis/bind.dis -a /mnt/foo /n/bar\n" +
		"  Exec /dis/veltro/tools/someprogram.dis args\n\n" +
		"The namespace is restricted: standard Unix commands (echo, cat, ls)\n" +
		"are NOT available. Use the dedicated tools instead:\n" +
		"  read/write/edit  - file I/O\n" +
		"  list             - directory listing\n" +
		"  find/search/grep - search\n\n" +
		"IMPORTANT: Inferno shell syntax, not POSIX:\n" +
		"  - No &&, ||; use ; to sequence\n" +
		"  - Single quotes for strings\n\n" +
		"Returns program output (CLI), or 'launched ... in presentation zone' (GUI).\n" +
		"Default timeout: 5 seconds (max 30s).";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	if(sh == nil) {
		sh = load Sh Sh->PATH;
		if(sh == nil)
			return "error: cannot load shell module (exec requires sh.dis; pass 'exec' to tools9p)";
	}

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

	# Strip trailing & — model sometimes appends it for "background" but
	# exec handles GUI launch asynchronously; & breaks firstword detection
	while(len cmd > 0 && cmd[len cmd - 1] == '&')
		cmd = cmd[0:len cmd - 1];
	while(len cmd > 0 && (cmd[len cmd - 1] == ' ' || cmd[len cmd - 1] == '\t'))
		cmd = cmd[0:len cmd - 1];

	if(cmd == "")
		return "error: usage: Exec <command>";

	# Convert double quotes to single quotes for Inferno shell compatibility
	# Inferno's sh uses single quotes for literal strings, not double quotes
	cmd = convertquotes(cmd);

	# For GUI programs in /dis/wm/, route to the presentation zone.
	# Detects /dis/wm/ programs three ways:
	#   1. Full .dis path:  exec /dis/wm/clock.dis
	#   2. Absolute no-ext: exec /dis/wm/clock    → tries /dis/wm/clock.dis
	#   3. Short name:      exec wm/clock          → tries /dis/wm/clock.dis
	# Only /dis/wm/* programs are routed to pres zone; CLI tools fall through.
	if(len cmd > 0) {
		firstword := cmd;
		for(i := 0; i < len firstword; i++) {
			if(firstword[i] == ' ' || firstword[i] == '\t') {
				firstword = firstword[0:i];
				break;
			}
		}
		dispath := "";
		if(len firstword > 4 && firstword[len firstword - 4:] == ".dis") {
			# Already has .dis extension
			dispath = firstword;
		} else if(len firstword > 0 && firstword[0] == '/') {
			# Absolute path without .dis extension — try appending .dis
			trypath := firstword + ".dis";
			(pok, nil) := sys->stat(trypath);
			if(pok >= 0)
				dispath = trypath;
		} else {
			# Short/relative name — try /dis/<firstword>.dis
			trypath := "/dis/" + firstword + ".dis";
			(pok, nil) := sys->stat(trypath);
			if(pok >= 0)
				dispath = trypath;
		}
		# Xenith is a full-environment GUI app; exec cannot target the
		# presentation zone for it and it would try to take over the display.
		# Force the agent to use the 'launch' tool instead.
		if(dispath != "" && len dispath >= 10 &&
		   dispath[len dispath - 10:] == "xenith.dis") {
			return "error: use 'launch xenith' — exec cannot target the presentation zone for xenith";
		}
		# Only route /dis/wm/* apps to presentation zone (wmclient apps)
		if(len dispath > 8 && dispath[0:8] == "/dis/wm/") {
			# Try /n/pres-launch (file2chan, if lucifer exported it).
			# Fall back to /tmp/veltro/pres-launch which lucifer polls every 200ms.
			pfd := sys->open("/n/pres-launch", Sys->OWRITE);
			if(pfd == nil)
				pfd = sys->create("/tmp/veltro/pres-launch", Sys->OWRITE, 8r644);
			if(pfd != nil) {
				data := array of byte dispath;
				sys->write(pfd, data, len data);
				pfd = nil;
				return "launched " + dispath + " in presentation zone";
			}
		}
	}

	# Create pipe for capturing output
	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0)
		return sys->sprint("error: cannot create pipe: %r");

	# Spawn command execution
	# Buffered capacity 1: goroutines can complete their send and exit
	# even after the alt has moved on, preventing indefinite blocking.
	result := chan[1] of string;
	spawn runcommand(cmd, fds[1], result);
	fds[1] = nil;

	# Read output with timeout
	output := "";
	done := 0;

	timeout := chan[1] of int;
	spawn timer(timeout, DEFAULT_TIMEOUT);

	reader := chan[1] of string;
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
