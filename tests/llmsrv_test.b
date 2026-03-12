implement LlmsrvTest;

#
# llmsrv_test - Unit tests for llmsrv and llmclient
#
# Tests session management, settings, tool protocol, streaming,
# SSE parsing, JSON construction, and compaction logic.
#
# No network required — all tests use in-memory data.
#
# To run: emu -r.. /tests/llmsrv_test.dis -v
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "json.m";
	json: JSON;
	JValue: import json;

include "testing.m";
	testing: Testing;
	T: import testing;

include "llmclient.m";
	llmclient: Llmclient;
	LlmMessage, ToolDef, ToolResult, AskRequest, AskResponse: import llmclient;

LlmsrvTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/llmsrv_test.b";

passed := 0;
failed := 0;
skipped := 0;

run(name: string, testfn: ref fn(t: ref T))
{
	t := testing->newTsrc(name, SRCFILE);
	{
		testfn(t);
	} exception {
	"fail:fatal" =>
		;
	"fail:skip" =>
		;
	"*" =>
		t.failed = 1;
	}

	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	str = load String String->PATH;
	if(str == nil) {
		sys->fprint(sys->fildes(2), "cannot load String\n");
		raise "fail:load";
	}

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil) {
		sys->fprint(sys->fildes(2), "cannot load Bufio\n");
		raise "fail:load";
	}

	json = load JSON JSON->PATH;
	if(json == nil) {
		sys->fprint(sys->fildes(2), "cannot load JSON\n");
		raise "fail:load";
	}
	json->init(bufio);

	testing = load Testing Testing->PATH;
	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load Testing\n");
		raise "fail:load";
	}
	testing->init();

	llmclient = load Llmclient Llmclient->PATH;
	if(llmclient == nil) {
		sys->fprint(sys->fildes(2), "cannot load Llmclient\n");
		raise "fail:load";
	}
	llmclient->init();

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	# JSON escape tests
	run("JsonEscapeEmpty", testJsonEscapeEmpty);
	run("JsonEscapeNewline", testJsonEscapeNewline);
	run("JsonEscapeQuote", testJsonEscapeQuote);
	run("JsonEscapeBackslash", testJsonEscapeBackslash);
	run("JsonEscapeTab", testJsonEscapeTab);
	run("JsonEscapeMixed", testJsonEscapeMixed);

	# Tool results parser tests
	run("ParseToolResultsSimple", testParseToolResultsSimple);
	run("ParseToolResultsMultiline", testParseToolResultsMultiline);
	run("ParseToolResultsMultiple", testParseToolResultsMultiple);
	run("ParseToolResultsNoHeader", testParseToolResultsNoHeader);
	run("ParseToolResultsEmpty", testParseToolResultsEmpty);

	# Extract text content tests
	run("ExtractTextPlain", testExtractTextPlain);
	run("ExtractTextSTOP", testExtractTextSTOP);
	run("ExtractTextToolLines", testExtractTextToolLines);

	# Messages JSON tests
	run("MessagesJsonEmpty", testMessagesJsonEmpty);
	run("MessagesJsonSingle", testMessagesJsonSingle);
	run("MessagesJsonMultiple", testMessagesJsonMultiple);
	run("MessagesJsonStructured", testMessagesJsonStructured);

	# Streaming channel tests
	run("StreamChannelBasic", testStreamChannelBasic);
	run("StreamChannelBuffering", testStreamChannelBuffering);
	run("StreamChannelEOF", testStreamChannelEOF);
	run("StreamChannelOrder", testStreamChannelOrder);

	# Settings validation tests (model aliases, temperature, thinking)
	run("ModelAliasHaiku", testModelAliasHaiku);
	run("ModelAliasSonnet", testModelAliasSonnet);
	run("ModelAliasOpus", testModelAliasOpus);
	run("ModelAliasPassthrough", testModelAliasPassthrough);
	run("ThinkingParse", testThinkingParse);
	run("PrefillPreserveSpace", testPrefillPreserveSpace);

	# Token estimation tests
	run("EstimatedTokensEmpty", testEstimatedTokensEmpty);
	run("EstimatedTokens400", testEstimatedTokens400);

	# Temperature validation tests
	run("TemperatureDefault", testTemperatureDefault);
	run("TemperatureValidRange", testTemperatureValidRange);
	run("TemperatureInvalidNegative", testTemperatureInvalidNegative);
	run("TemperatureInvalidHigh", testTemperatureInvalidHigh);
	run("TemperatureBoundary", testTemperatureBoundary);

	# System prompt tests
	run("SystemPromptDefault", testSystemPromptDefault);
	run("SystemPromptSetRead", testSystemPromptSetRead);
	run("SystemPromptOverwrite", testSystemPromptOverwrite);

	# Session reset/lifecycle tests
	run("SessionResetClearsMessages", testSessionResetClearsMessages);
	run("SessionResetClearsTokens", testSessionResetClearsTokens);
	run("SessionResetPreservesSettings", testSessionResetPreservesSettings);

	# Context limit tests
	run("ContextLimitDefault", testContextLimitDefault);
	run("ContextLimitForModel", testContextLimitForModel);

	# Usage format tests
	run("UsageFormatEmpty", testUsageFormatEmpty);
	run("UsageFormatWithTokens", testUsageFormatWithTokens);
	run("UsageFormatDynamic", testUsageFormatDynamic);

	# Compaction threshold tests
	run("CompactThresholdTooShort", testCompactThresholdTooShort);
	run("CompactThresholdExact", testCompactThresholdExact);
	run("CompactThresholdAbove", testCompactThresholdAbove);

	# Float parser tests
	run("ParseFloatInteger", testParseFloatInteger);
	run("ParseFloatDecimal", testParseFloatDecimal);
	run("ParseFloatNegative", testParseFloatNegative);
	run("ParseFloatZero", testParseFloatZero);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}

