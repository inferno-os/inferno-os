implement LuciferHelpersTest;

#
# Unit tests for shared helper functions used across Lucifer zones.
#
# The parseattrs/getattr pair is duplicated in lucictx.b, luciconv.b, and
# lucipres.b — it is the critical parser for all 9P ctl commands and file
# reads in the Lucifer UI.  A single copy is tested here.
#
# Also covers:
#   - parseattrs/getattr: attribute parsing from "key=val key2=val2" strings
#   - text= terminal attribute handling (embedded = signs in LLM responses)
#   - safename: filename sanitization for artifact export
#   - tabparsecells/tabissep/tabcountcols: table rendering helpers
#   - splitlines: line splitting for text/code display
#   - pathbase/pathparent: path component extraction
#   - slugify: name-to-slug conversion
#   - islaunchabledis: .dis app whitelist check
#   - sortstrlist: string list sorting
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

LuciferHelpersTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/lucifer_helpers_test.b";

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
# Local copies of Lucifer helper functions
# ============================================================================

Attr: adt {
	key: string;
	val: string;
};

# parseattrs — mirrors the implementation in lucictx.b/luciconv.b/lucipres.b
parseattrs(s: string): list of ref Attr
{
	kstarts := array[32] of int;
	eqposs := array[32] of int;
	nkp := 0;

	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;

	j := i;
	while(j < len s) {
		if(s[j] == '=') {
			kstart := j - 1;
			while(kstart > i && s[kstart - 1] != ' ' && s[kstart - 1] != '\t')
				kstart--;
			if(kstart >= 0 && kstart < j) {
				if(kstart == 0 || kstart == i || s[kstart - 1] == ' ' || s[kstart - 1] == '\t') {
					if(nkp >= len kstarts) {
						nks := array[len kstarts * 2] of int;
						nks[0:] = kstarts[0:nkp];
						kstarts = nks;
						neq := array[len eqposs * 2] of int;
						neq[0:] = eqposs[0:nkp];
						eqposs = neq;
					}
					kstarts[nkp] = kstart;
					eqposs[nkp] = j;
					nkp++;
				}
			}
		}
		j++;
	}

	attrs: list of ref Attr;
	for(k := 0; k < nkp; k++) {
		key := s[kstarts[k]:eqposs[k]];
		vstart := eqposs[k] + 1;
		vend: int;
		if(key != "text" && key != "data" && k + 1 < nkp) {
			vend = kstarts[k + 1];
			while(vend > vstart && (s[vend - 1] == ' ' || s[vend - 1] == '\t'))
				vend--;
		} else
			vend = len s;
		val := "";
		if(vstart < vend)
			val = s[vstart:vend];
		attrs = ref Attr(key, val) :: attrs;
		if(key == "text" || key == "data")
			break;
	}

	rev: list of ref Attr;
	for(; attrs != nil; attrs = tl attrs)
		rev = hd attrs :: rev;
	return rev;
}

getattr(attrs: list of ref Attr, key: string): string
{
	for(; attrs != nil; attrs = tl attrs)
		if((hd attrs).key == key)
			return (hd attrs).val;
	return nil;
}

# safename — mirrors lucipres.b
safename(s: string): string
{
	r := "";
	for(i := 0; i < len s && i < 64; i++) {
		c := s[i];
		if((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
		   (c >= '0' && c <= '9') || c == '-' || c == '_')
			r += s[i:i+1];
		else if(c == ' ' && len r > 0 && r[len r - 1] != '-')
			r += "-";
	}
	return r;
}

# trimcell — mirrors lucipres.b
trimcell(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t')) i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n')) j--;
	if(i >= j) return "";
	return s[i:j];
}

tabparsecells(line: string): list of string
{
	cells: list of string;
	i := 0;
	n := len line;
	while(i < n && (line[i] == ' ' || line[i] == '\t')) i++;
	if(i < n && line[i] == '|') i++;
	while(i < n) {
		j := i;
		while(j < n && line[j] != '|') j++;
		cell := trimcell(line[i:j]);
		cells = cell :: cells;
		if(j >= n) break;
		i = j + 1;
	}
	if(cells != nil && hd cells == "")
		cells = tl cells;
	rev: list of string;
	for(; cells != nil; cells = tl cells)
		rev = hd cells :: rev;
	return rev;
}

tabissep(line: string): int
{
	cells := tabparsecells(line);
	if(cells == nil) return 0;
	for(; cells != nil; cells = tl cells) {
		c := hd cells;
		if(len c == 0) return 0;
		for(i := 0; i < len c; i++) {
			ch := c[i];
			if(ch != '-' && ch != ':' && ch != ' ')
				return 0;
		}
	}
	return 1;
}

