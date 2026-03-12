implement Llmsrv;

#
# llmsrv - LLM Filesystem Service
#
# Plan 9-style Styx server exposing LLM access as a filesystem
# with clone-based multiplexing for concurrent sessions.
#
# Filesystem layout:
#   /n/llm/
#       new              read: allocates session N, returns "N\n"
#       N/               per-session directory
#           ask          rw: write prompt, read response (blocks until done)
#           stream       r:  blocking reads return chunks during generation
#           model        rw: model name (aliases: haiku/sonnet/opus)
#           temperature  rw: float 0.0-2.0
#           system       rw: system prompt
#           thinking     rw: "disabled" / "max" / integer
#           prefill      rw: assistant response prefill
#           tools        w:  write JSON tool definitions
#           context      r:  JSON conversation history
#           compact      rw: write to trigger compaction
#           ctl          w:  "reset" or "close"
#           usage        r:  "estimated_tokens/context_limit\n"
#
# Usage:
#   llmsrv                                    # mount at /n/llm (Anthropic API)
#   llmsrv -b openai -u http://host:11434/v1  # Ollama backend
#   llmsrv -m /mnt/llm                        # custom mount point
#   llmsrv -D                                 # debug tracing
#
# Example session:
#   id=`{cat /n/llm/new}
#   echo 'What is 2+2?' > /n/llm/$id/ask
#   cat /n/llm/$id/ask
#

include "sys.m";
	sys: Sys;
	Qid: import Sys;

include "draw.m";

include "arg.m";

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

include "styxservers.m";
	styxservers: Styxservers;
	Fid, Styxserver, Navigator, Navop: import styxservers;
	Enotfound, Eperm, Ebadarg: import styxservers;

include "string.m";
	str: String;

include "json.m";
	json: JSON;
	JValue: import json;

include "bufio.m";
	bufio: Bufio;

include "llmclient.m";
	llmclient: Llmclient;
	LlmMessage, ToolDef, ToolResult, AskRequest, AskResponse: import llmclient;

Llmsrv: module {
	init: fn(nil: ref Draw->Context, nil: list of string);
};

# File types (low byte of qid path)
Qroot:    con 0;
Qnew:     con 1;
# Per-session files start at 16
Qsessdir: con 16;
Qask:     con 17;
Qstream:  con 18;
Qmodel:   con 19;
Qtemp:    con 20;
Qsystem:  con 21;
Qthinking:con 22;
Qprefill: con 23;
Qtools:   con 24;
Qcontext: con 25;
Qcompact: con 26;
Qctl:     con 27;
Qusage:   con 28;

NSESSFILES: con 12;  # number of files per session dir

# Session state
LlmSession: adt {
	id:             int;
	messages:       list of ref LlmMessage;
	lastresponse:   string;
	totaltokens:    int;

	# Per-session settings
	model:          string;
	temperature:    real;
	systemprompt:   string;
	thinkingtokens: int;
	prefill:        string;
	tools:          list of ref ToolDef;

	# Streaming state
	streamch:       chan of string;  # nil when idle
	donech:         chan of int;     # signaled when gen completes
	genactive:      int;            # 1 during generation

	# Session lifecycle
	closed:         int;
	refs:           int;
};

stderr: ref Sys->FD;
user: string;
vers: int;

# Session pool
sessions: array of ref LlmSession;
nsessions: int;
nextsid: int;

# Backend configuration
backend: string;      # "api" or "openai"
apikey: string;
apiurl: string;       # Anthropic: hostname; OpenAI: base URL
defaultmodel: string;

# Completion notification for async ask reads
# When ask read arrives during generation, we spawn a goroutine
# that waits on donech then replies.

usage()
{
	sys->fprint(stderr, "Usage: llmsrv [-D] [-m mountpt] [-b api|openai] [-u url] [-k key] [-M model]\n");
	raise "fail:usage";
}