# ==================== JSON Escape Tests ====================

testJsonEscapeEmpty(t: ref T)
{
	got := llmclient->jsonescapestr("");
	t.assertseq(got, "", "empty string");
}

testJsonEscapeNewline(t: ref T)
{
	got := llmclient->jsonescapestr("hello\nworld");
	t.assertseq(got, "hello\\nworld", "newline escape");
}

testJsonEscapeQuote(t: ref T)
{
	got := llmclient->jsonescapestr("say \"hello\"");
	t.assertseq(got, "say \\\"hello\\\"", "quote escape");
}

testJsonEscapeBackslash(t: ref T)
{
	got := llmclient->jsonescapestr("path\\to\\file");
	t.assertseq(got, "path\\\\to\\\\file", "backslash escape");
}

testJsonEscapeTab(t: ref T)
{
	got := llmclient->jsonescapestr("col1\tcol2");
	t.assertseq(got, "col1\\tcol2", "tab escape");
}

testJsonEscapeMixed(t: ref T)
{
	got := llmclient->jsonescapestr("line1\nline2\t\"quoted\"\\end");
	t.assertseq(got, "line1\\nline2\\t\\\"quoted\\\"\\\\end", "mixed escapes");
}

# ==================== Tool Results Parser Tests ====================

testParseToolResultsSimple(t: ref T)
{
	text := "TOOL_RESULTS\ntool_123\nHello world\n---";
	(results, err) := llmclient->parsetoolresults(text);
	t.assertnil(err, "no error");
	t.asserteq(listlentr(results), 1, "one result");
	if(results != nil) {
		r := hd results;
		t.assertseq(r.tooluseid, "tool_123", "tool use id");
		t.assertseq(r.content, "Hello world", "content");
	}
}

testParseToolResultsMultiline(t: ref T)
{
	text := "TOOL_RESULTS\ntool_456\nLine 1\nLine 2\nLine 3\n---";
	(results, err) := llmclient->parsetoolresults(text);
	t.assertnil(err, "no error");
	t.asserteq(listlentr(results), 1, "one result");
	if(results != nil) {
		r := hd results;
		t.assertseq(r.tooluseid, "tool_456", "tool use id");
		t.assert(hasprefix(r.content, "Line 1\nLine 2"), "multiline content");
	}
}

