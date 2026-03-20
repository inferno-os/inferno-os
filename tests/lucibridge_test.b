implement LucibridgeTest;

#
# Unit tests for lucibridge pure functions.
#
# lucibridge contains many string-processing helpers that are testable
# without the full Inferno runtime (no /n/ui, /n/llm needed).
# These tests re-implement the functions locally (same pattern as
# lucifer_flicker_test.b) to validate the logic in isolation.
#
# Covers:
#   - getkv: key=value parser for manifest lines
#   - cleanresponse: LLM response cleanup (strip say/DONE/[Veltro])
#   - extractsay: extract say text and detect DONE
#   - extractargs: JSON {"args":"..."} envelope extraction
#   - filepathof: first Inferno path from args string
#   - pathbase: last path component (basename)
#   - firstlines: line truncation for tool result previews
#   - splitpathperm: "path [perm]" splitting
#   - extractpaths: path extraction from "path perm" lines
#   - lookuppathperm: permission lookup from path list
#   - strcontains: list membership check
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

LucibridgeTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/lucibridge_test.b";

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
	* =>
		t.failed = 1;
	}

	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

# ============================================================================
# Local copies of lucibridge functions (must stay in sync)
# ============================================================================

# Extract value for key from "key1=val1 key2=val2 ..." string
getkv(line, key: string): string
{
	target := key + "=";
	tlen := len target;
	i := 0;
	while(i <= len line - tlen) {
		if(line[i:i+tlen] == target) {
			start := i + tlen;
			end := start;
			while(end < len line && line[end] != ' ' && line[end] != '\t')
				end++;
			return line[start:end];
		}
		while(i < len line && line[i] != ' ' && line[i] != '\t')
			i++;
		while(i < len line && (line[i] == ' ' || line[i] == '\t'))
			i++;
	}
	return "";
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

strip(s: string): string
{
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == ' ' || s[len s - 1] == '\t'))
		s = s[0:len s - 1];
	# Also strip leading whitespace
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;
	return s[i:];
}

tolower(s: string): string
{
	r := s;
	for(i := 0; i < len r; i++)
		if(r[i] >= 'A' && r[i] <= 'Z')
			r[i] = r[i] + ('a' - 'A');
	return r;
}

cleanresponse(response: string): string
{
	(nil, lines) := sys->tokenize(response, "\n");
	result := "";
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		for(i := 0; i < len line; i++)
			if(line[i] != ' ' && line[i] != '\t')
				break;
		if(i < len line)
			line = line[i:];
		else
			line = "";
		if(line == "")
			continue;
		if(hasprefix(line, "[Veltro]"))
			line = strip(line[8:]);
		if(line == "")
			continue;
		lower := tolower(line);
		if(hasprefix(lower, "say "))
			line = strip(line[4:]);
		stripped := tolower(strip(line));
		if(stripped == "done")
			continue;
		if(result != "")
			result += "\n";
		result += line;
	}
	if(result == "")
		result = strip(response);
	return result;
}

extractsay(response: string): (string, int)
{
	(nil, lines) := sys->tokenize(response, "\n");
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		line = strip(line);
		if(line == "")
			continue;
		if(hasprefix(line, "[Veltro]"))
			line = strip(line[8:]);
		if(line == "")
			continue;
		lower := tolower(line);
		stripped := tolower(strip(line));
		if(stripped == "done")
			return (nil, 1);
		if(hasprefix(lower, "say ")) {
			text := strip(line[4:]);
			for(lines = tl lines; lines != nil; lines = tl lines) {
				rest := hd lines;
				rest = strip(rest);
				if(hasprefix(rest, "[Veltro]"))
					rest = strip(rest[8:]);
				rl := tolower(strip(rest));
				if(rl == "done")
					break;
				if(rest != "")
					text += " " + rest;
			}
			return (text, 0);
		}
		return (nil, 0);
	}
	return (nil, 0);
}