nomod(s: string)
{
	sys->fprint(stderr, "llmsrv: can't load %s: %r\n", s);
	raise "fail:load";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);

	styx = load Styx Styx->PATH;
	if(styx == nil) nomod(Styx->PATH);
	styx->init();

	styxservers = load Styxservers Styxservers->PATH;
	if(styxservers == nil) nomod(Styxservers->PATH);
	styxservers->init(styx);

	str = load String String->PATH;
	if(str == nil) nomod(String->PATH);

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil) nomod(Bufio->PATH);

	json = load JSON JSON->PATH;
	if(json == nil) nomod(JSON->PATH);
	json->init(bufio);

	llmclient = load Llmclient Llmclient->PATH;
	if(llmclient == nil) nomod(Llmclient->PATH);
	llmclient->init();

	arg := load Arg Arg->PATH;
	if(arg == nil) nomod(Arg->PATH);
	arg->init(args);

	mountpt := "/n/llm";
	backend = "api";
	apiurl = "";
	apikey = "";
	defaultmodel = "claude-sonnet-4-5-20250929";

	while((o := arg->opt()) != 0)
		case o {
		'D' => styxservers->traceset(1);
		'm' => mountpt = arg->earg();
		'b' => backend = arg->earg();
		'u' => apiurl = arg->earg();
		'k' => apikey = arg->earg();
		'M' => defaultmodel = arg->earg();
		* =>   usage();
		}
	arg = nil;

	# Read API key from environment if not provided
	if(apikey == "" && backend == "api") {
		apikey = readenv("ANTHROPIC_API_KEY");
		if(apikey == "") {
			sys->fprint(stderr, "llmsrv: ANTHROPIC_API_KEY not set\n");
			raise "fail:apikey";
		}
	}
	if(apikey == "" && backend == "openai")
		apikey = readenv("OPENAI_API_KEY");

	# Initialize pools
	sessions = array[16] of ref LlmSession;
	nsessions = 0;
	nextsid = 0;
	vers = 0;

	sys->pctl(Sys->FORKFD, nil);

	user = rf("/dev/user");
	if(user == nil)
		user = "inferno";

	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0) {
		sys->fprint(stderr, "llmsrv: can't create pipe: %r\n");
		raise "fail:pipe";
	}

	navops := chan of ref Navop;
	spawn navigator(navops);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big Qroot);
	fds[0] = nil;

	pidc := chan of int;
	spawn serveloop(tchan, srv, pidc, navops);
	<-pidc;

	ensuredir(mountpt);

	if(sys->mount(fds[1], nil, mountpt, Sys->MREPL|Sys->MCREATE, nil) < 0) {
		sys->fprint(stderr, "llmsrv: mount failed: %r\n");
		raise "fail:mount";
	}
}

# --- QID encoding ---

MKPATH(id, filetype: int): big
{
	return big ((id << 8) | filetype);
}

SESSID(path: big): int
{
	return (int path >> 8) & 16rFFFFFF;
}

FTYPE(path: big): int
{
	return int path & 16rFF;
}

# --- Session management ---

newsession(): ref LlmSession
{
	id := nextsid++;
	s := ref LlmSession(
		id,
		nil,           # messages
		"",            # lastresponse
		0,             # totaltokens
		defaultmodel,  # model
		0.7,           # temperature
		"",            # systemprompt
		0,             # thinkingtokens
		"",            # prefill
		nil,           # tools
		nil,           # streamch
		nil,           # donech
		0,             # genactive
		0,             # closed
		1              # refs (starts at 1)
	);

	if(nsessions >= len sessions) {
		ns := array[len sessions * 2] of ref LlmSession;
		ns[0:] = sessions[0:nsessions];
		sessions = ns;
	}
	sessions[nsessions++] = s;
	vers++;
	return s;
}

findsession(id: int): ref LlmSession
{
	for(i := 0; i < nsessions; i++)
		if(sessions[i].id == id)
			return sessions[i];
	return nil;
}

freesession(id: int)
{
	for(i := 0; i < nsessions; i++) {
		if(sessions[i].id == id) {
			sessions[i:] = sessions[i+1:nsessions];
			nsessions--;
			sessions[nsessions] = nil;
			vers++;
			return;
		}
	}
}

resetsession(sess: ref LlmSession)
{
	sess.messages = nil;
	sess.lastresponse = "";
	sess.totaltokens = 0;
}

closesession(sess: ref LlmSession)
{
	sess.closed = 1;
	freesession(sess.id);
}