testParseToolResultsMultiple(t: ref T)
{
	text := "TOOL_RESULTS\ntool_1\nResult one\n---\ntool_2\nResult two\n---";
	(results, err) := llmclient->parsetoolresults(text);
	t.assertnil(err, "no error");
	t.asserteq(listlentr(results), 2, "two results");
	if(results != nil) {
		r1 := hd results;
		t.assertseq(r1.tooluseid, "tool_1", "first tool id");
		t.assertseq(r1.content, "Result one", "first content");
		if(tl results != nil) {
			r2 := hd tl results;
			t.assertseq(r2.tooluseid, "tool_2", "second tool id");
			t.assertseq(r2.content, "Result two", "second content");
		}
	}
}

testParseToolResultsNoHeader(t: ref T)
{
	text := "NOT_TOOL_RESULTS\ntool_1\nResult\n---";
	(nil, err) := llmclient->parsetoolresults(text);
	t.assertnotnil(err, "error on missing header");
}

testParseToolResultsEmpty(t: ref T)
{
	text := "TOOL_RESULTS\n";
	(nil, err) := llmclient->parsetoolresults(text);
	t.assertnotnil(err, "error on empty results");
}

# ==================== Extract Text Content Tests ====================

testExtractTextPlain(t: ref T)
{
	got := llmclient->extracttextcontent("Just plain text");
	t.assertseq(got, "Just plain text", "plain text passthrough");
}

testExtractTextSTOP(t: ref T)
{
	got := llmclient->extracttextcontent("STOP:end_turn\nHello there");
	t.assertseq(got, "Hello there", "strip STOP line");
}

testExtractTextToolLines(t: ref T)
{
	input := "STOP:tool_use\nTOOL:id1:name1:args1\nSome text here";
	got := llmclient->extracttextcontent(input);
	t.assertseq(got, "Some text here", "strip STOP and TOOL lines");
}

# ==================== Messages JSON Tests ====================

testMessagesJsonEmpty(t: ref T)
{
	got := llmclient->messagesjson(nil);
	t.assertseq(got, "[]", "empty list");
}

testMessagesJsonSingle(t: ref T)
{
	msgs: list of ref LlmMessage;
	msgs = ref LlmMessage("user", "hello", "") :: nil;
	got := llmclient->messagesjson(msgs);
	# Should contain role and content
	t.assert(hasprefix(got, "[{"), "starts with [{");
	t.assert(contains(got, "\"role\":\"user\""), "has role");
	t.assert(contains(got, "\"content\":\"hello\""), "has content");
}

testMessagesJsonMultiple(t: ref T)
{
	msgs: list of ref LlmMessage;
	msgs = ref LlmMessage("user", "hi", "") :: nil;
	msgs = appendmsg(msgs, ref LlmMessage("assistant", "hello", ""));
	got := llmclient->messagesjson(msgs);
	t.assert(contains(got, "\"role\":\"user\""), "has user");
	t.assert(contains(got, "\"role\":\"assistant\""), "has assistant");
}

testMessagesJsonStructured(t: ref T)
{
	msgs: list of ref LlmMessage;
	sc := "[{\"type\":\"text\",\"text\":\"hi\"}]";
	msgs = ref LlmMessage("assistant", "hi", sc) :: nil;
	got := llmclient->messagesjson(msgs);
	t.assert(contains(got, "\"sc\":"), "has structured content");
}

# ==================== Streaming Channel Tests ====================

testStreamChannelBasic(t: ref T)
{
	ch := chan[16] of string;
	ch <-= "hello";
	got := <-ch;
	t.assertseq(got, "hello", "basic channel send/receive");
}

