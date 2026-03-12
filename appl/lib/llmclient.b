implement Llmclient;

#
# llmclient - LLM API client library
#
# HTTP-based access to LLM APIs with streaming SSE support.
# Supports Anthropic Messages API and OpenAI-compatible Chat Completions API.
#
# No external dependencies beyond Inferno stdlib + json module.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "tls.m";
	tlsmod: TLS;
	Conn: import tlsmod;

include "json.m";
	json: JSON;
	JValue: import json;

include "llmclient.m";

stderr: ref Sys->FD;

init()
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	str = load String String->PATH;
	if(str == nil)
		raise "fail:llmclient: cannot load String";

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		raise "fail:llmclient: cannot load Bufio";

	json = load JSON JSON->PATH;
	if(json == nil)
		raise "fail:llmclient: cannot load JSON";
	json->init(bufio);
}

# ==================== Anthropic Messages API ====================

askanthropic(apikey, apiurl: string, req: ref AskRequest): (ref AskResponse, string)
{
	if(apiurl == nil || apiurl == "")
		apiurl = "api.anthropic.com";

	body := buildanthropicrequest(req);

	headers := "Content-Type: application/json\r\n" +
		"x-api-key: " + apikey + "\r\n" +
		"anthropic-version: 2023-06-01\r\n";

	if(req.streamch != nil)
		headers += "Accept: text/event-stream\r\n";

	(respbody, err) := httpspost(apiurl, "443", "/v1/messages", headers, body);
	if(err != nil)
		return (nil, "anthropic: " + err);

	if(req.streamch != nil)
		return parseanthropicsse(respbody, req);

	return parseanthropicresponse(respbody, req);
}

buildanthropicrequest(req: ref AskRequest): string
{
	s := "{";
	s += "\"model\":" + jquote(req.model) + ",";
	s += "\"max_tokens\":4096,";
	s += sys->sprint("\"temperature\":%.2f", req.temperature);

	# System prompt
	if(req.systemprompt != "")
		s += ",\"system\":[{\"type\":\"text\",\"text\":" + jquote(req.systemprompt) + "}]";

	# Stream flag
	if(req.streamch != nil)
		s += ",\"stream\":true";

	# Messages
	s += ",\"messages\":[";
	first := 1;
	for(ml := req.messages; ml != nil; ml = tl ml) {
		m := hd ml;
		if(m.role == "system")
			continue;
		if(!first)
			s += ",";
		first = 0;
		s += buildanthropicmessage(m);
	}

	# Add new prompt or tool results
	if(req.toolresults != nil) {
		if(!first)
			s += ",";
		s += buildtoolresultsmessage(req.toolresults);
	} else if(req.prompt != "") {
		if(!first)
			s += ",";
		s += "{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":" + jquote(req.prompt) + "}]}";
	}

	# Add prefill (only when no tools)
	if(req.prefill != "" && req.tooldefs == nil) {
		s += ",{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":" + jquote(req.prefill) + "}]}";
	}

	s += "]";

	# Tool definitions
	if(req.tooldefs != nil) {
		s += ",\"tools\":[";
		tfirst := 1;
		for(tl2 := req.tooldefs; tl2 != nil; tl2 = tl tl2) {
			td := hd tl2;
			if(!tfirst)
				s += ",";
			tfirst = 0;
			s += "{\"name\":" + jquote(td.name) +
				",\"description\":" + jquote(td.description) +
				",\"input_schema\":" + td.inputschema + "}";
		}
		s += "],\"tool_choice\":{\"type\":\"auto\"}";
	}

	s += "}";
	return s;
}

buildanthropicmessage(m: ref LlmMessage): string
{
	role := m.role;

	# If structured content exists, use it directly
	if(m.sc != "") {
		return "{\"role\":" + jquote(role) + ",\"content\":" + m.sc + "}";
	}

	# Plain text message — guard against empty text blocks
	content := m.content;
	if(content == "")
		content = "...";

	return "{\"role\":" + jquote(role) + ",\"content\":[{\"type\":\"text\",\"text\":" + jquote(content) + "}]}";
}

buildtoolresultsmessage(results: list of ref ToolResult): string
{
	s := "{\"role\":\"user\",\"content\":[";
	first := 1;
	for(; results != nil; results = tl results) {
		r := hd results;
		if(!first)
			s += ",";
		first = 0;
		s += "{\"type\":\"tool_result\",\"tool_use_id\":" + jquote(r.tooluseid) +
			",\"content\":" + jquote(r.content) + "}";
	}
	s += "]}";
	return s;
}