# --- Model aliases ---

resolvemodel(name: string): string
{
	lname := str->tolower(name);
	case lname {
	"haiku" =>  return "claude-haiku-4-5-20251001";
	"sonnet" => return "claude-sonnet-4-5-20250929";
	"opus" =>   return "claude-opus-4-5-20251101";
	}
	return name;
}

# --- Token estimation ---

estimatedtokens(sess: ref LlmSession): int
{
	total := 0;
	for(ml := sess.messages; ml != nil; ml = tl ml) {
		m := hd ml;
		total += len m.content / 4;
	}
	return total;
}

CONTEXTLIMIT: con 200000;

# --- Backend call ---

callbackend(req: ref AskRequest): (ref AskResponse, string)
{
	if(backend == "openai")
		return llmclient->askopenai(apiurl, apikey, req);
	return llmclient->askanthropic(apikey, apiurl, req);
}

# --- Error classification ---

iscontentfiltererror(err: string): int
{
	return hasprefix(err, "content filtering") || contains(err, "content filtering policy");
}

istooluseerror(err: string): int
{
	return contains(err, "tool_use") && contains(err, "tool_result");
}

# --- Serve loop ---

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver,
	pidc: chan of int, navops: chan of ref Navop)
{
	pidc <-= sys->pctl(Sys->FORKNS|Sys->NEWFD, 1::2::srv.fd.fd::nil);

Serve:
	while((gm := <-tchan) != nil) {
		pick m := gm {
		Readerror =>
			sys->fprint(stderr, "llmsrv: fatal read error: %s\n", m.error);
			break Serve;

		Open =>
			c := srv.getfid(m.fid);
			if(c == nil) {
				srv.open(m);
				break;
			}

			mode := styxservers->openmode(m.mode);
			if(mode < 0) {
				srv.reply(ref Rmsg.Error(m.tag, Ebadarg));
				break;
			}

			qid := Qid(c.path, 0, c.qtype);
			c.open(mode, qid);
			srv.reply(ref Rmsg.Open(m.tag, qid, srv.iounit()));

		Read =>
			(c, err) := srv.canread(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, err));
				break;
			}

			if(c.qtype & Sys->QTDIR) {
				srv.read(m);
				break;
			}

			ft := FTYPE(c.path);
			sid := SESSID(c.path);

			case ft {
			Qnew =>
				sess := newsession();
				data := array of byte (string sess.id + "\n");
				srv.reply(styxservers->readbytes(m, data));

			Qask =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				if(sess.genactive) {
					# Block until generation completes, then reply
					spawn asyncaskread(srv, m, sess);
				} else {
					content := sess.lastresponse;
					if(content != "" && content[len content - 1] != '\n')
						content += "\n";
					srv.reply(styxservers->readbytes(m, array of byte content));
				}

			Qstream =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				# Spawn async reader that blocks on stream channel
				spawn asyncstreamread(srv, m, sess);

			Qmodel =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				srv.reply(styxservers->readbytes(m, array of byte (sess.model + "\n")));

			Qtemp =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				srv.reply(styxservers->readbytes(m, array of byte sys->sprint("%.2f\n", sess.temperature)));

			Qsystem =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				content := sess.systemprompt;
				if(content != "" && content[len content - 1] != '\n')
					content += "\n";
				srv.reply(styxservers->readbytes(m, array of byte content));

			Qthinking =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				content: string;
				if(sess.thinkingtokens < 0)
					content = "max\n";
				else if(sess.thinkingtokens == 0)
					content = "disabled\n";
				else
					content = string sess.thinkingtokens + "\n";
				srv.reply(styxservers->readbytes(m, array of byte content));

			Qprefill =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				content := sess.prefill;
				if(content != "" && content[len content - 1] != '\n')
					content += "\n";
				srv.reply(styxservers->readbytes(m, array of byte content));

			Qcontext =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				content := llmclient->messagesjson(sess.messages) + "\n";
				srv.reply(styxservers->readbytes(m, array of byte content));

			Qcompact =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				srv.reply(styxservers->readbytes(m, array of byte "write to compact conversation\n"));

			Qctl =>
				# Write-only file
				srv.reply(styxservers->readbytes(m, nil));

			Qusage =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				estimated := estimatedtokens(sess);
				content := sys->sprint("%d/%d\n", estimated, CONTEXTLIMIT);
				srv.reply(styxservers->readbytes(m, array of byte content));

			Qtools =>
				# Write-only
				srv.reply(styxservers->readbytes(m, nil));

			* =>
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
			}

		Write =>
			(c, merr) := srv.canwrite(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, merr));
				break;
			}

			ft := FTYPE(c.path);
			sid := SESSID(c.path);

			case ft {
			Qask =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				if(sess.closed) {
					srv.reply(ref Rmsg.Error(m.tag, Eperm));
					break;
				}
				prompt := strip(string m.data);
				if(prompt == "") {
					srv.reply(ref Rmsg.Write(m.tag, len m.data));
					break;
				}
				# Begin generation: allocate channels before spawning
				sess.streamch = chan[256] of string;
				sess.donech = chan of int;
				sess.genactive = 1;
				# Spawn async generation, reply to write immediately
				spawn asyncgen(srv, m.tag, len m.data, sess, prompt);

			Qmodel =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				model := resolvemodel(strip(string m.data));
				if(model != "")
					sess.model = model;
				srv.reply(ref Rmsg.Write(m.tag, len m.data));

			Qtemp =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				tstr := strip(string m.data);
				temp := parsefloat(tstr);
				if(temp < 0.0 || temp > 2.0) {
					srv.reply(ref Rmsg.Error(m.tag, "temperature must be between 0.0 and 2.0"));
					break;
				}
				sess.temperature = temp;
				srv.reply(ref Rmsg.Write(m.tag, len m.data));

			Qsystem =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				sess.systemprompt = strip(string m.data);
				srv.reply(ref Rmsg.Write(m.tag, len m.data));

			Qthinking =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				value := strip(string m.data);
				case value {
				"max" or "-1" =>
					sess.thinkingtokens = -1;
				"disabled" or "off" or "0" =>
					sess.thinkingtokens = 0;
				* =>
					n := strtoint(value);
					if(n < 0) {
						srv.reply(ref Rmsg.Error(m.tag, "invalid thinking budget"));
						break;
					}
					sess.thinkingtokens = n;
				}
				srv.reply(ref Rmsg.Write(m.tag, len m.data));

			Qprefill =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				# Don't strip — prefill may have intentional trailing space
				# But remove trailing newline since shell adds it
				pf := string m.data;
				if(len pf > 0 && pf[len pf - 1] == '\n')
					pf = pf[:len pf - 1];
				sess.prefill = pf;
				srv.reply(ref Rmsg.Write(m.tag, len m.data));

			Qtools =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				content := strip(string m.data);
				if(content == "") {
					# Clear tools
					sess.tools = nil;
					srv.reply(ref Rmsg.Write(m.tag, len m.data));
					break;
				}
				(tools, terr) := parsetooldefs(content);
				if(terr != nil) {
					srv.reply(ref Rmsg.Error(m.tag, "tools: " + terr));
					break;
				}
				sess.tools = tools;
				srv.reply(ref Rmsg.Write(m.tag, len m.data));

			Qcompact =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				spawn asynccompact(srv, m.tag, len m.data, sess);

			Qctl =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				cmd := strip(string m.data);
				case cmd {
				"reset" =>
					resetsession(sess);
					srv.reply(ref Rmsg.Write(m.tag, len m.data));
				"close" =>
					closesession(sess);
					srv.reply(ref Rmsg.Write(m.tag, len m.data));
				* =>
					srv.reply(ref Rmsg.Error(m.tag, "unknown command: " + cmd));
				}

			* =>
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
			}

		Clunk =>
			srv.clunk(m);

		Remove =>
			srv.remove(m);

		* =>
			srv.default(gm);
		}
	}
	navops <-= nil;
}