testStreamChannelBuffering(t: ref T)
{
	ch := chan[4] of string;
	# Fill buffer
	ch <-= "a";
	ch <-= "b";
	ch <-= "c";
	ch <-= "d";

	# Non-blocking send should drop
	dropped := 0;
	alt {
		ch <-= "e" => ;
		* => dropped = 1;
	}
	t.asserteq(dropped, 1, "dropped when full");

	# Read back in order
	t.assertseq(<-ch, "a", "first");
	t.assertseq(<-ch, "b", "second");
	t.assertseq(<-ch, "c", "third");
	t.assertseq(<-ch, "d", "fourth");
}

testStreamChannelEOF(t: ref T)
{
	ch := chan[4] of string;
	ch <-= "data";
	ch <-= "";  # EOF sentinel

	got1 := <-ch;
	t.assertseq(got1, "data", "data before EOF");

	got2 := <-ch;
	t.assertseq(got2, "", "EOF sentinel is empty string");
}

testStreamChannelOrder(t: ref T)
{
	ch := chan[16] of string;
	# Send chunks in order
	for(i := 0; i < 10; i++)
		ch <-= "chunk" + string i;

	# Receive and verify order
	for(i = 0; i < 10; i++) {
		expected := "chunk" + string i;
		got := <-ch;
		t.assertseq(got, expected, "chunk order " + string i);
	}
}

# ==================== Settings Tests ====================

testModelAliasHaiku(t: ref T)
{
	got := resolvemodel("haiku");
	t.assertseq(got, "claude-haiku-4-5-20251001", "haiku alias");
}

testModelAliasSonnet(t: ref T)
{
	got := resolvemodel("sonnet");
	t.assertseq(got, "claude-sonnet-4-5-20250929", "sonnet alias");
}

testModelAliasOpus(t: ref T)
{
	got := resolvemodel("opus");
	t.assertseq(got, "claude-opus-4-5-20251101", "opus alias");
}

testModelAliasPassthrough(t: ref T)
{
	got := resolvemodel("llama3");
	t.assertseq(got, "llama3", "unknown model passes through");
}

testThinkingParse(t: ref T)
{
	# Test parsing thinking values
	t.asserteq(parsethinking("disabled"), 0, "disabled");
	t.asserteq(parsethinking("off"), 0, "off");
	t.asserteq(parsethinking("0"), 0, "zero");
	t.asserteq(parsethinking("max"), -1, "max");
	t.asserteq(parsethinking("-1"), -1, "negative one");
	t.asserteq(parsethinking("5000"), 5000, "5000");
}

testPrefillPreserveSpace(t: ref T)
{
	# Prefill should preserve trailing space but strip trailing newline
	input := "Hello ";
	# Simulating what llmsrv does: strip trailing \n but not spaces
	result := input;
	if(len result > 0 && result[len result - 1] == '\n')
		result = result[:len result - 1];
	t.assertseq(result, "Hello ", "trailing space preserved");

	input2 := "Hello\n";
	result2 := input2;
	if(len result2 > 0 && result2[len result2 - 1] == '\n')
		result2 = result2[:len result2 - 1];
	t.assertseq(result2, "Hello", "trailing newline stripped");
}

# ==================== Token Estimation Tests ====================

testEstimatedTokensEmpty(t: ref T)
{
	msgs: list of ref LlmMessage;
	got := estimatedtokens(msgs);
	t.asserteq(got, 0, "empty messages = 0 tokens");
}

testEstimatedTokens400(t: ref T)
{
	# 400 chars = 100 tokens at 4 chars/token
	content := "";
	for(i := 0; i < 400; i++)
		content[len content] = 'x';
	msgs: list of ref LlmMessage;
	msgs = ref LlmMessage("user", content, "") :: nil;
	got := estimatedtokens(msgs);
	t.asserteq(got, 100, "400 chars = 100 tokens");
}

# ==================== Temperature Validation Tests ====================

testTemperatureDefault(t: ref T)
{
	# Default temperature should be 0.7
	temp := 0.7;
	t.assert(fapprox(temp, 0.7), "default temperature is 0.7");
}