tabcountcols(line: string): int
{
	n := 0;
	for(cl := tabparsecells(line); cl != nil; cl = tl cl)
		n++;
	return n;
}

splitlines(text: string): list of string
{
	if(text == nil || text == "")
		return "" :: nil;
	lines: list of string;
	i := 0;
	linestart := 0;
	while(i < len text) {
		if(text[i] == '\n') {
			lines = text[linestart:i] :: lines;
			linestart = i + 1;
		}
		i++;
	}
	if(linestart < len text)
		lines = text[linestart:] :: lines;
	rev: list of string;
	for(; lines != nil; lines = tl lines)
		rev = hd lines :: rev;
	return rev;
}

pathbase(s: string): string
{
	if(s == nil || s == "")
		return "";
	while(len s > 1 && s[len s - 1] == '/')
		s = s[0:len s - 1];
	i := len s - 1;
	while(i > 0 && s[i] != '/')
		i--;
	if(s[i] == '/')
		return s[i + 1:];
	return s;
}

pathparent(s: string): string
{
	if(s == nil || s == "" || s == "/")
		return "/";
	while(len s > 1 && s[len s - 1] == '/')
		s = s[0:len s - 1];
	i := len s - 1;
	while(i > 0 && s[i] != '/')
		i--;
	if(i == 0)
		return "/";
	return s[0:i];
}

slugify(s: string): string
{
	r := s;
	for(i := 0; i < len r; i++) {
		c := r[i];
		if(c >= 'A' && c <= 'Z')
			r[i] = c + ('a' - 'A');
		else if(c == ' ' || c == '\t')
			r[i] = '-';
	}
	return r;
}

islaunchabledis(path: string): int
{
	if(len path < 5 || path[len path - 4:] != ".dis")
		return 0;
	prefixes := "/dis/wm/" :: "/dis/charon/" :: "/dis/xenith/" :: nil;
	for(pl := prefixes; pl != nil; pl = tl pl) {
		pfx := hd pl;
		if(len path >= len pfx && path[0:len pfx] == pfx)
			return 1;
	}
	return 0;
}

sortstrlist(l: list of string): list of string
{
	n := 0;
	for(p := l; p != nil; p = tl p)
		n++;
	if(n == 0)
		return nil;
	a := array[n] of string;
	i := 0;
	for(p = l; p != nil; p = tl p)
		a[i++] = hd p;
	for(i = 1; i < n; i++) {
		v := a[i];
		j := i - 1;
		while(j >= 0 && a[j] > v) {
			a[j + 1] = a[j];
			j--;
		}
		a[j + 1] = v;
	}
	result: list of string;
	for(i = n - 1; i >= 0; i--)
		result = a[i] :: result;
	return result;
}

# ============================================================================
# Tests
# ============================================================================

# --- parseattrs / getattr tests ---

testParseattrsBasic(t: ref T)
{
	attrs := parseattrs("role=human text=Hello world");
	t.assertseq(getattr(attrs, "role"), "human", "parseattrs role");
	t.assertseq(getattr(attrs, "text"), "Hello world", "parseattrs text (terminal)");
}

testParseattrsMultipleKeys(t: ref T)
{
	attrs := parseattrs("path=/api/test label=TestAPI type=api status=streaming");
	t.assertseq(getattr(attrs, "path"), "/api/test", "parseattrs path");
	t.assertseq(getattr(attrs, "label"), "TestAPI", "parseattrs label");
	t.assertseq(getattr(attrs, "type"), "api", "parseattrs type");
	t.assertseq(getattr(attrs, "status"), "streaming", "parseattrs status");
}

testParseattrsTextTerminal(t: ref T)
{
	# text= is a terminal key — everything after it is the value,
	# even if it contains embedded "key=value" patterns
	attrs := parseattrs("role=veltro text=access=read type=text path=/foo");
	t.assertseq(getattr(attrs, "role"), "veltro", "text terminal: role");
	text := getattr(attrs, "text");
	t.assertnotnil(text, "text terminal: text exists");
	# The full text including embedded = patterns should be preserved
	t.assert(len text > len "access=read", "text terminal: full text preserved");
}

testParseattrsDataTerminal(t: ref T)
{
	# data= is also terminal, like text=
	attrs := parseattrs("id=test type=markdown data=# Hello\nSome content");
	t.assertseq(getattr(attrs, "id"), "test", "data terminal: id");
	t.assertseq(getattr(attrs, "type"), "markdown", "data terminal: type");
	data := getattr(attrs, "data");
	t.assertnotnil(data, "data terminal: data exists");
}