# --- Async generation goroutine ---

asyncgen(srv: ref Styxserver, writetag: int, writelen: int,
	sess: ref LlmSession, prompt: string)
{
	# Reply to the write immediately
	srv.reply(ref Rmsg.Write(writetag, writelen));

	# Check for TOOL_RESULTS
	if(hasprefix(prompt, "TOOL_RESULTS\n") || hasprefix(prompt, "TOOL_RESULTS\r\n")) {
		(results, perr) := llmclient->parsetoolresults(prompt);
		if(perr != nil) {
			sess.lastresponse = "Error: " + perr;
			endgeneration(sess);
			return;
		}
		askwithtoolresults(sess, results);
		endgeneration(sess);
		return;
	}

	# Normal prompt
	askprompt(sess, prompt);
	endgeneration(sess);
}

askprompt(sess: ref LlmSession, prompt: string)
{
	req := ref AskRequest(
		sess.messages,    # messages
		prompt,           # prompt
		sess.model,       # model
		sess.temperature, # temperature
		sess.systemprompt,# systemprompt
		sess.thinkingtokens, # thinkingtokens
		sess.prefill,     # prefill
		sess.tools,       # tooldefs
		nil,              # toolresults
		sess.streamch     # streamch
	);

	(resp, err) := callbackend(req);
	if(err != nil) {
		# Error recovery
		if(iscontentfiltererror(err) || istooluseerror(err)) {
			# Reset and retry
			sess.messages = nil;
			req.messages = nil;
			(resp, err) = callbackend(req);
			if(err != nil) {
				sess.lastresponse = "Error: " + err;
				return;
			}
		} else {
			sess.lastresponse = "Error: " + err;
			return;
		}
	}

	# Update session state
	textcontent := llmclient->extracttextcontent(resp.response);
	sess.messages = addmessage(sess.messages, "user", prompt, "");
	sess.messages = addmessage(sess.messages, "assistant", textcontent, resp.structuredjson);
	sess.totaltokens += resp.tokens;
	sess.lastresponse = resp.response;
}