parseanthropicresponse(body: string, req: ref AskRequest): (ref AskResponse, string)
{
	(jv, jerr) := readjsonstring(body);
	if(jerr != nil)
		return (nil, "anthropic: parse error: " + jerr);

	# Check for error response
	errv := jv.get("error");
	if(errv != nil) {
		emsg := jv.get("error").get("message");
		if(emsg != nil) {
			pick em := emsg {
			String => return (nil, em.s);
			}
		}
		return (nil, "anthropic: API error");
	}

	# Extract tokens
	tokens := 0;
	usage := jv.get("usage");
	if(usage != nil) {
		itok := usage.get("input_tokens");
		otok := usage.get("output_tokens");
		if(itok != nil) pick iv := itok { Int => tokens += int iv.value; }
		if(otok != nil) pick ov := otok { Int => tokens += int ov.value; }
	}

	# Extract content blocks
	content := jv.get("content");
	if(content == nil)
		return (nil, "anthropic: no content in response");

	textparts: list of string;
	toollines: list of string;
	structblocks: list of string;
	stopreason := "";

	srv := jv.get("stop_reason");
	if(srv != nil) pick sr := srv { String => stopreason = sr.s; }

	pick ca := content {
	Array =>
		for(i := 0; i < len ca.a; i++) {
			block := ca.a[i];
			typev := block.get("type");
			if(typev == nil)
				continue;
			typestr := "";
			pick tv := typev { String => typestr = tv.s; }

			case typestr {
			"text" =>
				textv := block.get("text");
				if(textv != nil) {
					pick tv := textv {
					String =>
						if(tv.s != "") {
							textparts = tv.s :: textparts;
							structblocks = ("{\"type\":\"text\",\"text\":" + jquote(tv.s) + "}") :: structblocks;
						}
					}
				}
			"tool_use" =>
				idv := block.get("id");
				namev := block.get("name");
				inputv := block.get("input");
				id := "";
				name := "";
				inputjson := "{}";
				if(idv != nil) pick iv := idv { String => id = iv.s; }
				if(namev != nil) pick nv := namev { String => name = nv.s; }
				if(inputv != nil)
					inputjson = inputv.text();
				args := extracttoolargs(inputjson);
				safeargs := replaceall(args, "\n", "\\n");
				toollines = sys->sprint("TOOL:%s:%s:%s", id, name, safeargs) :: toollines;
				structblocks = ("{\"type\":\"tool_use\",\"id\":" + jquote(id) +
					",\"name\":" + jquote(name) +
					",\"input\":" + inputjson + "}") :: structblocks;
			}
		}
	}

	# No tools defined — plain text mode
	if(req.tooldefs == nil) {
		text := joinrev(textparts, "");
		if(req.prefill != "" && !hasprefix(text, req.prefill))
			text = req.prefill + text;
		return (ref AskResponse(text, "", tokens), nil);
	}

	# Tool mode — build STOP: response
	structjson := "";
	if(structblocks != nil)
		structjson = "[" + joinrev(structblocks, ",") + "]";

	response := "";
	if(stopreason == "tool_use")
		response = "STOP:tool_use\n";
	else
		response = "STOP:end_turn\n";
	response += joinrev(toollines, "\n");
	if(toollines != nil)
		response += "\n";
	response += joinrev(textparts, "");

	return (ref AskResponse(response, structjson, tokens), nil);
}