testParseattrsLeadingWhitespace(t: ref T)
{
	attrs := parseattrs("  role=human text=hello");
	t.assertseq(getattr(attrs, "role"), "human", "leading whitespace stripped");
}

testParseattrsMissingKey(t: ref T)
{
	attrs := parseattrs("role=human");
	result := getattr(attrs, "missing");
	t.assertnil(result, "missing key returns nil");
}

testParseattrsEmpty(t: ref T)
{
	attrs := parseattrs("");
	result := getattr(attrs, "anything");
	t.assertnil(result, "empty string returns nil for any key");
}

testParseattrsEmbeddedEquals(t: ref T)
{
	# Regression: LLM responses contain patterns like "max_tokens=4096"
	# text= must capture everything after it, not stop at embedded =
	s := "role=veltro text=The setting max_tokens=4096 controls generation length.";
	attrs := parseattrs(s);
	text := getattr(attrs, "text");
	t.assertnotnil(text, "embedded equals: text exists");
	# Check the full sentence is preserved
	hassubstr := 0;
	needle := "max_tokens=4096";
	for(i := 0; i <= len text - len needle; i++)
		if(text[i:i+len needle] == needle) { hassubstr = 1; break; }
	t.assert(hassubstr != 0, "embedded equals: max_tokens=4096 preserved in text");
}

# --- safename tests ---

testSafenameAlphanumeric(t: ref T)
{
	t.assertseq(safename("HelloWorld123"), "HelloWorld123",
		"safename: alphanumeric passes through");
}

testSafenameSpaces(t: ref T)
{
	t.assertseq(safename("Hello World"), "Hello-World",
		"safename: spaces become hyphens");
}

testSafenameSpecialChars(t: ref T)
{
	# dots are not in the allowed set (a-z A-Z 0-9 - _)
	t.assertseq(safename("file@name!.txt"), "filenametxt",
		"safename: special chars stripped");
}

testSafenameLeadingSpace(t: ref T)
{
	# Leading space: len r > 0 check means no leading hyphen
	t.assertseq(safename(" hello"), "hello",
		"safename: leading space produces no leading hyphen");
}

testSafenameEmpty(t: ref T)
{
	t.assertseq(safename(""), "", "safename: empty string");
}

testSafenameHyphensUnderscores(t: ref T)
{
	t.assertseq(safename("my-file_name"), "my-file_name",
		"safename: hyphens and underscores preserved");
}

testSafenameTruncation(t: ref T)
{
	# safename truncates at 64 characters
	long := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; # 70 chars
	result := safename(long);
	t.asserteq(len result, 64, "safename: truncated at 64 chars");
}

# --- tabparsecells tests ---

testTabparsecellsBasic(t: ref T)
{
	cells := tabparsecells("| Name | Age | City |");
	t.assertseq(hd cells, "Name", "tabparsecells first cell");
	t.assertseq(hd tl cells, "Age", "tabparsecells second cell");
	t.assertseq(hd tl tl cells, "City", "tabparsecells third cell");
}

testTabparsecellsNoPipes(t: ref T)
{
	cells := tabparsecells("just text");
	t.assert(cells != nil, "tabparsecells without pipes returns non-nil");
	t.assertseq(hd cells, "just text", "tabparsecells without pipes: single cell");
}

testTabparsecellsTrimming(t: ref T)
{
	cells := tabparsecells("|  Name  |  Age  |");
	t.assertseq(hd cells, "Name", "tabparsecells trims whitespace");
	t.assertseq(hd tl cells, "Age", "tabparsecells trims second cell");
}

# --- tabissep tests ---

testTabissepDashes(t: ref T)
{
	t.asserteq(tabissep("|---|---|"), 1, "tabissep: dashes is separator");
}

testTabissepColons(t: ref T)
{
	t.asserteq(tabissep("|:---:|:---|"), 1, "tabissep: colons and dashes is separator");
}

testTabissepContent(t: ref T)
{
	t.asserteq(tabissep("| Name | Age |"), 0, "tabissep: content is not separator");
}

testTabissepEmpty(t: ref T)
{
	t.asserteq(tabissep(""), 0, "tabissep: empty is not separator");
}

# --- tabcountcols tests ---

testTabcountcolsThree(t: ref T)
{
	t.asserteq(tabcountcols("| A | B | C |"), 3, "tabcountcols: 3 columns");
}

testTabcountcolsOne(t: ref T)
{
	t.asserteq(tabcountcols("| A |"), 1, "tabcountcols: 1 column");
}