extractargs(json: string): string
{
	n := len json;
	key := "\"args\"";
	klen := len key;
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
	for(; i < n && (json[i] == ' ' || json[i] == '\t' || json[i] == ':'); i++)
		;
	if(i >= n || json[i] != '"')
		return json;
	i++;
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

strcontains(l: list of string, name: string): int
{
	for(; l != nil; l = tl l)
		if(hd l == name)
			return 1;
	return 0;
}

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

extractpaths(lines: list of string): list of string
{
	result: list of string;
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		(p, nil) := splitpathperm(line);
		if(p != "")
			result = p :: result;
	}
	rev: list of string;
	for(r := result; r != nil; r = tl r)
		rev = hd r :: rev;
	return rev;
}

lookuppathperm(lines: list of string, path: string): string
{
	for(; lines != nil; lines = tl lines) {
		(p, perm) := splitpathperm(hd lines);
		if(p == path)
			return perm;
	}
	return "rw";
}

# ============================================================================
# Tests
# ============================================================================

# --- getkv tests ---

testGetkvBasic(t: ref T)
{
	line := "path=/n/local/tmp label=tmp perm=rw";
	t.assertseq(getkv(line, "path"), "/n/local/tmp", "getkv path");
	t.assertseq(getkv(line, "label"), "tmp", "getkv label");
	t.assertseq(getkv(line, "perm"), "rw", "getkv perm");
}

testGetkvMissing(t: ref T)
{
	line := "path=/foo label=bar";
	t.assertseq(getkv(line, "missing"), "", "getkv missing key returns empty");
}

testGetkvFirstToken(t: ref T)
{
	line := "path=/dev/time label=Clock perm=ro";
	t.assertseq(getkv(line, "path"), "/dev/time", "getkv first token");
}

testGetkvLastToken(t: ref T)
{
	line := "path=/n/llm label=LLM perm=ro";
	t.assertseq(getkv(line, "perm"), "ro", "getkv last token");
}

testGetkvEmpty(t: ref T)
{
	t.assertseq(getkv("", "key"), "", "getkv empty line");
}

testGetkvPartialMatch(t: ref T)
{
	# "pathname" should not match "path"
	line := "pathname=/foo path=/bar";
	t.assertseq(getkv(line, "path"), "/bar", "getkv no partial match on pathname");
}

# --- cleanresponse tests ---

testCleanResponsePlainText(t: ref T)
{
	t.assertseq(cleanresponse("Hello world"), "Hello world",
		"plain text passes through");
}

testCleanResponseStripVeltroPrefix(t: ref T)
{
	t.assertseq(cleanresponse("[Veltro] Hello"), "Hello",
		"strip [Veltro] prefix");
}

testCleanResponseStripSay(t: ref T)
{
	t.assertseq(cleanresponse("say Hello world"), "Hello world",
		"strip say prefix");
}

testCleanResponseStripDone(t: ref T)
{
	result := cleanresponse("Hello world\nDONE");
	t.assertseq(result, "Hello world", "strip DONE line");
}

testCleanResponseMultiLine(t: ref T)
{
	result := cleanresponse("[Veltro] say Hello\nDONE");
	t.assertseq(result, "Hello", "strip [Veltro], say, and DONE");
}

testCleanResponseEmpty(t: ref T)
{
	# Empty response should return stripped original
	result := cleanresponse("  ");
	t.assertseq(result, "", "empty response");
}

# --- extractsay tests ---

testExtractSayBasic(t: ref T)
{
	(text, done) := extractsay("say Hello world");
	t.assertseq(text, "Hello world", "extractsay basic text");
	t.asserteq(done, 0, "extractsay not done");
}

testExtractSayDone(t: ref T)
{
	(text, done) := extractsay("DONE");
	t.assertnil(text, "extractsay DONE returns nil text");
	t.asserteq(done, 1, "extractsay DONE returns done=1");
}