askwithtoolresults(sess: ref LlmSession, results: list of ref ToolResult)
{
	# Record tool results in history BEFORE API call
	toolresultstext := "tool results submitted";
	toolresultsjson := buildtoolresultsjson(results);
	sess.messages = addmessage(sess.messages, "user", toolresultstext, toolresultsjson);

	req := ref AskRequest(
		sess.messages,    # messages
		"",               # prompt (empty for tool results)
		sess.model,       # model
		sess.temperature, # temperature
		sess.systemprompt,# systemprompt
		sess.thinkingtokens, # thinkingtokens
		"",               # prefill (empty mid-tool-loop)
		sess.tools,       # tooldefs
		results,          # toolresults
		sess.streamch     # streamch
	);

	(resp, err) := callbackend(req);
	if(err != nil) {
		if(iscontentfiltererror(err)) {
			sess.messages = nil;
			synthetic := "STOP:end_turn\nContent filtering policy blocked a tool result. Session history reset.";
			sess.lastresponse = synthetic;
			return;
		}
		# Add synthetic assistant error to keep role alternation valid
		errmsg := "Error: " + err;
		sess.messages = addmessage(sess.messages, "assistant", errmsg, "");
		sess.lastresponse = errmsg;
		return;
	}

	textcontent := llmclient->extracttextcontent(resp.response);
	sess.messages = addmessage(sess.messages, "assistant", textcontent, resp.structuredjson);
	sess.totaltokens += resp.tokens;
	sess.lastresponse = resp.response;
}

endgeneration(sess: ref LlmSession)
{
	ch := sess.streamch;
	done := sess.donech;
	# Do NOT nil streamch — leave closed channel readable for late readers
	sess.donech = nil;
	sess.genactive = 0;
	if(ch != nil) {
		# Close the channel by sending a nil sentinel
		# In Limbo, we can't close channels, so we send empty string as EOF marker
		# Actually, Limbo channels can't be "closed" like Go.
		# Convention: send nil/empty as EOF marker, then nil the channel after done signal
		alt {
			ch <-= "" => ;
			* => ;
		}
	}
	if(done != nil)
		done <-= 0;
}

# --- Async blocking reads ---

asyncaskread(srv: ref Styxserver, m: ref Tmsg.Read, sess: ref LlmSession)
{
	# Block until generation completes
	donech := sess.donech;
	if(donech != nil)
		<-donech;

	content := sess.lastresponse;
	if(content != "" && content[len content - 1] != '\n')
		content += "\n";

	srv.reply(styxservers->readbytes(m, array of byte content));
}