# --- splitlines tests ---

testSplitlinesBasic(t: ref T)
{
	lines := splitlines("line1\nline2\nline3");
	t.assertseq(hd lines, "line1", "splitlines: first line");
	t.assertseq(hd tl lines, "line2", "splitlines: second line");
	t.assertseq(hd tl tl lines, "line3", "splitlines: third line");
}

testSplitlinesTrailingNewline(t: ref T)
{
	lines := splitlines("a\nb\n");
	# Should have 3 entries: "a", "b", and empty trailing (from linestart < len)
	# Actually: "a\nb\n" → "a" at 0:1, "b" at 2:3, trailing newline means
	# linestart=4 == len text, so no trailing entry. Just "a" and "b".
	t.assertseq(hd lines, "a", "splitlines trailing: first");
	t.assertseq(hd tl lines, "b", "splitlines trailing: second");
}

testSplitlinesEmpty(t: ref T)
{
	lines := splitlines("");
	t.assert(lines != nil, "splitlines empty returns non-nil");
	t.assertseq(hd lines, "", "splitlines empty returns single empty string");
}

testSplitlinesSingleLine(t: ref T)
{
	lines := splitlines("no newlines here");
	t.assertseq(hd lines, "no newlines here", "splitlines single line");
}

# --- pathbase tests ---

testPathbaseFile(t: ref T)
{
	t.assertseq(pathbase("/usr/local/bin/foo"), "foo", "pathbase file");
}

testPathbaseDir(t: ref T)
{
	t.assertseq(pathbase("/usr/local/bin/"), "bin", "pathbase dir trailing slash");
}

testPathbaseRoot(t: ref T)
{
	# "/" → s[1:] = ""
	t.assertseq(pathbase("/"), "", "pathbase root returns empty");
}

testPathbaseEmpty(t: ref T)
{
	t.assertseq(pathbase(""), "", "pathbase empty");
}

# --- pathparent tests ---

testPathparentBasic(t: ref T)
{
	t.assertseq(pathparent("/usr/local/bin"), "/usr/local", "pathparent basic");
}

testPathparentRoot(t: ref T)
{
	t.assertseq(pathparent("/"), "/", "pathparent root");
}

testPathparentTopLevel(t: ref T)
{
	t.assertseq(pathparent("/foo"), "/", "pathparent top-level");
}

testPathparentTrailingSlash(t: ref T)
{
	t.assertseq(pathparent("/usr/local/"), "/usr", "pathparent trailing slash");
}

testPathparentEmpty(t: ref T)
{
	t.assertseq(pathparent(""), "/", "pathparent empty");
}

# --- slugify tests ---

testSlugifyBasic(t: ref T)
{
	t.assertseq(slugify("Hello World"), "hello-world", "slugify basic");
}

testSlugifyLowercase(t: ref T)
{
	t.assertseq(slugify("ABC"), "abc", "slugify uppercase to lowercase");
}

testSlugifyTabs(t: ref T)
{
	t.assertseq(slugify("a\tb"), "a-b", "slugify tab to hyphen");
}

testSlugifyAlreadyLower(t: ref T)
{
	t.assertseq(slugify("already-lower"), "already-lower", "slugify no-op");
}

# --- islaunchabledis tests ---

testIslaunchabledisWm(t: ref T)
{
	t.asserteq(islaunchabledis("/dis/wm/clock.dis"), 1,
		"islaunchabledis: /dis/wm/ allowed");
}

testIslaunchabledisCharon(t: ref T)
{
	t.asserteq(islaunchabledis("/dis/charon/charon.dis"), 1,
		"islaunchabledis: /dis/charon/ allowed");
}

testIslaunchabledisXenith(t: ref T)
{
	t.asserteq(islaunchabledis("/dis/xenith/xenith.dis"), 1,
		"islaunchabledis: /dis/xenith/ allowed");
}

testIslaunchabledisNotAllowed(t: ref T)
{
	t.asserteq(islaunchabledis("/dis/cmd/ls.dis"), 0,
		"islaunchabledis: /dis/cmd/ not allowed");
}

testIslaunchabledisNotDis(t: ref T)
{
	t.asserteq(islaunchabledis("/dis/wm/clock.b"), 0,
		"islaunchabledis: non-.dis file not allowed");
}

testIslaunchabledisShort(t: ref T)
{
	t.asserteq(islaunchabledis("a.dis"), 0,
		"islaunchabledis: short path not allowed");
}

# --- sortstrlist tests ---

