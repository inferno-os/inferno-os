implement LuciBridge;

#
# lucibridge - Connects Lucifer UI to Veltro agent via /n/llm
#
# Reads human messages from /n/ui/activity/{id}/conversation/input
# (blocking read), runs the Veltro agent loop (LLM + tools), and writes
# responses and tool activity back to the UI as role=veltro messages.
#
# Usage: lucibridge [-v] [-n maxsteps] [-a actid] [-t tools] [-p paths]
#   -v            verbose logging
#   -n steps      max agent steps per turn (default: 20)
#   -a id         activity ID (default: 0)
#   -t tools      comma-separated initial tool list (e.g. read,list,write)
#   -p paths      comma-separated namespace paths to expose via /n/local/
#
# Prerequisites:
#   - luciuisrv running (serves /n/ui/)
#   - LLM service mounted at /n/llm/
#   - tools9p running (serves /tool/) — optional but enables tool use
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "arg.m";
	arg: Arg;

include "agentlib.m";
	agentlib: AgentLib;

LuciBridge: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

DEFAULT_MAX_STEPS: con 20;
MAX_MAX_STEPS: con 100;

verbose := 0;
autospeak := 0;
maxsteps := DEFAULT_MAX_STEPS;
stderr: ref Sys->FD;

# LLM session state
sessionid := "";
llmfd: ref Sys->FD;

# Activity state
actid := 0;
convcount := 0;		# messages written to conversation by this bridge
userinteracted := 0;	# set after user sends a message (suppresses urgency)

# Tool tracking: raw string from /tool/tools; updated when tool set changes
currenttoolsraw := "";
toolmount := "/tool";	# "/tool" for activity 0, "/tool.N" for child N

# Path tracking: raw string from /tool/paths; updated when path set changes
currentpathsraw := "";

# CLI overrides from -t/-p flags
toolargs: list of string;	# from -t flag (comma-separated tool names)
pathargs: list of string;	# from -p flag (comma-separated paths)

BRIDGE_SUFFIX: con "\n\nYou are the AI assistant in a Lucifer activity. " +
	"The user sends messages through the UI. " +
	"Respond naturally with text for conversational messages, greetings, and answers. " +
	"Use tools only when the user asks you to perform a specific task.";

META_PROMPT_PATH: con "/lib/veltro/meta.txt";

log(msg: string)
{
	if(verbose)
		sys->fprint(stderr, "lucibridge: %s\n", msg);
}

fatal(msg: string)
{
	sys->fprint(stderr, "lucibridge: %s\n", msg);
	raise "fail:" + msg;
}

writefile(path, data: string): int
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return -1;
	b := array of byte data;
	return sys->write(fd, b, len b);
}

# Extract value for key from "key1=val1 key2=val2 ..." string
getkv(line, key: string): string
{
	target := key + "=";
	tlen := len target;
	i := 0;
	while(i <= len line - tlen) {
		if(line[i:i+tlen] == target) {
			# Found key= at position i
			start := i + tlen;
			end := start;
			while(end < len line && line[end] != ' ' && line[end] != '\t')
				end++;
			return line[start:end];
		}
		# Skip to next whitespace-separated token
		while(i < len line && line[i] != ' ' && line[i] != '\t')
			i++;
		while(i < len line && (line[i] == ' ' || line[i] == '\t'))
			i++;
	}
	return "";
}

# Read a field from a simple key=value config file (one per line)
readndbfield(path, field: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[4096] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	content := string buf[0:n];
	prefix := field + "=";
	plen := len prefix;
	for(i := 0; i < len content; ) {
		# Find end of line
		eol := i;
		while(eol < len content && content[eol] != '\n')
			eol++;
		if(eol - i >= plen && content[i:i+plen] == prefix)
			return content[i+plen:eol];
		i = eol + 1;
	}
	return nil;
}

# Register namespace entries from the manifest written by tools9p.
# The manifest reflects the agent's actual restricted namespace — it is
# the single source of truth.  No hardcoded path lists.
registernamespace()
{
	# Read the manifest written by tools9p — it reflects the agent's
	# actual restricted namespace.  This is the single source of truth;
	# no hardcoded path lists.
	mpath: string;
	if(actid == 0)
		mpath = "/tmp/veltro/.ns/manifest";
	else
		mpath = "/tmp/veltro/.ns/manifest." + string actid;

	ctxpath := sys->sprint("/n/ui/activity/%d/context/ctl", actid);
	nreg := 0;

	mdata := agentlib->readfile(mpath);
	if(mdata != "") {
		# Manifest format: path=X label=Y perm=Z (one per line)
		(nil, lines) := sys->tokenize(mdata, "\n");
		for(; lines != nil; lines = tl lines) {
			line := agentlib->strip(hd lines);
			if(line == "")
				continue;
			# Parse key=value pairs from manifest line
			path := getkv(line, "path");
			label := getkv(line, "label");
			perm := getkv(line, "perm");
			if(path == "")
				continue;
			if(label == "")
				label = path;
			# Classify: /n/* and /dev/* are services/devices, rest are fs
			atype := "fs";
			if(len path > 3 && path[0:3] == "/n/")
				atype = "service";
			else if(len path > 5 && path[0:5] == "/dev/")
				atype = "device";
			cmd := "resource add path=" + path +
				" label=" + label +
				" type=" + atype +
				" status=idle";
			if(perm != "")
				cmd += " via=" + perm;
			if(writefile(ctxpath, cmd) >= 0)
				nreg++;
		}
	} else {
		log("context: manifest not found at " + mpath);
	}

	# Also register speech if available but not already in manifest
	hasspeech := 0;
	if(mdata != "") {
		(nil, sl) := sys->tokenize(mdata, "\n");
		for(; sl != nil; sl = tl sl)
			if(agentlib->hasprefix(hd sl, "path=/n/speech"))
				hasspeech = 1;
	}
	if(!hasspeech) {
		(speechok, nil) := sys->stat("/n/speech");
		if(speechok >= 0) {
			cmd := "resource add path=/n/speech label=Speech type=service status=idle";
			if(writefile(ctxpath, cmd) >= 0)
				nreg++;
		}
	}

	log(sys->sprint("context: registered %d namespace entries", nreg));
}

