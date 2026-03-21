implement ToolVision;

#
# vision - Dual-backend AI vision tool for Veltro agent
#
# Analyzes images using either a local GPU (TensorRT via /mnt/gpu)
# or the Anthropic Messages API (cloud). Auto-detects which backend
# is available; prefers local GPU when mounted with a vision model.
#
# Usage:
#   vision <imagepath> [prompt]          # Auto-detect backend
#   vision --local <imagepath>           # Force local GPU
#   vision --cloud <imagepath> [prompt]  # Force Anthropic API
#
# Examples:
#   vision /tmp/photo.jpg
#   vision /tmp/diagram.png What components are shown?
#   vision --local /tmp/capture.png
#   vision --cloud /tmp/screenshot.png Extract all visible text
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

include "factotum.m";
	factotum: Factotum;

include "../tool.m";

ToolVision: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

# Cloud backend constants
APIKEY_PATH: con "/lib/veltro/keys/anthropic";
API_URL: con "https://api.anthropic.com/v1/messages";
API_VERSION: con "2023-06-01";
MODEL: con "claude-sonnet-4-20250514";
MAX_IMAGE_SIZE: con 5242880;	# 5MB
MAX_TOKENS: con 4096;
REQUEST_TIMEOUT: con 60000;	# 60 seconds

# Local GPU backend constants
GPUDIR: con "/mnt/gpu";

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";
	# Webclient and base64 loaded lazily (only needed for cloud backend)
	return nil;
}

# Lazy-load cloud backend dependencies
initcloud(): string
{
	if(webclient != nil)
		return nil;
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
		"  vision <imagepath> [prompt]          # Auto-detect backend\n" +
		"  vision --local <imagepath>           # Force local GPU\n" +
		"  vision --cloud <imagepath> [prompt]  # Force Anthropic API\n\n" +
		"Arguments:\n" +
		"  imagepath - Path to image file (PNG, JPEG, GIF, WebP)\n" +
		"  prompt    - Analysis prompt (cloud only; default: \"Describe this image in detail.\")\n\n" +
		"Backends:\n" +
		"  local - Uses TensorRT via /mnt/gpu (Jetson Orin, etc.)\n" +
		"  cloud - Uses Anthropic Messages API with Claude vision\n" +
		"  auto  - Prefers local GPU if mounted; falls back to cloud\n\n" +
		"Examples:\n" +
		"  vision /tmp/photo.jpg\n" +
		"  vision /tmp/diagram.png What components are shown?\n" +
		"  vision --local /tmp/capture.png\n" +
		"  vision --cloud /tmp/screenshot.png Extract all visible text\n\n" +
		"Notes:\n" +
		"  Maximum image size: 5MB\n" +
		"  Cloud requires API key in " + APIKEY_PATH + "\n" +
		"  Local requires /mnt/gpu mounted with a vision model loaded";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	# Parse arguments: [--local|--cloud] <imagepath> [prompt...]
	(n, argv) := sys->tokenize(args, " \t");
	if(n < 1)
		return "error: usage: vision [--local|--cloud] <imagepath> [prompt]";

	# Check for backend flag
	backend := "auto";
	first := hd argv;
	if(first == "--local") {
		backend = "local";
		argv = tl argv;
		n--;
	} else if(first == "--cloud") {
		backend = "cloud";
		argv = tl argv;
		n--;
	}

	if(n < 1)
		return "error: usage: vision [--local|--cloud] <imagepath> [prompt]";

	imagepath := hd argv;
	argv = tl argv;

	# Join remaining args as prompt (used by cloud backend)
	prompt := "";
	for(; argv != nil; argv = tl argv) {
		if(prompt != "")
			prompt += " ";
		prompt += hd argv;
	}
	if(prompt == "")
		prompt = "Describe this image in detail.";

	# Route to appropriate backend
	case backend {
	"cloud" =>
		return cloudvision(imagepath, prompt);
	"local" =>
		if(!gpuavailable())
			return "error: --local specified but " + GPUDIR + " not mounted";
		model := findvisionmodel();
		if(model == "")
			return "error: no vision model loaded on GPU. Load a model via: echo 'load <name> <path>' > " + GPUDIR + "/ctl";
		return gpuinfer(imagepath, model);
	* =>
		# Auto-detect: prefer local if available
		if(gpuavailable()) {
			model := findvisionmodel();
			if(model != "")
				return gpuinfer(imagepath, model);
		}
		return cloudvision(imagepath, prompt);
	}
}

