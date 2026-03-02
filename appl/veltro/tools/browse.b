implement ToolBrowse;

#
# browse - Web browser tool for Veltro agent
#
# Fetches a URL, formats HTML to plain text, and displays it
# in a Xenith window. Returns the window ID and page title.
#
# Usage:
#   browse <url>
#
# Examples:
#   browse https://example.com
#   browse https://www.ietf.org/rfc/rfc2616.txt
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "webclient.m";
	webclient: Webclient;
	Response, Header: import webclient;

include "html.m";
	html: HTML;
	Lex, Attr: import html;

include "formatter.m";

include "../tool.m";

ToolBrowse: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

XENITH_ROOT: con "/chan";

htmlfmt: Formatter;

# Windows created by this tool
owned: list of string;

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
	html = load HTML HTML->PATH;
	if(html == nil)
		return "cannot load HTML";
	htmlfmt = load Formatter "/dis/xenith/render/htmlfmt.dis";
	if(htmlfmt == nil)
		return "cannot load htmlfmt";
	htmlfmt->init();
	owned = nil;
	return nil;
}

name(): string
{
	return "browse";
}

doc(): string
{
	return "Browse - Web page viewer\n\n" +
		"Fetches a URL, formats HTML to plain text, and displays\n" +
		"the result in a Xenith window.\n\n" +
		"Usage:\n" +
		"  browse <url>              Fetch and display web page\n\n" +
		"Arguments:\n" +
		"  url - Full URL (http:// or https://)\n\n" +
		"The tool fetches the page via HTTP/HTTPS, extracts and formats\n" +
		"the HTML content as readable text (headings, paragraphs, lists,\n" +
		"code blocks, links, tables), creates a Xenith window, and writes\n" +
		"the formatted text to it.\n\n" +
		"Returns: <window-id> <page-title>\n\n" +
		"Examples:\n" +
		"  browse https://example.com\n" +
		"  browse https://www.ietf.org/rfc/rfc2616.txt\n";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	url := strip(args);
	if(url == "")
		return "error: usage: browse <url>";

	# Validate URL
	lurl := "";
	for(i := 0; i < len url; i++) {
		c := url[i];
		if(c >= 'A' && c <= 'Z')
			c += 'a' - 'A';
		lurl[len lurl] = c;
	}
	if(!hasprefix(lurl, "http://") && !hasprefix(lurl, "https://"))
		return "error: URL must start with http:// or https://";

	# Fetch URL
	hdrs: list of Header;
	hdrs = Header("User-Agent", "Veltro/1.0 (Infernode)") :: hdrs;
	(resp, err) := webclient->request("GET", url, hdrs, nil);
	if(err != nil)
		return "error: fetch failed: " + err;

	if(resp.statuscode >= 400)
		return sys->sprint("error: HTTP %d %s", resp.statuscode, resp.status);

	if(resp.body == nil || len resp.body == 0)
		return "error: empty response";

	bodytext := string resp.body;

	# Determine content type
	ct := resp.hdrval("Content-Type");
	if(ct == nil)
		ct = "";

	# Extract page title from HTML
	title := "";
	formatted := "";

	if(ishtml(ct, bodytext)) {
		# Extract title
		title = extracttitle(resp.body);
		if(title == "")
			title = url;

		# Format HTML to text
		formatted = htmlfmt->format(bodytext, 80);
		if(formatted == nil || len formatted == 0)
			formatted = bodytext;  # fallback to raw text
	} else {
		# Non-HTML: use raw text
		title = url;
		formatted = bodytext;
	}

	# Create Xenith window
	winid := createwindow(title);
	if(hasprefix(winid, "error:"))
		return winid;

	# Write formatted content to body
	werr := writebody(winid, formatted);
	if(werr != nil)
		return sys->sprint("error: %s (window %s created)", werr, winid);

	return winid + " " + title;
}

