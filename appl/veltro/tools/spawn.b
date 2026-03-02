implement ToolSpawn;

#
# spawn - Create subagent(s) with secure namespace isolation for Veltro agent
#
# SYNTAX (v4 — parallel-capable, breaking change from v3):
# =========================================================
#   Spawn [timeout=N] -- tools=<t> paths=<p> [options] :: <task>
#                     -- tools=<t2> paths=<p2> :: <task2>
#
# Each -- section is one subagent (max 5). The :: separator is REQUIRED.
# Global options (timeout=N in seconds) go before the first --.
# Subagents run in parallel; results collected with per-subagent timeout.
# Note: task text must not contain ' -- ' (section separator).
#
# SECURITY MODEL (v4):
# ====================
# Same as v3 (FORKNS + bind-replace), extended for parallel children.
# Each child gets:
#   - Its OWN SubAgent module instance (prevents data-race on subagent globals)
#   - Its OWN LLM session (/n/llm/new clone pattern)
#   - Its OWN tools= and paths= (no sharing between parallel agents)
#   - Fresh NEWPGRP, FORKNS, NEWENV, NEWFD, NODEVS
# Tool modules are shared (read-only after init — no mutable global state).
#
# Child isolation steps (same as v3):
#   1. pctl(NEWPGRP)   - Empty srv registry
#   2. pctl(FORKNS)    - Fork parent's restricted namespace
#   3. pctl(NEWENV)    - Empty environment
#   4. Open LLM FDs    - While /n/llm still accessible
#   5. restrictns()    - Further bind-replace restrictions
#   6. verifysafefds() - Verify FDs 0-2 are safe
#   7. pctl(NEWFD)     - Prune all other FDs
#   8. pctl(NODEVS)    - Block #U/#p/#c
#   9. samod->runloop() - Execute task using dedicated SubAgent instance
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";
include "../nsconstruct.m";
	nsconstruct: NsConstruct;
include "../subagent.m";

ToolSpawn: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

# Per-subagent specification (parsed from args)
SubSpec: adt {
	tools:     list of string;
	paths:     list of string;
	shellcmds: list of string;
	llmconfig: ref NsConstruct->LLMConfig;
	task:      string;
};

# Wrapper so SubAgent module values can be stored in a list
SubAgentSlot: adt {
	mod: SubAgent;
};

# Pre-loaded tool modules.
# Shared across parallel children — safe because tool modules have no
# mutable globals after init().
PreloadedTool: adt {
	name: string;
	mod:  Tool;
};
preloadedtools: list of ref PreloadedTool;

# Result from a collector goroutine
ResultMsg: adt {
	idx:    int;
	result: string;
};

MAX_SUBAGENTS:      con 5;
DEFAULT_TIMEOUT_MS: con 300000;   # 5 minutes
RESULT_END:         con "\n<<EOF>>\n";

inited := 0;

init(): string
{
	if(inited)
		return nil;
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";
	nsconstruct = load NsConstruct NsConstruct->PATH;
	if(nsconstruct == nil)
		return "cannot load NsConstruct";
	nsconstruct->init();
	inited = 1;
	return nil;
}

name(): string
{
	return "spawn";
}

