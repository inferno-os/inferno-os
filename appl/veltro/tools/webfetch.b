implement ToolWebfetch;

#
# webfetch - Fetch web page and extract readable text for Veltro agent
#
# Fetches a URL via HTTPS and converts HTML to clean, readable text.
# Strips navigation, scripts, styles, and other noise — returns only
# the meaningful content. This is the "read a web page" tool.
#
# Usage:
#   webfetch <url>
#   webfetch <url> <prompt>
#
# The optional prompt tells the agent what to focus on when reading
# the page, but the tool itself always returns the full extracted text.
# The prompt is reserved for future AI-summarization support.
#
# Examples:
#   webfetch https://example.com/article
#   webfetch https://en.wikipedia.org/wiki/Plan_9_from_Bell_Labs
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "webclient.m";
	webclient: Webclient;

include "../tool.m";

ToolWebfetch: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

REQUEST_TIMEOUT: con 30000;	# 30 seconds
MAX_BODY: con 512 * 1024;	# 512KB max page size

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";
	webclient = load Webclient Webclient->PATH;
	if(webclient == nil)
		return "cannot load Webclient";
	err := webclient->init();
	if(err != nil)
		return "Webclient init: " + err;
	return nil;
}

name(): string
{
	return "webfetch";
}

doc(): string
{
	return "Webfetch - Fetch a web page and extract readable text\n\n" +
		"Usage:\n" +
		"  webfetch <url>\n" +
		"  webfetch <url> <prompt>\n\n" +
		"Arguments:\n" +
		"  url    - Full URL (https://...)\n" +
		"  prompt - What to focus on (optional, for future use)\n\n" +
		"Examples:\n" +
		"  webfetch https://example.com/article\n" +
		"  webfetch https://en.wikipedia.org/wiki/Plan_9\n\n" +
		"Fetches the page and returns clean readable text.\n" +
		"HTML tags, scripts, styles, and navigation are stripped.\n" +
		"Block elements become paragraphs. Links show their URLs.\n" +
		"Requires /net access (trusted agents only).";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	# Parse: first token is URL, rest is optional prompt
	s := strip(args);
	if(s == "")
		return "error: usage: webfetch <url> [prompt]";

	url := s;
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t') {
			url = s[0:i];
			break;
		}
	}

	# Validate URL scheme
	lurl := str->tolower(url);
	if(!hasprefix(lurl, "http://") && !hasprefix(lurl, "https://"))
		return "error: URL must start with http:// or https://";

	# SSRF protection: block requests to internal/private network addresses
	host := extracthost(url);
	if(isblocked(host))
		return "error: requests to internal/private network addresses are not allowed";

	# Fetch with timeout
	hdrs := Webclient->Header("User-Agent", "Veltro/1.0 (readable text extraction)") ::
		Webclient->Header("Accept", "text/html, application/xhtml+xml, text/plain, */*") :: nil;

	result := chan[1] of (ref Webclient->Response, string);
	spawn dofetch(url, hdrs, result);

	timeout := chan[1] of int;
	spawn timer(timeout, REQUEST_TIMEOUT);

	resp: ref Webclient->Response;
	err: string;
	alt {
	(r, e) := <-result =>
		(resp, err) = (r, e);
	<-timeout =>
		return "error: request timed out (30s)";
	}

	if(err != nil)
		return "error: fetch failed: " + err;
	if(resp.statuscode >= 400)
		return sys->sprint("error: HTTP %d", resp.statuscode);
	if(resp.body == nil || len resp.body == 0)
		return "error: empty response";

	# Truncate oversized responses
	body := resp.body;
	if(len body > MAX_BODY)
		body = body[0:MAX_BODY];

	raw := string body;

	# Detect content type — if not HTML, return raw text
	ctype := getheader(resp.headers, "content-type");
	if(ctype != "" && !hassubstr(str->tolower(ctype), "html"))
		return raw;

	# Extract readable text from HTML
	return html2text(raw);
}

# Get a response header value by name (case-insensitive)
getheader(hdrs: list of Webclient->Header, name: string): string
{
	lname := str->tolower(name);
	for(; hdrs != nil; hdrs = tl hdrs) {
		h := hd hdrs;
		if(str->tolower(h.name) == lname)
			return h.value;
	}
	return "";
}

