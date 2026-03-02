implement Repl;

#
# repl - Interactive Veltro Agent Chat
#
# A REPL where users have ongoing conversations with Veltro.
# Works in two modes:
#   - Xenith mode: window with Send/Clear/Reset/Delete tag buttons
#   - Terminal mode: line-oriented stdin/stdout when Xenith unavailable
#
# Usage:
#   repl [-v] [-n maxsteps]
#
# Requires:
#   - /tool mounted (via tools9p)
#   - /n/llm mounted (LLM interface)
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "arg.m";

include "string.m";
	str: String;

include "nsconstruct.m";
	nsconstruct: NsConstruct;

include "xenithwin.m";
	xenithwin: Xenithwin;
	Win, Event: import xenithwin;

include "agentlib.m";
	agentlib: AgentLib;

Repl: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

# Defaults
DEFAULT_MAX_STEPS: con 50;
MAX_MAX_STEPS: con 100;

# Configuration
verbose := 0;
maxsteps := DEFAULT_MAX_STEPS;

stderr: ref Sys->FD;

# LLM session state
sessionid := "";
llmfd: ref Sys->FD;

# Window state (Xenith mode only)
w: ref Win;
hostpt := 0;
busy := 0;

usage()
{
	sys->fprint(stderr, "Usage: repl [-v] [-n maxsteps] [-p paths]\n");
	sys->fprint(stderr, "\nOptions:\n");
	sys->fprint(stderr, "  -v          Verbose output\n");
	sys->fprint(stderr, "  -n steps    Maximum steps per turn (default: %d, max: %d)\n",
		DEFAULT_MAX_STEPS, MAX_MAX_STEPS);
	sys->fprint(stderr, "  -p paths    Comma-separated /n/local/ paths to expose (e.g. /n/local/Users/you/proj)\n");
	sys->fprint(stderr, "\nRequires /tool and /n/llm to be mounted.\n");
	raise "fail:usage";
}

nomod(s: string)
{
	sys->fprint(stderr, "repl: can't load %s: %r\n", s);
	raise "fail:load";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		nomod(Bufio->PATH);

	str = load String String->PATH;
	if(str == nil)
		nomod(String->PATH);

	agentlib = load AgentLib AgentLib->PATH;
	if(agentlib == nil)
		nomod(AgentLib->PATH);
	agentlib->init();

	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	arg->init(args);

	pathlist: list of string;
	while((o := arg->opt()) != 0)
		case o {
		'v' =>	verbose = 1;
		'n' =>
			n := int arg->earg();
			if(n < 1)
				n = 1;
			if(n > MAX_MAX_STEPS)
				n = MAX_MAX_STEPS;
			maxsteps = n;
		'p' =>
			(nil, pathlist) = sys->tokenize(arg->earg(), ",");
		* =>	usage();
		}
	arg = nil;

	agentlib->setverbose(verbose);

	# Check required mounts
	if(!agentlib->pathexists("/tool")) {
		sys->fprint(stderr, "repl: /tool not mounted (run tools9p first)\n");
		raise "fail:no /tool";
	}
	if(!agentlib->pathexists("/n/llm")) {
		sys->fprint(stderr, "repl: /n/llm not mounted\n");
		raise "fail:no /n/llm";
	}

	# Detect Xenith and create window BEFORE namespace restriction.
	# /chan (Xenith 9P) exposes ALL window contents — after restriction
	# it must be hidden. Open FDs before restriction so they survive.
	xmode := 0;
	if(xenithavail()) {
		xenithwin = load Xenithwin Xenithwin->PATH;
		if(xenithwin == nil)
			nomod(Xenithwin->PATH);
		xenithwin->init();
		w = Win.wnew();              # opens ctl, event via /chan
		w.wname("/+Veltro");
		w.wtagwrite(" Send Voice Clear Reset Delete");  # opens tag transiently
		# Eagerly open addr and data — used later by wreplace, wread, readinput.
		# After restriction /chan is gone, but these FDs persist.
		w.addr = w.openfile("addr");
		w.data = w.openfile("data");
		xmode = 1;
	}

	# Namespace restriction (v3): FORKNS + bind-replace
	# Must happen after mount checks and Xenith window creation,
	# but before session creation
	nsconstruct = load NsConstruct NsConstruct->PATH;
	if(nsconstruct != nil) {
		nsconstruct->init();

		# Read tools list before restriction to grant correct capabilities.
		# exec tool needs sh.dis+cmd/; xenith tool needs /chan.
		(nil, toollist) := sys->tokenize(agentlib->readfile("/tool/tools"), "\n");
		xgrant := 0;
		for(tl2 := toollist; tl2 != nil; tl2 = tl tl2)
			if(hd tl2 == "xenith") { xgrant = 1; break; }

		sys->pctl(Sys->FORKNS, nil);

		caps := ref NsConstruct->Capabilities(
			toollist, pathlist, nil, nil, nil, nil, 0, xgrant
		);

		nserr := nsconstruct->restrictns(caps);
		if(nserr != nil)
			sys->fprint(stderr, "repl: namespace restriction failed: %s\n", nserr);
		else if(verbose)
			sys->fprint(stderr, "repl: namespace restricted\n");
	}

	# Create LLM session
	initsession();

	# Enter mode — window already created if Xenith available
	if(xmode)
		xenithmode();
	else
		termmode();
}