asyncstreamread(srv: ref Styxserver, m: ref Tmsg.Read, sess: ref LlmSession)
{
	ch := sess.streamch;
	if(ch == nil) {
		# No active generation — EOF
		srv.reply(styxservers->readbytes(m, nil));
		return;
	}

	chunk := <-ch;
	if(chunk == nil || chunk == "") {
		# Channel "closed" (EOF sentinel)
		srv.reply(styxservers->readbytes(m, nil));
		return;
	}

	srv.reply(styxservers->readbytes(m, array of byte chunk));
}

# --- Async compaction ---

asynccompact(srv: ref Styxserver, tag: int, count: int, sess: ref LlmSession)
{
	# Count messages
	nmsg := 0;
	for(ml := sess.messages; ml != nil; ml = tl ml)
		nmsg++;

	if(nmsg < 4) {
		srv.reply(ref Rmsg.Write(tag, count));
		return;
	}

	# Build conversation text for summarization
	convtext := "";
	for(ml = sess.messages; ml != nil; ml = tl ml) {
		m := hd ml;
		if(m.role == "system")
			continue;
		convtext += m.role + ": " + m.content + "\n\n";
	}

	req := ref AskRequest(
		nil,       # messages
		"Summarize this conversation concisely, preserving key facts, decisions, file paths, code snippets, and all context needed to continue the work:\n\n" + convtext,
		sess.model,
		0.3,       # low temperature for summarization
		"",        # no system prompt
		0,         # no thinking
		"",        # no prefill
		nil,       # no tools
		nil,       # no tool results
		nil        # no streaming
	);

	(resp, err) := callbackend(req);
	if(err != nil) {
		srv.reply(ref Rmsg.Error(tag, "compact: " + err));
		return;
	}

	# Replace history with compact summary
	sess.messages = nil;
	sess.messages = addmessage(sess.messages, "user",
		"Context from earlier in this session:\n" + resp.response, "");
	sess.messages = addmessage(sess.messages, "assistant",
		"Understood. I have the context from our previous work and will continue from there.", "");
	sess.totaltokens = resp.tokens;

	srv.reply(ref Rmsg.Write(tag, count));
}

# --- Tool definition parsing ---

parsetooldefs(content: string): (list of ref ToolDef, string)
{
	bio := bufio->aopen(array of byte content);
	if(bio == nil)
		return (nil, "cannot create buffer");
	(jv, jerr) := json->readjson(bio);
	if(jerr != nil)
		return (nil, "invalid JSON: " + jerr);

	tools: list of ref ToolDef;
	pick a := jv {
	Array =>
		for(i := len a.a - 1; i >= 0; i--) {
			td := a.a[i];
			name := "";
			desc := "";
			schema := "{}";
			nv := td.get("name");
			if(nv != nil) pick n := nv { String => name = n.s; }
			dv := td.get("description");
			if(dv != nil) pick d := dv { String => desc = d.s; }
			sv := td.get("input_schema");
			if(sv != nil)
				schema = sv.text();
			tools = ref ToolDef(name, desc, schema) :: tools;
		}
	* =>
		return (nil, "expected JSON array");
	}
	return (tools, nil);
}

# --- Tool results JSON builder ---

buildtoolresultsjson(results: list of ref ToolResult): string
{
	s := "[";
	first := 1;
	for(; results != nil; results = tl results) {
		r := hd results;
		if(!first)
			s += ",";
		first = 0;
		s += "{\"type\":\"tool_result\",\"tool_use_id\":" +
			llmclient->jsonescapestr("\"" + r.tooluseid + "\"") +
			",\"content\":" + jquote(r.content) + "}";
	}
	s += "]";
	return s;
}

# --- Directory generation ---

dir(qid: Sys->Qid, name: string, length: big, perm: int): ref Sys->Dir
{
	d := ref sys->zerodir;
	d.qid = qid;
	if(qid.qtype & Sys->QTDIR)
		perm |= Sys->DMDIR;
	d.mode = perm;
	d.name = name;
	d.uid = user;
	d.gid = user;
	d.length = length;
	return d;
}