# Convert HTML to readable plain text.
#
# Strategy:
# 1. Remove <script>, <style>, <nav>, <header>, <footer>, <aside> blocks entirely
# 2. Convert block elements (<p>, <h1>-<h6>, <div>, <li>, <br>, <tr>) to newlines
# 3. Convert <a href="url">text</a> to "text (url)"
# 4. Strip all remaining tags
# 5. Decode common HTML entities
# 6. Collapse whitespace and blank lines
html2text(html: string): string
{
	s := html;

	# Phase 1: Remove invisible/noise blocks entirely
	s = removeblocks(s, "script");
	s = removeblocks(s, "style");
	s = removeblocks(s, "nav");
	s = removeblocks(s, "noscript");
	s = removeblocks(s, "svg");

	# Phase 2: Convert links to "text (url)" before stripping tags
	s = convertlinks(s);

	# Phase 3: Insert newlines for block elements
	s = blocktags2nl(s);

	# Phase 4: Strip all remaining HTML tags
	s = striptags(s);

	# Phase 5: Decode HTML entities
	s = decodeentities(s);

	# Phase 6: Clean up whitespace
	s = cleanwhitespace(s);

	return s;
}

# Remove all occurrences of <tag>...</tag> (case-insensitive)
removeblocks(s, tag: string): string
{
	result := "";
	i := 0;
	while(i < len s) {
		# Look for opening tag
		tagstart := findtagi(s, "<" + tag, i);
		if(tagstart < 0) {
			result += s[i:];
			break;
		}
		# Make sure it's actually <tag> or <tag ...> not <tagfoo>
		endpos := tagstart + len tag + 1;
		if(endpos < len s && s[endpos] != '>' && s[endpos] != ' ' &&
		   s[endpos] != '\t' && s[endpos] != '\n' && s[endpos] != '/') {
			result += s[i:endpos];
			i = endpos;
			continue;
		}
		result += s[i:tagstart];
		# Find closing </tag>
		closestart := findtagi(s, "</" + tag, endpos);
		if(closestart < 0) {
			# No closing tag — remove rest
			break;
		}
		# Skip past closing tag's >
		j := closestart;
		while(j < len s && s[j] != '>')
			j++;
		i = j + 1;
	}
	return result;
}

# Case-insensitive find of needle starting from pos
findtagi(s, needle: string, pos: int): int
{
	nlen := len needle;
	if(nlen > len s)
		return -1;
	for(i := pos; i <= len s - nlen; i++) {
		match := 1;
		for(j := 0; j < nlen; j++) {
			a := s[i+j];
			b := needle[j];
			if(a >= 'A' && a <= 'Z')
				a += 'a' - 'A';
			if(b >= 'A' && b <= 'Z')
				b += 'a' - 'A';
			if(a != b) {
				match = 0;
				break;
			}
		}
		if(match)
			return i;
	}
	return -1;
}

# Convert <a href="url">text</a> to "text (url)"
convertlinks(s: string): string
{
	result := "";
	i := 0;
	while(i < len s) {
		astart := findtagi(s, "<a ", i);
		if(astart < 0) {
			result += s[i:];
			break;
		}
		result += s[i:astart];

		# Find end of opening <a> tag
		tagend := findchar(s, '>', astart);
		if(tagend < 0) {
			result += s[astart:];
			break;
		}

		# Extract href from tag attributes
		href := extractattr(s[astart:tagend+1], "href");

		# Find closing </a>
		closestart := findtagi(s, "</a", tagend);
		if(closestart < 0) {
			# No closing tag — just emit the text after >
			i = tagend + 1;
			continue;
		}

		# Link text is between > and </a
		linktext := s[tagend+1:closestart];

		# Skip past </a>
		j := closestart;
		while(j < len s && s[j] != '>')
			j++;
		i = j + 1;

		# Emit: "text (url)" or just "text" if no href
		lt := strip(striptags(linktext));
		if(lt == "")
			continue;
		if(href != "" && href != "#" && !hasprefix(href, "javascript:"))
			result += lt + " (" + href + ")";
		else
			result += lt;
	}
	return result;
}

# Extract an attribute value from an HTML tag string like <a href="url" class="x">
extractattr(tag, attrname: string): string
{
	needle := str->tolower(attrname) + "=";
	ltag := str->tolower(tag);
	pos := findstr(ltag, needle);
	if(pos < 0)
		return "";
	pos += len needle;
	if(pos >= len tag)
		return "";

	# Quoted value?
	if(tag[pos] == '"' || tag[pos] == '\'') {
		quote := tag[pos];
		pos++;
		end := pos;
		while(end < len tag && tag[end] != quote)
			end++;
		return tag[pos:end];
	}
	# Unquoted value — ends at space or >
	end := pos;
	while(end < len tag && tag[end] != ' ' && tag[end] != '>' && tag[end] != '\t')
		end++;
	return tag[pos:end];
}