parseanthropicsse(body: string, req: ref AskRequest): (ref AskResponse, string)
{
	# The body was received in full from httpspost.
	# Parse SSE events from it line by line.
	# For true streaming over TLS, we'd need to read incrementally,
	# but httpspost reads to completion. The streaming chunks are still
	# sent to req.streamch for the Styx stream file.

	fulltext := "";
	toollines: list of string;
	structblocks: list of string;
	tokens := 0;
	stopreason := "";

	lines := splitlines(body);
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		if(line == "" || line == "\r")
			continue;
		if(!hasprefix(line, "data: "))
			continue;
		data := line[6:];
		if(data == "[DONE]")
			break;

		(jv, jerr) := readjsonstring(data);
		if(jerr != nil)
			continue;

		typev := jv.get("type");
		if(typev == nil)
			continue;
		typestr := "";
		pick tv := typev { String => typestr = tv.s; }

		case typestr {
		"content_block_delta" =>
			delta := jv.get("delta");
			if(delta == nil)
				continue;
			dtv := delta.get("type");
			if(dtv == nil)
				continue;
			dtypestr := "";
			pick dtval := dtv { String => dtypestr = dtval.s; }
			if(dtypestr == "text_delta") {
				textv := delta.get("text");
				if(textv != nil) {
					pick tv := textv {
					String =>
						fulltext += tv.s;
						if(req.streamch != nil) {
							alt {
								req.streamch <-= tv.s => ;
								* => ;  # drop if full
							}
						}
					}
				}
			}
		"message_delta" =>
			usagev := jv.get("usage");
			if(usagev != nil) {
				otv := usagev.get("output_tokens");
				if(otv != nil) pick ov := otv { Int => tokens += int ov.value; }
			}
			srv := jv.get("delta");
			if(srv != nil) {
				srr := srv.get("stop_reason");
				if(srr != nil) pick sr := srr { String => stopreason = sr.s; }
			}
		"message_start" =>
			msgv := jv.get("message");
			if(msgv != nil) {
				usagev := msgv.get("usage");
				if(usagev != nil) {
					itv := usagev.get("input_tokens");
					if(itv != nil) pick iv := itv { Int => tokens += int iv.value; }
				}
			}
		"content_block_start" =>
			cb := jv.get("content_block");
			if(cb != nil) {
				cbtv := cb.get("type");
				if(cbtv != nil) {
					cbtypestr := "";
					pick ct := cbtv { String => cbtypestr = ct.s; }
					if(cbtypestr == "tool_use") {
						idv := cb.get("id");
						namev := cb.get("name");
						id := "";
						name := "";
						if(idv != nil) pick iv := idv { String => id = iv.s; }
						if(namev != nil) pick nv := namev { String => name = nv.s; }
						# Tool input arrives in content_block_delta events
						# For now capture the tool metadata
						toollines = sys->sprint("TOOL:%s:%s:{}", id, name) :: toollines;
						structblocks = ("{\"type\":\"tool_use\",\"id\":" + jquote(id) +
							",\"name\":" + jquote(name) +
							",\"input\":{}}") :: structblocks;
					}
				}
			}
		}
	}

	# Build response
	if(req.tooldefs == nil) {
		if(req.prefill != "" && !hasprefix(fulltext, req.prefill))
			fulltext = req.prefill + fulltext;
		return (ref AskResponse(fulltext, "", tokens), nil);
	}

	if(fulltext != "") {
		structblocks = ("{\"type\":\"text\",\"text\":" + jquote(fulltext) + "}") :: structblocks;
	}

	structjson := "";
	if(structblocks != nil)
		structjson = "[" + joinrev(structblocks, ",") + "]";

	response := "";
	if(stopreason == "tool_use")
		response = "STOP:tool_use\n";
	else
		response = "STOP:end_turn\n";
	response += joinrev(toollines, "\n");
	if(toollines != nil)
		response += "\n";
	response += fulltext;

	return (ref AskResponse(response, structjson, tokens), nil);
}

# ==================== OpenAI-Compatible API ====================

askopenai(baseurl, apikey: string, req: ref AskRequest): (ref AskResponse, string)
{
	if(baseurl == nil || baseurl == "")
		baseurl = "http://localhost:11434/v1";

	body := buildopenairequestjson(req);

	# Parse URL to determine http vs https, host, port, path
	(scheme, host, port, path, uerr) := parseurl(baseurl + "/chat/completions");
	if(uerr != nil)
		return (nil, "openai: " + uerr);

	headers := "Content-Type: application/json\r\n";
	if(apikey != nil && apikey != "" && apikey != "not-needed")
		headers += "Authorization: Bearer " + apikey + "\r\n";

	respbody: string;
	err: string;

	if(scheme == "https")
		(respbody, err) = httpspost(host, port, path, headers, body);
	else
		(respbody, err) = httppost(host, port, path, headers, body);

	if(err != nil)
		return (nil, "openai: " + err);

	if(req.streamch != nil)
		return parseopenaisseresponse(respbody, req);

	return parseopenairesponse(respbody, req);
}