# Speak text via speech9p (fire-and-forget, runs in spawned goroutine)
speaktext(text: string)
{
	# Update context zone status
	ctxpath := sys->sprint("/n/ui/activity/%d/context/ctl", actid);
	writefile(ctxpath, "resource update path=speech status=active");

	fd := sys->open("/n/speech/say", Sys->OWRITE);
	if(fd == nil) {
		log("speaktext: cannot open /n/speech/say");
		writefile(ctxpath, "resource update path=speech status=idle");
		return;
	}
	b := array of byte text;
	sys->write(fd, b, len b);

	writefile(ctxpath, "resource update path=speech status=idle");
}

# Read from a blocking fd, strip trailing newline
blockread(fd: ref Sys->FD): string
{
	buf := array[65536] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	s := string buf[0:n];
	if(len s > 0 && s[len s - 1] == '\n')
		s = s[0:len s - 1];
	return s;
}

# Write a message to the activity conversation
writemsg(role, text: string)
{
	path := sys->sprint("/n/ui/activity/%d/conversation/ctl", actid);
	msg := "role=" + role + " text=" + text;
	if(writefile(path, msg) < 0)
		sys->fprint(stderr, "lucibridge: write to %s failed: %r\n", path);
	else
		convcount++;
}

# Set activity status
setstatus(status: string)
{
	path := sys->sprint("/n/ui/activity/%d/status", actid);
	writefile(path, status);
}

seturgency(level: int)
{
	path := sys->sprint("/n/ui/activity/%d/urgency", actid);
	writefile(path, string level);
}

# Create LLM session with system prompt
initsession(): string
{
	log("initsession: creating LLM session");
	sessionid = agentlib->createsession();
	if(sessionid == "")
		return "cannot create LLM session";
	log("initsession: session " + sessionid);

	# Build system prompt from namespace discovery
	ns := agentlib->discovernamespace();
	log("initsession: namespace discovered");
	sysprompt := agentlib->buildsystemprompt(ns);
	log(sys->sprint("initsession: system prompt %d bytes", len array of byte sysprompt));

	# Append bridge/meta suffix, truncating base if needed
	suffix := BRIDGE_SUFFIX;
	if(actid == 0) {
		meta := agentlib->readfile(META_PROMPT_PATH);
		if(meta != nil)
			suffix = "\n\n" + agentlib->strip(meta);
	}
	MAXWRITE: con 65000;
	suffixbytes := array of byte suffix;
	basebytes := array of byte sysprompt;
	if(len basebytes + len suffixbytes > MAXWRITE) {
		room := MAXWRITE - len suffixbytes;
		if(room < 0)
			room = 0;
		# Walk back to a valid UTF-8 character boundary to avoid
		# cutting a multi-byte sequence in half.
		while(room > 0) {
			b := int basebytes[room - 1];
			if(b < 16r80)
				break;			# ASCII byte -- safe boundary
			if((b & 16rC0) != 16r80) {
				room--;			# lead byte of incomplete char -- skip it
				break;
			}
			room--;				# continuation byte -- keep backing up
		}
		sysprompt = string basebytes[0:room];
	}
	sysprompt += suffix;

	# Open ask fd first so the session stays alive (refs >= 1) while we write
	# system and tools.  Without this, Limbo's GC finalizes each setup fd
	# concurrently and can drop refs to 0 between writes, deleting the session.
	askpath := "/n/llm/" + sessionid + "/ask";
	llmfd = sys->open(askpath, Sys->ORDWR);
	if(llmfd == nil)
		return sys->sprint("cannot open %s: %r", askpath);

	systempath := "/n/llm/" + sessionid + "/system";
	agentlib->setsystemprompt(systempath, sysprompt);

	# Install tool definitions for native tool_use protocol.
	# "say" is intentionally excluded: Claude responds with end_turn text directly,
	# avoiding the tool-call→acknowledgement loop that produces spurious "..." replies.
	# Tools come from /tool/tools if available (task tools only).
	toollist: list of string;
	if(agentlib->pathexists(toolmount)) {
		tools := agentlib->readfile(toolmount + "/tools");
		(nil, tls) := sys->tokenize(tools, "\n");
		for(t := tls; t != nil; t = tl t) {
			nm := str->tolower(hd t);
			if(nm != "say")
				toollist = hd t :: toollist;
		}
	}
	agentlib->initsessiontools(sessionid, toollist);
	if(agentlib->pathexists(toolmount))
		currenttoolsraw = agentlib->readfile(toolmount + "/tools");

	# Bind any paths already registered in /tool/paths (e.g. from -p flag)
	currentpathsraw = "";
	applypathchanges();

	# Register each available tool as a context resource so the context zone
	# can display and track which tools the agent is using.
	nreg := 0;
	for(t := toollist; t != nil; t = tl t) {
		nm := str->tolower(hd t);
		r := writefile(sys->sprint("/n/ui/activity/%d/context/ctl", actid),
			"resource add path=" + nm + " label=" + hd t + " type=tool status=idle");
		if(r >= 0)
			nreg++;
	}
	log(sys->sprint("context: registered %d tools as resources", nreg));

	# Register speech resource if speech9p is available
	if(autospeak) {
		ctxpath := sys->sprint("/n/ui/activity/%d/context/ctl", actid);
		writefile(ctxpath, "resource add path=speech label=Speech type=tool status=idle");
		log("context: registered speech resource");
	}

	# Register namespace entries (services, devices, filesystems) as resources
	registernamespace();

	log(sys->sprint("session %s, prompt %d bytes", sessionid, len array of byte sysprompt));
	return nil;
}