testExtractSayMultiline(t: ref T)
{
	(text, nil) := extractsay("say First line\nSecond line\nDONE");
	t.assert(text != nil, "extractsay multiline returns text");
	t.assert(hasprefix(text, "First line"), "extractsay multiline starts with first line");
}

testExtractSayToolInvocation(t: ref T)
{
	(text, done) := extractsay("read /path/to/file");
	t.assertnil(text, "tool invocation returns nil text");
	t.asserteq(done, 0, "tool invocation returns done=0");
}

testExtractSayVeltroPrefix(t: ref T)
{
	(text, nil) := extractsay("[Veltro] say Hello");
	t.assertseq(text, "Hello", "extractsay with [Veltro] prefix");
}

# --- extractargs tests ---

testExtractArgsBasic(t: ref T)
{
	json := "{\"args\": \"read /path/to/file.txt\"}";
	result := extractargs(json);
	t.assertseq(result, "read /path/to/file.txt", "extractargs basic");
}

testExtractArgsEscapedNewline(t: ref T)
{
	json := "{\"args\": \"line1\\nline2\"}";
	result := extractargs(json);
	t.assertseq(result, "line1\nline2", "extractargs escaped newline");
}

testExtractArgsEscapedQuote(t: ref T)
{
	json := "{\"args\": \"say \\\"hello\\\"\"}";
	result := extractargs(json);
	t.assertseq(result, "say \"hello\"", "extractargs escaped quote");
}

testExtractArgsEscapedBackslash(t: ref T)
{
	json := "{\"args\": \"path\\\\to\\\\file\"}";
	result := extractargs(json);
	t.assertseq(result, "path\\to\\file", "extractargs escaped backslash");
}

testExtractArgsNoArgsKey(t: ref T)
{
	json := "{\"tool\": \"read\"}";
	result := extractargs(json);
	t.assertseq(result, json, "extractargs without args key returns original");
}

testExtractArgsEmpty(t: ref T)
{
	json := "{\"args\": \"\"}";
	result := extractargs(json);
	# Empty args returns original json (result == "" check)
	t.assertseq(result, json, "extractargs empty args returns original");
}

testExtractArgsEscapedTab(t: ref T)
{
	json := "{\"args\": \"col1\\tcol2\"}";
	result := extractargs(json);
	t.assertseq(result, "col1\tcol2", "extractargs escaped tab");
}

# --- filepathof tests ---

testFilepathofBasic(t: ref T)
{
	t.assertseq(filepathof("read /path/to/file"), "/path/to/file",
		"filepathof basic path");
}

testFilepathofMultiplePaths(t: ref T)
{
	t.assertseq(filepathof("copy /src/file /dst/file"), "/src/file",
		"filepathof returns first path");
}

testFilepathofNoPath(t: ref T)
{
	result := filepathof("just some text without paths");
	t.assertnil(result, "filepathof no path returns nil");
}

testFilepathofSlashOnly(t: ref T)
{
	# Single "/" is length 1, so not > 1
	result := filepathof("cd /");
	t.assertnil(result, "filepathof bare / is not a path (len <= 1)");
}

testFilepathofMixedArgs(t: ref T)
{
	t.assertseq(filepathof("write -f /output/data.txt"), "/output/data.txt",
		"filepathof with flags");
}

# --- pathbase tests ---

testPathbaseBasic(t: ref T)
{
	t.assertseq(pathbase("/usr/local/bin"), "bin", "pathbase basic");
}

testPathbaseTrailingSlash(t: ref T)
{
	t.assertseq(pathbase("/usr/local/bin/"), "bin", "pathbase trailing slash");
}

testPathbaseRoot(t: ref T)
{
	# "/" → path[1:] = ""
	t.assertseq(pathbase("/"), "", "pathbase root returns empty");
}

testPathbaseSingleComponent(t: ref T)
{
	t.assertseq(pathbase("/file"), "file", "pathbase single component");
}