buildopenairequestjson(req: ref AskRequest): string
{
	s := "{";
	s += "\"model\":" + jquote(req.model) + ",";
	s += "\"max_tokens\":4096,";
	s += sys->sprint("\"temperature\":%.2f", req.temperature);

	# Stream
	if(req.streamch != nil)
		s += ",\"stream\":true,\"stream_options\":{\"include_usage\":true}";

	# Ollama thinking options
	s += ",\"options\":" + thinkoptions(req.thinkingtokens);

	# Messages
	s += ",\"messages\":[";
	first := 1;

	# System prompt
	if(req.systemprompt != "") {
		s += "{\"role\":\"system\",\"content\":" + jquote(req.systemprompt) + "}";
		first = 0;
	}

	# History (system messages merged into system prompt above)
	for(ml := req.messages; ml != nil; ml = tl ml) {
		m := hd ml;
		if(m.role == "system") {
			if(!first) s += ",";
			first = 0;
			s += "{\"role\":\"system\",\"content\":" + jquote(m.content) + "}";
			continue;
		}
		if(!first) s += ",";
		first = 0;
		if(m.sc != "")
			s += buildopenaitoolmessage(m);
		else
			s += "{\"role\":" + jquote(m.role) + ",\"content\":" + jquote(m.content) + "}";
	}

	# New prompt or tool results
	if(req.toolresults != nil) {
		for(trl := req.toolresults; trl != nil; trl = tl trl) {
			r := hd trl;
			if(!first) s += ",";
			first = 0;
			s += "{\"role\":\"tool\",\"content\":" + jquote(r.content) +
				",\"tool_call_id\":" + jquote(r.tooluseid) + "}";
		}
	} else if(req.prompt != "") {
		if(!first) s += ",";
		first = 0;
		s += "{\"role\":\"user\",\"content\":" + jquote(req.prompt) + "}";
	}

	s += "]";

	# Tool definitions
	if(req.tooldefs != nil) {
		s += ",\"tools\":[";
		tfirst := 1;
		for(tdl := req.tooldefs; tdl != nil; tdl = tl tdl) {
			td := hd tdl;
			if(!tfirst) s += ",";
			tfirst = 0;
			s += "{\"type\":\"function\",\"function\":{" +
				"\"name\":" + jquote(td.name) + "," +
				"\"description\":" + jquote(td.description) + "," +
				"\"parameters\":" + td.inputschema + "}}";
		}
		s += "],\"tool_choice\":\"auto\"";
	}

	s += "}";
	return s;
}

buildopenaitoolmessage(m: ref LlmMessage): string
{
	# Reconstruct assistant message with tool_calls from structured content
	(jv, jerr) := readjsonstring(m.sc);
	if(jerr != nil)
		return "{\"role\":\"assistant\",\"content\":" + jquote(m.content) + "}";

	content := "";
	toolcalls := "";
	tcfirst := 1;
	idx := 0;

	pick a := jv {
	Array =>
		for(i := 0; i < len a.a; i++) {
			block := a.a[i];
			typev := block.get("type");
			if(typev == nil) continue;
			typestr := "";
			pick tv := typev { String => typestr = tv.s; }

			case typestr {
			"text" =>
				textv := block.get("text");
				if(textv != nil) pick tv := textv { String => content += tv.s; }
			"tool_use" =>
				idv := block.get("id");
				namev := block.get("name");
				inputv := block.get("input");
				id := "";
				name := "";
				inputjson := "{}";
				if(idv != nil) pick iv := idv { String => id = iv.s; }
				if(namev != nil) pick nv := namev { String => name = nv.s; }
				if(inputv != nil) inputjson = inputv.text();

				if(!tcfirst) toolcalls += ",";
				tcfirst = 0;
				toolcalls += sys->sprint("{\"index\":%d,\"id\":%s,\"type\":\"function\",\"function\":{\"name\":%s,\"arguments\":%s}}",
					idx, jquote(id), jquote(name), jquote(inputjson));
				idx++;
			}
		}
	}

	s := "{\"role\":\"assistant\"";
	if(content != "")
		s += ",\"content\":" + jquote(content);
	else
		s += ",\"content\":\"\"";
	if(toolcalls != "")
		s += ",\"tool_calls\":[" + toolcalls + "]";
	s += "}";
	return s;
}

thinkoptions(tokens: int): string
{
	if(tokens == 0)
		return "{\"think\":false}";
	level := "high";
	if(tokens > 0 && tokens <= 10000)
		level = "low";
	else if(tokens > 0 && tokens <= 20000)
		level = "medium";
	return "{\"think\":true,\"think_level\":\"" + level + "\"}";
}

