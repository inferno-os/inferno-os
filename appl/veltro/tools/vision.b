implement ToolVision;

#
# vision - AI vision tool for Veltro agent
#
# Analyzes images using the Anthropic Messages API with vision.
# Reads image files, base64-encodes them, and sends to Claude
# for analysis. Uses Webclient for native TLS 1.3 HTTPS.
#
# Usage:
#   vision <imagepath>              # Describe the image
#   vision <imagepath> <prompt>     # Analyze with specific prompt
#
# Examples:
#   vision /tmp/photo.jpg
#   vision /tmp/diagram.png What components are shown?
#   vision /tmp/screenshot.png Extract all visible text
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "webclient.m";
	webclient: Webclient;

include "encoding.m";
	base64: Encoding;

include "../tool.m";

ToolVision: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

APIKEY_PATH: con "/lib/veltro/keys/anthropic";
API_URL: con "https://api.anthropic.com/v1/messages";
API_VERSION: con "2023-06-01";
MODEL: con "claude-sonnet-4-20250514";
MAX_IMAGE_SIZE: con 5242880;	# 5MB
MAX_TOKENS: con 4096;
REQUEST_TIMEOUT: con 60000;	# 60 seconds

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
	base64 = load Encoding Encoding->BASE64PATH;
	if(base64 == nil)
		return "cannot load base64 encoding";
	return nil;
}

name(): string
{
	return "vision";
}

doc(): string
{
	return "Vision - Analyze images using AI vision\n\n" +
		"Usage:\n" +
		"  vision <imagepath>              # Describe the image\n" +
		"  vision <imagepath> <prompt>     # Analyze with specific prompt\n\n" +
		"Arguments:\n" +
		"  imagepath - Path to image file (PNG, JPEG, GIF, WebP)\n" +
		"  prompt    - Analysis prompt (default: \"Describe this image in detail.\")\n\n" +
		"Examples:\n" +
		"  vision /tmp/photo.jpg\n" +
		"  vision /tmp/diagram.png What components are shown?\n" +
		"  vision /tmp/screenshot.png Extract all visible text\n\n" +
		"Maximum image size: 5MB.\n" +
		"Requires API key in " + APIKEY_PATH + ".";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	# Parse arguments: <imagepath> [prompt...]
	(n, argv) := sys->tokenize(args, " \t");
	if(n < 1)
		return "error: usage: vision <imagepath> [prompt]";

	imagepath := hd argv;
	argv = tl argv;

	# Join remaining args as prompt
	prompt := "";
	for(; argv != nil; argv = tl argv) {
		if(prompt != "")
			prompt += " ";
		prompt += hd argv;
	}
	if(prompt == "")
		prompt = "Describe this image in detail.";

	# Read API key
	apikey := readapikey();
	if(apikey == "")
		return "error: Anthropic API key not configured. Place key in " + APIKEY_PATH;

	# Detect media type
	mtype := mediatype(imagepath);
	if(mtype == "")
		return "error: unsupported image format. Supported: PNG, JPEG, GIF, WebP";

	# Read image file
	imgdata := readbytes(imagepath);
	if(imgdata == nil)
		return "error: cannot read image: " + imagepath;

	# Validate size
	if(len imgdata > MAX_IMAGE_SIZE)
		return sys->sprint("error: image too large (%d bytes). Maximum: %d bytes", len imgdata, MAX_IMAGE_SIZE);

	# Base64 encode
	b64 := base64->enc(imgdata);

	# Build JSON request body
	body := buildrequest(mtype, b64, prompt);
	reqbody := array of byte body;

	# Build headers
	hdrs := Webclient->Header("Content-Type", "application/json") ::
		Webclient->Header("x-api-key", apikey) ::
		Webclient->Header("anthropic-version", API_VERSION) ::
		Webclient->Header("User-Agent", "Veltro/1.0") :: nil;

	# Execute request with timeout
	result := chan[1] of (ref Webclient->Response, string);
	spawn dorequest(hdrs, reqbody, result);

	timeout := chan[1] of int;
	spawn timer(timeout, REQUEST_TIMEOUT);

	resp: ref Webclient->Response;
	err: string;
	alt {
	(r, e) := <-result =>
		(resp, err) = (r, e);
	<-timeout =>
		return "error: vision request timed out (60s)";
	}

	if(err != nil)
		return "error: " + err;
	if(resp.body == nil || len resp.body == 0)
		return "error: empty response from API";

	output := string resp.body;

	# Check for HTTP error
	if(resp.statuscode >= 400)
		return sys->sprint("error: API returned HTTP %d: %s", resp.statuscode, extracterror(output));

	# Extract text from response
	text := extracttext(output);
	if(text == "")
		return "error: could not parse API response";

	return text;
}