testPathbaseMultipleTrailingSlashes(t: ref T)
{
	t.assertseq(pathbase("/foo/bar///"), "bar", "pathbase multiple trailing slashes");
}

# --- firstlines tests ---

testFirstlinesBasic(t: ref T)
{
	s := "line1\nline2\nline3\nline4\n";
	result := firstlines(s, 2);
	t.assertseq(result, "line1\nline2\n", "firstlines 2 of 4");
}

testFirstlinesExact(t: ref T)
{
	s := "a\nb\n";
	result := firstlines(s, 2);
	t.assertseq(result, "a\nb\n", "firstlines exact match");
}

testFirstlinesMore(t: ref T)
{
	s := "only\n";
	result := firstlines(s, 5);
	t.assertseq(result, "only\n", "firstlines more requested than available");
}

testFirstlinesZero(t: ref T)
{
	s := "line1\nline2\n";
	result := firstlines(s, 0);
	t.assertseq(result, "", "firstlines 0 returns empty");
}

# --- splitpathperm tests ---

testSplitpathpermRw(t: ref T)
{
	(path, perm) := splitpathperm("/n/local/tmp rw");
	t.assertseq(path, "/n/local/tmp", "splitpathperm rw: path");
	t.assertseq(perm, "rw", "splitpathperm rw: perm");
}

testSplitpathpermRo(t: ref T)
{
	(path, perm) := splitpathperm("/n/local/docs ro");
	t.assertseq(path, "/n/local/docs", "splitpathperm ro: path");
	t.assertseq(perm, "ro", "splitpathperm ro: perm");
}

testSplitpathpermDefault(t: ref T)
{
	(path, perm) := splitpathperm("/n/local/tmp");
	t.assertseq(path, "/n/local/tmp", "splitpathperm default: path");
	t.assertseq(perm, "rw", "splitpathperm default: perm is rw");
}

testSplitpathpermUnknownSuffix(t: ref T)
{
	# Suffix "foo" is not "ro" or "rw" — return whole string as path
	(path, perm) := splitpathperm("/path foo");
	t.assertseq(path, "/path foo", "splitpathperm unknown suffix: whole string");
	t.assertseq(perm, "rw", "splitpathperm unknown suffix: default rw");
}

# --- extractpaths tests ---

testExtractpathsBasic(t: ref T)
{
	lines := "/n/local/tmp rw" :: "/n/local/docs ro" :: nil;
	paths := extractpaths(lines);
	t.assert(paths != nil, "extractpaths returns non-nil");
	t.assertseq(hd paths, "/n/local/tmp", "extractpaths first path");
	t.assertseq(hd tl paths, "/n/local/docs", "extractpaths second path");
}

testExtractpathsPreservesOrder(t: ref T)
{
	lines := "/a" :: "/b" :: "/c" :: nil;
	paths := extractpaths(lines);
	t.assertseq(hd paths, "/a", "extractpaths order: first");
	t.assertseq(hd tl paths, "/b", "extractpaths order: second");
	t.assertseq(hd tl tl paths, "/c", "extractpaths order: third");
}

# --- lookuppathperm tests ---

testLookuppathpermFound(t: ref T)
{
	lines := "/a rw" :: "/b ro" :: "/c rw" :: nil;
	t.assertseq(lookuppathperm(lines, "/b"), "ro", "lookuppathperm found ro");
	t.assertseq(lookuppathperm(lines, "/a"), "rw", "lookuppathperm found rw");
}

testLookuppathpermNotFound(t: ref T)
{
	lines := "/a rw" :: nil;
	t.assertseq(lookuppathperm(lines, "/missing"), "rw",
		"lookuppathperm missing path defaults to rw");
}

# --- strcontains tests ---

testStrcontainsFound(t: ref T)
{
	l := "read" :: "write" :: "edit" :: nil;
	t.asserteq(strcontains(l, "write"), 1, "strcontains found");
}

testStrcontainsNotFound(t: ref T)
{
	l := "read" :: "write" :: nil;
	t.asserteq(strcontains(l, "exec"), 0, "strcontains not found");
}