# Check if content appears to be HTML
ishtml(ct, body: string): int
{
	lct := "";
	for(i := 0; i < len ct; i++) {
		c := ct[i];
		if(c >= 'A' && c <= 'Z')
			c += 'a' - 'A';
		lct[len lct] = c;
	}
	if(hasprefix(lct, "text/html"))
		return 1;

	# Check body for HTML markers
	if(len body >= 256)
		body = body[0:256];
	for(i = 0; i < len body; i++) {
		c := body[i];
		if(c == ' ' || c == '\t' || c == '\n' || c == '\r')
			continue;
		if(c == '<') {
			rest := "";
			for(j := i; j < len body; j++) {
				rc := body[j];
				if(rc >= 'A' && rc <= 'Z')
					rc += 'a' - 'A';
				rest[len rest] = rc;
			}
			if(len rest >= 9 && rest[0:9] == "<!doctype")
				return 1;
			if(len rest >= 5 && rest[0:5] == "<html")
				return 1;
		}
		break;
	}
	return 0;
}

# Extract <title> from HTML
extracttitle(data: array of byte): string
{
	tokens := html->lex(data, HTML->UTF8, 0);
	if(tokens == nil)
		return "";

	intitle := 0;
	title := "";
	for(i := 0; i < len tokens; i++) {
		tok := tokens[i];
		if(tok.tag == HTML->Ttitle) {
			intitle = 1;
			continue;
		}
		if(tok.tag == HTML->Ttitle + HTML->RBRA) {
			break;
		}
		if(intitle && tok.tag == HTML->Data)
			title += tok.text;
	}

	# Clean whitespace
	result := "";
	lastspace := 1;
	for(i = 0; i < len title; i++) {
		c := title[i];
		if(c == '\n' || c == '\r' || c == '\t')
			c = ' ';
		if(c == ' ') {
			if(!lastspace) {
				result[len result] = ' ';
				lastspace = 1;
			}
		} else {
			result[len result] = c;
			lastspace = 0;
		}
	}
	# Trim trailing space
	if(len result > 0 && result[len result - 1] == ' ')
		result = result[0:len result - 1];
	return result;
}

# Create a Xenith window, return window ID
createwindow(name: string): string
{
	newctl := XENITH_ROOT + "/new/ctl";
	fd := sys->open(newctl, Sys->ORDWR);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r (is Xenith running?)", newctl);

	sys->write(fd, array[0] of byte, 0);

	buf := array[64] of byte;
	n := sys->read(fd, buf, len buf);
	fd = nil;

	if(n <= 0)
		return "error: failed to create window";

	(winid, nil) := splitfirst(string buf[0:n]);

	# Track ownership
	owned = winid :: owned;

	# Set window name
	if(name != "") {
		ctlpath := sys->sprint("%s/%s/ctl", XENITH_ROOT, winid);
		ctlfd := sys->open(ctlpath, Sys->OWRITE);
		if(ctlfd != nil) {
			namecmd := sys->sprint("name %s\n", name);
			sys->write(ctlfd, array of byte namecmd, len namecmd);
			ctlfd = nil;
		}
	}

	return winid;
}

# Write text to window body
writebody(winid, text: string): string
{
	filepath := sys->sprint("%s/%s/body", XENITH_ROOT, winid);
	fd := sys->open(filepath, Sys->OWRITE | Sys->OTRUNC);
	if(fd == nil)
		return sys->sprint("cannot open %s: %r", filepath);

	data := array of byte text;
	n := sys->write(fd, data, len data);
	fd = nil;

	if(n != len data)
		return sys->sprint("write failed: %r");

	# Mark as clean
	ctlpath := sys->sprint("%s/%s/ctl", XENITH_ROOT, winid);
	ctlfd := sys->open(ctlpath, Sys->OWRITE);
	if(ctlfd != nil) {
		cmd := array of byte "clean\n";
		sys->write(ctlfd, cmd, len cmd);
		ctlfd = nil;
	}

	return nil;
}

# --- Helpers ---

strip(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n'))
		j--;
	if(i >= j)
		return "";
	return s[i:j];
}

splitfirst(s: string): (string, string)
{
	s = strip(s);
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t')
			return (s[0:i], strip(s[i:]));
	}
	return (s, "");
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}