# Check if Xenith window system is available.
# Use stat on /chan/index — do NOT open /chan/new/ctl, as that creates a window.
xenithavail(): int
{
	(ok, nil) := sys->stat("/chan/index");
	return ok >= 0;
}

# REPL mode suffix appended to system prompt.
# Tool format instructions are NOT needed — native tool_use protocol handles that.
REPL_SUFFIX: con "\n\nYou are in interactive REPL mode.\n" +
	"For greetings or clarifying questions: respond with text directly.\n" +
	"For ALL research, factual claims, or data questions: you MUST call tools first.\n" +
	"NEVER answer research questions from training knowledge. If a tool is unavailable, say so explicitly.";

# Create a new LLM session with REPL system prompt. Returns error string or nil.
newsession(): string
{
	sessionid = agentlib->createsession();
	if(sessionid == "")
		return "cannot create LLM session";

	ns := agentlib->discovernamespace();
	sysprompt := agentlib->buildsystemprompt(ns);

	# Append REPL suffix. If total exceeds 9P write limit, truncate
	# the base prompt to make room — the suffix is essential.
	MAXWRITE: con 8000;
	suffixbytes := array of byte REPL_SUFFIX;
	basebytes := array of byte sysprompt;
	if(len basebytes + len suffixbytes > MAXWRITE) {
		room := MAXWRITE - len suffixbytes;
		if(room < 0)
			room = 0;
		sysprompt = string basebytes[0:room];
		if(verbose)
			sys->fprint(stderr, "repl: truncated base prompt to %d bytes for REPL suffix\n", room);
	}
	sysprompt += REPL_SUFFIX;

	if(verbose) {
		sys->fprint(stderr, "repl: session %s\n", sessionid);
		sys->fprint(stderr, "repl: system prompt: %d bytes\n", len array of byte sysprompt);
		sys->fprint(stderr, "repl: namespace:\n%s\n", ns);
	}

	systempath := "/n/llm/" + sessionid + "/system";
	agentlib->setsystemprompt(systempath, sysprompt);

	# Install tool definitions for native tool_use protocol.
	# Must happen before the first Ask so llm9p sends tools in the API request.
	(nil, toollist) := sys->tokenize(agentlib->readfile("/tool/tools"), "\n");
	agentlib->initsessiontools(sessionid, toollist);

	askpath := "/n/llm/" + sessionid + "/ask";
	llmfd = sys->open(askpath, Sys->ORDWR);
	if(llmfd == nil)
		return sys->sprint("cannot open %s: %r", askpath);

	return nil;
}

# Create LLM session and set up system prompt
initsession()
{
	err := newsession();
	if(err != nil) {
		sys->fprint(stderr, "repl: %s\n", err);
		raise "fail:no LLM session";
	}
}

#
# ==================== Terminal Mode ====================
#

termmode()
{
	sys->print("Veltro REPL (terminal mode)\n");
	sys->print("Type a message, or /voice to speak. /quit to exit, /reset for new session.\n\n");

	stdin := bufio->fopen(sys->fildes(0), Sys->OREAD);
	if(stdin == nil) {
		sys->fprint(stderr, "repl: cannot open stdin\n");
		raise "fail:stdin";
	}

	for(;;) {
		sys->print("veltro> ");

		line := stdin.gets('\n');
		if(line == nil)
			break;

		# Strip trailing newline
		if(len line > 0 && line[len line - 1] == '\n')
			line = line[:len line - 1];
		line = agentlib->strip(line);
		if(line == "")
			continue;

		# Commands
		if(line == "/quit" || line == "/exit")
			break;
		if(line == "/reset") {
			termreset();
			continue;
		}
		if(line == "/clear") {
			sys->print("\n");
			continue;
		}
		if(line == "/voice" || line == "/v") {
			voiceline := voiceinput();
			if(voiceline != "") {
				sys->print("> %s\n", voiceline);
				termagent(voiceline);
			}
			continue;
		}

		# Run agent synchronously
		termagent(line);
	}

	sys->print("\n");
}