doc(): string
{
	return "Spawn - Create subagent(s) with secure namespace isolation\n\n" +
		"Usage:\n" +
		"  Spawn [timeout=N] -- tools=<t> paths=<p> [options] :: <task>\n" +
		"                    -- tools=<t2> paths=<p2> :: <task2>\n\n" +
		"Each -- section defines one subagent (max " + string MAX_SUBAGENTS + ").\n" +
		"The :: separator between spec and task is REQUIRED in every section.\n\n" +
		"Global options (before the first --):\n" +
		"  timeout=N     Seconds before each subagent is killed (default: 300)\n\n" +
		"Per-subagent options (in each -- section, before ::):\n" +
		"  tools=        Comma-separated tools to grant (REQUIRED)\n" +
		"  paths=        Comma-separated paths to expose\n" +
		"  shellcmds=    Comma-separated shell commands to allow\n" +
		"  model=        LLM model (default: haiku)\n" +
		"  temperature=  LLM temperature 0.0-2.0 (default: 0.7)\n" +
		"  thinking=     Thinking budget: off, max, or token count\n" +
		"  agenttype=    Load prompt from /lib/veltro/agents/<type>.txt\n" +
		"  system=       System prompt string (overrides agenttype)\n\n" +
		"Examples:\n" +
		"  Spawn -- tools=read,list paths=/appl :: List all .b files\n" +
		"  Spawn -- tools=read,list agenttype=explore paths=/appl :: Find handlers\n" +
		"  Spawn timeout=60\n" +
		"       -- tools=read paths=/appl :: Analyze structure\n" +
		"       -- tools=grep paths=/lib :: Search for patterns\n\n" +
		"Output:\n" +
		"  Single subagent: result returned directly.\n" +
		"  Multiple: === Subagent N: <task> === blocks, one per agent.\n\n" +
		"Security:\n" +
		"  Each subagent gets its own tools, paths, and LLM session.\n" +
		"  Each parallel child gets a fresh SubAgent instance (no data races).\n" +
		"  Environment is empty. Capability attenuation: child can only narrow.\n" +
		"  Task text must not contain ' -- ' (section separator).";
}

exec(args: string): string
{
	if(sys == nil)
		init();
	if(nsconstruct == nil)
		return "error: cannot load nsconstruct module";

	# Parse all subagent specs
	(specs, timeout_ms, perr) := parsespecs(strip(args));
	if(perr != "")
		return "error: " + perr;
	if(specs == nil)
		return "error: no subagent specs provided";

	# Count specs
	N := 0;
	{
		cntlist := specs;
		for(; cntlist != nil; cntlist = tl cntlist)
			N++;
	}

	# Pre-load one fresh SubAgent instance per spec, BEFORE any namespace
	# restriction or spawn.  subagent.b has module-level globals (loadedtools,
	# loadedtoolnames, llmaskfd) set in runloop().  If N parallel children
	# shared one SubAgent instance they would race on those globals.
	# Each `load SubAgent SubAgent->PATH` returns an independent instance
	# with its own globals.
	samods: list of ref SubAgentSlot;
	{
		sscnt := specs;
		for(; sscnt != nil; sscnt = tl sscnt) {
			sa := load SubAgent SubAgent->PATH;
			if(sa == nil)
				return sys->sprint("error: cannot load subagent: %r");
			saerr := sa->init();
			if(saerr != nil)
				return "error: cannot init subagent: " + saerr;
			samods = ref SubAgentSlot(sa) :: samods;
		}
	}
	samods = reversesamods(samods);

	# Pre-load tool modules (union of all specs' tool sets), BEFORE namespace
	# restriction.  Tools are stateless after init() — sharing is safe.
	toolerr := preloadmulti(specs);
	if(toolerr != "")
		return "error: " + toolerr;

	# Result channel: buffered N so collector goroutines never block.
	resultchan := chan[N] of ref ResultMsg;

	# Launch all subagents in parallel
	idx := 0;
	speclist := specs;
	salist := samods;
	while(speclist != nil) {
		spec := hd speclist;
		slot := hd salist;
		speclist = tl speclist;
		salist = tl salist;

		caps := ref NsConstruct->Capabilities(
			spec.tools,
			spec.paths,
			spec.shellcmds,
			spec.llmconfig,
			0 :: 1 :: 2 :: nil,
			nil,
			0,
			0
		);

		pipefds := array[2] of ref Sys->FD;
		if(sys->pipe(pipefds) < 0) {
			# Send error directly — channel is buffered, won't block
			resultchan <-= ref ResultMsg(idx, "ERROR:cannot create pipe");
			idx++;
			continue;
		}

		spawn runchild(pipefds[1], caps, spec.task, slot.mod);
		pipefds[1] = nil;
		spawn collectorwithTimeout(pipefds[0], resultchan, timeout_ms, idx);
		idx++;
	}

	# Collect all results (order via idx field, not arrival order)
	results := array[N] of string;
	for(i := 0; i < N; i++) {
		msg := <-resultchan;
		results[msg.idx] = msg.result;
	}

	# Format output
	if(N == 1) {
		r := results[0];
		if(hasprefix(r, "ERROR:"))
			return "error: " + r[6:];
		return r;
	}

	out := "";
	idx = 0;
	for(ss := specs; ss != nil; ss = tl ss) {
		spec := hd ss;
		if(out != "")
			out += "\n\n";
		r := results[idx];
		if(hasprefix(r, "ERROR:"))
			r = "error: " + r[6:];
		out += sys->sprint("=== Subagent %d: %s ===\n", idx+1, tasksummary(spec.task)) + r;
		idx++;
	}
	return out;
}