# Insert newlines before block-level elements
blocktags2nl(s: string): string
{
	# Replace block tags with newlines
	blocktags := array[] of {
		"p", "div", "section", "article", "main",
		"h1", "h2", "h3", "h4", "h5", "h6",
		"li", "dt", "dd",
		"tr", "blockquote", "pre",
		"br", "hr"
	};

	for(ti := 0; ti < len blocktags; ti++) {
		tag := blocktags[ti];
		# Replace opening tags with newline
		s = replacetag(s, "<" + tag + ">", "\n");
		s = replacetag(s, "<" + tag + " ", "\n");
		# Replace closing tags with newline
		s = replacetag(s, "</" + tag + ">", "\n");
	}

	# <br/> and <br /> variants
	s = replacetag(s, "<br/>", "\n");
	s = replacetag(s, "<br />", "\n");

	# Heading markers: add ## prefix after newline for structure
	for(h := 1; h <= 6; h++) {
		opentag := sys->sprint("<h%d>", h);
		closetag := sys->sprint("</h%d>", h);
		prefix := "";
		for(hi := 0; hi < h; hi++)
			prefix += "#";
		prefix += " ";
		s = replacetag(s, opentag, "\n" + prefix);
		s = replacetag(s, closetag, "\n");
	}

	return s;
}

# Case-insensitive tag replacement
replacetag(s, tag, replacement: string): string
{
	result := "";
	i := 0;
	while(i < len s) {
		pos := findtagi(s, tag, i);
		if(pos < 0) {
			result += s[i:];
			break;
		}
		result += s[i:pos] + replacement;
		# If tag ends with space (attribute match), skip to >
		j := pos + len tag;
		if(len tag > 0 && tag[len tag - 1] == ' ') {
			while(j < len s && s[j] != '>')
				j++;
			if(j < len s)
				j++; # skip >
		}
		i = j;
	}
	return result;
}

# Strip all HTML tags from string
striptags(s: string): string
{
	result := "";
	intag := 0;
	for(i := 0; i < len s; i++) {
		if(s[i] == '<')
			intag = 1;
		else if(s[i] == '>')
			intag = 0;
		else if(!intag)
			result[len result] = s[i];
	}
	return result;
}

# Decode common HTML entities
decodeentities(s: string): string
{
	s = replaceall(s, "&amp;", "&");
	s = replaceall(s, "&lt;", "<");
	s = replaceall(s, "&gt;", ">");
	s = replaceall(s, "&quot;", "\"");
	s = replaceall(s, "&#39;", "'");
	s = replaceall(s, "&apos;", "'");
	s = replaceall(s, "&nbsp;", " ");
	s = replaceall(s, "&mdash;", "—");
	s = replaceall(s, "&ndash;", "–");
	s = replaceall(s, "&hellip;", "...");
	s = replaceall(s, "&copy;", "(c)");
	s = replaceall(s, "&reg;", "(R)");
	s = replaceall(s, "&trade;", "(TM)");
	s = replaceall(s, "&laquo;", "<<");
	s = replaceall(s, "&raquo;", ">>");

	# Numeric character references: &#NNN; and &#xHH;
	s = decodenumericentities(s);

	return s;
}

# Decode &#NNN; and &#xHH; numeric character references
decodenumericentities(s: string): string
{
	result := "";
	i := 0;
	while(i < len s) {
		if(i + 3 < len s && s[i] == '&' && s[i+1] == '#') {
			# Find the semicolon
			j := i + 2;
			while(j < len s && j < i + 10 && s[j] != ';')
				j++;
			if(j < len s && s[j] == ';') {
				numstr := s[i+2:j];
				codepoint := 0;
				valid := 1;
				if(len numstr > 0 && (numstr[0] == 'x' || numstr[0] == 'X')) {
					# Hex
					for(k := 1; k < len numstr; k++) {
						c := numstr[k];
						if(c >= '0' && c <= '9')
							codepoint = codepoint * 16 + (c - '0');
						else if(c >= 'a' && c <= 'f')
							codepoint = codepoint * 16 + (c - 'a' + 10);
						else if(c >= 'A' && c <= 'F')
							codepoint = codepoint * 16 + (c - 'A' + 10);
						else {
							valid = 0;
							break;
						}
					}
				} else {
					# Decimal
					for(k := 0; k < len numstr; k++) {
						c := numstr[k];
						if(c >= '0' && c <= '9')
							codepoint = codepoint * 10 + (c - '0');
						else {
							valid = 0;
							break;
						}
					}
				}
				if(valid && codepoint > 0 && codepoint < 16r110000) {
					result[len result] = codepoint;
					i = j + 1;
					continue;
				}
			}
		}
		result[len result] = s[i];
		i++;
	}
	return result;
}

# Replace all occurrences of old with new
replaceall(s, old, new: string): string
{
	if(old == "" || old == new)
		return s;
	result := "";
	i := 0;
	while(i < len s) {
		pos := findstr(s[i:], old);
		if(pos < 0) {
			result += s[i:];
			break;
		}
		result += s[i:i+pos] + new;
		i += pos + len old;
	}
	return result;
}