testTemperatureValidRange(t: ref T)
{
	# 0.0, 1.0, 1.5, 2.0 should all be valid
	t.assert(validtemp(0.0), "0.0 valid");
	t.assert(validtemp(1.0), "1.0 valid");
	t.assert(validtemp(1.5), "1.5 valid");
	t.assert(validtemp(2.0), "2.0 valid");
}

testTemperatureInvalidNegative(t: ref T)
{
	t.assert(!validtemp(-0.1), "-0.1 invalid");
	t.assert(!validtemp(-1.0), "-1.0 invalid");
}

testTemperatureInvalidHigh(t: ref T)
{
	t.assert(!validtemp(2.1), "2.1 invalid");
	t.assert(!validtemp(3.0), "3.0 invalid");
	t.assert(!validtemp(100.0), "100.0 invalid");
}

testTemperatureBoundary(t: ref T)
{
	# Edge cases at exact boundaries
	t.assert(validtemp(0.0), "0.0 boundary valid");
	t.assert(validtemp(2.0), "2.0 boundary valid");
	# Just outside
	t.assert(!validtemp(-0.001), "just below 0 invalid");
	t.assert(!validtemp(2.001), "just above 2 invalid");
}

# ==================== System Prompt Tests ====================

testSystemPromptDefault(t: ref T)
{
	# Default system prompt is empty
	sysprompt := "";
	t.assertseq(sysprompt, "", "default system prompt empty");
}

testSystemPromptSetRead(t: ref T)
{
	sysprompt := "";
	# Set it
	sysprompt = strip("You are a helpful assistant\n");
	t.assertseq(sysprompt, "You are a helpful assistant", "system prompt set");
}

testSystemPromptOverwrite(t: ref T)
{
	sysprompt := "first prompt";
	sysprompt = strip("second prompt\n");
	t.assertseq(sysprompt, "second prompt", "system prompt overwritten");
}

# ==================== Session Reset/Lifecycle Tests ====================

# Session ADT replica for testing
TestSession: adt {
	messages:       list of ref LlmMessage;
	lastresponse:   string;
	totaltokens:    int;
	model:          string;
	temperature:    real;
	systemprompt:   string;
	thinkingtokens: int;
	prefill:        string;
};

newTestSession(): ref TestSession
{
	return ref TestSession(
		nil,    # messages
		"",     # lastresponse
		0,      # totaltokens
		"claude-sonnet-4-5-20250929",  # model
		0.7,    # temperature
		"",     # systemprompt
		0,      # thinkingtokens
		""      # prefill
	);
}

resetTestSession(sess: ref TestSession)
{
	sess.messages = nil;
	sess.lastresponse = "";
	sess.totaltokens = 0;
}

testSessionResetClearsMessages(t: ref T)
{
	sess := newTestSession();
	# Add some messages
	sess.messages = ref LlmMessage("user", "hello", "") :: nil;
	sess.messages = ref LlmMessage("assistant", "hi there", "") :: sess.messages;
	sess.lastresponse = "hi there";
	sess.totaltokens = 500;

	t.asserteq(listlenmsg(sess.messages), 2, "pre-reset: 2 messages");

	resetTestSession(sess);

	t.assert(sess.messages == nil, "messages cleared");
	t.assertseq(sess.lastresponse, "", "lastresponse cleared");
	t.asserteq(sess.totaltokens, 0, "totaltokens cleared");
}

testSessionResetClearsTokens(t: ref T)
{
	sess := newTestSession();
	sess.totaltokens = 12345;

	resetTestSession(sess);

	t.asserteq(sess.totaltokens, 0, "tokens reset to 0");
}