# Pre-load tool modules for the union of all specs' tool sets.
# Returns "" on success, error string on failure.
preloadmulti(specs: list of ref SubSpec): string
{
	# Collect union of tool names (deduplicated)
	seen: list of string;
	for(ss := specs; ss != nil; ss = tl ss) {
		spec := hd ss;
		for(t := spec.tools; t != nil; t = tl t) {
			nm := hd t;
			if(!inlist(nm, seen))
				seen = nm :: seen;
		}
	}

	preloadedtools = nil;
	for(s := seen; s != nil; s = tl s) {
		nm := hd s;
		path := "/dis/veltro/tools/" + nm + ".dis";
		mod := load Tool path;
		if(mod == nil)
			return sys->sprint("cannot load tool %s: %r", nm);
		merr := mod->init();
		if(merr != nil)
			return sys->sprint("cannot init tool %s: %s", nm, merr);
		preloadedtools = ref PreloadedTool(nm, mod) :: preloadedtools;
	}

	return "";
}

# Parse all subagent specs from the exec() args string.
#
# Syntax:  [timeout=N] -- spec1 :: task1 -- spec2 :: task2 ...
#   where spec = tools=<t> [paths=<p>] [model=M] ...
#
# Returns (specs, timeout_ms, error).  On error, specs is nil.
parsespecs(s: string): (list of ref SubSpec, int, string)
{
	timeout_ms := DEFAULT_TIMEOUT_MS;
	s = strip(s);

	if(s == "")
		return (nil, 0, "usage: Spawn [timeout=N] -- tools=<t> paths=<p> :: <task>");

	# Separate global options from subagent sections.
	# If s starts with "--", there are no global options.
	global := "";
	rest := "";
	if(len s >= 2 && s[0:2] == "--") {
		# Skip the leading "--" — rest is the first section's body
		rest = strip(s[2:]);
	} else {
		# Global options precede the first " -- "
		(global, rest) = spliton(s, " -- ");
		rest = strip(rest);
		global = strip(global);
	}

	# Parse global options (currently only timeout=N)
	if(global != "") {
		(nil, gtoks) := sys->tokenize(global, " \t");
		for(; gtoks != nil; gtoks = tl gtoks) {
			tok := hd gtoks;
			if(hasprefix(tok, "timeout=")) {
				t := int tok[8:];
				if(t > 0)
					timeout_ms = t * 1000;
			}
		}
	}

	if(rest == "")
		return (nil, 0, "usage: Spawn [timeout=N] -- tools=<t> paths=<p> :: <task>");

	# Split rest on " -- " to get individual section strings
	subparts := splitonall(rest, " -- ");

	if(listlen(subparts) > MAX_SUBAGENTS)
		return (nil, 0, sys->sprint("too many subagents (max %d)", MAX_SUBAGENTS));

	specs: list of ref SubSpec;
	for(; subparts != nil; subparts = tl subparts) {
		(spec, serr) := parsespecsection(strip(hd subparts));
		if(serr != "")
			return (nil, 0, serr);
		specs = spec :: specs;
	}

	specs = reversespecs(specs);
	return (specs, timeout_ms, "");
}