testSortstrlistBasic(t: ref T)
{
	l := "cherry" :: "apple" :: "banana" :: nil;
	sorted := sortstrlist(l);
	t.assertseq(hd sorted, "apple", "sortstrlist: first");
	t.assertseq(hd tl sorted, "banana", "sortstrlist: second");
	t.assertseq(hd tl tl sorted, "cherry", "sortstrlist: third");
}

testSortstrlistAlreadySorted(t: ref T)
{
	l := "a" :: "b" :: "c" :: nil;
	sorted := sortstrlist(l);
	t.assertseq(hd sorted, "a", "sortstrlist sorted: first");
	t.assertseq(hd tl sorted, "b", "sortstrlist sorted: second");
}

testSortstrlistEmpty(t: ref T)
{
	sorted := sortstrlist(nil);
	t.assert(sorted == nil, "sortstrlist: nil returns nil");
}

testSortstrlistSingle(t: ref T)
{
	sorted := sortstrlist("only" :: nil);
	t.assertseq(hd sorted, "only", "sortstrlist: single element");
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

	# parseattrs / getattr
	run("ParseattrsBasic", testParseattrsBasic);
	run("ParseattrsMultipleKeys", testParseattrsMultipleKeys);
	run("ParseattrsTextTerminal", testParseattrsTextTerminal);
	run("ParseattrsDataTerminal", testParseattrsDataTerminal);
	run("ParseattrsLeadingWhitespace", testParseattrsLeadingWhitespace);
	run("ParseattrsMissingKey", testParseattrsMissingKey);
	run("ParseattrsEmpty", testParseattrsEmpty);
	run("ParseattrsEmbeddedEquals", testParseattrsEmbeddedEquals);

	# safename
	run("SafenameAlphanumeric", testSafenameAlphanumeric);
	run("SafenameSpaces", testSafenameSpaces);
	run("SafenameSpecialChars", testSafenameSpecialChars);
	run("SafenameLeadingSpace", testSafenameLeadingSpace);
	run("SafenameEmpty", testSafenameEmpty);
	run("SafenameHyphensUnderscores", testSafenameHyphensUnderscores);
	run("SafenameTruncation", testSafenameTruncation);

	# tabparsecells
	run("TabparsecellsBasic", testTabparsecellsBasic);
	run("TabparsecellsNoPipes", testTabparsecellsNoPipes);
	run("TabparsecellsTrimming", testTabparsecellsTrimming);

	# tabissep
	run("TabissepDashes", testTabissepDashes);
	run("TabissepColons", testTabissepColons);
	run("TabissepContent", testTabissepContent);
	run("TabissepEmpty", testTabissepEmpty);

	# tabcountcols
	run("TabcountcolsThree", testTabcountcolsThree);
	run("TabcountcolsOne", testTabcountcolsOne);

	# splitlines
	run("SplitlinesBasic", testSplitlinesBasic);
	run("SplitlinesTrailingNewline", testSplitlinesTrailingNewline);
	run("SplitlinesEmpty", testSplitlinesEmpty);
	run("SplitlinesSingleLine", testSplitlinesSingleLine);

	# pathbase
	run("PathbaseFile", testPathbaseFile);
	run("PathbaseDir", testPathbaseDir);
	run("PathbaseRoot", testPathbaseRoot);
	run("PathbaseEmpty", testPathbaseEmpty);

	# pathparent
	run("PathparentBasic", testPathparentBasic);
	run("PathparentRoot", testPathparentRoot);
	run("PathparentTopLevel", testPathparentTopLevel);
	run("PathparentTrailingSlash", testPathparentTrailingSlash);
	run("PathparentEmpty", testPathparentEmpty);

	# slugify
	run("SlugifyBasic", testSlugifyBasic);
	run("SlugifyLowercase", testSlugifyLowercase);
	run("SlugifyTabs", testSlugifyTabs);
	run("SlugifyAlreadyLower", testSlugifyAlreadyLower);

	# islaunchabledis
	run("IslaunchabledisWm", testIslaunchabledisWm);
	run("IslaunchabledisCharon", testIslaunchabledisCharon);
	run("IslaunchabledisXenith", testIslaunchabledisXenith);
	run("IslaunchabledisNotAllowed", testIslaunchabledisNotAllowed);
	run("IslaunchabledisNotDis", testIslaunchabledisNotDis);
	run("IslaunchabledisShort", testIslaunchabledisShort);

	# sortstrlist
	run("SortstrlistBasic", testSortstrlistBasic);
	run("SortstrlistAlreadySorted", testSortstrlistAlreadySorted);
	run("SortstrlistEmpty", testSortstrlistEmpty);
	run("SortstrlistSingle", testSortstrlistSingle);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