# Build the Anthropic Messages API request JSON
buildrequest(mtype, b64data, prompt: string): string
{
	return "{" +
		"\"model\":\"" + MODEL + "\"," +
		"\"max_tokens\":" + string MAX_TOKENS + "," +
		"\"messages\":[{" +
			"\"role\":\"user\"," +
			"\"content\":[" +
				"{\"type\":\"image\",\"source\":{" +
					"\"type\":\"base64\"," +
					"\"media_type\":\"" + mtype + "\"," +
					"\"data\":\"" + b64data + "\"" +
				"}}," +
				"{\"type\":\"text\",\"text\":\"" + jsonstr(prompt) + "\"}" +
			"]" +
		"}]" +
	"}";
}

# Detect media type from file extension
mediatype(path: string): string
{
	lpath := str->tolower(path);
	if(hassuffix(lpath, ".png"))
		return "image/png";
	if(hassuffix(lpath, ".jpg") || hassuffix(lpath, ".jpeg"))
		return "image/jpeg";
	if(hassuffix(lpath, ".gif"))
		return "image/gif";
	if(hassuffix(lpath, ".webp"))
		return "image/webp";
	return "";
}

# Extract text content from Anthropic Messages API response
# Response format: {"content":[{"type":"text","text":"..."}],...}
extracttext(json: string): string
{
	# Find "content" array
	cpos := findstr(json, "\"content\"");
	if(cpos < 0)
		return "";

	# Find first "text" field after "type":"text"
	tpos := findstr(json[cpos:], "\"type\":\"text\"");
	if(tpos < 0)
		# Try alternate spacing
		tpos = findstr(json[cpos:], "\"type\": \"text\"");
	if(tpos < 0)
		return "";
	tpos += cpos;

	# Find the "text" field value after the type
	vpos := findstr(json[tpos + 10:], "\"text\"");
	if(vpos < 0)
		return "";
	vpos += tpos + 10;

	# Skip past "text": to the value
	vpos += 6; # len "\"text\""
	while(vpos < len json && (json[vpos] == ' ' || json[vpos] == ':'))
		vpos++;
	if(vpos >= len json || json[vpos] != '"')
		return "";
	vpos++; # skip opening quote

	# Read value, handling JSON escapes
	value := "";
	while(vpos < len json && json[vpos] != '"') {
		if(json[vpos] == '\\' && vpos + 1 < len json) {
			vpos++;
			case json[vpos] {
			'n'  => value += "\n";
			't'  => value += "\t";
			'"'  => value += "\"";
			'\\' => value += "\\";
			'/'  => value += "/";
			*    => value[len value] = json[vpos];
			}
		} else {
			value[len value] = json[vpos];
		}
		vpos++;
	}
	return value;
}

# Extract error message from API error response
extracterror(json: string): string
{
	# Try to find "message" field in error response
	mpos := findstr(json, "\"message\"");
	if(mpos < 0)
		return json;

	# Skip to value
	mpos += 9; # len "\"message\""
	while(mpos < len json && (json[mpos] == ' ' || json[mpos] == ':'))
		mpos++;
	if(mpos >= len json || json[mpos] != '"')
		return json;
	mpos++;

	value := "";
	while(mpos < len json && json[mpos] != '"') {
		if(json[mpos] == '\\' && mpos + 1 < len json) {
			mpos++;
			value[len value] = json[mpos];
		} else {
			value[len value] = json[mpos];
		}
		mpos++;
	}
	if(value != "")
		return value;
	return json;
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

# Read entire file as bytes (chunked)
readbytes(path: string): array of byte
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;

	chunks: list of array of byte;
	total := 0;
	for(;;) {
		buf := array[65536] of byte;
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		chunks = buf[0:n] :: chunks;
		total += n;
	}

	if(total == 0)
		return nil;

	# Assemble chunks in order
	result := array[total] of byte;
	pos := total;
	for(; chunks != nil; chunks = tl chunks) {
		chunk := hd chunks;
		pos -= len chunk;
		result[pos:] = chunk;
	}
	return result;
}

# Perform HTTP request in a goroutine (allows timeout via alt)
dorequest(hdrs: list of Webclient->Header, reqbody: array of byte,
	result: chan of (ref Webclient->Response, string))
{
	(resp, err) := webclient->request("POST", API_URL, hdrs, reqbody);
	result <-= (resp, err);
}

# Timer goroutine
timer(ch: chan of int, ms: int)
{
	sys->sleep(ms);
	ch <-= 1;
}

# Escape string for JSON
jsonstr(s: string): string
{
	result := "";
	for(i := 0; i < len s; i++) {
		case s[i] {
		'"'  => result += "\\\"";
		'\\' => result += "\\\\";
		'\n' => result += "\\n";
		'\r' => result += "\\r";
		'\t' => result += "\\t";
		*    => result[len result] = s[i];
		}
	}
	return result;
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

# Check if string has prefix
hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

# Check if string has suffix
hassuffix(s, suffix: string): int
{
	return len s >= len suffix && s[len s - len suffix:] == suffix;
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