# Collapse runs of whitespace and blank lines
cleanwhitespace(s: string): string
{
	# Replace tabs with spaces
	result := "";
	for(i := 0; i < len s; i++) {
		if(s[i] == '\t')
			result[len result] = ' ';
		else
			result[len result] = s[i];
	}
	s = result;

	# Collapse multiple spaces into one
	result = "";
	prevspace := 0;
	for(i = 0; i < len s; i++) {
		if(s[i] == ' ') {
			if(!prevspace) {
				result[len result] = ' ';
				prevspace = 1;
			}
		} else {
			result[len result] = s[i];
			prevspace = 0;
		}
	}
	s = result;

	# Collapse 3+ consecutive newlines into 2
	result = "";
	nlcount := 0;
	for(i = 0; i < len s; i++) {
		if(s[i] == '\n') {
			nlcount++;
			if(nlcount <= 2)
				result[len result] = '\n';
		} else {
			nlcount = 0;
			result[len result] = s[i];
		}
	}
	s = result;

	# Trim leading/trailing whitespace on each line
	lines := splitlines(s);
	result = "";
	for(; lines != nil; lines = tl lines) {
		line := strip(hd lines);
		if(result != "" || line != "")
			result += line + "\n";
	}

	return strip(result);
}

# Split string into lines
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
	result: list of string;
	for(; lines != nil; lines = tl lines)
		result = hd lines :: result;
	return result;
}

# ---- SSRF protection (same as http.b) ----

# Extract host from URL
extracthost(url: string): string
{
	s := url;
	for(i := 0; i < len s; i++) {
		if(i + 2 < len s && s[i] == '/' && s[i+1] == '/') {
			s = s[i+2:];
			break;
		}
	}
	for(i := 0; i < len s; i++) {
		if(s[i] == '/') {
			s = s[0:i];
			break;
		}
	}
	for(i := 0; i < len s; i++) {
		if(s[i] == ':') {
			s = s[0:i];
			break;
		}
	}
	for(i := 0; i < len s; i++) {
		if(s[i] == '@') {
			s = s[i+1:];
			break;
		}
	}
	return str->tolower(s);
}

# Check if host is blocked (internal/private/metadata)
isblocked(host: string): int
{
	if(len host > 2 && host[0] == '[' && host[len host - 1] == ']')
		host = host[1:len host - 1];
	if(host == "localhost" || host == "127.0.0.1" || host == "::1" ||
	   host == "0.0.0.0" || host == "[::1]" || host == "[::0]" ||
	   host == "0:0:0:0:0:0:0:1" || host == "::ffff:127.0.0.1" ||
	   host == "0000:0000:0000:0000:0000:0000:0000:0001")
		return 1;
	if(hasprefix(host, "::"))
		return 1;
	if(hasprefix(host, "10."))
		return 1;
	if(hasprefix(host, "172.")) {
		rest := host[4:];
		for(i := 0; i < len rest; i++) {
			if(rest[i] == '.') {
				octet := int rest[0:i];
				if(octet >= 16 && octet <= 31)
					return 1;
				break;
			}
		}
	}
	if(hasprefix(host, "192.168."))
		return 1;
	if(hasprefix(host, "169.254."))
		return 1;
	if(hasprefix(host, "fd") || hasprefix(host, "fc"))
		return 1;
	if(hasprefix(host, "fe80"))
		return 1;
	if(host == "metadata.google.internal" || host == "metadata")
		return 1;
	alldigits := len host > 0;
	for(i := 0; i < len host; i++) {
		if(host[i] < '0' || host[i] > '9') {
			alldigits = 0;
			break;
		}
	}
	if(alldigits)
		return 1;
	if(hasprefix(host, "0x") || hasprefix(host, "0X"))
		return 1;
	return 0;
}

# ---- Utility functions ----

dofetch(url: string, hdrs: list of Webclient->Header, result: chan of (ref Webclient->Response, string))
{
	(resp, err) := webclient->request("GET", url, hdrs, nil);
	result <-= (resp, err);
}

timer(ch: chan of int, ms: int)
{
	sys->sleep(ms);
	ch <-= 1;
}

findstr(s, sub: string): int
{
	if(len sub > len s)
		return -1;
	for(i := 0; i <= len s - len sub; i++) {
		match := 1;
		for(j := 0; j < len sub; j++) {
			if(s[i+j] != sub[j]) {
				match = 0;
				break;
			}
		}
		if(match)
			return i;
	}
	return -1;
}

findchar(s: string, c: int, start: int): int
{
	for(i := start; i < len s; i++) {
		if(s[i] == c)
			return i;
	}
	return -1;
}

hassubstr(s, sub: string): int
{
	return findstr(s, sub) >= 0;
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