# Parse one section of the form "tools=<t> [opts...] :: <task>".
# Returns (spec, error).
parsespecsection(section: string): (ref SubSpec, string)
{
	if(section == "")
		return (nil, "empty section after --");

	# Split on " :: " to separate spec options from task text
	(specpart, taskpart) := spliton(section, " :: ");
	task := strip(taskpart);
	if(task == "")
		return (nil, "missing ' :: ' separator in section: \"" + section + "\"");

	spec := ref SubSpec;
	spec.task = task;

	llmmodel   := "haiku";
	llmtemp    := 0.7;
	llmsystem  := "";
	llmthink   := 0;
	agenttype  := "";

	(nil, tokens) := sys->tokenize(specpart, " \t");
	for(; tokens != nil; tokens = tl tokens) {
		tv := hd tokens;
		if(hasprefix(tv, "tools=")) {
			(nil, tlist) := sys->tokenize(tv[6:], ",");
			for(; tlist != nil; tlist = tl tlist)
				spec.tools = str->tolower(hd tlist) :: spec.tools;
			spec.tools = reverse(spec.tools);
		} else if(hasprefix(tv, "paths=")) {
			(nil, plist) := sys->tokenize(tv[6:], ",");
			for(; plist != nil; plist = tl plist)
				spec.paths = hd plist :: spec.paths;
			spec.paths = reverse(spec.paths);
		} else if(hasprefix(tv, "shellcmds=")) {
			(nil, clist) := sys->tokenize(tv[10:], ",");
			for(; clist != nil; clist = tl clist)
				spec.shellcmds = str->tolower(hd clist) :: spec.shellcmds;
			spec.shellcmds = reverse(spec.shellcmds);
		} else if(hasprefix(tv, "model=")) {
			llmmodel = str->tolower(tv[6:]);
		} else if(hasprefix(tv, "temperature=")) {
			llmtemp = real tv[12:];
			if(llmtemp < 0.0)
				llmtemp = 0.0;
			if(llmtemp > 2.0)
				llmtemp = 2.0;
		} else if(hasprefix(tv, "thinking=")) {
			thinkval := str->tolower(tv[9:]);
			if(thinkval == "off" || thinkval == "0")
				llmthink = 0;
			else if(thinkval == "max" || thinkval == "on")
				llmthink = -1;
			else {
				llmthink = int thinkval;
				if(llmthink < 0)
					llmthink = 0;
				if(llmthink > 30000)
					llmthink = 30000;
			}
		} else if(hasprefix(tv, "system=")) {
			llmsystem = stripquotes(tv[7:]);
		} else if(hasprefix(tv, "agenttype=")) {
			agenttype = str->tolower(tv[10:]);
		}
	}

	if(spec.tools == nil)
		return (nil, "tools= is required in each section");

	if(llmsystem == "" && agenttype != "")
		llmsystem = loadagentprompt(agenttype);
	if(llmsystem == "")
		llmsystem = loadagentprompt("default");

	spec.llmconfig = ref NsConstruct->LLMConfig(llmmodel, llmtemp, llmsystem, llmthink);
	return (spec, "");
}

# Collector goroutine: reads result from pipe with a per-subagent timeout.
# Sends a ResultMsg to resultchan when done (result or timeout error).
collectorwithTimeout(readfd: ref Sys->FD, resultchan: chan of ref ResultMsg, timeout_ms, idx: int)
{
	innerc := chan of string;
	spawn pipereader(readfd, innerc);
	timeoutc := chan of int;
	spawn timer(timeoutc, timeout_ms);
	result: string;
	alt {
	result = <-innerc =>
		;
	<-timeoutc =>
		result = sys->sprint("ERROR:subagent timed out after %ds", timeout_ms / 1000);
	}
	resultchan <-= ref ResultMsg(idx, result);
}

