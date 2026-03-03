implement LuciBridge;

#
# lucibridge - Connects Lucifer UI to Veltro agent via llm9p
#
# Reads human messages from /n/ui/activity/{id}/conversation/input
# (blocking read), runs the Veltro agent loop (LLM + tools), and writes
# responses and tool activity back to the UI as role=veltro messages.
#
# Usage: lucibridge [-v] [-n maxsteps] [-a actid]
#   -v            verbose logging
#   -n steps      max agent steps per turn (default: 20)
#   -a id         activity ID (default: 0)
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

	askpath := "/n/llm/" + sessionid + "/ask";
	llmfd = sys->open(askpath, Sys->ORDWR);
	if(llmfd == nil)
		return sys->sprint("cannot open %s: %r", askpath);

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
readllmfd(fd: ref Sys->FD): string
{
	buf := array[1048576] of byte;
	n := sys->pread(fd, buf, len buf, big 0);
	if(n <= 0)
		return "";
	return string buf[0:n];
}

# Update an existing conversation message in place (for streaming token display).
updateliveconvmsg(idx: int, text: string)
{
	path := sys->sprint("/n/ui/activity/%d/conversation/ctl", actid);
	msg := "update idx=" + string idx + " text=" + text;
	if(writefile(path, msg) < 0)
		sys->fprint(stderr, "lucibridge: updateliveconvmsg failed: %r\n");
}

# Run the agent loop for one human turn using native tool_use protocol.
# Each step starts async LLM generation. If /stream is available (new llm9p),
# tokens are streamed into a live placeholder message. Otherwise (old llm9p,
# blocking write), the response is displayed directly — no placeholder needed,
# avoiding the event-delivery race where pushevent("conversation update N")
# fires before nslistener re-issues its pending read.
agentturn(input: string)
{
	setstatus("working");
	prompt := input;
	streambase := "/n/llm/" + sessionid;

	for(step := 0; step < maxsteps; step++) {
		log(sys->sprint("step %d", step + 1));

		# Start async generation — returns immediately with new llm9p,
		# blocks until done with old llm9p.
		writellmfd(llmfd, prompt);

		# Try to open stream file. Presence indicates new llm9p with async Write.
		streampath := streambase + "/stream";
		streamfd := sys->open(streampath, Sys->OREAD);

		# placeholder_idx >= 0 means we're in streaming mode.
		placeholder_idx := -1;
		if(streamfd != nil) {
			# STREAMING MODE: reserve a placeholder, stream tokens into it.
			placeholder_idx = convcount;
			writemsg("veltro", "▌");

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
				updateliveconvmsg(placeholder_idx, growing + "▌");
			}
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
		if(stopreason != "tool_use" || tools == nil)
			break;

		# Execute tools, intercepting say locally.
		results: list of (string, string);
		for(tc := tools; tc != nil; tc = tl tc) {
			(id, name, args) := hd tc;
			if(str->tolower(name) == "say") {
				writemsg("veltro", extractargs(args));
				results = (id, "said") :: results;
			} else {
				result := agentlib->calltool(name, args);
				log("tool " + name + ": " + agentlib->truncate(result, 100));
				if(len result > AgentLib->STREAM_THRESHOLD) {
					scratch := agentlib->writescratch(result, step);
					result = sys->sprint("(output written to %s, %d bytes)", scratch, len result);
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
		* =>
			sys->fprint(stderr, "usage: lucibridge [-v] [-n maxsteps] [-a actid]\n");
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

		# Record human message in UI
		writemsg("human", human);

		# Run agent turn
		agentturn(human);
	}
}
