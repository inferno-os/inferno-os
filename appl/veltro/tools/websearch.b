implement ToolWebsearch;

#
# websearch - Web search tool for Veltro agent
#
# Searches the web using Brave Search API via native HTTPS.
# Uses Webclient module for TLS 1.3 with certificate verification.
# API key must be in /lib/veltro/keys/brave (one line, key only).
#
# Usage:
#   websearch <query>
#
# Examples:
#   websearch Inferno OS distributed system
#   websearch Plan 9 from Bell Labs
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "webclient.m";
	webclient: Webclient;

include "../tool.m";

ToolWebsearch: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

APIKEY_PATH: con "/lib/veltro/keys/brave";
REQUEST_TIMEOUT: con 30000;	# 30 seconds

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
	return "websearch";
}

doc(): string
{
	return "Websearch - Search the web using Brave Search\n\n" +
		"Usage:\n" +
		"  websearch <query>\n\n" +
		"Arguments:\n" +
		"  query - Search terms\n\n" +
		"Examples:\n" +
		"  websearch Inferno OS distributed system\n" +
		"  websearch Plan 9 from Bell Labs\n\n" +
		"Returns titles, URLs, and descriptions of top results.\n" +
		"Requires API key in /lib/veltro/keys/brave.";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	query := strip(args);
	if(query == "")
		return "error: usage: websearch <query>";

	# Read API key
	apikey := readapikey();
	if(apikey == "")
		return "error: Brave Search API key not configured. Place key in " + APIKEY_PATH;

	# URL-encode query
	encoded := urlencode(query);

	# Execute search via Webclient with timeout
	url := "https://api.search.brave.com/res/v1/web/search?q=" + encoded + "&count=5";
	hdrs := Webclient->Header("Accept", "application/json") ::
		Webclient->Header("X-Subscription-Token", apikey) :: nil;

	# Buffered capacity 1: goroutines can complete their send and exit
	# even after the alt has moved on, preventing indefinite blocking.
	result := chan[1] of (ref Webclient->Response, string);
	spawn dosearch(url, hdrs, result);

	timeout := chan[1] of int;
	spawn timer(timeout, REQUEST_TIMEOUT);

	resp: ref Webclient->Response;
	err: string;
	alt {
	(r, e) := <-result =>
		(resp, err) = (r, e);
	<-timeout =>
		return "error: search request timed out (30s)";
	}

	if(err != nil)
		return "error: search failed: " + err;
	if(resp.body == nil || len resp.body == 0)
		return "error: empty response from Brave Search";

	output := string resp.body;

	# Parse and format results
	return formatresults(output);
}

# Read API key from file
readapikey(): string
{
	fd := sys->open(APIKEY_PATH, Sys->OREAD);
	if(fd == nil)
		return "";
	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "";
	return strip(string buf[0:n]);
}

# URL-encode a string (spaces → +, special chars → %XX)
urlencode(s: string): string
{
	result := "";
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c == ' ')
			result += "+";
		else if((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
				(c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~')
			result[len result] = c;
		else {
			# %XX encode
			result += "%" + hexbyte(c);
		}
	}
	return result;
}

hexbyte(c: int): string
{
	hex := "0123456789ABCDEF";
	s := "  ";
	s[0] = hex[(c >> 4) & 16rf];
	s[1] = hex[c & 16rf];
	return s;
}

# Format Brave Search JSON response into readable text
# Extracts title, url, description from web.results[] array
formatresults(json: string): string
{
	# Find the "results" array
	rpos := findstr(json, "\"results\"");
	if(rpos < 0)
		return "error: no results found in response";

	# Find the opening bracket of the results array
	astart := findchar(json, '[', rpos);
	if(astart < 0)
		return "error: malformed response";

	result := "";
	count := 0;
	pos := astart + 1;

	# Extract each result object
	while(count < 5 && pos < len json) {
		# Find next object start
		ostart := findchar(json, '{', pos);
		if(ostart < 0)
			break;

		# Find matching close brace (handle nesting)
		oend := findmatchbrace(json, ostart);
		if(oend < 0)
			break;

		obj := json[ostart:oend+1];

		title := extractfield(obj, "title");
		url := extractfield(obj, "url");
		desc := extractfield(obj, "description");

		if(title != "" && url != "") {
			count++;
			if(result != "")
				result += "\n\n";
			result += sys->sprint("%d. %s\n   %s", count, title, url);
			if(desc != "")
				result += "\n   " + desc;
		}

		pos = oend + 1;
	}

	if(count == 0)
		return "No results found.";

	return result;
}

# Extract a JSON string field value by key name
# Handles escaped quotes within values
extractfield(json, key: string): string
{
	# Search for "key":"
	needle := "\"" + key + "\"";
	pos := findstr(json, needle);
	if(pos < 0)
		return "";

	# Skip past the key and find the colon
	pos += len needle;
	while(pos < len json && json[pos] != ':')
		pos++;
	if(pos >= len json)
		return "";
	pos++; # skip colon

	# Skip whitespace
	while(pos < len json && (json[pos] == ' ' || json[pos] == '\t' || json[pos] == '\n'))
		pos++;
	if(pos >= len json || json[pos] != '"')
		return "";
	pos++; # skip opening quote

	# Read value, handling escapes
	value := "";
	while(pos < len json && json[pos] != '"') {
		if(json[pos] == '\\' && pos + 1 < len json) {
			pos++;
			case json[pos] {
			'n' =>
				value[len value] = '\n';
			't' =>
				value[len value] = '\t';
			'"' =>
				value[len value] = '"';
			'\\' =>
				value[len value] = '\\';
			'/' =>
				value[len value] = '/';
			* =>
				value[len value] = json[pos];
			}
		} else {
			value[len value] = json[pos];
		}
		pos++;
	}
	# Strip HTML tags from description
	return striphtml(value);
}

# Strip HTML tags from a string
striphtml(s: string): string
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

# Find substring in string, return position or -1
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

# Find character in string starting from pos, return position or -1
findchar(s: string, c: int, start: int): int
{
	for(i := start; i < len s; i++) {
		if(s[i] == c)
			return i;
	}
	return -1;
}

# Find matching close brace, handling nesting
findmatchbrace(s: string, start: int): int
{
	depth := 0;
	instr := 0;
	for(i := start; i < len s; i++) {
		if(instr) {
			if(s[i] == '\\' && i + 1 < len s)
				i++; # skip escaped char
			else if(s[i] == '"')
				instr = 0;
		} else {
			case s[i] {
			'"' =>
				instr = 1;
			'{' =>
				depth++;
			'}' =>
				depth--;
				if(depth == 0)
					return i;
			}
		}
	}
	return -1;
}

# Perform search in a separate goroutine (allows caller to apply a timeout)
dosearch(url: string, hdrs: list of Webclient->Header, result: chan of (ref Webclient->Response, string))
{
	(resp, err) := webclient->request("GET", url, hdrs, nil);
	result <-= (resp, err);
}

# Timer goroutine: send on ch after ms milliseconds
timer(ch: chan of int, ms: int)
{
	sys->sleep(ms);
	ch <-= 1;
}

# Strip leading/trailing whitespace
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