# Strip prefill, "say", and "DONE" from LLM responses.
# Used in chat-only mode where parseaction can't read /tool/tools.
cleanresponse(response: string): string
{
	(nil, lines) := sys->tokenize(response, "\n");
	result := "";
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		# Strip leading whitespace
		for(i := 0; i < len line; i++)
			if(line[i] != ' ' && line[i] != '\t')
				break;
		if(i < len line)
			line = line[i:];
		else
			line = "";
		if(line == "")
			continue;
		# Strip [Veltro] prefix
		if(agentlib->hasprefix(line, "[Veltro]"))
			line = agentlib->strip(line[8:]);
		if(line == "")
			continue;
		# Strip "say " prefix
		lower := str->tolower(line);
		if(agentlib->hasprefix(lower, "say "))
			line = agentlib->strip(line[4:]);
		# Skip DONE lines
		stripped := str->tolower(agentlib->strip(line));
		if(stripped == "done")
			continue;
		if(result != "")
			result += "\n";
		result += line;
	}
	if(result == "")
		result = agentlib->strip(response);
	return result;
}

# Extract say text and DONE from LLM response.
# Returns (text, done): text is nil if no say found.
extractsay(response: string): (string, int)
{
	(nil, lines) := sys->tokenize(response, "\n");
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		line = agentlib->strip(line);
		if(line == "")
			continue;
		if(agentlib->hasprefix(line, "[Veltro]"))
			line = agentlib->strip(line[8:]);
		if(line == "")
			continue;
		lower := str->tolower(line);
		stripped := str->tolower(agentlib->strip(line));
		if(stripped == "done")
			return (nil, 1);
		if(agentlib->hasprefix(lower, "say ")) {
			# Collect all remaining lines as say text
			text := agentlib->strip(line[4:]);
			for(lines = tl lines; lines != nil; lines = tl lines) {
				rest := hd lines;
				rest = agentlib->strip(rest);
				if(agentlib->hasprefix(rest, "[Veltro]"))
					rest = agentlib->strip(rest[8:]);
				rl := str->tolower(agentlib->strip(rest));
				if(rl == "done")
					break;
				if(rest != "")
					text += " " + rest;
			}
			return (text, 0);
		}
		# Not say or done — this is a tool invocation or preamble
		return (nil, 0);
	}
	return (nil, 0);
}

# Write prompt to the LLM ask fd (non-blocking: starts background generation).
writellmfd(fd: ref Sys->FD, prompt: string)
{
	b := array of byte prompt;
	n := sys->write(fd, b, len b);
	if(n < 0)
		sys->fprint(stderr, "lucibridge: writellmfd failed: %r\n");
}

# Read complete LLM response from the ask fd at offset 0.
# Blocks until the background generation goroutine completes.
# Uses chunked reads to avoid a 1MB pool allocation per LLM call.
readllmfd(fd: ref Sys->FD): string
{
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
	return result;
}

# Update an existing conversation message in place (for streaming token display).
updateliveconvmsg(idx: int, text: string)
{
	path := sys->sprint("/n/ui/activity/%d/conversation/ctl", actid);
	msg := "update idx=" + string idx + " text=" + text;
	if(writefile(path, msg) < 0)
		sys->fprint(stderr, "lucibridge: updateliveconvmsg failed: %r\n");
}

# Display welcome.md in the presentation zone on first launch.
# Two-level guard prevents duplicate tabs:
#   1. artifact check  — idempotent within a luciuisrv session (same emu run)
#   2. marker file     — cross-session guard so it only appears once ever
showwelcome(aid: int)
{
	# Idempotent: if the welcome artifact is already showing (e.g. lucibridge
	# restarted inside the same running luciuisrv), do nothing.
	typepath := sys->sprint("/n/ui/activity/%d/presentation/welcome/type", aid);
	(atok, nil) := sys->stat(typepath);
	if(atok >= 0)
		return;

	# Cross-session guard.  Use a plain (non-hidden) filename: trfs on some
	# platforms silently fails sys->stat on dot-files, causing the marker to
	# be missed and the welcome to reappear on every launch.
	marker := "/lib/veltro/welcome_shown";
	(ok, nil) := sys->stat(marker);
	if(ok >= 0)
		return;

	wfd := sys->open("/lib/veltro/welcome.md", Sys->OREAD);
	if(wfd == nil)
		return;
	buf := array[65536] of byte;
	n := sys->read(wfd, buf, len buf);
	wfd = nil;
	if(n <= 0)
		return;
	content := string buf[0:n];

	pctl := sys->sprint("/n/ui/activity/%d/presentation/ctl", aid);
	writefile(pctl, "create id=welcome type=markdown label=Welcome");
	datapath := sys->sprint("/n/ui/activity/%d/presentation/welcome/data", aid);
	writefile(datapath, content);
	writefile(pctl, "center id=welcome");

	fd := sys->create(marker, Sys->OWRITE, 8r644);
	fd = nil;
}

# Find the first Inferno path (starts with /) in tool args.
# Generic — decoupled from which tool is being called or its arg order.
filepathof(args: string): string
{
	(nil, toks) := sys->tokenize(args, " \t\n");
	for(t := toks; t != nil; t = tl t) {
		tok := hd t;
		if(len tok > 1 && tok[0] == '/')
			return tok;
	}
	return nil;
}

# Return the last path component (basename).
pathbase(path: string): string
{
	n := len path;
	while(n > 1 && path[n-1] == '/')
		n--;
	path = path[0:n];
	i := n - 1;
	while(i > 0 && path[i] != '/')
		i--;
	if(path[i] == '/')
		return path[i+1:];
	return path;
}

# firstlines returns the first n newline-terminated lines of s.
# Used to keep a preview of large tool results inline for the LLM.
firstlines(s: string, n: int): string
{
	out := "";
	count := 0;
	for(i := 0; i < len s && count < n; i++) {
		out[len out] = s[i];
		if(s[i] == '\n')
			count++;
	}
	return out;
}