termreset()
{
	err := newsession();
	if(err != nil) {
		sys->print("[error: %s]\n", err);
		return;
	}
	sys->print("[session reset]\n\n");
}

# Execute a single tool in a goroutine, send result to channel.
runtoolchan(tool, args: string, ch: chan of string)
{
	ch <-= agentlib->calltool(tool, args);
}

# Execute a list of native tool_use calls in parallel.
# calls: list of (tool_use_id, name, args) from parsellmresponse.
# Returns list of (tool_use_id, content) for buildtoolresults.
exectools(calls: list of (string, string, string), step: int): list of (string, string)
{
	n := 0;
	i: int;
	for(cl := calls; cl != nil; cl = tl cl)
		n++;

	# Single tool: execute inline (avoid goroutine overhead)
	if(n == 1) {
		(id, name, args) := hd calls;
		r := agentlib->calltool(name, args);
		if(len r > AgentLib->STREAM_THRESHOLD) {
			scratchfile := agentlib->writescratch(r, step);
			r = sys->sprint("(output written to %s, %d bytes)", scratchfile, len r);
		}
		return (id, r) :: nil;
	}

	# Multiple tools: one channel per tool for ordered collection
	channels := array[n] of chan of string;
	for(i = 0; i < n; i++)
		channels[i] = chan of string;

	cl2 := calls;
	for(i = 0; cl2 != nil; i++) {
		(nil, name, args) := hd cl2;
		cl2 = tl cl2;
		spawn runtoolchan(name, args, channels[i]);
	}

	# Collect results in original order
	results: list of (string, string);
	cl3 := calls;
	for(i = 0; cl3 != nil; i++) {
		(id, nil, nil) := hd cl3;
		cl3 = tl cl3;
		r := <-channels[i];
		if(len r > AgentLib->STREAM_THRESHOLD) {
			scratchfile := agentlib->writescratch(r, step * 10 + i);
			r = sys->sprint("(output written to %s, %d bytes)", scratchfile, len r);
		}
		results = (id, r) :: results;
	}

	# Reverse to restore original order
	rev: list of (string, string);
	for(rl := results; rl != nil; rl = tl rl)
		rev = (hd rl) :: rev;
	return rev;
}

termagent(input: string)
{
	sys->print("[thinking...]\n");
	response := agentlib->queryllmfd(llmfd, input);
	if(response == "") {
		sys->print("[error: LLM returned empty response]\n\n");
		return;
	}

	for(step := 0; step < maxsteps; step++) {
		if(verbose)
			sys->fprint(stderr, "repl: step %d\n", step + 1);

		(stopreason, tools, text) := agentlib->parsellmresponse(response);

		# Display any text content from the LLM
		if(text != "")
			sys->print("%s\n", text);

		# If no tool calls, the LLM is done
		if(stopreason == "end_turn" || stopreason == "" || tools == nil)
			return;

		# Display tool invocations
		for(tc := tools; tc != nil; tc = tl tc) {
			(nil, name, args) := hd tc;
			if(str->tolower(name) == "say")
				sys->print("%s\n", args);
			else
				sys->print("[%s %s]\n", name, agentlib->truncate(args, 80));
		}

		# Execute all tools (parallel if multiple)
		results := exectools(tools, step);

		if(verbose) {
			for(rl := results; rl != nil; rl = tl rl) {
				(rid, rval) := hd rl;
				sys->fprint(stderr, "repl: tool %s result: %s\n", rid, rval);
			}
		}

		# Submit tool results and get next LLM response
		sys->print("[thinking...]\n");
		wire := agentlib->buildtoolresults(results);
		response = agentlib->queryllmfd(llmfd, wire);
		if(response == "") {
			sys->print("[error: empty response after tool results]\n\n");
			return;
		}
	}

	sys->print("[max steps reached]\n\n");
}

#
# ==================== Xenith Mode ====================
#

xenithmode()
{
	# Window already created in init() before namespace restriction.
	# FDs (ctl, event, addr, data) are open and survive restriction.
	spawn xmainloop();
}