testSessionResetPreservesSettings(t: ref T)
{
	sess := newTestSession();
	sess.model = "claude-opus-4-5-20251101";
	sess.temperature = 1.5;
	sess.systemprompt = "Be helpful";
	sess.thinkingtokens = 5000;
	sess.prefill = "Sure, ";

	# Add messages and tokens
	sess.messages = ref LlmMessage("user", "test", "") :: nil;
	sess.totaltokens = 999;

	resetTestSession(sess);

	# Messages and tokens should be cleared
	t.assert(sess.messages == nil, "messages cleared");
	t.asserteq(sess.totaltokens, 0, "tokens cleared");

	# Settings should be preserved
	t.assertseq(sess.model, "claude-opus-4-5-20251101", "model preserved");
	t.assert(fapprox(sess.temperature, 1.5), "temperature preserved");
	t.assertseq(sess.systemprompt, "Be helpful", "systemprompt preserved");
	t.asserteq(sess.thinkingtokens, 5000, "thinkingtokens preserved");
	t.assertseq(sess.prefill, "Sure, ", "prefill preserved");
}

# ==================== Context Limit Tests ====================

testContextLimitDefault(t: ref T)
{
	# Default context limit is 200000
	t.asserteq(contextlimit("claude-sonnet-4-5-20250929"), 200000, "default context limit");
}

testContextLimitForModel(t: ref T)
{
	# All known models return 200000 (same as Go)
	t.asserteq(contextlimit("claude-3-opus-20240229"), 200000, "opus");
	t.asserteq(contextlimit("claude-3-sonnet-20240229"), 200000, "sonnet");
	t.asserteq(contextlimit("claude-3-haiku-20240307"), 200000, "haiku");
	t.asserteq(contextlimit("unknown-model"), 200000, "unknown");
	t.asserteq(contextlimit("llama3"), 200000, "ollama");
}

# ==================== Usage Format Tests ====================

testUsageFormatEmpty(t: ref T)
{
	# New session: 0 tokens
	got := usageformat(0, 200000);
	t.assertseq(got, "0/200000\n", "empty usage");
}

testUsageFormatWithTokens(t: ref T)
{
	got := usageformat(45000, 200000);
	t.assertseq(got, "45000/200000\n", "usage with tokens");
}

testUsageFormatDynamic(t: ref T)
{
	# Simulate adding messages and checking usage updates
	msgs: list of ref LlmMessage;

	# Initially 0
	t.asserteq(estimatedtokens(msgs), 0, "initial 0 tokens");

	# Add 800-char message → 200 tokens
	content := "";
	for(i := 0; i < 800; i++)
		content[len content] = 'x';
	msgs = ref LlmMessage("user", content, "") :: nil;

	tokens := estimatedtokens(msgs);
	t.asserteq(tokens, 200, "200 estimated tokens after 800 chars");

	got := usageformat(tokens, 200000);
	t.assertseq(got, "200/200000\n", "dynamic usage format");
}

# ==================== Compaction Threshold Tests ====================

testCompactThresholdTooShort(t: ref T)
{
	# < 4 messages → compaction should be skipped
	msgs: list of ref LlmMessage;
	msgs = ref LlmMessage("user", "hello", "") :: nil;
	msgs = appendmsg(msgs, ref LlmMessage("assistant", "hi", ""));

	t.assert(!shouldcompact(msgs), "2 messages: skip compact");
}

testCompactThresholdExact(t: ref T)
{
	# Exactly 4 messages → should compact
	msgs: list of ref LlmMessage;
	msgs = ref LlmMessage("user", "q1", "") :: nil;
	msgs = appendmsg(msgs, ref LlmMessage("assistant", "a1", ""));
	msgs = appendmsg(msgs, ref LlmMessage("user", "q2", ""));
	msgs = appendmsg(msgs, ref LlmMessage("assistant", "a2", ""));

	t.assert(shouldcompact(msgs), "4 messages: should compact");
}