# strcontains returns 1 if name is in the list l.
strcontains(l: list of string, name: string): int
{
	for(; l != nil; l = tl l)
		if(hd l == name)
			return 1;
	return 0;
}

# Extract just the path portion from "path perm" lines.
# "path rw" → "path"; "path" → "path" (backward compat)
extractpaths(lines: list of string): list of string
{
	result: list of string;
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		(p, nil) := splitpathperm(line);
		if(p != "")
			result = p :: result;
	}
	# Reverse to preserve order
	rev: list of string;
	for(r := result; r != nil; r = tl r)
		rev = hd r :: rev;
	return rev;
}

# Split "path [perm]" into (path, perm). Default perm is "rw".
splitpathperm(s: string): (string, string)
{
	for(i := len s - 1; i > 0; i--) {
		if(s[i] == ' ') {
			tail := s[i+1:];
			if(tail == "ro" || tail == "rw")
				return (s[0:i], tail);
			break;
		}
	}
	return (s, "rw");
}

# Look up the permission for a path from /tool/paths lines.
# Returns "ro" or "rw". Default is "rw" if not found.
lookuppathperm(lines: list of string, path: string): string
{
	for(; lines != nil; lines = tl lines) {
		(p, perm) := splitpathperm(hd lines);
		if(p == path)
			return perm;
	}
	return "rw";
}

# Sync the running tools9p to match the wanted list.
# Adds/removes tools via /tool/ctl to reconcile current state.
synctoolset(want: list of string)
{
	if(!agentlib->pathexists(toolmount))
		return;
	cur := agentlib->readfile(toolmount + "/tools");
	(nil, curtl) := sys->tokenize(cur, "\n");
	for(w := want; w != nil; w = tl w)
		if(!strcontains(curtl, hd w))
			writefile(toolmount + "/ctl", "add " + hd w);
	for(c := curtl; c != nil; c = tl c)
		if(!strcontains(want, hd c))
			writefile(toolmount + "/ctl", "remove " + hd c);
}

# Apply path changes from /tool/paths into lucibridge's namespace.
# Diffs current /tool/paths against currentpathsraw; binds new paths,
# unmounts removed paths.  Called at turn start and from initsession.
# /tool/paths format: "path perm" per line (e.g. "/n/local/Users/pdfinn/tmp rw").
applypathchanges()
{
	if(!agentlib->pathexists(toolmount))
		return;
	latest := agentlib->readfile(toolmount + "/paths");
	if(latest == currentpathsraw)
		return;
	(nil, newlines) := sys->tokenize(latest, "\n");
	(nil, oldlines) := sys->tokenize(currentpathsraw, "\n");

	# Extract just the path portion from "path perm" lines for diff comparison
	newpaths := extractpaths(newlines);
	oldpaths := extractpaths(oldlines);

	# Bind newly added paths into lucibridge's namespace.
	# Paths already under /n/local/ are accessible via the trfs OS mount —
	# no rebind needed (and no writable target would exist anyway).
	# Inferno-native paths (/dis/, /lib/, /n/llm/, etc.) are already in the
	# namespace — binding them to /n/local/<base> would fail (no such dir).
	ctxpath := sys->sprint("/n/ui/activity/%d/context/ctl", actid);
	for(np := newpaths; np != nil; np = tl np) {
		p := hd np;
		if(p == "" || strcontains(oldpaths, p))
			continue;
		if(len p >= 9 && p[0:9] == "/n/local/") {
			log("path accessible: " + p);
		} else if(len p >= 5 && p[0:5] == "/dis/") {
			log("path accessible (Inferno-native): " + p);
		} else {
			base := pathbase(p);
			if(base == nil || base == "")
				base = "path";
			tgt := "/n/local/" + base;
			if(sys->bind(p, tgt, Sys->MBEFORE) < 0)
				log("bindpath " + p + ": failed");
			else
				log("bound " + p + " -> " + tgt);
		}
		# Push resource event so namespace view updates immediately
		base := pathbase(p);
		if(base == nil || base == "")
			base = p;
		writefile(ctxpath, "resource upsert path=" + p +
			" label=" + base + " type=fs status=idle via=bound");
	}

	# Unmount removed paths (only those we actually bound, not /n/local/ pass-throughs)
	for(op := oldpaths; op != nil; op = tl op) {
		p := hd op;
		if(p == "" || strcontains(newpaths, p))
			continue;
		if(!(len p >= 9 && p[0:9] == "/n/local/")) {
			base := pathbase(p);
			if(base == nil || base == "")
				base = "path";
			tgt := "/n/local/" + base;
			sys->unmount(nil, tgt);
			log("unbound " + p);
		}
		# Push resource event so namespace view updates immediately
		writefile(ctxpath, "resource remove " + p);
	}

	currentpathsraw = latest;

	# Refresh the system prompt so the LLM knows about the updated path set.
	# (Mirrors the initsessiontools() call that fires when the tool set changes.)
	if(sessionid != "") {
		ns := agentlib->discovernamespace();
		sysprompt := agentlib->buildsystemprompt(ns);
		sfx := BRIDGE_SUFFIX;
		if(actid == 0) {
			meta := agentlib->readfile(META_PROMPT_PATH);
			if(meta != nil)
				sfx = "\n\n" + agentlib->strip(meta);
		}
		MAXWRITE: con 65000;
		suffixbytes := array of byte sfx;
		if(len array of byte sysprompt + len suffixbytes > MAXWRITE)
			sysprompt = string (array of byte sysprompt)[0:MAXWRITE - len suffixbytes];
		sysprompt += sfx;
		systempath := "/n/llm/" + sessionid + "/system";
		agentlib->setsystemprompt(systempath, sysprompt);
		log("system prompt updated with new paths");
	}
}