dirgen(p: big): (ref Sys->Dir, string)
{
	ft := FTYPE(p);
	sid := SESSID(p);

	case ft {
	Qroot =>
		return (dir(Qid(p, vers, Sys->QTDIR), "/", big 0, 8r755), nil);
	Qnew =>
		return (dir(Qid(p, vers, Sys->QTFILE), "new", big 0, 8r444), nil);
	Qsessdir =>
		return (dir(Qid(p, vers, Sys->QTDIR), string sid, big 0, 8r755), nil);
	Qask =>
		return (dir(Qid(p, vers, Sys->QTFILE), "ask", big 0, 8r666), nil);
	Qstream =>
		return (dir(Qid(p, vers, Sys->QTFILE), "stream", big 0, 8r444), nil);
	Qmodel =>
		return (dir(Qid(p, vers, Sys->QTFILE), "model", big 0, 8r666), nil);
	Qtemp =>
		return (dir(Qid(p, vers, Sys->QTFILE), "temperature", big 0, 8r666), nil);
	Qsystem =>
		return (dir(Qid(p, vers, Sys->QTFILE), "system", big 0, 8r666), nil);
	Qthinking =>
		return (dir(Qid(p, vers, Sys->QTFILE), "thinking", big 0, 8r666), nil);
	Qprefill =>
		return (dir(Qid(p, vers, Sys->QTFILE), "prefill", big 0, 8r666), nil);
	Qtools =>
		return (dir(Qid(p, vers, Sys->QTFILE), "tools", big 0, 8r222), nil);
	Qcontext =>
		return (dir(Qid(p, vers, Sys->QTFILE), "context", big 0, 8r444), nil);
	Qcompact =>
		return (dir(Qid(p, vers, Sys->QTFILE), "compact", big 0, 8r644), nil);
	Qctl =>
		return (dir(Qid(p, vers, Sys->QTFILE), "ctl", big 0, 8r222), nil);
	Qusage =>
		return (dir(Qid(p, vers, Sys->QTFILE), "usage", big 0, 8r444), nil);
	}

	return (nil, Enotfound);
}

# --- Navigator ---

navigator(navops: chan of ref Navop)
{
	while((m := <-navops) != nil) {
		pick n := m {
		Stat =>
			n.reply <-= dirgen(n.path);

		Walk =>
			ft := FTYPE(n.path);
			sid := SESSID(n.path);

			case ft {
			Qroot =>
				case n.name {
				".." =>
					;  # stay at root
				"new" =>
					n.path = MKPATH(0, Qnew);
				* =>
					# Try as session ID
					id := strtoint(n.name);
					if(id >= 0 && findsession(id) != nil)
						n.path = MKPATH(id, Qsessdir);
					else {
						n.reply <-= (nil, Enotfound);
						continue;
					}
				}
				n.reply <-= dirgen(n.path);

			Qsessdir =>
				case n.name {
				".." =>
					n.path = big Qroot;
				"ask" =>
					n.path = MKPATH(sid, Qask);
				"stream" =>
					n.path = MKPATH(sid, Qstream);
				"model" =>
					n.path = MKPATH(sid, Qmodel);
				"temperature" =>
					n.path = MKPATH(sid, Qtemp);
				"system" =>
					n.path = MKPATH(sid, Qsystem);
				"thinking" =>
					n.path = MKPATH(sid, Qthinking);
				"prefill" =>
					n.path = MKPATH(sid, Qprefill);
				"tools" =>
					n.path = MKPATH(sid, Qtools);
				"context" =>
					n.path = MKPATH(sid, Qcontext);
				"compact" =>
					n.path = MKPATH(sid, Qcompact);
				"ctl" =>
					n.path = MKPATH(sid, Qctl);
				"usage" =>
					n.path = MKPATH(sid, Qusage);
				* =>
					n.reply <-= (nil, Enotfound);
					continue;
				}
				n.reply <-= dirgen(n.path);

			* =>
				# Files are not directories
				case n.name {
				".." =>
					if(ft >= Qsessdir)
						n.path = MKPATH(sid, Qsessdir);
					else
						n.path = big Qroot;
					n.reply <-= dirgen(n.path);
				* =>
					n.reply <-= (nil, "not a directory");
				}
			}

		Readdir =>
			ft := FTYPE(m.path);

			case ft {
			Qroot =>
				# Root: new + session directories
				entries: list of big;
				entries = MKPATH(0, Qnew) :: entries;
				for(i := 0; i < nsessions; i++)
					entries = MKPATH(sessions[i].id, Qsessdir) :: entries;

				# Reverse to preserve order
				rev: list of big;
				for(; entries != nil; entries = tl entries)
					rev = hd entries :: rev;
				entries = rev;

				i = 0;
				for(e := entries; e != nil; e = tl e) {
					if(i >= n.offset && n.count > 0) {
						n.reply <-= dirgen(hd e);
						n.count--;
					}
					i++;
				}
				n.reply <-= (nil, nil);

			Qsessdir =>
				sid := SESSID(m.path);
				files := array[] of {
					MKPATH(sid, Qask),
					MKPATH(sid, Qstream),
					MKPATH(sid, Qmodel),
					MKPATH(sid, Qtemp),
					MKPATH(sid, Qsystem),
					MKPATH(sid, Qthinking),
					MKPATH(sid, Qprefill),
					MKPATH(sid, Qtools),
					MKPATH(sid, Qcontext),
					MKPATH(sid, Qcompact),
					MKPATH(sid, Qctl),
					MKPATH(sid, Qusage),
				};
				i := n.offset;
				for(; i < len files && n.count > 0; i++) {
					n.reply <-= dirgen(files[i]);
					n.count--;
				}
				n.reply <-= (nil, nil);

			* =>
				n.reply <-= (nil, "not a directory");
			}
		}
	}
}