# Run one child agent with FORKNS + bind-replace namespace isolation.
# samod is a dedicated SubAgent instance — not shared with any other child.
runchild(pipefd: ref Sys->FD, caps: ref NsConstruct->Capabilities, task: string, samod: SubAgent)
{
	# Step 1: Fresh process group (empty service registry)
	sys->pctl(Sys->NEWPGRP, nil);

	# Step 2: Fork namespace (inherits already-restricted parent namespace)
	sys->pctl(Sys->FORKNS, nil);

	# Step 3: Empty environment (no inherited secrets)
	sys->pctl(Sys->NEWENV, nil);

	# Step 4: Create LLM session using /n/llm/new clone pattern.
	# Each child gets its own session — fully isolated from parent and siblings.
	llmaskfd: ref Sys->FD;
	if(caps.llmconfig != nil) {
		newfd := sys->open("/n/llm/new", Sys->OREAD);
		if(newfd != nil) {
			buf := array[32] of byte;
			n := sys->read(newfd, buf, len buf);
			newfd = nil;
			if(n > 0) {
				sessionid := string buf[0:n];
				if(len sessionid > 0 && sessionid[len sessionid - 1] == '\n')
					sessionid = sessionid[0:len sessionid - 1];
				if(sessionid != "") {
					# Configure model
					modelfd := sys->open("/n/llm/" + sessionid + "/model", Sys->OWRITE);
					if(modelfd != nil) {
						modeldata := array of byte caps.llmconfig.model;
						sys->write(modelfd, modeldata, len modeldata);
						modelfd = nil;
					}

					# Configure thinking
					thinkfd := sys->open("/n/llm/" + sessionid + "/thinking", Sys->OWRITE);
					if(thinkfd != nil) {
						thinkstr: string;
						if(caps.llmconfig.thinking == 0)
							thinkstr = "off";
						else if(caps.llmconfig.thinking < 0)
							thinkstr = "max";
						else
							thinkstr = string caps.llmconfig.thinking;
						thinkdata := array of byte thinkstr;
						sys->write(thinkfd, thinkdata, len thinkdata);
						thinkfd = nil;
					}

					# Configure system prompt
					if(caps.llmconfig.system != "") {
						sysfd := sys->open("/n/llm/" + sessionid + "/system", Sys->OWRITE);
						if(sysfd != nil) {
							sysdata := array of byte caps.llmconfig.system;
							sys->write(sysfd, sysdata, len sysdata);
							sysfd = nil;
						}
					}

					# Open ask fd (used by runloop)
					llmaskfd = sys->open("/n/llm/" + sessionid + "/ask", Sys->ORDWR);
				}
			}
		}
	}

	# Step 5: Apply namespace restrictions (FORKNS + bind-replace)
	err := nsconstruct->restrictns(caps);
	if(err != nil) {
		writeresult(pipefd, "ERROR:namespace restriction failed: " + err);
		return;
	}

	# Step 6: Verify FDs 0-2 are safe endpoints
	verifysafefds();

	# Step 7: Prune FDs — keep stdin, stdout, stderr, pipe, and LLM ask fd
	keepfds := 0 :: 1 :: 2 :: pipefd.fd :: nil;
	if(llmaskfd != nil)
		keepfds = llmaskfd.fd :: keepfds;
	sys->pctl(Sys->NEWFD, keepfds);

	# Step 8: Block device naming (after all bind operations)
	sys->pctl(Sys->NODEVS, nil);

	# Step 9: Build tool list for this child (filter preloadedtools to this spec)
	toolmods: list of Tool;
	toolnames: list of string;
	for(pt := preloadedtools; pt != nil; pt = tl pt) {
		if(inlist((hd pt).name, caps.tools)) {
			toolmods = (hd pt).mod :: toolmods;
			toolnames = (hd pt).name :: toolnames;
		}
	}

	systemprompt := "";
	if(caps.llmconfig != nil)
		systemprompt = caps.llmconfig.system;

	# Run the agent loop using the dedicated (non-shared) SubAgent instance
	result := samod->runloop(task, toolmods, toolnames, systemprompt, llmaskfd, 50);

	writeresult(pipefd, result);
	pipefd = nil;
}