# ==================== Local GPU Backend ====================

# Check if GPU filesystem is mounted and accessible
gpuavailable(): int
{
	fd := sys->open(GPUDIR + "/ctl", Sys->OREAD);
	if(fd == nil)
		return 0;
	buf := array[64] of byte;
	n := sys->read(fd, buf, len buf);
	return n > 0;
}

# Find a loaded vision model by scanning /mnt/gpu/models/
# Returns first model name found, or "" if none loaded.
findvisionmodel(): string
{
	fd := sys->open(GPUDIR + "/models", Sys->OREAD);
	if(fd == nil)
		return "";
	(ndir, dirs) := sys->dirread(fd);
	if(ndir <= 0)
		return "";
	# Return first model found
	return dirs[0].name;
}

# Run inference on local GPU via /mnt/gpu session protocol.
# Follows the clone-based session pattern from gpu.b:runinfer().
gpuinfer(imagepath, model: string): string
{
	# 1. Read clone to get session ID
	sid := readfile(GPUDIR + "/clone");
	if(sid == "" || sid[0] == 'e')
		return "error: failed to allocate GPU session: " + sid;
	if(len sid > 0 && sid[len sid - 1] == '\n')
		sid = sid[0:len sid - 1];

	sessdir := GPUDIR + "/" + sid;

	# 2. Set model
	err := writefile(sessdir + "/ctl", "model " + model);
	if(err != nil)
		return "error: " + err;

	# 3. Read and write input image
	imgdata := readbytes(imagepath);
	if(imgdata == nil)
		return "error: cannot read image: " + imagepath;

	if(len imgdata > MAX_IMAGE_SIZE)
		return sys->sprint("error: image too large (%d bytes). Maximum: %d bytes", len imgdata, MAX_IMAGE_SIZE);

	err = writebytes(sessdir + "/input", imgdata);
	if(err != nil)
		return "error: writing input: " + err;

	# 4. Trigger inference
	err = writefile(sessdir + "/ctl", "infer");
	if(err != nil)
		return "error: inference failed: " + err;

	# 5. Check status
	status := readfile(sessdir + "/status");
	if(status == "" || hasprefix(status, "error"))
		return "error: " + status;

	# 6. Read output
	output := readfile(sessdir + "/output");
	if(output == "")
		return "(no output)";
	return output;
}

# ==================== Cloud Backend ====================

# Analyze image via Anthropic Messages API
cloudvision(imagepath, prompt: string): string
{
	# Lazy-load cloud dependencies
	err := initcloud();
	if(err != nil)
		return "error: " + err;

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

# ==================== I/O Helpers ====================

# Read API key from factotum, falling back to file
readapikey(): string
{
	# Try factotum first
	if(factotum == nil)
		factotum = load Factotum Factotum->PATH;
	if(factotum != nil){
		factotum->init();
		(nil, password) := factotum->getuserpasswd("proto=pass service=anthropic");
		if(password != nil && password != "")
			return password;
	}

	# Fall back to file (migration)
	fd := sys->open(APIKEY_PATH, Sys->OREAD);
	if(fd == nil)
		return "";
	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "";
	return strip(string buf[0:n]);
}

# Read entire file as text
readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return "";
	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "";
	return string buf[0:n];
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

# Write string to file
writefile(path, data: string): string
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return "cannot open " + path + ": " + errmsg();
	b := array of byte data;
	n := sys->write(fd, b, len b);
	if(n != len b)
		return "write failed: " + errmsg();
	return nil;
}

# Write bytes to file
writebytes(path: string, data: array of byte): string
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return "cannot open " + path + ": " + errmsg();
	n := sys->write(fd, data, len data);
	if(n != len data)
		return "write failed: " + errmsg();
	return nil;
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

# ==================== String Helpers ====================

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

# Get system error message
errmsg(): string
{
	fd := sys->open("/dev/sysctl", Sys->OREAD);
	if(fd == nil)
		return "unknown error";
	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "unknown error";
	return string buf[0:n];
}