xmainloop()
{
	c := chan of Event;
	agentout := chan of string;	# unbuffered: rendezvous ensures text is visible before calltool starts speech

	spawn w.wslave(c);

	loop: for(;;) alt {
	msg := <-agentout =>
		if(msg == nil) {
			busy = 0;
			if(verbose)
				sys->fprint(stderr, "repl: agent done, busy=0\n");
		} else
			appendoutput(msg);

	e := <-c =>
		case e.c1 {
		'M' or 'K' =>
			case e.c2 {
			'x' or 'X' =>
				s := getexectext(e, c);
				n := doexec(s, agentout);
				if(n == 0)
					w.wwriteevent(ref e);
				else if(n < 0)
					break loop;
			'l' or 'L' =>
				w.wwriteevent(ref e);
			}
		}
	}
	w.wdel(1);
}

# Extract command text from execute event, consuming secondary/arg events
getexectext(e: Event, c: chan of Event): string
{
	eq := e;
	na := 0;
	ea: Event;

	if(e.flag & 2)
		eq = <-c;
	if(e.flag & 8) {
		ea = <-c;
		na = ea.nb;
		<-c;	# toss
	}

	s: string;
	if(eq.q1 > eq.q0 && eq.nb == 0)
		s = w.wread(eq.q0, eq.q1);
	else
		s = string eq.b[0:eq.nb];
	if(na)
		s += " " + string ea.b[0:ea.nb];
	return s;
}

# Dispatch tag commands. Returns: 1=handled, 0=pass to xenith, -1=exit
doexec(cmd: string, agentout: chan of string): int
{
	cmd = str->drop(cmd, " \t\n");
	(word, nil) := agentlib->splitfirst(cmd);
	if(verbose)
		sys->fprint(stderr, "repl: doexec: '%s'\n", word);
	case word {
	"Send" =>
		dosend(agentout);
	"Voice" =>
		dovoice(agentout);
	"Clear" =>
		doclear();
	"Reset" =>
		doreset();
	"Del" or "Delete" =>
		return -1;
	* =>
		return 0;
	}
	return 1;
}

# Harvest user input from below hostpt, dispatch to agent
dosend(agentout: chan of string)
{
	if(verbose)
		sys->fprint(stderr, "repl: dosend: busy=%d hostpt=%d\n", busy, hostpt);

	if(busy) {
		appendoutput("[busy -- agent is still working]\n");
		return;
	}

	# Read input from hostpt to end of body
	input := readinput();
	input = agentlib->strip(input);
	if(verbose)
		sys->fprint(stderr, "repl: dosend: input=%d bytes '%s'\n",
			len input, agentlib->truncate(input, 60));
	if(input == "")
		return;

	# Clear the input area
	w.wreplace(sys->sprint("#%d,$", hostpt), "");

	# Echo the user's message
	appendoutput("> " + input + "\n");

	busy = 1;
	spawn xagentthread(input, agentout);
}

# Read body text from hostpt to end
readinput(): string
{
	addr := sys->sprint("#%d,$", hostpt);
	if(verbose)
		sys->fprint(stderr, "repl: readinput: addr='%s'\n", addr);
	if(!w.wsetaddr(addr, 1)) {
		# hostpt past body end — recover by reading actual body length
		if(verbose)
			sys->fprint(stderr, "repl: readinput: wsetaddr FAILED, recovering\n");
		if(w.wsetaddr("$", 1)) {
			abuf := array[24] of byte;
			n := sys->read(w.addr, abuf, len abuf);
			if(n > 0) {
				hostpt = int string abuf[0:n];
				if(verbose)
					sys->fprint(stderr, "repl: readinput: hostpt recovered to %d\n", hostpt);
			}
		}
		return "";
	}

	# Read from the addr/data pair
	if(w.data == nil)
		w.data = w.openfile("data");

	result := "";
	buf := array[4096] of byte;
	for(;;) {
		n := sys->read(w.data, buf, len buf);
		if(verbose && n <= 0)
			sys->fprint(stderr, "repl: readinput: read returned %d\n", n);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	if(verbose)
		sys->fprint(stderr, "repl: readinput: got %d bytes\n", len result);
	return result;
}

# Voice input for Xenith mode: record, transcribe, send to agent
dovoice(agentout: chan of string)
{
	if(verbose)
		sys->fprint(stderr, "repl: dovoice: busy=%d\n", busy);

	if(busy) {
		appendoutput("[busy -- agent is still working]\n");
		return;
	}

	appendoutput("[listening...]\n");
	input := voiceinput();
	if(input == "")
		return;

	appendoutput("> " + input + "\n");
	busy = 1;
	spawn xagentthread(input, agentout);
}

# Record and transcribe via /n/speech/hear
voiceinput(): string
{
	SPEECH_HEAR: con "/n/speech/hear";

	(ok, nil) := sys->stat(SPEECH_HEAR);
	if(ok < 0) {
		sys->print("[voice: /n/speech not mounted]\n");
		return "";
	}

	sys->print("[recording 5 seconds...]\n");

	fd := sys->open(SPEECH_HEAR, Sys->ORDWR);
	if(fd == nil) {
		sys->print("[voice: cannot open %s: %r]\n", SPEECH_HEAR);
		return "";
	}

	# Write start command to trigger recording
	cmd := array of byte "start 5000";
	sys->write(fd, cmd, len cmd);

	# Read transcription
	sys->seek(fd, big 0, Sys->SEEKSTART);
	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}

	result = agentlib->strip(result);
	if(result == "" || agentlib->hasprefix(result, "error:")) {
		sys->print("[voice: no speech detected]\n");
		return "";
	}

	return result;
}