# ---- Helper functions ----

# Verify FDs 0-2 are safe; redirect to /dev/null if missing.
verifysafefds()
{
	if(sys->fildes(0) == nil) {
		null := sys->open("/dev/null", Sys->OREAD);
		if(null != nil)
			sys->dup(null.fd, 0);
	}
	if(sys->fildes(1) == nil) {
		null := sys->open("/dev/null", Sys->OWRITE);
		if(null != nil)
			sys->dup(null.fd, 1);
	}
	if(sys->fildes(2) == nil) {
		null := sys->open("/dev/null", Sys->OWRITE);
		if(null != nil)
			sys->dup(null.fd, 2);
	}
}

# Write result string to pipe followed by the sentinel marker.
writeresult(fd: ref Sys->FD, result: string)
{
	data := array of byte (result + RESULT_END);
	sys->write(fd, data, len data);
}

# Read from pipe until sentinel or EOF; send complete result to resultch.
pipereader(fd: ref Sys->FD, resultch: chan of string)
{
	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
		if(len result >= len RESULT_END) {
			endpos := len result - len RESULT_END;
			if(result[endpos:] == RESULT_END) {
				result = result[0:endpos];
				break;
			}
		}
	}
	resultch <-= result;
}

# Timer goroutine: send on ch after ms milliseconds.
timer(ch: chan of int, ms: int)
{
	sys->sleep(ms);
	ch <-= 1;
}

# Load agent prompt from /lib/veltro/agents/<type>.txt.
loadagentprompt(agenttype: string): string
{
	fd := sys->open("/lib/veltro/agents/" + agenttype + ".txt", Sys->OREAD);
	if(fd == nil)
		return "";
	buf := array[4096] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "";
	return string buf[0:n];
}

# Split args string on all occurrences of sep; return ordered list of parts.
splitonall(s, sep: string): list of string
{
	parts: list of string;
	for(;;) {
		(before, after) := spliton(s, sep);
		parts = before :: parts;
		if(after == "")
			break;
		s = after;
	}
	return reverse(parts);
}

# Split s on the first occurrence of sep.
# Returns (before, after) where after excludes sep.
# Returns (s, "") if sep not found.
spliton(s, sep: string): (string, string)
{
	for(i := 0; i <= len s - len sep; i++) {
		if(s[i:i+len sep] == sep)
			return (s[0:i], s[i+len sep:]);
	}
	return (s, "");
}

# Strip leading and trailing whitespace.
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

# Return 1 if s has the given prefix, 0 otherwise.
hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

# Return 1 if needle is in the list, 0 otherwise.
inlist(needle: string, l: list of string): int
{
	for(; l != nil; l = tl l)
		if(hd l == needle)
			return 1;
	return 0;
}

# Reverse a list of strings.
reverse(l: list of string): list of string
{
	result: list of string;
	for(; l != nil; l = tl l)
		result = hd l :: result;
	return result;
}

# Reverse a list of SubSpecs.
reversespecs(l: list of ref SubSpec): list of ref SubSpec
{
	result: list of ref SubSpec;
	for(; l != nil; l = tl l)
		result = hd l :: result;
	return result;
}

# Reverse a list of SubAgentSlots.
reversesamods(l: list of ref SubAgentSlot): list of ref SubAgentSlot
{
	result: list of ref SubAgentSlot;
	for(; l != nil; l = tl l)
		result = hd l :: result;
	return result;
}

# Count the length of a list of strings.
listlen(l: list of string): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

# Return first N characters of task, truncated with "..." if longer.
tasksummary(task: string): string
{
	if(len task <= 50)
		return task;
	return task[0:47] + "...";
}

# Strip surrounding single or double quotes from a string.
stripquotes(s: string): string
{
	if(len s < 2)
		return s;
	if((s[0] == '"' && s[len s - 1] == '"') ||
	   (s[0] == '\'' && s[len s - 1] == '\''))
		return s[1:len s - 1];
	return s;
}