parseopenairesponse(body: string, req: ref AskRequest): (ref AskResponse, string)
{
	(jv, jerr) := readjsonstring(body);
	if(jerr != nil)
		return (nil, "openai: parse error: " + jerr);

	# Check for error
	errv := jv.get("error");
	if(errv != nil) {
		emsg := errv.get("message");
		if(emsg != nil) pick em := emsg { String => return (nil, em.s); }
		return (nil, "openai: API error");
	}

	# Extract tokens
	tokens := 0;
	usage := jv.get("usage");
	if(usage != nil) {
		tv := usage.get("total_tokens");
		if(tv != nil) pick t := tv { Int => tokens = int t.value; }
	}

	# Extract response
	choices := jv.get("choices");
	if(choices == nil)
		return (nil, "openai: no choices in response");

	responsetext := "";
	finishreason := "";
	toolcalls: list of (string, string, string);  # (id, name, args)

	pick ca := choices {
	Array =>
		if(len ca.a == 0)
			return (nil, "openai: empty choices");
		choice := ca.a[0];

		frv := choice.get("finish_reason");
		if(frv != nil) pick fr := frv { String => finishreason = fr.s; }

		msg := choice.get("message");
		if(msg != nil) {
			cv := msg.get("content");
			if(cv != nil) pick c := cv { String => responsetext = c.s; }

			tcv := msg.get("tool_calls");
			if(tcv != nil) {
				pick tca := tcv {
				Array =>
					for(i := 0; i < len tca.a; i++) {
						tc := tca.a[i];
						idv := tc.get("id");
						fnv := tc.get("function");
						id := "";
						name := "";
						args := "";
						if(idv != nil) pick iv := idv { String => id = iv.s; }
						if(fnv != nil) {
							nv := fnv.get("name");
							av := fnv.get("arguments");
							if(nv != nil) pick n := nv { String => name = n.s; }
							if(av != nil) pick a := av { String => args = a.s; }
						}
						toolcalls = (id, name, args) :: toolcalls;
					}
				}
			}
		}
	}

	if(tokens == 0)
		tokens = estimatetokens(responsetext);

	# Plain text mode
	if(req.tooldefs == nil) {
		if(req.prefill != "" && !hasprefix(responsetext, req.prefill))
			responsetext = req.prefill + responsetext;
		return (ref AskResponse(responsetext, "", tokens), nil);
	}

	# Tool mode — build STOP: response
	textparts: list of string;
	toolentries: list of string;
	structblocks: list of string;

	if(responsetext != "") {
		textparts = responsetext :: nil;
		structblocks = ("{\"type\":\"text\",\"text\":" + jquote(responsetext) + "}") :: structblocks;
	}

	# Reverse toolcalls to restore original order
	revtc: list of (string, string, string);
	for(; toolcalls != nil; toolcalls = tl toolcalls)
		revtc = hd toolcalls :: revtc;

	for(; revtc != nil; revtc = tl revtc) {
		(id, name, args) := hd revtc;
		safeargs := replaceall(args, "\n", "\\n");
		toolentries = sys->sprint("TOOL:%s:%s:%s", id, name, safeargs) :: toolentries;
		inputjson := args;
		if(inputjson == "")
			inputjson = "{}";
		structblocks = ("{\"type\":\"tool_use\",\"id\":" + jquote(id) +
			",\"name\":" + jquote(name) +
			",\"input\":" + inputjson + "}") :: structblocks;
	}

	structjson := "";
	if(structblocks != nil)
		structjson = "[" + joinrev(structblocks, ",") + "]";

	response := "";
	if(finishreason == "tool_calls")
		response = "STOP:tool_use\n";
	else
		response = "STOP:end_turn\n";
	response += joinrev(toolentries, "\n");
	if(toolentries != nil)
		response += "\n";
	response += joinrev(textparts, "");

	return (ref AskResponse(response, structjson, tokens), nil);
}