# Handle slash commands from the input channel.
# Returns 1 if the command was handled (don't pass to agent), 0 otherwise.
handleslash(cmd: string): int
{
	if(len cmd == 0 || cmd[0] != '/')
		return 0;
	rest := cmd[1:];
	(verb, afterverb) := str->splitl(rest, " \t");
	cmdarg := str->drop(afterverb, " \t");
	ack := "";
	case verb {
	"bind" =>
		if(cmdarg == "") {
			ack = "usage: /bind <path> [ro|rw]";
		} else {
			writefile(toolmount + "/ctl", "bindpath " + cmdarg);
			# Push context event so the namespace view updates immediately
			ctxpath := sys->sprint("/n/ui/activity/%d/context/ctl", actid);
			base := pathbase(cmdarg);
			if(base == nil || base == "")
				base = cmdarg;
			writefile(ctxpath, "resource upsert path=" + cmdarg +
				" label=" + base + " type=fs status=idle via=bound");
			ack = "bound: " + cmdarg;
		}
	"unbind" =>
		if(cmdarg == "") {
			ack = "usage: /unbind <path>";
		} else {
			writefile(toolmount + "/ctl", "unbindpath " + cmdarg);
			# Push context event so the namespace view updates immediately
			ctxpath := sys->sprint("/n/ui/activity/%d/context/ctl", actid);
			writefile(ctxpath, "resource remove " + cmdarg);
			ack = "unbound: " + cmdarg;
		}
	"tools" =>
		if(len cmdarg == 0) {
			ack = "usage: /tools +name or /tools -name";
		} else if(cmdarg[0] == '+') {
			writefile(toolmount + "/ctl", "add " + cmdarg[1:]);
			ack = "tool added: " + cmdarg[1:];
		} else if(cmdarg[0] == '-') {
			writefile(toolmount + "/ctl", "remove " + cmdarg[1:]);
			ack = "tool removed: " + cmdarg[1:];
		} else {
			ack = "usage: /tools +name or /tools -name";
		}
	"voice" =>
		if(cmdarg == "" || cmdarg == "on") {
			autospeak = 1;
			ack = "voice: auto-speak enabled";
		} else if(cmdarg == "off") {
			autospeak = 0;
			ack = "voice: auto-speak disabled";
		} else {
			# Set voice name
			writefile("/n/speech/ctl", "voice " + cmdarg);
			ack = "voice: set to " + cmdarg;
		}
	"diff" =>
		ack = cowdiff();
	"promote" =>
		ack = cowpromote(cmdarg);
	"revert" =>
		ack = cowrevert(cmdarg);
	"help" =>
		ack = "/bind <path>  — add namespace path\n" +
		      "/unbind <path>  — remove namespace path\n" +
		      "/tools +name  — add tool\n" +
		      "/tools -name  — remove tool\n" +
		      "/voice on|off  — toggle auto-speak\n" +
		      "/voice <name>  — change voice\n" +
		      "/diff  — show cowfs changes\n" +
		      "/promote [path]  — promote cowfs changes\n" +
		      "/revert [path]  — revert cowfs changes";
	* =>
		return 0;	# unknown slash: pass to agent
	}
	writemsg("assistant", ack);
	return 1;
}

# --- Cowfs slash command helpers ---

Cowfs: module {
	PATH: con "/dis/veltro/cowfs.dis";
	diff:        fn(overlaydir: string): list of string;
	promote:     fn(basepath, overlaydir: string): (int, string);
	revert:      fn(overlaydir: string): string;
	promotefile: fn(basepath, overlaydir, relpath: string): string;
	revertfile:  fn(overlaydir, relpath: string): string;
};

cowfindoverlay(): string
{
	# Overlay dir is /tmp/veltro/cow/{actid}-*
	prefix := sys->sprint("%d-", actid);
	fd := sys->open("/tmp/veltro/cow", Sys->OREAD);
	if(fd == nil)
		return nil;
	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			nm := dirs[i].name;
			if(len nm >= len prefix && nm[0:len prefix] == prefix)
				return "/tmp/veltro/cow/" + nm;
		}
	}
	return nil;
}

cowdiff(): string
{
	cowfs := load Cowfs Cowfs->PATH;
	if(cowfs == nil)
		return "error: cannot load cowfs module";
	overlay := cowfindoverlay();
	if(overlay == nil)
		return "no cowfs overlay for this activity";
	changes := cowfs->diff(overlay);
	if(changes == nil)
		return "no changes";
	result := "";
	for(; changes != nil; changes = tl changes) {
		if(result != "")
			result += "\n";
		result += hd changes;
	}
	return result;
}

cowpromote(arg: string): string
{
	cowfs := load Cowfs Cowfs->PATH;
	if(cowfs == nil)
		return "error: cannot load cowfs module";
	overlay := cowfindoverlay();
	if(overlay == nil)
		return "no cowfs overlay for this activity";
	# Read basepath from .cowmeta
	basepath := agentlib->readfile(overlay + "/.cowmeta");
	if(basepath != nil) {
		# Trim trailing whitespace/newlines
		while(len basepath > 0 && (basepath[len basepath - 1] == '\n' || basepath[len basepath - 1] == ' '))
			basepath = basepath[0:len basepath - 1];
	}
	if(basepath == nil || basepath == "")
		return "error: cannot determine base path";
	if(arg != "") {
		err := cowfs->promotefile(basepath, overlay, arg);
		if(err != nil)
			return "error: " + err;
		return "promoted: " + arg;
	}
	(n, err) := cowfs->promote(basepath, overlay);
	if(err != nil)
		return "error: " + err;
	return sys->sprint("promoted %d file(s)", n);
}

