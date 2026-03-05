implement LuciBridge;

#
# lucibridge - Connects Lucifer UI to Veltro agent via llm9p
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
#   - llm9p mounted at /n/llm/
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
maxsteps := DEFAULT_MAX_STEPS;
stderr: ref Sys->FD;

# LLM session state
sessionid := "";
llmfd: ref Sys->FD;

# Activity state
actid := 0;
convcount := 0;		# messages written to conversation by this bridge

# Tool tracking: raw string from /tool/tools; updated when tool set changes
currenttoolsraw := "";

# Path tracking: raw string from /tool/paths; updated when path set changes
currentpathsraw := "";

# CLI overrides from -t/-p flags
toolargs: list of string;	# from -t flag (comma-separated tool names)
pathargs: list of string;	# from -p flag (comma-separated paths)

BRIDGE_SUFFIX: con "\n\nYou are the AI assistant in a Lucifer activity. " +
	"The user sends messages through the UI. " +
	"Respond naturally with text for conversational messages, greetings, and answers. " +
	"Use tools only when the user asks you to perform a specific task.";

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

# Create LLM session with system prompt
initsession(): string
{
	sessionid = agentlib->createsession();
	if(sessionid == "")
		return "cannot create LLM session";

	# Build system prompt from namespace discovery
	ns := agentlib->discovernamespace();
	sysprompt := agentlib->buildsystemprompt(ns);

	# Append bridge suffix, truncating base if needed
	MAXWRITE: con 8000;
	suffixbytes := array of byte BRIDGE_SUFFIX;
	basebytes := array of byte sysprompt;
	if(len basebytes + len suffixbytes > MAXWRITE) {
		room := MAXWRITE - len suffixbytes;
		if(room < 0)
			room = 0;
		sysprompt = string basebytes[0:room];
	}
	sysprompt += BRIDGE_SUFFIX;

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
	if(agentlib->pathexists("/tool")) {
		tools := agentlib->readfile("/tool/tools");
		(nil, tls) := sys->tokenize(tools, "\n");
		for(t := tls; t != nil; t = tl t) {
			nm := str->tolower(hd t);
			if(nm != "say")
				toollist = hd t :: toollist;
		}
	}
	agentlib->initsessiontools(sessionid, toollist);
	if(agentlib->pathexists("/tool"))
		currenttoolsraw = agentlib->readfile("/tool/tools");

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

# Extract the "args" string value from {"args": "..."} JSON.
# Returns the unescaped string, or the raw json if parsing fails.
extractargs(json: string): string
{
	n := len json;
	key := "\"args\"";
	klen := len key;

	# Find "args" key
	i := 0;
	found := 0;
	for(; i <= n - klen; i++) {
		if(json[i:i+klen] == key) {
			found = 1;
			i += klen;
			break;
		}
	}
	if(!found)
		return json;

	# Skip whitespace and ':'
	for(; i < n && (json[i] == ' ' || json[i] == '\t' || json[i] == ':'); i++)
		;
	if(i >= n || json[i] != '"')
		return json;
	i++;	# skip opening '"'

	# Collect string with JSON unescaping
	result := "";
	for(; i < n && json[i] != '"'; i++) {
		if(json[i] == '\\' && i+1 < n) {
			i++;
			case json[i] {
			'n'  => result += "\n";
			'r'  => result += "\r";
			't'  => result += "\t";
			'"'  => result += "\"";
			'\\' => result += "\\";
			*    => result += json[i:i+1];
			}
		} else
			result += json[i:i+1];
	}
	if(result == "")
		return json;
	return result;
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

# Sync the running tools9p to match the wanted list.
# Adds/removes tools via /tool/ctl to reconcile current state.
synctoolset(want: list of string)
{
	if(!agentlib->pathexists("/tool"))
		return;
	cur := agentlib->readfile("/tool/tools");
	(nil, curtl) := sys->tokenize(cur, "\n");
	for(w := want; w != nil; w = tl w)
		if(!strcontains(curtl, hd w))
			writefile("/tool/ctl", "add " + hd w);
	for(c := curtl; c != nil; c = tl c)
		if(!strcontains(want, hd c))
			writefile("/tool/ctl", "remove " + hd c);
}

# Apply path changes from /tool/paths into lucibridge's namespace.
# Diffs current /tool/paths against currentpathsraw; binds new paths,
# unmounts removed paths.  Called at turn start and from initsession.
applypathchanges()
{
	if(!agentlib->pathexists("/tool"))
		return;
	latest := agentlib->readfile("/tool/paths");
	if(latest == currentpathsraw)
		return;
	(nil, newpaths) := sys->tokenize(latest, "\n");
	(nil, oldpaths) := sys->tokenize(currentpathsraw, "\n");

	# Bind newly added paths into lucibridge's namespace.
	# Paths already under /n/local/ are accessible via the trfs OS mount —
	# no rebind needed (and no writable target would exist anyway).
	for(np := newpaths; np != nil; np = tl np) {
		p := hd np;
		if(p == "" || strcontains(oldpaths, p))
			continue;
		if(len p >= 9 && p[0:9] == "/n/local/") {
			log("path accessible: " + p);
			continue;
		}
		base := pathbase(p);
		if(base == nil || base == "")
			base = "path";
		tgt := "/n/local/" + base;
		if(sys->bind(p, tgt, Sys->MBEFORE) < 0)
			log("bindpath " + p + ": failed");
		else
			log("bound " + p + " -> " + tgt);
	}

	# Unmount removed paths (only those we actually bound, not /n/local/ pass-throughs)
	for(op := oldpaths; op != nil; op = tl op) {
		p := hd op;
		if(p == "" || strcontains(newpaths, p))
			continue;
		if(len p >= 9 && p[0:9] == "/n/local/")
			continue;
		base := pathbase(p);
		if(base == nil || base == "")
			base = "path";
		tgt := "/n/local/" + base;
		sys->unmount(nil, tgt);
		log("unbound " + p);
	}

	currentpathsraw = latest;

	# Refresh the system prompt so the LLM knows about the updated path set.
	# (Mirrors the initsessiontools() call that fires when the tool set changes.)
	if(sessionid != "") {
		ns := agentlib->discovernamespace();
		sysprompt := agentlib->buildsystemprompt(ns);
		MAXWRITE: con 8000;
		suffixbytes := array of byte BRIDGE_SUFFIX;
		if(len array of byte sysprompt + len suffixbytes > MAXWRITE)
			sysprompt = string (array of byte sysprompt)[0:MAXWRITE - len suffixbytes];
		sysprompt += BRIDGE_SUFFIX;
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
	arg := str->drop(afterverb, " \t");
	ack := "";
	case verb {
	"bind" =>
		if(arg == "") {
			ack = "usage: /bind <path>";
		} else {
			writefile("/tool/ctl", "bindpath " + arg);
			ack = "bound: " + arg;
		}
	"unbind" =>
		if(arg == "") {
			ack = "usage: /unbind <path>";
		} else {
			writefile("/tool/ctl", "unbindpath " + arg);
			ack = "unbound: " + arg;
		}
	"tools" =>
		if(len arg == 0) {
			ack = "usage: /tools +name or /tools -name";
		} else if(arg[0] == '+') {
			writefile("/tool/ctl", "add " + arg[1:]);
			ack = "tool added: " + arg[1:];
		} else if(arg[0] == '-') {
			writefile("/tool/ctl", "remove " + arg[1:]);
			ack = "tool removed: " + arg[1:];
		} else {
			ack = "usage: /tools +name or /tools -name";
		}
	"help" =>
		ack = "/bind <path>  — add namespace path\n" +
		      "/unbind <path>  — remove namespace path\n" +
		      "/tools +name  — add tool\n" +
		      "/tools -name  — remove tool";
	* =>
		return 0;	# unknown slash: pass to agent
	}
	writemsg("assistant", ack);
	return 1;
}

# Run the agent loop for one human turn using native tool_use protocol.
# Each step starts async LLM generation. If /stream is available (new llm9p),
# tokens are streamed into a live placeholder message. Otherwise (old llm9p,
# blocking write), the response is displayed directly — no placeholder needed,
# avoiding the event-delivery race where pushevent("conversation update N")
# fires before nslistener re-issues its pending read.
agentturn(input: string)
{
	# Apply any namespace path changes (via /tool/ctl bindpath/unbindpath).
	applypathchanges();

	# If the tool set changed (via /tool/ctl), reinitialize the LLM session tools
	# so the LLM knows about added/removed tools before processing this turn.
	if(agentlib->pathexists("/tool")) {
		latest := agentlib->readfile("/tool/tools");
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
		log(sys->sprint("step %d", step + 1));

		# Start async generation — returns immediately with new llm9p,
		# blocks until done with old llm9p.
		writellmfd(llmfd, prompt);

		# Try to open stream file. Presence indicates new llm9p with async Write.
		streampath := streambase + "/stream";
		streamfd := sys->open(streampath, Sys->OREAD);

		# placeholder_idx >= 0 means we created a streaming placeholder bubble.
		# We defer creation until the first chunk so tool-only steps (0 chunks,
		# empty text) produce no bubble at all instead of a blank one.
		placeholder_idx := -1;
		if(streamfd != nil) {
			log("stream: reading " + streampath);
			buf := array[512] of byte;
			growing := "";
			nchunks := 0;
			for(;;) {
				n := sys->read(streamfd, buf, len buf);
				if(n <= 0)
					break;
				growing += string buf[0:n];
				nchunks++;
				# Create placeholder on the first chunk, seeded with actual text
				# so the message never shows bare ▌ without content.
				if(placeholder_idx < 0) {
					placeholder_idx = convcount;
					writemsg("veltro", growing + "▌");
				}
				# Batch UI updates: update every 4 chunks to reduce
				# allocation churn and rlayout re-render frequency.
				# Sleep after each update so the draw loop has time to
				# render the intermediate state — prevents "all at once"
				# appearance when llm9p pre-buffers all chunks.
				if((nchunks & 3) == 0) {
					updateliveconvmsg(placeholder_idx, growing + "▌");
					sys->sleep(50);
				}
			}
			# Final update with accumulated content (no cursor)
			if(placeholder_idx >= 0 && nchunks > 0)
				updateliveconvmsg(placeholder_idx, growing + "▌");
			log(sys->sprint("stream: done (%d chunks, %d bytes)", nchunks, len growing));
			streamfd = nil;
		} else {
			sys->fprint(stderr, "lucibridge: stream open %s failed: %r\n", streampath);
			log("stream: not available (old llm9p); using direct display");
		}

		# Pread complete formatted response (blocks until generation done).
		response := readllmfd(llmfd);
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
		if(placeholder_idx >= 0)
			updateliveconvmsg(placeholder_idx, text);
		else if(text != "")
			writemsg("veltro", text);

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
				writemsg("veltro", extractargs(args));
				results = (id, "said") :: results;
			} else {
				# Mark the tool as active in the context zone for the full duration.
				nm := str->tolower(name);
				ctxpath := sys->sprint("/n/ui/activity/%d/context/ctl", actid);
				writefile(ctxpath, "resource activity " + nm);
				writefile(ctxpath, "resource update path=" + nm + " status=active");
				log("context: active " + nm);

				# extractargs: unwrap {"args":"<value>"} JSON envelope from Anthropic
				# native tool_use protocol before forwarding to tools9p.
				#
				# Bug history: when the native tool_use protocol was introduced,
				# extractargs() was added but only called for the local "say" intercept.
				# All other tools received the raw JSON wrapper as their args string.
				# tools9p's exec tool then saw '{"args":' as the first command word →
				# "error: unknown command" for every tool call.  Fixed here by always
				# extracting args before calltool() and filepathof().
				eargs := extractargs(args);

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

				result := agentlib->calltool(name, eargs);
				writefile(ctxpath, "resource update path=" + nm + " status=idle");
				if(fpath != nil)
					writefile(ctxpath, "resource update path=" + fpath + " status=idle");
				log("tool " + name + ": " + agentlib->truncate(result, 100));
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

	if(hitlimit)
		writemsg("veltro", sys->sprint(
			"(reached %d-step limit — send another message to continue)", maxsteps));
	setstatus("idle");
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
	while((c := arg->opt()) != 0) {
		case c {
		'v' =>
			verbose = 1;
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
				"usage: lucibridge [-v] [-n maxsteps] [-a actid] [-t tools] [-p paths]\n");
			raise "fail:usage";
		}
	}

	agentlib->setverbose(verbose);

	# Verify prerequisites
	if(sys->open("/n/ui/ctl", Sys->OREAD) == nil)
		fatal("/n/ui/ not mounted — start luciuisrv first");
	if(!agentlib->pathexists("/n/llm"))
		fatal("/n/llm/ not mounted — mount llm9p first");

	# Tools are optional — bridge works as simple chat relay without them
	if(agentlib->pathexists("/tool"))
		log("tools available at /tool");
	else
		log("no /tool mount — running in chat-only mode");

	# Apply -t tool override: sync tools9p to the specified set
	if(toolargs != nil)
		synctoolset(toolargs);

	# Apply -p path bindings: register in tools9p so applypathchanges() in
	# initsession() picks them up, and lucictx can read them from /tool/paths.
	for(pp := pathargs; pp != nil; pp = tl pp)
		writefile("/tool/ctl", "bindpath " + hd pp);

	# Create LLM session
	err := initsession();
	if(err != nil)
		fatal(err);

	inputpath := sys->sprint("/n/ui/activity/%d/conversation/input", actid);

	log(sys->sprint("ready — activity %d, session %s, max %d steps", actid, sessionid, maxsteps));

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

		# Run agent turn
		agentturn(human);
	}
}