parseopenaisseresponse(body: string, req: ref AskRequest): (ref AskResponse, string)
{
	fulltext := "";
	tokens := 0;
	finishreason := "";

	# Tool call delta accumulation
	# Using parallel lists as maps (index → id, name, args)
	tcids: list of string;
	tcnames: list of string;
	tcargs: list of string;

	lines := splitlines(body);
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		line = stripnl(line);
		if(line == "")
			continue;
		if(!hasprefix(line, "data: "))
			continue;
		data := line[6:];
		if(data == "[DONE]")
			break;

		(jv, jerr) := readjsonstring(data);
		if(jerr != nil)
			continue;

		# Usage
		usagev := jv.get("usage");
		if(usagev != nil) {
			tv := usagev.get("total_tokens");
			if(tv != nil) pick t := tv { Int => tokens = int t.value; }
		}

		# Choices
		choices := jv.get("choices");
		if(choices == nil)
			continue;

		pick ca := choices {
		Array =>
			if(len ca.a == 0)
				continue;
			choice := ca.a[0];

			# Finish reason
			frv := choice.get("finish_reason");
			if(frv != nil) pick fr := frv { String => if(fr.s != "") finishreason = fr.s; }

			delta := choice.get("delta");
			if(delta == nil)
				continue;

			# Text delta
			cv := delta.get("content");
			if(cv != nil) {
				pick c := cv {
				String =>
					if(c.s != "") {
						fulltext += c.s;
						if(req.streamch != nil) {
							alt {
								req.streamch <-= c.s => ;
								* => ;  # drop if full
							}
						}
					}
				}
			}

			# Tool call deltas
			tcv := delta.get("tool_calls");
			if(tcv != nil) {
				pick tca := tcv {
				Array =>
					for(i := 0; i < len tca.a; i++) {
						tc := tca.a[i];
						# Get index
						idxv := tc.get("index");
						idx := 0;
						if(idxv != nil) pick iv := idxv { Int => idx = int iv.value; }

						# Ensure lists are long enough
						while(listlen(tcids) <= idx) {
							tcids = append(tcids, "");
							tcnames = append(tcnames, "");
							tcargs = append(tcargs, "");
						}

						# Merge deltas
						idv := tc.get("id");
						if(idv != nil) pick iv := idv { String => if(iv.s != "") tcids = listset(tcids, idx, iv.s); }

						fnv := tc.get("function");
						if(fnv != nil) {
							nv := fnv.get("name");
							if(nv != nil) pick n := nv { String => if(n.s != "") tcnames = listset(tcnames, idx, listget(tcnames, idx) + n.s); }
							av := fnv.get("arguments");
							if(av != nil) pick a := av { String => tcargs = listset(tcargs, idx, listget(tcargs, idx) + a.s); }
						}
					}
				}
			}
		}
	}

	if(tokens == 0)
		tokens = estimatetokens(fulltext);

	# Plain text mode
	if(req.tooldefs == nil) {
		if(req.prefill != "" && !hasprefix(fulltext, req.prefill))
			fulltext = req.prefill + fulltext;
		return (ref AskResponse(fulltext, "", tokens), nil);
	}

	# Tool mode
	textparts: list of string;
	toolentries: list of string;
	structblocks: list of string;

	if(fulltext != "") {
		textparts = fulltext :: nil;
		structblocks = ("{\"type\":\"text\",\"text\":" + jquote(fulltext) + "}") :: nil;
	}

	n := listlen(tcids);
	for(i := 0; i < n; i++) {
		id := listget(tcids, i);
		name := listget(tcnames, i);
		args := listget(tcargs, i);
		safeargs := replaceall(args, "\n", "\\n");
		toolentries = sys->sprint("TOOL:%s:%s:%s", id, name, safeargs) :: toolentries;
		inputjson := args;
		if(inputjson == "")
			inputjson = "{}";
		structblocks = ("{\"type\":\"tool_use\",\"id\":" + jquote(id) +
			",\"name\":" + jquote(name) +
			",\"input\":" + inputjson + "}") :: structblocks;
	}

	structjson := "";
	if(structblocks != nil)
		structjson = "[" + joinrev(structblocks, ",") + "]";

	response := "";
	if(finishreason == "tool_calls")
		response = "STOP:tool_use\n";
	else
		response = "STOP:end_turn\n";
	response += joinrev(toolentries, "\n");
	if(toolentries != nil)
		response += "\n";
	response += joinrev(textparts, "");

	return (ref AskResponse(response, structjson, tokens), nil);
}

# ==================== Public Utilities ====================

parsetoolresults(text: string): (list of ref ToolResult, string)
{
	lines := splitlines(text);
	if(lines == nil || hd lines != "TOOL_RESULTS")
		return (nil, "missing TOOL_RESULTS header");

	lines = tl lines;  # skip header
	results: list of ref ToolResult;

	while(lines != nil) {
		# Skip blank lines
		if(hd lines == "" || hd lines == "\r") {
			lines = tl lines;
			continue;
		}

		# Next non-empty line is tool_use_id
		tooluseid := strip(hd lines);
		lines = tl lines;

		# Collect content lines until "---" or end
		contentlines: list of string;
		while(lines != nil && hd lines != "---") {
			contentlines = hd lines :: contentlines;
			lines = tl lines;
		}
		# Skip "---" separator
		if(lines != nil && hd lines == "---")
			lines = tl lines;

		content := joinrev(contentlines, "\n");
		# Trim trailing newlines
		while(len content > 0 && content[len content - 1] == '\n')
			content = content[:len content - 1];

		results = ref ToolResult(tooluseid, content) :: results;
	}

	if(results == nil)
		return (nil, "TOOL_RESULTS contained no results");

	# Reverse to preserve order
	rev: list of ref ToolResult;
	for(; results != nil; results = tl results)
		rev = hd results :: rev;

	return (rev, nil);
}

