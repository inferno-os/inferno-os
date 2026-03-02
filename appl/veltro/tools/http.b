implement ToolHttp;

#
# http - HTTP client tool for Veltro agent
#
# Performs HTTP requests and returns response body.
# Uses Webclient module for HTTP/HTTPS with native TLS 1.3.
# DNS resolution via Inferno's connection server.
#
# Usage:
#   http GET <url>                    # GET request
#   http POST <url> <body>            # POST request
#   http PUT <url> <body>             # PUT request
#   http DELETE <url>                 # DELETE request
#   http HEAD <url>                   # HEAD request (headers only)
#
# Examples:
#   http GET http://example.com/api
#   http GET https://api.github.com/
#   http POST http://localhost:8080/data '{"key": "value"}'
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "webclient.m";
	webclient: Webclient;

include "../tool.m";

ToolHttp: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

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
	return "http";
}

doc(): string
{
	return "Http - HTTP/HTTPS client\n\n" +
		"Usage:\n" +
		"  http GET <url>              # GET request\n" +
		"  http POST <url> <body>      # POST request\n" +
		"  http PUT <url> <body>       # PUT request\n" +
		"  http DELETE <url>           # DELETE request\n" +
		"  http HEAD <url>             # HEAD request\n\n" +
		"Arguments:\n" +
		"  url  - Full URL (http:// or https://)\n" +
		"  body - Request body (for POST/PUT)\n\n" +
		"Examples:\n" +
		"  http GET http://example.com/api\n" +
		"  http GET https://api.github.com/\n" +
		"  http POST http://localhost:8080/data '{\"key\": \"value\"}'\n\n" +
		"HTTP and HTTPS use native TLS 1.3 with certificate verification.\n" +
		"Hostnames are resolved via Inferno's connection server.";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	# Parse arguments
	(n, argv) := sys->tokenize(args, " \t");
	if(n < 2)
		return "error: usage: http <METHOD> <url> [body]";

	method := str->toupper(hd argv);
	argv = tl argv;
	url := hd argv;
	argv = tl argv;

	body := "";
	if(argv != nil) {
		# Join remaining args as body
		for(; argv != nil; argv = tl argv) {
			if(body != "")
				body += " ";
			body += hd argv;
		}
		body = stripquotes(body);
	}

	# Validate method
	case method {
	"GET" or "POST" or "PUT" or "DELETE" or "HEAD" or "PATCH" =>
		;
	* =>
		return "error: unsupported HTTP method: " + method;
	}

	# Validate URL scheme
	lurl := str->tolower(url);
	if(!hasprefix(lurl, "http://") && !hasprefix(lurl, "https://"))
		return "error: invalid URL: must start with http:// or https://";

	# Build headers
	hdrs: list of Webclient->Header;
	hdrs = Webclient->Header("User-Agent", "Veltro/1.0") :: hdrs;
	if(body != "")
		hdrs = Webclient->Header("Content-Type", "application/json") :: hdrs;

	# Build request body
	reqbody: array of byte;
	if(body != "")
		reqbody = array of byte body;

	# Execute request
	(resp, err) := webclient->request(method, url, hdrs, reqbody);
	if(err != nil)
		return "error: " + err;

	# For HEAD, return headers
	if(method == "HEAD") {
		result := "";
		for(h := resp.headers; h != nil; h = tl h) {
			hdr := hd h;
			if(result != "")
				result += "\n";
			result += hdr.name + ": " + hdr.value;
		}
		return result;
	}

	# For error status, include status line
	if(resp.statuscode >= 400)
		return sys->sprint("error: HTTP %d\n%s", resp.statuscode, string resp.body);

	return string resp.body;
}

# Strip surrounding quotes
stripquotes(s: string): string
{
	if(len s < 2)
		return s;
	if((s[0] == '"' && s[len s - 1] == '"') ||
	   (s[0] == '\'' && s[len s - 1] == '\''))
		return s[1:len s - 1];
	return s;
}

# Check if string has prefix
hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}