# --- Message list helpers ---

addmessage(msgs: list of ref LlmMessage, role, content, sc: string): list of ref LlmMessage
{
	# Append to end by reversing, prepending, reversing
	rev: list of ref LlmMessage;
	for(ml := msgs; ml != nil; ml = tl ml)
		rev = hd ml :: rev;
	rev = ref LlmMessage(role, content, sc) :: rev;
	result: list of ref LlmMessage;
	for(; rev != nil; rev = tl rev)
		result = hd rev :: result;
	return result;
}

# --- Helpers ---

ensuredir(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil)
		return;

	for(i := len path - 1; i > 0; i--) {
		if(path[i] == '/') {
			ensuredir(path[0:i]);
			break;
		}
	}

	fd = sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
	if(fd == nil)
		sys->fprint(stderr, "llmsrv: cannot create directory %s: %r\n", path);
}

rf(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return nil;
	b := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, b, len b);
	if(n < 0)
		return nil;
	return string b[0:n];
}

readenv(name: string): string
{
	s := rf("/env/" + name);
	if(s != nil)
		s = strip(s);
	return s;
}

strtoint(s: string): int
{
	n := 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c < '0' || c > '9')
			return -1;
		n = n * 10 + (c - '0');
	}
	if(len s == 0)
		return -1;
	return n;
}

parsefloat(s: string): real
{
	# Simple float parser for "N.NN" format
	neg := 0;
	i := 0;
	if(i < len s && s[i] == '-') {
		neg = 1;
		i++;
	}
	whole := 0.0;
	for(; i < len s && s[i] >= '0' && s[i] <= '9'; i++)
		whole = whole * 10.0 + real(s[i] - '0');

	frac := 0.0;
	if(i < len s && s[i] == '.') {
		i++;
		div := 10.0;
		for(; i < len s && s[i] >= '0' && s[i] <= '9'; i++) {
			frac += real(s[i] - '0') / div;
			div *= 10.0;
		}
	}
	result := whole + frac;
	if(neg)
		result = -result;
	return result;
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

contains(s, sub: string): int
{
	if(len sub > len s)
		return 0;
	for(i := 0; i <= len s - len sub; i++)
		if(s[i:i+len sub] == sub)
			return 1;
	return 0;
}

strip(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n' || s[j-1] == '\r'))
		j--;
	if(i >= j)
		return "";
	return s[i:j];
}

jquote(s: string): string
{
	return "\"" + llmclient->jsonescapestr(s) + "\"";
}