extracttextcontent(response: string): string
{
	if(!hasprefix(response, "STOP:"))
		return response;

	lines := splitlines(response);
	textlines: list of string;
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		if(hasprefix(line, "STOP:") || hasprefix(line, "TOOL:"))
			continue;
		textlines = line :: textlines;
	}
	return joinrev(textlines, "\n");
}

messagesjson(msgs: list of ref LlmMessage): string
{
	s := "[";
	first := 1;
	for(; msgs != nil; msgs = tl msgs) {
		m := hd msgs;
		if(!first)
			s += ",";
		first = 0;
		s += "{\"role\":" + jquote(m.role) +
			",\"content\":" + jquote(m.content);
		if(m.sc != "")
			s += ",\"sc\":" + jquote(m.sc);
		s += "}";
	}
	s += "]";
	return s;
}

jsonescapestr(s: string): string
{
	result := "";
	for(i := 0; i < len s; i++) {
		c := s[i];
		case c {
		'\\' => result += "\\\\";
		'"' =>  result += "\\\"";
		'\n' => result += "\\n";
		'\r' => result += "\\r";
		'\t' => result += "\\t";
		* =>    result[len result] = c;
		}
	}
	return result;
}

# ==================== HTTP Client ====================

httppost(host, port, path, headers, body: string): (string, string)
{
	addr := "tcp!" + host + "!" + port;
	(ok, conn) := sys->dial(addr, nil);
	if(ok < 0)
		return (nil, sys->sprint("cannot connect to %s: %r", addr));

	contentlen := len array of byte body;
	req := "POST " + path + " HTTP/1.0\r\n" +
		"Host: " + host + "\r\n" +
		"Content-Length: " + string contentlen + "\r\n" +
		headers +
		"Connection: close\r\n" +
		"\r\n" + body;

	data := array of byte req;
	if(sys->write(conn.dfd, data, len data) < 0)
		return (nil, sys->sprint("write failed: %r"));

	# Read response
	response := "";
	buf := array[8192] of byte;
	while((n := sys->read(conn.dfd, buf, len buf)) > 0)
		response += string buf[0:n];

	(nil, nil, rbody) := parsehttpresponse(response);
	return (rbody, nil);
}

httpspost(host, port, path, headers, body: string): (string, string)
{
	if(tlsmod == nil) {
		tlsmod = load TLS TLS->PATH;
		if(tlsmod == nil)
			return (nil, "cannot load TLS module");
		terr := tlsmod->init();
		if(terr != nil)
			return (nil, "TLS init: " + terr);
	}

	(ok, conn) := sys->dial("tcp!" + host + "!" + port, nil);
	if(ok < 0)
		return (nil, sys->sprint("cannot connect to %s: %r", host));

	config := tlsmod->defaultconfig();
	config.servername = host;

	(tc, cerr) := tlsmod->client(conn.dfd, config);
	if(cerr != nil)
		return (nil, "TLS: " + cerr);

	contentlen := len array of byte body;
	req := "POST " + path + " HTTP/1.0\r\n" +
		"Host: " + host + "\r\n" +
		"Content-Length: " + string contentlen + "\r\n" +
		headers +
		"Connection: close\r\n" +
		"\r\n" + body;

	data := array of byte req;
	if(tc.write(data, len data) < 0) {
		tc.close();
		return (nil, "TLS write failed");
	}

	# Read response
	response := "";
	buf := array[8192] of byte;
	while((n := tc.read(buf, len buf)) > 0)
		response += string buf[0:n];
	tc.close();

	# Check for HTTP error status
	(status, nil, rbody) := parsehttpresponse(response);
	if(status != "" && !hasprefix(status, "HTTP/1.1 200") && !hasprefix(status, "HTTP/1.0 200")) {
		if(rbody != "")
			return (nil, "HTTP error: " + strip(status) + ": " + rbody);
		return (nil, "HTTP error: " + strip(status));
	}

	return (rbody, nil);
}

parsehttpresponse(response: string): (string, string, string)
{
	# Find status line
	statusend := 0;
	for(; statusend < len response; statusend++)
		if(response[statusend] == '\n')
			break;
	if(statusend == 0)
		return ("", "", "");

	status := response[0:statusend];

	# Find headers end (double newline)
	headersend := statusend + 1;
	for(; headersend < len response - 1; headersend++) {
		if(response[headersend] == '\n' &&
		   (response[headersend+1] == '\n' || response[headersend+1] == '\r'))
			break;
	}

	headers := "";
	if(headersend > statusend + 1)
		headers = response[statusend+1:headersend];

	# Find body
	bodystart := headersend + 1;
	if(bodystart < len response && response[bodystart] == '\r')
		bodystart++;
	if(bodystart < len response && response[bodystart] == '\n')
		bodystart++;

	bodys := "";
	if(bodystart < len response)
		bodys = response[bodystart:];

	return (status, headers, bodys);
}