cowrevert(arg: string): string
{
	cowfs := load Cowfs Cowfs->PATH;
	if(cowfs == nil)
		return "error: cannot load cowfs module";
	overlay := cowfindoverlay();
	if(overlay == nil)
		return "no cowfs overlay for this activity";
	if(arg != "") {
		err := cowfs->revertfile(overlay, arg);
		if(err != nil)
			return "error: " + err;
		return "reverted: " + arg;
	}
	err := cowfs->revert(overlay);
	if(err != nil)
		return "error: " + err;
	return "all changes reverted";
}

# Run the agent loop for one human turn using native tool_use protocol.
# Each step starts async LLM generation. If /stream is available (new llmsrv),
# tokens are streamed into a live placeholder message. Otherwise (old llmsrv,
# blocking write), the response is displayed directly — no placeholder needed,
# avoiding the event-delivery race where pushevent("conversation update N")
# fires before nslistener re-issues its pending read.
agentturn(input: string)
{
	# Apply any namespace path changes (via /tool/ctl bindpath/unbindpath).
	applypathchanges();

	# If the tool set changed (via /tool/ctl), reinitialize the LLM session tools
	# so the LLM knows about added/removed tools before processing this turn.
	if(agentlib->pathexists(toolmount)) {
		latest := agentlib->readfile(toolmount + "/tools");
		if(latest != nil && latest != currenttoolsraw) {
			currenttoolsraw = latest;
			(nil, tls) := sys->tokenize(latest, "\n");
			newtoollist: list of string;
			for(t := tls; t != nil; t = tl t) {
				nm := str->tolower(hd t);
				if(nm != "say")
					newtoollist = hd t :: newtoollist;
			}
			agentlib->initsessiontools(sessionid, newtoollist);
			log("tools updated: " + latest);
		}
	}

	setstatus("working");
	prompt := input;
	streambase := "/n/llm/" + sessionid;

	hitlimit := 1;
	for(step := 0; step < maxsteps; step++) {
		log(sys->sprint("step %d: writing %d bytes to LLM", step + 1, len array of byte prompt));

		# Start async generation — returns immediately with new llmsrv,
		# blocks until done with old llmsrv.
		writellmfd(llmfd, prompt);

		# Try to open stream file. Presence indicates new llmsrv with async Write.
		streampath := streambase + "/stream";
		streamfd := sys->open(streampath, Sys->OREAD);

		# placeholder_idx >= 0 means we created a streaming placeholder bubble.
		# For step 0 (first response to a user message) create the placeholder
		# immediately so the user sees a ▌ cursor while waiting — llmsrv's CLI
		# backend has async writes but the /stream file currently returns 0 chunks
		# (chunks are only available via pread from /ask after generation completes).
		# For step > 0 (tool-execution follow-ups) defer creation to the first
		# actual chunk, so tool-only steps produce no spurious bubble.
		placeholder_idx := -1;
		if(streamfd != nil) {
			log("stream: reading " + streampath);
			buf := array[512] of byte;
			growing := "";
			nchunks := 0;
			# Show activity cursor immediately on the first step.
			if(step == 0) {
				placeholder_idx = convcount;
				writemsg("veltro", "▌");
			}
			for(;;) {
				n := sys->read(streamfd, buf, len buf);
				if(n <= 0)
					break;
				growing += string buf[0:n];
				nchunks++;
				# Create placeholder on the first chunk if not already created
				# (steps > 0), seeded with actual text.
				if(placeholder_idx < 0) {
					placeholder_idx = convcount;
					writemsg("veltro", growing + "▌");
				}
				# Batch UI updates: update every 4 chunks to reduce
				# allocation churn and rlayout re-render frequency.
				# Sleep after each update so the draw loop has time to
				# render the intermediate state — prevents "all at once"
				# appearance when llmsrv pre-buffers all chunks.
				if((nchunks & 3) == 0) {
					updateliveconvmsg(placeholder_idx, growing + "▌");
					sys->sleep(50);
				}
			}
			# Final update with accumulated content (no cursor).
			# When nchunks == 0 (CLI backend, no streaming), clear the
			# cursor so it doesn't look stuck while pread blocks.
			if(placeholder_idx >= 0) {
				if(nchunks > 0)
					updateliveconvmsg(placeholder_idx, growing);
				else
					updateliveconvmsg(placeholder_idx, "…");
			}
			log(sys->sprint("stream: done (%d chunks, %d bytes)", nchunks, len growing));
			streamfd = nil;
		} else {
			sys->fprint(stderr, "lucibridge: stream open %s failed: %r\n", streampath);
			log("stream: not available (old llmsrv); using direct display");
		}

		# Pread complete formatted response (blocks until generation done).
		log("step " + string (step + 1) + ": waiting for LLM response...");
		response := readllmfd(llmfd);
		log(sys->sprint("step %d: LLM response %d bytes", step + 1, len array of byte response));
		if(response == "") {
			if(placeholder_idx >= 0)
				updateliveconvmsg(placeholder_idx, "(no response from LLM)");
			else
				writemsg("veltro", "(no response from LLM)");
			break;
		}

		log("llm: " + agentlib->truncate(response, 200));

		(stopreason, tools, text) := agentlib->parsellmresponse(response);

		# Display response: update placeholder (streaming) or add new message (legacy).
		# When text is empty during tool_use, the LLM emitted only tool calls
		# with no accompanying text — clear the placeholder so no empty tile
		# is visible.  Previously we showed "[toolname]" but the event that
		# carries this update to luciconv can be dropped by the non-blocking
		# channel send in nslistener, leaving a stale "▌" cursor that is
		# invisible in the bitmap font → an empty tile.  Clearing to "" is
		# reliable: even if the update event is dropped, the next event for
		# this index (or the full loadmessages on activity switch) will read
		# the empty text and skip the tile.
		if(text != "") {
			if(placeholder_idx >= 0)
				updateliveconvmsg(placeholder_idx, text);
			else
				writemsg("veltro", text);
		} else if(placeholder_idx >= 0) {
			# Tool-only or empty response: clear placeholder so tile is hidden
			updateliveconvmsg(placeholder_idx, "");
		}

		# Plain text or end_turn: done.
		if(stopreason != "tool_use" || tools == nil) {
			hitlimit = 0;
			break;
		}

		# Execute tools, intercepting say locally.
		results: list of (string, string);
		for(tc := tools; tc != nil; tc = tl tc) {
			(id, name, args) := hd tc;
			if(str->tolower(name) == "say") {
				writemsg("veltro", args);
				results = (id, "said") :: results;
			} else {
				# Mark the tool as active in the context zone for the full duration.
				nm := str->tolower(name);
				ctxpath := sys->sprint("/n/ui/activity/%d/context/ctl", actid);
				writefile(ctxpath, "resource activity " + nm);
				writefile(ctxpath, "resource update path=" + nm + " status=active");
				log("context: active " + nm);

				eargs := args;

				# Surface the file/dir this tool is accessing
				fpath := filepathof(eargs);
				if(fpath != nil) {
					base := pathbase(fpath);
					ftype := "file";
					if(fpath[len fpath - 1] == '/')
						ftype = "dir";
					writefile(ctxpath, "resource upsert path=" + fpath +
						" label=" + base + " type=" + ftype +
						" via=" + nm + " status=active");
					log("context: file " + fpath + " via " + nm);
				}

				setstatus(nm);
				log("tool " + name + ": calling with " + string len eargs + " bytes");
				result := agentlib->calltool(name, eargs);
				setstatus("working");
				writefile(ctxpath, "resource update path=" + nm + " status=idle");
				if(fpath != nil)
					writefile(ctxpath, "resource update path=" + fpath + " status=idle");
				log("tool " + name + ": done, " + agentlib->truncate(result, 100));
				if(len result > AgentLib->STREAM_THRESHOLD) {
					# Never re-scratch reads of scratch files — creates an infinite loop
					# where each read produces another scratch file of similar size.
					isscratchread := nm == "read" &&
						len eargs >= len AgentLib->SCRATCH_PATH &&
						eargs[0:len AgentLib->SCRATCH_PATH] == AgentLib->SCRATCH_PATH;
					if(isscratchread) {
						# Truncate so LLM gets as much as possible inline.
						result = result[0:AgentLib->STREAM_THRESHOLD] +
							"\n... (truncated — content continues in " + eargs + ")";
					} else {
						scratch := agentlib->writescratch(result, step);
						# Keep first 3 lines inline so LLM has examples to act on immediately.
						# IMPORTANT: stay small — TOOL_RESULTS must fit in one 9P Write (~8KB).
						# 3 lines x ~80 bytes x 20 parallel tools < 5KB, safely under msize.
						preview := firstlines(result, 3);
						result = preview +
							sys->sprint("\n... (%d total bytes — full output at %s)",
								len result, scratch);
					}
					}
				results = (id, result) :: results;
			}
		}

		# Reverse results (list was built by prepending).
		rev: list of (string, string);
		for(rl := results; rl != nil; rl = tl rl)
			rev = (hd rl) :: rev;

		prompt = agentlib->buildtoolresults(rev);
	}

	if(hitlimit) {
		writemsg("veltro", sys->sprint(
			"(reached %d-step limit — send another message to continue)", maxsteps));
		setstatus("idle");
	} else {
		# Agent turn completed normally.  For spawned tasks (actid > 0),
		# signal the user only for the initial autonomous turn (before
		# the user has interacted).  Once the user has sent a message,
		# further completions don't raise urgency — the user is already
		# engaged and the blinking tile is distracting.
		# "complete" tells the MA this TA finished its autonomous assignment.
		if(actid > 0 && !userinteracted)
			setstatus("complete");
		else
			setstatus("idle");
		if(actid > 0 && !userinteracted)
			seturgency(1);
	}
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	str = load String String->PATH;
	if(str == nil)
		fatal("cannot load String");

	arg = load Arg Arg->PATH;
	if(arg == nil)
		fatal("cannot load Arg");

	agentlib = load AgentLib AgentLib->PATH;
	if(agentlib == nil)
		fatal("cannot load agentlib: " + AgentLib->PATH);
	agentlib->init();

	arg->init(args);
	# NOTE: settoolmount() is called after arg parsing sets actid (below)
	while((c := arg->opt()) != 0) {
		case c {
		'v' =>
			verbose = 1;
		's' =>
			autospeak = 1;
		'n' =>
			s := arg->arg();
			if(s == nil)
				fatal("-n requires step count");
			(maxsteps, nil) = str->toint(s, 10);
			if(maxsteps < 1)
				maxsteps = 1;
			if(maxsteps > MAX_MAX_STEPS)
				maxsteps = MAX_MAX_STEPS;
		'a' =>
			s := arg->arg();
			if(s == nil)
				fatal("-a requires activity ID");
			(actid, nil) = str->toint(s, 10);
		't' =>
			s := arg->arg();
			if(s == nil)
				fatal("-t requires tool list");
			(nil, toolargs) = sys->tokenize(s, ",");
		'p' =>
			s := arg->arg();
			if(s == nil)
				fatal("-p requires path list");
			(nil, pathargs) = sys->tokenize(s, ",");
		* =>
			sys->fprint(stderr,
				"usage: lucibridge [-v] [-s] [-n maxsteps] [-a actid] [-t tools] [-p paths]\n");
			raise "fail:usage";
		}
	}

	agentlib->setverbose(verbose);

	# Set tools9p mount point based on activity ID
	if(actid > 0)
		toolmount = "/tool." + string actid;
	agentlib->settoolmount(toolmount);

	# Verify prerequisites
	if(sys->open("/n/ui/ctl", Sys->OREAD) == nil)
		fatal("/n/ui/ not mounted — start luciuisrv first");
	if(!agentlib->pathexists("/n/llm")) {
		# Check if this is an API key issue
		backend := readndbfield("/lib/ndb/llm", "backend");
		if(backend == nil || backend == "" || backend == "api") {
			# No LLM service — guide the user through first-time setup
			writemsg("veltro",
				"Welcome to InferNode! I'm **Veltro**, your AI agent.\n\n" +
				"I need an LLM connection to work. I've opened the **Keyring** for you " +
				"\u2014 add your Anthropic API key there (select *API Key*, enter `anthropic` " +
				"as the service name, and paste your key).\n\n" +
				"If you'd prefer to use a **local LLM** (Ollama), open **Settings** from the " +
				"context zone and switch the LLM backend.\n\n" +
				"Once configured, restart InferNode and I'll be ready to help.");
			log("no /n/llm and backend=api — displayed setup guidance");

			# Launch Keyring in the presentation zone
			pctl := sys->sprint("/n/ui/activity/%d/presentation/ctl", actid);
			writefile(pctl, "create id=keyring type=app dis=/dis/wm/keyring.dis label=Keyring");
			sys->sleep(300);
			writefile(pctl, "center id=keyring");

			# Don't fatal — stay alive so the user can read the message
			# and interact with the keyring app.  Poll for /n/llm.
			log("waiting for /n/llm to appear...");
			for(;;) {
				sys->sleep(3000);
				if(agentlib->pathexists("/n/llm"))
					break;
			}
			log("/n/llm appeared — continuing startup");
		} else {
			fatal("/n/llm/ not mounted — start llmsrv or mount remote LLM");
		}
	}

	# Tools are optional — bridge works as simple chat relay without them
	if(agentlib->pathexists(toolmount))
		log("tools available at " + toolmount);
	else
		log("no " + toolmount + " mount — running in chat-only mode");

	# Apply -t tool override: sync tools9p to the specified set
	if(toolargs != nil)
		synctoolset(toolargs);

	# Apply -p path bindings: register in tools9p so applypathchanges() in
	# initsession() picks them up, and lucictx can read them from /tool/paths.
	# Paths may have :ro or :rw suffix (e.g. "/n/local/Users/tmp:ro").
	# Convert colon-suffix to space-separated format for tools9p ctl.
	for(pp := pathargs; pp != nil; pp = tl pp) {
		parg := hd pp;
		if(len parg > 3 && parg[len parg - 3:] == ":ro")
			parg = parg[0:len parg - 3] + " ro";
		else if(len parg > 3 && parg[len parg - 3:] == ":rw")
			parg = parg[0:len parg - 3] + " rw";
		writefile(toolmount + "/ctl", "bindpath " + parg);
	}

	# Create LLM session
	err := initsession();
	if(err != nil)
		fatal(err);

	# Show welcome document on first launch
	showwelcome(actid);

	# Sync convcount with messages already in the conversation (e.g. the
	# task tool injects a system context message before we start).
	# Without this, placeholder_idx is off-by-one and streaming updates
	# overwrite the wrong message slot, mixing up roles.
	convbase := sys->sprint("/n/ui/activity/%d/conversation", actid);
	for(convcount = 0; ; convcount++) {
		(cok, nil) := sys->stat(sys->sprint("%s/%d", convbase, convcount));
		if(cok < 0)
			break;
	}

	# For child TAs (actid > 0): read the task brief and optional instructions
	# written by the task tool.  Append them to the LLM system prompt inside
	# <task> and <instructions> tags so the TA knows its assignment.
	taskbrief := "";
	if(actid > 0) {
		briefpath := sys->sprint("/tmp/veltro/brief.%d", actid);
		taskbrief = agentlib->readfile(briefpath);
		if(taskbrief != nil)
			taskbrief = agentlib->strip(taskbrief);
		else
			taskbrief = "";

		instrpath := sys->sprint("/tmp/veltro/instructions.%d", actid);
		taskinstr := agentlib->readfile(instrpath);
		if(taskinstr != nil)
			taskinstr = agentlib->strip(taskinstr);
		else
			taskinstr = "";

		if(taskbrief != "" || taskinstr != "") {
			systempath := "/n/llm/" + sessionid + "/system";
			cursys := agentlib->readfile(systempath);
			if(cursys == nil)
				cursys = "";
			injection := "";
			if(taskbrief != "")
				injection += "\n\n<task>" + taskbrief + "</task>";
			if(taskinstr != "")
				injection += "\n\n<instructions>" + taskinstr + "</instructions>";
			agentlib->setsystemprompt(systempath, cursys + injection);
			log("injected task brief into system prompt: " + agentlib->truncate(taskbrief, 100));
			if(taskinstr != "")
				log("injected instructions: " + agentlib->truncate(taskinstr, 100));
		}
	}

	inputpath := sys->sprint("/n/ui/activity/%d/conversation/input", actid);

	log(sys->sprint("ready — activity %d, session %s, max %d steps, %d existing msgs",
		actid, sessionid, maxsteps, convcount));

	# Autonomous first turn for TAs: the task brief is in the system prompt,
	# now send a short trigger so the LLM responds based on its assignment.
	if(taskbrief != "")
		agentturn("Begin.");

	# Main loop: re-open input fd each iteration because 9P offset
	# advances after read, causing subsequent reads to return EOF.
	for(;;) {
		inputfd := sys->open(inputpath, Sys->OREAD);
		if(inputfd == nil)
			fatal("cannot open " + inputpath);
		human := blockread(inputfd);
		inputfd = nil;
		if(human == nil) {
			log("input closed");
			break;
		}
		log("human: " + human);

		# Slash commands (/bind, /unbind, /tools, /help) are handled locally.
		# They update tools9p state and reply immediately; agent is not invoked.
		if(handleslash(human))
			continue;

		# Record human message in UI
		writemsg("human", human);
		# Revert "complete" → "idle" once the human engages this TA.
		if(!userinteracted)
			setstatus("idle");
		userinteracted = 1;

		# Run agent turn
		agentturn(human);
	}
}