# Insert text at hostpt, advance hostpt
appendoutput(text: string)
{
	addr := sys->sprint("#%d,#%d", hostpt, hostpt);
	if(!w.wsetaddr(addr, 1)) {
		if(verbose)
			sys->fprint(stderr, "repl: appendoutput: addr '%s' failed\n", addr);
		return;
	}
	b := array of byte text;
	n := sys->write(w.data, b, len b);
	if(n == len b)
		hostpt += len text;
	else if(verbose)
		sys->fprint(stderr, "repl: appendoutput: data write failed: %r\n");
	w.ctlwrite("show\n");
}

# Clear body, reset hostpt (keep LLM session)
doclear()
{
	w.wreplace(",", "");
	hostpt = 0;
	w.ctlwrite("clean\n");
}

# Create new LLM session, clear body
doreset()
{
	doclear();

	err := newsession();
	if(err != nil) {
		appendoutput("[error: " + err + "]\n");
		return;
	}
	appendoutput("[session reset]\n");
}

# Agent thread for Xenith mode: sends display text on agentout channel
xagentthread(input: string, agentout: chan of string)
{
	if(verbose)
		sys->fprint(stderr, "repl: xagentthread: start\n");
	{
		xagentsteps(input, agentout);
	} exception {
	* =>
		sys->fprint(stderr, "repl: agent exception\n");
		agentout <-= "[error: agent exception]\n";
	}
	agentout <-= nil;	# signal completion to event loop
	if(verbose)
		sys->fprint(stderr, "repl: xagentthread: done\n");
}

xagentsteps(input: string, agentout: chan of string)
{
	agentout <-= "[thinking...]\n";
	response := agentlib->queryllmfd(llmfd, input);
	if(response == "") {
		agentout <-= "[error: LLM returned empty response]\n\n";
		return;
	}

	for(step := 0; step < maxsteps; step++) {
		if(verbose)
			sys->fprint(stderr, "repl: step %d\n", step + 1);

		(stopreason, tools, text) := agentlib->parsellmresponse(response);

		# Display any text content from the LLM
		if(text != "")
			agentout <-= text + "\n";

		# If no tool calls, the LLM is done
		if(stopreason == "end_turn" || stopreason == "" || tools == nil)
			return;

		# Display tool invocations
		for(tc := tools; tc != nil; tc = tl tc) {
			(nil, name, args) := hd tc;
			if(str->tolower(name) == "say")
				agentout <-= args + "\n";
			else
				agentout <-= "[" + name + " " + agentlib->truncate(args, 80) + "]\n";
		}

		# Execute all tools (parallel if multiple)
		results := exectools(tools, step);

		if(verbose) {
			for(rl := results; rl != nil; rl = tl rl) {
				(rid, rval) := hd rl;
				sys->fprint(stderr, "repl: tool %s result: %s\n", rid, rval);
			}
		}

		# Submit tool results and get next LLM response
		agentout <-= "[thinking...]\n";
		wire := agentlib->buildtoolresults(results);
		response = agentlib->queryllmfd(llmfd, wire);
		if(response == "") {
			agentout <-= "[error: empty response after tool results]\n\n";
			return;
		}
	}
}