testStrcontainsEmpty(t: ref T)
{
	t.asserteq(strcontains(nil, "anything"), 0, "strcontains empty list");
}

# ============================================================================
# Main
# ============================================================================

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	# getkv
	run("GetkvBasic", testGetkvBasic);
	run("GetkvMissing", testGetkvMissing);
	run("GetkvFirstToken", testGetkvFirstToken);
	run("GetkvLastToken", testGetkvLastToken);
	run("GetkvEmpty", testGetkvEmpty);
	run("GetkvPartialMatch", testGetkvPartialMatch);

	# cleanresponse
	run("CleanResponsePlainText", testCleanResponsePlainText);
	run("CleanResponseStripVeltroPrefix", testCleanResponseStripVeltroPrefix);
	run("CleanResponseStripSay", testCleanResponseStripSay);
	run("CleanResponseStripDone", testCleanResponseStripDone);
	run("CleanResponseMultiLine", testCleanResponseMultiLine);
	run("CleanResponseEmpty", testCleanResponseEmpty);

	# extractsay
	run("ExtractSayBasic", testExtractSayBasic);
	run("ExtractSayDone", testExtractSayDone);
	run("ExtractSayMultiline", testExtractSayMultiline);
	run("ExtractSayToolInvocation", testExtractSayToolInvocation);
	run("ExtractSayVeltroPrefix", testExtractSayVeltroPrefix);

	# extractargs
	run("ExtractArgsBasic", testExtractArgsBasic);
	run("ExtractArgsEscapedNewline", testExtractArgsEscapedNewline);
	run("ExtractArgsEscapedQuote", testExtractArgsEscapedQuote);
	run("ExtractArgsEscapedBackslash", testExtractArgsEscapedBackslash);
	run("ExtractArgsNoArgsKey", testExtractArgsNoArgsKey);
	run("ExtractArgsEmpty", testExtractArgsEmpty);
	run("ExtractArgsEscapedTab", testExtractArgsEscapedTab);

	# filepathof
	run("FilepathofBasic", testFilepathofBasic);
	run("FilepathofMultiplePaths", testFilepathofMultiplePaths);
	run("FilepathofNoPath", testFilepathofNoPath);
	run("FilepathofSlashOnly", testFilepathofSlashOnly);
	run("FilepathofMixedArgs", testFilepathofMixedArgs);

	# pathbase
	run("PathbaseBasic", testPathbaseBasic);
	run("PathbaseTrailingSlash", testPathbaseTrailingSlash);
	run("PathbaseRoot", testPathbaseRoot);
	run("PathbaseSingleComponent", testPathbaseSingleComponent);
	run("PathbaseMultipleTrailingSlashes", testPathbaseMultipleTrailingSlashes);

	# firstlines
	run("FirstlinesBasic", testFirstlinesBasic);
	run("FirstlinesExact", testFirstlinesExact);
	run("FirstlinesMore", testFirstlinesMore);
	run("FirstlinesZero", testFirstlinesZero);

	# splitpathperm
	run("SplitpathpermRw", testSplitpathpermRw);
	run("SplitpathpermRo", testSplitpathpermRo);
	run("SplitpathpermDefault", testSplitpathpermDefault);
	run("SplitpathpermUnknownSuffix", testSplitpathpermUnknownSuffix);

	# extractpaths
	run("ExtractpathsBasic", testExtractpathsBasic);
	run("ExtractpathsPreservesOrder", testExtractpathsPreservesOrder);

	# lookuppathperm
	run("LookuppathpermFound", testLookuppathpermFound);
	run("LookuppathpermNotFound", testLookuppathpermNotFound);

	# strcontains
	run("StrcontainsFound", testStrcontainsFound);
	run("StrcontainsNotFound", testStrcontainsNotFound);
	run("StrcontainsEmpty", testStrcontainsEmpty);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