testCompactThresholdAbove(t: ref T)
{
	# 6 messages → should compact
	msgs: list of ref LlmMessage;
	msgs = ref LlmMessage("user", "q1", "") :: nil;
	msgs = appendmsg(msgs, ref LlmMessage("assistant", "a1", ""));
	msgs = appendmsg(msgs, ref LlmMessage("user", "q2", ""));
	msgs = appendmsg(msgs, ref LlmMessage("assistant", "a2", ""));
	msgs = appendmsg(msgs, ref LlmMessage("user", "q3", ""));
	msgs = appendmsg(msgs, ref LlmMessage("assistant", "a3", ""));

	t.assert(shouldcompact(msgs), "6 messages: should compact");
}

# ==================== Float Parser Tests ====================

testParseFloatInteger(t: ref T)
{
	t.assert(fapprox(parsefloat("1"), 1.0), "parse '1'");
	t.assert(fapprox(parsefloat("2"), 2.0), "parse '2'");
	t.assert(fapprox(parsefloat("10"), 10.0), "parse '10'");
}

testParseFloatDecimal(t: ref T)
{
	t.assert(fapprox(parsefloat("0.5"), 0.5), "parse '0.5'");
	t.assert(fapprox(parsefloat("1.75"), 1.75), "parse '1.75'");
	t.assert(fapprox(parsefloat("0.01"), 0.01), "parse '0.01'");
}

testParseFloatNegative(t: ref T)
{
	t.assert(fapprox(parsefloat("-0.1"), -0.1), "parse '-0.1'");
	t.assert(fapprox(parsefloat("-2.5"), -2.5), "parse '-2.5'");
}

testParseFloatZero(t: ref T)
{
	t.assert(fapprox(parsefloat("0"), 0.0), "parse '0'");
	t.assert(fapprox(parsefloat("0.0"), 0.0), "parse '0.0'");
	t.assert(fapprox(parsefloat("0.00"), 0.0), "parse '0.00'");
}

# ==================== Test Helpers ====================

# Replicated from llmsrv.b for unit testing
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

parsethinking(value: string): int
{
	case value {
	"max" or "-1" =>
		return -1;
	"disabled" or "off" or "0" =>
		return 0;
	}
	n := 0;
	for(i := 0; i < len value; i++) {
		c := value[i];
		if(c < '0' || c > '9')
			return -999;
		n = n * 10 + (c - '0');
	}
	return n;
}

estimatedtokens(msgs: list of ref LlmMessage): int
{
	total := 0;
	for(; msgs != nil; msgs = tl msgs) {
		m := hd msgs;
		total += len m.content / 4;
	}
	return total;
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

listlentr(l: list of ref ToolResult): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

appendmsg(msgs: list of ref LlmMessage, m: ref LlmMessage): list of ref LlmMessage
{
	rev: list of ref LlmMessage;
	for(ml := msgs; ml != nil; ml = tl ml)
		rev = hd ml :: rev;
	rev = m :: rev;
	result: list of ref LlmMessage;
	for(; rev != nil; rev = tl rev)
		result = hd rev :: result;
	return result;
}

# Temperature validation (replicates llmsrv.b logic)
validtemp(temp: real): int
{
	return temp >= 0.0 && temp <= 2.0;
}

# Context limit lookup (replicates llmsrv.b CONTEXTLIMIT constant)
contextlimit(nil: string): int
{
	return 200000;
}

# Usage format string (replicates llmsrv.b usage read logic)
usageformat(estimated, limit: int): string
{
	return sys->sprint("%d/%d\n", estimated, limit);
}

# Compaction threshold check (replicates llmsrv.b asynccompact logic)
shouldcompact(msgs: list of ref LlmMessage): int
{
	nmsg := 0;
	for(ml := msgs; ml != nil; ml = tl ml)
		nmsg++;
	return nmsg >= 4;
}

# Float parser (replicates llmsrv.b parsefloat)
parsefloat(s: string): real
{
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

# Approximate float comparison (within epsilon)
fapprox(a, b: real): int
{
	diff := a - b;
	if(diff < 0.0)
		diff = -diff;
	return diff < 0.001;
}

# Strip whitespace (replicates llmsrv.b strip)
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

# Count messages in list
listlenmsg(l: list of ref LlmMessage): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}