parseurl(url: string): (string, string, string, string, string)
{
	scheme := "http";
	port := "80";
	i: int;

	if(len url > 7 && str->tolower(url[0:7]) == "http://") {
		url = url[7:];
	} else if(len url > 8 && str->tolower(url[0:8]) == "https://") {
		scheme = "https";
		port = "443";
		url = url[8:];
	} else {
		return ("", "", "", "", "invalid URL");
	}

	# Find path
	path := "/";
	for(i = 0; i < len url; i++) {
		if(url[i] == '/') {
			path = url[i:];
			url = url[0:i];
			break;
		}
	}

	# Find port
	host := url;
	for(i = 0; i < len url; i++) {
		if(url[i] == ':') {
			host = url[0:i];
			port = url[i+1:];
			break;
		}
	}

	return (scheme, host, port, path, nil);
}

# ==================== Helpers ====================

readjsonstring(s: string): (ref JValue, string)
{
	bio := bufio->aopen(array of byte s);
	if(bio == nil)
		return (nil, "cannot create buffer");
	return json->readjson(bio);
}

jquote(s: string): string
{
	return "\"" + jsonescapestr(s) + "\"";
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
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

stripnl(s: string): string
{
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == '\r'))
		s = s[:len s - 1];
	return s;
}

splitlines(s: string): list of string
{
	lines: list of string;
	start := 0;
	for(i := 0; i < len s; i++) {
		if(s[i] == '\n') {
			lines = s[start:i] :: lines;
			start = i + 1;
		}
	}
	if(start < len s)
		lines = s[start:] :: lines;

	# Reverse
	rev: list of string;
	for(; lines != nil; lines = tl lines)
		rev = hd lines :: rev;
	return rev;
}

replaceall(s, old, new: string): string
{
	result := "";
	i := 0;
	while(i <= len s - len old) {
		if(s[i:i+len old] == old) {
			result += new;
			i += len old;
		} else {
			result[len result] = s[i];
			i++;
		}
	}
	while(i < len s) {
		result[len result] = s[i];
		i++;
	}
	return result;
}

joinrev(l: list of string, sep: string): string
{
	# Reverse the list first, then join
	rev: list of string;
	for(; l != nil; l = tl l)
		rev = hd l :: rev;

	result := "";
	first := 1;
	for(; rev != nil; rev = tl rev) {
		if(!first)
			result += sep;
		first = 0;
		result += hd rev;
	}
	return result;
}

estimatetokens(s: string): int
{
	n := len s;
	if(n == 0)
		return 0;
	return n / 4;
}

extracttoolargs(inputjson: string): string
{
	(jv, jerr) := readjsonstring(inputjson);
	if(jerr != nil)
		return inputjson;

	pick obj := jv {
	Object =>
		# Check for "args" key first
		for(ml := obj.mem; ml != nil; ml = tl ml) {
			(name, val) := hd ml;
			if(name == "args") {
				pick sv := val { String => return sv.s; }
			}
		}
		# Fallback: join all string values
		parts: list of string;
		for(ml = obj.mem; ml != nil; ml = tl ml) {
			(nil, val) := hd ml;
			pick sv := val { String => parts = sv.s :: parts; }
		}
		return joinrev(parts, " ");
	}
	return inputjson;
}

# List helper functions (for tool call delta accumulation)

listlen(l: list of string): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

listget(l: list of string, idx: int): string
{
	for(i := 0; l != nil; l = tl l) {
		if(i == idx)
			return hd l;
		i++;
	}
	return "";
}

listset(l: list of string, idx: int, val: string): list of string
{
	result: list of string;
	i := 0;
	for(ol := l; ol != nil; ol = tl ol) {
		if(i == idx)
			result = val :: result;
		else
			result = hd ol :: result;
		i++;
	}
	# Reverse
	rev: list of string;
	for(; result != nil; result = tl result)
		rev = hd result :: rev;
	return rev;
}

append(l: list of string, val: string): list of string
{
	# Append to end by reversing, prepending, reversing
	rev: list of string;
	for(ol := l; ol != nil; ol = tl ol)
		rev = hd ol :: rev;
	rev = val :: rev;
	result: list of string;
	for(; rev != nil; rev = tl rev)
		result = hd rev :: result;
	return result;
}
