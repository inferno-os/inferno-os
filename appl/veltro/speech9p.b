implement Speech9p;

#
# speech9p - 9P file server for speech synthesis and recognition
#
# Presents TTS/STT as a filesystem, the Plan 9 way.
# Engine backends are pluggable: host commands or HTTP APIs.
#
# Filesystem structure:
#   /n/speech/
#   ├── ctl        (rw)  Configuration: engine, voice, lang, etc.
#   ├── say        (rw)  Write text, read status. Plays audio on /dev/audio.
#   ├── hear       (rw)  Write "start", read transcribed text from /dev/audio.
#   └── voices     (r)   List available voices for current engine.
#
# Usage:
#   speech9p                       # Start with defaults
#   speech9p -D                    # With 9P debug tracing
#   speech9p -m /n/speech          # Custom mount point
#   speech9p -e cmd                # Use host command engine
#   speech9p -e api                # Use HTTP API engine
#   speech9p -e api -k <key>       # API engine with key
#
# Examples:
#   echo 'Hello world' > /n/speech/say         # Speak text
#   echo 'start' > /n/speech/hear              # Start listening
#   cat /n/speech/hear                          # Read transcription
#   echo 'voice alloy' > /n/speech/ctl         # Change voice
#   cat /n/speech/voices                        # List voices
#   cat /n/speech/ctl                           # Show current config
#

include "sys.m";
	sys: Sys;
	Qid: import Sys;

include "draw.m";

include "arg.m";

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

include "styxservers.m";
	styxservers: Styxservers;
	Fid, Styxserver, Navigator, Navop: import styxservers;
	Enotfound, Eperm, Ebadarg: import styxservers;

include "string.m";
	str: String;

Speech9p: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

# Qid layout for synthetic files
Qroot, Qctl, Qsay, Qhear, Qvoices: con iota;

# Per-fid state for say and hear operations
FidState: adt {
	fid:      int;
	sayreq:   string;          # Text written to say
	sayresp:  array of byte;   # Status response from say
	hearresp: array of byte;   # Transcription result from hear
};

# Engine backends
ENGINE_CMD: con 0;   # Host OS commands via #C (devcmd)
ENGINE_API: con 1;   # HTTP API (OpenAI, etc.)

# Current configuration
engine := ENGINE_CMD;
voice := "";
lang := "en";
apiurl := "";
apikey := "";
audrate := 22050;
audchans := 1;
audbits := 16;

# Platform-specific defaults for cmd engine
cmdtts := "";    # Set in initplatform()
cmdstt := "";    # Set in initplatform()
hearduration := 5000;  # Recording duration in ms (default 5s)

stderr: ref Sys->FD;
user: string;
mountpt := "/n/speech";
fidstates: list of ref FidState;

nomod(s: string)
{
	sys->fprint(stderr, "speech9p: can't load %s: %r\n", s);
	raise "fail:load";
}

usage()
{
	sys->fprint(stderr, "Usage: speech9p [-D] [-m mountpoint] [-e engine] [-k apikey]\n");
	sys->fprint(stderr, "  -D            Enable 9P debug tracing\n");
	sys->fprint(stderr, "  -m mountpoint Mount point (default: /n/speech)\n");
	sys->fprint(stderr, "  -e engine     Engine: cmd (default), api\n");
	sys->fprint(stderr, "  -k key        API key (for api engine)\n");
	sys->fprint(stderr, "  -u url        API base URL\n");
	sys->fprint(stderr, "  -v voice      Default voice\n");
	sys->fprint(stderr, "  -l lang       Language code (default: en)\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);

	styx = load Styx Styx->PATH;
	if(styx == nil)
		nomod(Styx->PATH);
	styx->init();

	styxservers = load Styxservers Styxservers->PATH;
	if(styxservers == nil)
		nomod(Styxservers->PATH);
	styxservers->init(styx);

	str = load String String->PATH;
	if(str == nil)
		nomod(String->PATH);

	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	arg->init(args);

	while((o := arg->opt()) != 0)
		case o {
		'D' =>	styxservers->traceset(1);
		'm' =>	mountpt = arg->earg();
		'e' =>
			e := arg->earg();
			case e {
			"cmd" =>	engine = ENGINE_CMD;
			"api" =>	engine = ENGINE_API;
			* =>
				sys->fprint(stderr, "speech9p: unknown engine '%s'\n", e);
				usage();
			}
		'k' =>	apikey = arg->earg();
		'u' =>	apiurl = arg->earg();
		'v' =>	voice = arg->earg();
		'l' =>	lang = arg->earg();
		* =>	usage();
		}
	arg = nil;

	# Detect platform and set defaults
	initplatform();

	sys->pctl(Sys->FORKFD, nil);

	user = rf("/dev/user");
	if(user == nil)
		user = "inferno";

	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0) {
		sys->fprint(stderr, "speech9p: can't create pipe: %r\n");
		raise "fail:pipe";
	}

	navops := chan of ref Navop;
	spawn navigator(navops);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big Qroot);
	fds[0] = nil;

	pidc := chan of int;
	spawn serveloop(tchan, srv, pidc, navops);
	<-pidc;

	# Ensure mount point exists
	ensuredir(mountpt);

	if(sys->mount(fds[1], nil, mountpt, Sys->MREPL|Sys->MCREATE, nil) < 0) {
		sys->fprint(stderr, "speech9p: mount failed: %r\n");
		raise "fail:mount";
	}
}

# Detect host platform and set default commands
initplatform()
{
	# Read host OS type from /dev/sysctl or infer from emulator
	# The emulator sets /dev/sysname; we detect platform from
	# which cmd device paths exist
	platform := detectplatform();

	case platform {
	"macos" =>
		# macOS: built-in 'say' for TTS, ffmpeg+whisper for STT
		if(cmdtts == "")
			cmdtts = "say";
		if(cmdstt == "")
			cmdstt = "whisper-cli";
		if(voice == "")
			voice = "samantha";
	"linux" =>
		# Linux: espeak-ng or piper for TTS, whisper for STT
		if(cmdtts == "")
			cmdtts = "espeak-ng --stdout";
		if(cmdstt == "")
			cmdstt = "";  # Needs Whisper or similar
		if(voice == "")
			voice = "default";
	"windows" =>
		# Windows: PowerShell for TTS
		if(cmdtts == "")
			cmdtts = "powershell -Command \"Add-Type -AssemblyName System.Speech; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.SetOutputToWaveFile('/tmp/speech_out.wav'); $s.Speak\"";
		if(cmdstt == "")
			cmdstt = "";
		if(voice == "")
			voice = "default";
	* =>
		# Unknown platform - leave empty, user must configure
		if(voice == "")
			voice = "default";
	}

	# Default API URL for OpenAI-compatible endpoints
	if(apiurl == "")
		apiurl = "https://api.openai.com/v1";
}

# Detect host platform by probing the environment
detectplatform(): string
{
	# The emulator sets emuhost in /env (see emu/port/main.c)
	emuos := rf("/env/emuhost");
	if(emuos != nil) {
		lower := str->tolower(strip(emuos));
		if(hasprefix(lower, "macosx") || hasprefix(lower, "darwin") || hasprefix(lower, "macos"))
			return "macos";
		if(hasprefix(lower, "linux"))
			return "linux";
		if(hasprefix(lower, "nt") || hasprefix(lower, "windows"))
			return "windows";
	}

	return "unknown";
}

# Read current config as text
readconfig(): string
{
	ename := "cmd";
	if(engine == ENGINE_API)
		ename = "api";

	result := "engine " + ename + "\n";
	result += "voice " + voice + "\n";
	result += "lang " + lang + "\n";
	result += "rate " + string audrate + "\n";
	result += "chans " + string audchans + "\n";
	result += "bits " + string audbits + "\n";

	if(engine == ENGINE_CMD) {
		result += "cmdtts " + cmdtts + "\n";
		result += "cmdstt " + cmdstt + "\n";
	}

	if(engine == ENGINE_API) {
		result += "apiurl " + apiurl + "\n";
		if(apikey != "")
			result += "apikey (set)\n";
		else
			result += "apikey (not set)\n";
	}

	return result;
}

# Parse and apply a configuration command
applyconfig(cmd: string): string
{
	(n, argv) := sys->tokenize(cmd, " \t\n");
	if(n < 2)
		return "error: usage: <key> <value>";

	key := hd argv;
	argv = tl argv;

	# Join remaining as value
	val := "";
	for(; argv != nil; argv = tl argv) {
		if(val != "")
			val += " ";
		val += hd argv;
	}

	case key {
	"engine" =>
		case val {
		"cmd" =>	engine = ENGINE_CMD;
		"api" =>	engine = ENGINE_API;
		* =>		return "error: unknown engine: " + val;
		}
	"voice" =>
		voice = val;
	"lang" =>
		lang = val;
	"rate" =>
		r := int val;
		if(r < 8000 || r > 48000)
			return "error: rate must be 8000-48000";
		audrate = r;
	"chans" =>
		c := int val;
		if(c != 1 && c != 2)
			return "error: chans must be 1 or 2";
		audchans = c;
	"bits" =>
		b := int val;
		if(b != 8 && b != 16)
			return "error: bits must be 8 or 16";
		audbits = b;
	"cmdtts" =>
		cmdtts = val;
	"cmdstt" =>
		cmdstt = val;
	"apiurl" =>
		apiurl = val;
	"apikey" =>
		apikey = val;
	* =>
		return "error: unknown config key: " + key;
	}

	return "ok";
}

# List voices for current engine
listvoices(): string
{
	case engine {
	ENGINE_CMD =>
		return listcmdvoices();
	ENGINE_API =>
		return listapivoices();
	}
	return "";
}

# List voices available from host command
listcmdvoices(): string
{
	platform := detectplatform();
	case platform {
	"macos" =>
		# macOS: say -v ? lists voices
		return runcmd("say -v \\?");
	"linux" =>
		# espeak-ng: --voices lists available voices
		return runcmd("espeak-ng --voices");
	}
	return "(voice listing not available for this platform)";
}

# List voices for API engine
listapivoices(): string
{
	# Standard voices for OpenAI-compatible APIs
	return "alloy\necho\nfable\nnova\nonyx\nshimmer\n";
}

# === TTS: Text to Speech ===

# Async wrapper for TTS — runs in spawned thread so serveloop stays responsive
asyncsay(fs: ref FidState, text: string)
{
	result := dosay(text);
	fs.sayresp = array of byte result;
}

# Synthesize text and play through /dev/audio
dosay(text: string): string
{
	if(text == "")
		return "error: no text to speak";

	case engine {
	ENGINE_CMD =>
		return saycmd(text);
	ENGINE_API =>
		return sayapi(text);
	}
	return "error: no engine configured";
}

# TTS via host command (platform-specific)
saycmd(text: string): string
{
	if(cmdtts == "")
		return "error: no TTS command configured for this platform";

	# Sanitize text: replace single quotes to prevent injection
	safe := sanitize(text);

	platform := detectplatform();
	case platform {
	"macos" =>
		return saycmd_macos(safe);
	"linux" =>
		return saycmd_linux(safe);
	"windows" =>
		return saycmd_windows(safe);
	}

	return "error: unsupported platform for cmd engine";
}

# macOS TTS: use 'say' command directly
# The 'say' command plays through the host audio device natively
saycmd_macos(text: string): string
{
	# Write text to say's stdin via devcmd data pipe
	# This avoids shell quoting issues entirely
	return runcmd_stdin(sys->sprint("say -v %s", voice), text);
}

# Linux TTS: use espeak-ng or piper
# Pipe text to stdin to avoid shell quoting issues
saycmd_linux(text: string): string
{
	if(hasprefix(cmdtts, "piper"))
		return runcmd_stdin(cmdtts + " --output-raw > /dev/fd/1", text);
	else
		return runcmd_stdin(sys->sprint("%s -v %s -s 160 --stdin --stdout", cmdtts, voice), text);
}

# Windows TTS via PowerShell (untested — placeholder)
saycmd_windows(nil: string): string
{
	return "error: Windows TTS not yet implemented";
}

# TTS via HTTP API (OpenAI-compatible)
sayapi(text: string): string
{
	if(apikey == "")
		return "error: API key not set (use: echo 'apikey <key>' > /n/speech/ctl)";

	# Build JSON request body
	apivoice := voice;
	if(apivoice == "" || apivoice == "default" || apivoice == "samantha")
		apivoice = "alloy";

	body := "{\"model\":\"tts-1\",\"input\":\"" + jsonesc(text) +
		"\",\"voice\":\"" + apivoice +
		"\",\"response_format\":\"pcm\"}";

	# Make HTTP POST to TTS endpoint
	url := apiurl + "/audio/speech";
	audiodata := apipost(url, body, "application/json");
	if(audiodata == nil)
		return "error: API request failed";

	# Write PCM data to /dev/audio
	return playpcm(audiodata);
}

# === STT: Speech to Text ===

# Record from /dev/audio and transcribe
dohear(): string
{
	case engine {
	ENGINE_CMD =>
		return hearcmd();
	ENGINE_API =>
		return hearapi();
	}
	return "error: no engine configured";
}

# STT via host commands (record + transcribe, all host-side)
hearcmd(): string
{
	if(cmdstt == "")
		return "error: no STT command configured\n" +
			"hint: install whisper-cpp and set: echo 'cmdstt whisper-cli' > /n/speech/ctl";

	platform := detectplatform();
	case platform {
	"macos" =>
		return hearcmd_macos();
	"linux" =>
		return hearcmd_linux();
	}
	return "error: STT not supported on this platform";
}

# macOS STT: ffmpeg records from mic, whisper-cli transcribes
hearcmd_macos(): string
{
	tmpfile := "/tmp/speech_stt.wav";
	duration := string (hearduration / 1000);

	# Record from macOS microphone via ffmpeg
	# -f avfoundation -i :0 = default audio input device
	# 16kHz mono WAV is what whisper expects
	reccmd := "ffmpeg -y -f avfoundation -i :0 -t " + duration +
		" -ar 16000 -ac 1 -sample_fmt s16 " + tmpfile +
		" </dev/null 2>/dev/null";
	result := runcmd(reccmd);
	if(hasprefix(result, "error:"))
		return result;

	# Transcribe with whisper-cli
	# -np = no prints (timestamps etc), -nt = no timestamps, just text
	modelpath := "/opt/homebrew/share/whisper-cpp/models/ggml-base.en.bin";
	wcmd := cmdstt + " -m " + modelpath + " -nt -np -f " + tmpfile +
		" 2>/dev/null";
	text := strip(runcmd(wcmd));
	if(text == "" || hasprefix(text, "error:"))
		return "error: transcription failed";

	return text;
}

# Linux STT: arecord + whisper-cli
hearcmd_linux(): string
{
	tmpfile := "/tmp/speech_stt.wav";
	duration := string (hearduration / 1000);

	# Record via arecord (ALSA)
	reccmd := "arecord -f S16_LE -r 16000 -c 1 -d " + duration +
		" " + tmpfile + " 2>/dev/null";
	result := runcmd(reccmd);
	if(hasprefix(result, "error:"))
		return result;

	# Transcribe
	wcmd := cmdstt + " -nt -np -f " + tmpfile + " 2>/dev/null";
	text := strip(runcmd(wcmd));
	if(text == "" || hasprefix(text, "error:"))
		return "error: transcription failed";

	return text;
}

# STT via HTTP API (OpenAI Whisper-compatible)
hearapi(): string
{
	if(apikey == "")
		return "error: API key not set";

	tmpfile := "/tmp/speech_stt.wav";

	# Record audio
	err := recordaudio(tmpfile, 5000);
	if(err != nil)
		return "error: recording failed: " + err;

	# Read recorded file
	audiodata := readbinaryfile(tmpfile);
	if(audiodata == nil)
		return "error: cannot read recorded audio";

	# POST to Whisper API as multipart form
	url := apiurl + "/audio/transcriptions";
	result := apitranscribe(url, audiodata);
	return result;
}

# === Audio I/O helpers ===

# Configure and play audio data from a file through /dev/audio
playfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r", path);

	# Configure audio output
	configaudio("out");

	# Open audio device
	afd := sys->open("/dev/audio", Sys->OWRITE);
	if(afd == nil)
		return sys->sprint("error: cannot open /dev/audio: %r");

	# Stream data
	buf := array[Sys->ATOMICIO] of byte;
	total := 0;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		if(sys->write(afd, buf, n) < 0)
			return sys->sprint("error: audio write failed: %r");
		total += n;
	}

	return sys->sprint("ok: played %d bytes", total);
}

# Play raw PCM data through /dev/audio
playpcm(data: array of byte): string
{
	configaudio("out");

	afd := sys->open("/dev/audio", Sys->OWRITE);
	if(afd == nil)
		return sys->sprint("error: cannot open /dev/audio: %r");

	if(sys->write(afd, data, len data) < 0)
		return sys->sprint("error: audio write failed: %r");

	return sys->sprint("ok: played %d bytes", len data);
}

# Record audio from /dev/audio to file
# duration_ms: recording duration in milliseconds
recordaudio(path: string, duration_ms: int): string
{
	configaudio("in");

	afd := sys->open("/dev/audio", Sys->OREAD);
	if(afd == nil)
		return sys->sprint("cannot open /dev/audio: %r");

	ofd := sys->create(path, Sys->OWRITE, 8r644);
	if(ofd == nil)
		return sys->sprint("cannot create %s: %r", path);

	# Write WAV header for compatibility with STT engines
	wavhdr := makewavheader(duration_ms);
	if(sys->write(ofd, wavhdr, len wavhdr) < 0)
		return sys->sprint("cannot write header: %r");

	# Calculate bytes to record
	bytespersec := audrate * audchans * (audbits / 8);
	totalbytes := (bytespersec * duration_ms) / 1000;

	buf := array[Sys->ATOMICIO] of byte;
	recorded := 0;
	while(recorded < totalbytes) {
		want := len buf;
		if(recorded + want > totalbytes)
			want = totalbytes - recorded;
		n := sys->read(afd, buf, want);
		if(n <= 0)
			break;
		sys->write(ofd, buf[:n], n);
		recorded += n;
	}

	# Update WAV header with actual size
	updatewavsize(ofd, recorded);

	return nil;
}

# Configure /dev/audioctl for input or output
configaudio(direction: string)
{
	ctl := sys->open("/dev/audioctl", Sys->OWRITE);
	if(ctl == nil)
		return;

	writectl(ctl, sys->sprint("%s rate %d", direction, audrate));
	writectl(ctl, sys->sprint("%s chans %d", direction, audchans));
	writectl(ctl, sys->sprint("%s bits %d", direction, audbits));
	writectl(ctl, sys->sprint("%s enc pcm", direction));
}

writectl(fd: ref Sys->FD, cmd: string)
{
	data := array of byte cmd;
	sys->write(fd, data, len data);
}

# Create a minimal WAV header
makewavheader(duration_ms: int): array of byte
{
	bytespersec := audrate * audchans * (audbits / 8);
	datasize := (bytespersec * duration_ms) / 1000;
	filesize := datasize + 36;
	blockalign := audchans * (audbits / 8);

	hdr := array[44] of byte;

	# RIFF header
	hdr[0:] = array of byte "RIFF";
	put32le(hdr, 4, filesize);
	hdr[8:] = array of byte "WAVE";

	# fmt chunk
	hdr[12:] = array of byte "fmt ";
	put32le(hdr, 16, 16);          # chunk size
	put16le(hdr, 20, 1);           # PCM format
	put16le(hdr, 22, audchans);
	put32le(hdr, 24, audrate);
	put32le(hdr, 28, bytespersec);
	put16le(hdr, 32, blockalign);
	put16le(hdr, 34, audbits);

	# data chunk
	hdr[36:] = array of byte "data";
	put32le(hdr, 40, datasize);

	return hdr;
}

# Update WAV header data size after recording
updatewavsize(fd: ref Sys->FD, datasize: int)
{
	buf := array[4] of byte;

	# Update RIFF size (offset 4)
	put32le(buf, 0, datasize + 36);
	sys->pwrite(fd, buf, 4, big 4);

	# Update data chunk size (offset 40)
	put32le(buf, 0, datasize);
	sys->pwrite(fd, buf, 4, big 40);
}

# Little-endian integer encoding
put16le(buf: array of byte, off, val: int)
{
	buf[off] = byte (val & 16rFF);
	buf[off+1] = byte ((val >> 8) & 16rFF);
}

put32le(buf: array of byte, off, val: int)
{
	buf[off] = byte (val & 16rFF);
	buf[off+1] = byte ((val >> 8) & 16rFF);
	buf[off+2] = byte ((val >> 16) & 16rFF);
	buf[off+3] = byte ((val >> 24) & 16rFF);
}

# === Host command execution via #C (devcmd) ===

cmdbound := 0;

# Ensure #C device is bound
bindcmd()
{
	if(cmdbound)
		return;
	if(sys->stat("/cmd/clone").t0 == -1)
		sys->bind("#C", "/", Sys->MBEFORE);
	cmdbound = 1;
}

# Run a host command and return output
runcmd(cmd: string): string
{
	bindcmd();

	# Open cmd device
	cfd := sys->open("/cmd/clone", Sys->ORDWR);
	if(cfd == nil)
		return sys->sprint("error: cannot open /cmd/clone: %r");

	# Read the command directory number
	buf := array[32] of byte;
	n := sys->read(cfd, buf, len buf);
	if(n <= 0)
		return "error: cannot read cmd number";

	dir := "/cmd/" + string buf[0:n];

	# Write exec command to clone fd (this is how devcmd works)
	execcmd := "exec /bin/sh -c '" + cmd + "'";
	if(sys->fprint(cfd, "%s", execcmd) < 0)
		return sys->sprint("error: exec failed: %r");

	# Read stdout from data file
	outfd := sys->open(dir + "/data", Sys->OREAD);
	if(outfd == nil)
		return sys->sprint("error: cannot open %s/data: %r", dir);

	result := "";
	rbuf := array[8192] of byte;
	for(;;) {
		n = sys->read(outfd, rbuf, len rbuf);
		if(n <= 0)
			break;
		result += string rbuf[0:n];
	}

	return result;
}

# Run a host command, piping text to its stdin, return stdout
runcmd_stdin(cmd, input: string): string
{
	bindcmd();

	cfd := sys->open("/cmd/clone", Sys->ORDWR);
	if(cfd == nil)
		return sys->sprint("error: cannot open /cmd/clone: %r");

	buf := array[32] of byte;
	n := sys->read(cfd, buf, len buf);
	if(n <= 0)
		return "error: cannot read cmd number";

	dir := "/cmd/" + string buf[0:n];

	execcmd := "exec /bin/sh -c '" + cmd + "'";
	if(sys->fprint(cfd, "%s", execcmd) < 0)
		return sys->sprint("error: exec failed: %r");

	# Open data for write (stdin) and read (stdout) separately
	tofd := sys->open(dir + "/data", Sys->OWRITE);
	if(tofd == nil)
		return sys->sprint("error: cannot open %s/data for write: %r", dir);

	fromfd := sys->open(dir + "/data", Sys->OREAD);
	if(fromfd == nil)
		return sys->sprint("error: cannot open %s/data for read: %r", dir);

	# Open wait file BEFORE reading stdout to avoid race condition:
	# devcmd's cmdproc() only writes exit status to waitq if it's non-nil.
	# waitq is created lazily in cmdopen(Qwait). If the child exits before
	# we open the wait file, cmdproc finds waitq==nil and the status is
	# lost — qread then blocks forever.
	waitfd := sys->open(dir + "/wait", Sys->OREAD);

	# Write input to stdin, then close to signal EOF
	data := array of byte input;
	sys->write(tofd, data, len data);
	tofd = nil;

	# Read stdout
	result := "";
	rbuf := array[8192] of byte;
	for(;;) {
		n = sys->read(fromfd, rbuf, len rbuf);
		if(n <= 0)
			break;
		result += string rbuf[0:n];
	}

	# Wait for child process to exit
	if(waitfd != nil) {
		wbuf := array[256] of byte;
		sys->read(waitfd, wbuf, len wbuf);
		waitfd = nil;
	}

	if(result == "")
		return "ok";
	return result;
}

# === HTTP API helpers ===

# POST JSON to an API endpoint, return response bytes
apipost(url, body, contenttype: string): array of byte
{
	(scheme, host, port, path, err) := parseurl(url);
	if(err != nil)
		return nil;

	addr := sys->sprint("tcp!%s!%s", host, port);

	fd: ref Sys->FD;
	if(scheme == "https") {
		(sfd, serr) := sslconnect(host, port);
		if(serr != nil)
			return nil;
		fd = sfd;
	} else {
		(ok, conn) := sys->dial(addr, nil);
		if(ok < 0)
			return nil;
		fd = conn.dfd;
	}

	# Build HTTP request
	request := sys->sprint("POST %s HTTP/1.1\r\nHost: %s\r\n", path, host);
	request += "Connection: close\r\n";
	request += sys->sprint("Content-Type: %s\r\n", contenttype);
	request += sys->sprint("Content-Length: %d\r\n", len body);
	if(apikey != "")
		request += "Authorization: Bearer " + apikey + "\r\n";
	request += "\r\n";
	request += body;

	reqbytes := array of byte request;
	if(sys->write(fd, reqbytes, len reqbytes) < 0)
		return nil;

	# Read response
	result: list of array of byte;
	total := 0;
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		chunk := array[n] of byte;
		chunk[0:] = buf[0:n];
		result = chunk :: result;
		total += n;
	}

	# Reassemble response
	resp := array[total] of byte;
	off := total;
	for(; result != nil; result = tl result) {
		chunk := hd result;
		off -= len chunk;
		resp[off:] = chunk;
	}

	# Strip HTTP headers - find blank line
	for(i := 0; i < len resp - 3; i++) {
		if(resp[i] == byte '\r' && resp[i+1] == byte '\n' &&
		   resp[i+2] == byte '\r' && resp[i+3] == byte '\n')
			return resp[i+4:];
	}

	return resp;
}

# POST audio for transcription (multipart form)
apitranscribe(url: string, audiodata: array of byte): string
{
	(scheme, host, port, path, err) := parseurl(url);
	if(err != nil)
		return "error: " + err;

	addr := sys->sprint("tcp!%s!%s", host, port);

	fd: ref Sys->FD;
	if(scheme == "https") {
		(sfd, serr) := sslconnect(host, port);
		if(serr != nil)
			return "error: " + serr;
		fd = sfd;
	} else {
		(ok, conn) := sys->dial(addr, nil);
		if(ok < 0)
			return sys->sprint("error: cannot connect: %r");
		fd = conn.dfd;
	}

	# Build multipart form
	boundary := "----InfernoBoundary9p2000";
	body := "--" + boundary + "\r\n";
	body += "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n";
	body += "Content-Type: audio/wav\r\n\r\n";

	suffix := "\r\n--" + boundary + "\r\n";
	suffix += "Content-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1";
	suffix += "\r\n--" + boundary + "\r\n";
	suffix += "Content-Disposition: form-data; name=\"language\"\r\n\r\n" + lang;
	suffix += "\r\n--" + boundary + "--\r\n";

	bodyprefix := array of byte body;
	bodysuffix := array of byte suffix;
	contentlen := len bodyprefix + len audiodata + len bodysuffix;

	# Build HTTP request
	request := sys->sprint("POST %s HTTP/1.1\r\nHost: %s\r\n", path, host);
	request += "Connection: close\r\n";
	request += sys->sprint("Content-Type: multipart/form-data; boundary=%s\r\n", boundary);
	request += sys->sprint("Content-Length: %d\r\n", contentlen);
	if(apikey != "")
		request += "Authorization: Bearer " + apikey + "\r\n";
	request += "\r\n";

	reqbytes := array of byte request;

	# Write request header + body prefix
	sys->write(fd, reqbytes, len reqbytes);
	sys->write(fd, bodyprefix, len bodyprefix);
	# Write audio data
	sys->write(fd, audiodata, len audiodata);
	# Write body suffix
	sys->write(fd, bodysuffix, len bodysuffix);

	# Read response
	response := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		response += string buf[0:n];
	}

	# Extract body from HTTP response
	(nil, nil, rbody) := parseresponse(response);

	# Parse JSON response to extract text
	# Simple extraction: look for "text" field
	return extractjsontext(rbody);
}

# SSL connection
sslconnect(host, port: string): (ref Sys->FD, string)
{
	addr := sys->sprint("tcp!%s!%s", host, port);
	(ok, conn) := sys->dial(addr, nil);
	if(ok < 0)
		return (nil, sys->sprint("cannot connect to %s: %r", addr));

	sslctl := sys->open("/net/ssl/clone", Sys->ORDWR);
	if(sslctl == nil)
		return (nil, "HTTPS not available: /net/ssl not found");

	buf := array[32] of byte;
	n := sys->read(sslctl, buf, len buf);
	if(n <= 0)
		return (nil, "cannot read SSL connection number");

	connnum := string buf[0:n];

	ctlpath := "/net/ssl/" + connnum + "/ctl";
	ctl := sys->open(ctlpath, Sys->OWRITE);
	if(ctl == nil)
		return (nil, "cannot open SSL ctl");

	cmd := sys->sprint("fd %d", conn.dfd.fd);
	if(sys->write(ctl, array of byte cmd, len cmd) < 0)
		return (nil, "cannot set SSL fd");

	if(sys->write(ctl, array of byte "start", 5) < 0)
		return (nil, "cannot start SSL");

	datapath := "/net/ssl/" + connnum + "/data";
	data := sys->open(datapath, Sys->ORDWR);
	if(data == nil)
		return (nil, "cannot open SSL data");

	return (data, nil);
}

# === JSON helpers ===

# Escape a string for JSON
jsonesc(s: string): string
{
	result := "";
	for(i := 0; i < len s; i++) {
		case s[i] {
		'"' =>	result += "\\\"";
		'\\' =>	result += "\\\\";
		'\n' =>	result += "\\n";
		'\r' =>	result += "\\r";
		'\t' =>	result += "\\t";
		* =>	result[len result] = s[i];
		}
	}
	return result;
}

# Extract "text" field from JSON response
extractjsontext(json: string): string
{
	# Look for "text": "..."
	target := "\"text\"";
	for(i := 0; i <= len json - len target; i++) {
		if(json[i:i+len target] == target) {
			# Skip to value
			j := i + len target;
			while(j < len json && (json[j] == ' ' || json[j] == ':'))
				j++;
			if(j < len json && json[j] == '"') {
				j++;
				result := "";
				while(j < len json && json[j] != '"') {
					if(json[j] == '\\' && j+1 < len json) {
						j++;
						case json[j] {
						'n' =>	result[len result] = '\n';
						'r' =>	result[len result] = '\r';
						't' =>	result[len result] = '\t';
						* =>	result[len result] = json[j];
						}
					} else {
						result[len result] = json[j];
					}
					j++;
				}
				return result;
			}
		}
	}
	return json;
}

# === URL parsing ===

parseurl(url: string): (string, string, string, string, string)
{
	scheme := "http";
	port := "80";

	if(len url > 8 && str->tolower(url[0:8]) == "https://") {
		scheme = "https";
		port = "443";
		url = url[8:];
	} else if(len url > 7 && str->tolower(url[0:7]) == "http://") {
		url = url[7:];
	} else {
		return ("", "", "", "", "invalid URL");
	}

	path := "/";
	for(i := 0; i < len url; i++) {
		if(url[i] == '/') {
			path = url[i:];
			url = url[0:i];
			break;
		}
	}

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

# Parse HTTP response
parseresponse(response: string): (string, string, string)
{
	statusend := 0;
	for(; statusend < len response; statusend++) {
		if(response[statusend] == '\n')
			break;
	}
	if(statusend == 0)
		return ("", "", "");

	status := response[0:statusend];

	headersend := statusend + 1;
	for(; headersend < len response - 1; headersend++) {
		if(response[headersend] == '\n' &&
		   (response[headersend+1] == '\n' || response[headersend+1] == '\r'))
			break;
	}

	headers := "";
	if(headersend > statusend + 1)
		headers = response[statusend+1:headersend];

	bodystart := headersend + 1;
	if(bodystart < len response && response[bodystart] == '\r')
		bodystart++;
	if(bodystart < len response && response[bodystart] == '\n')
		bodystart++;

	body := "";
	if(bodystart < len response)
		body = response[bodystart:];

	return (status, headers, body);
}

# === Utility functions ===

readbinaryfile(path: string): array of byte
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;

	chunks: list of array of byte;
	total := 0;
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		chunk := array[n] of byte;
		chunk[0:] = buf[0:n];
		chunks = chunk :: chunks;
		total += n;
	}

	result := array[total] of byte;
	off := total;
	for(; chunks != nil; chunks = tl chunks) {
		c := hd chunks;
		off -= len c;
		result[off:] = c;
	}
	return result;
}

# Sanitize text for shell command arguments
# Replace characters that could cause shell injection
sanitize(text: string): string
{
	result := "";
	for(i := 0; i < len text; i++) {
		c := text[i];
		# Only allow safe characters
		if((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
		   (c >= '0' && c <= '9') || c == ' ' || c == '.' ||
		   c == ',' || c == '!' || c == '?' || c == '-' ||
		   c == ':' || c == ';' || c == '(' || c == ')' ||
		   c == '\'' || c == '\n')
			result[len result] = c;
	}
	return result;
}

rf(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return nil;
	b := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, b, len b);
	if(n < 0)
		return nil;
	return string b[0:n];
}

pathexists(path: string): int
{
	(ok, nil) := sys->stat(path);
	return ok >= 0;
}

ensuredir(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil)
		return;
	fd = sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
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

# === Per-fid state management ===

getfidstate(fid: int): ref FidState
{
	for(l := fidstates; l != nil; l = tl l) {
		if((hd l).fid == fid)
			return hd l;
	}
	fs := ref FidState(fid, "", nil, nil);
	fidstates = fs :: fidstates;
	return fs;
}

delfidstate(fid: int)
{
	newlist: list of ref FidState;
	for(l := fidstates; l != nil; l = tl l) {
		if((hd l).fid != fid)
			newlist = hd l :: newlist;
	}
	fidstates = newlist;
}

# === 9P Navigator ===

navigator(navops: chan of ref Navop)
{
	while((m := <-navops) != nil) {
		pick n := m {
		Stat =>
			n.reply <-= dirgen(int n.path);
		Walk =>
			walkto(n);
		Readdir =>
			readdir(n, int n.path);
		}
	}
}

walkto(n: ref Navop.Walk)
{
	parent := int n.path;

	case parent {
	Qroot =>
		case n.name {
		"ctl" =>
			n.path = big Qctl;
			n.reply <-= dirgen(int n.path);
		"say" =>
			n.path = big Qsay;
			n.reply <-= dirgen(int n.path);
		"hear" =>
			n.path = big Qhear;
			n.reply <-= dirgen(int n.path);
		"voices" =>
			n.path = big Qvoices;
			n.reply <-= dirgen(int n.path);
		* =>
			n.reply <-= (nil, Enotfound);
		}
	* =>
		n.reply <-= (nil, Enotfound);
	}
}

dirgen(path: int): (ref Sys->Dir, string)
{
	d := ref sys->zerodir;
	d.uid = user;
	d.gid = user;
	d.muid = user;
	d.atime = 0;
	d.mtime = 0;

	case path {
	Qroot =>
		d.name = ".";
		d.mode = Sys->DMDIR | 8r555;
		d.qid.qtype = Sys->QTDIR;
	Qctl =>
		d.name = "ctl";
		d.mode = 8r666;
	Qsay =>
		d.name = "say";
		d.mode = 8r666;
	Qhear =>
		d.name = "hear";
		d.mode = 8r666;
	Qvoices =>
		d.name = "voices";
		d.mode = 8r444;
	* =>
		return (nil, Enotfound);
	}

	d.qid.path = big path;
	return (d, nil);
}

readdir(n: ref Navop.Readdir, path: int)
{
	case path {
	Qroot =>
		entries := array[] of {Qctl, Qsay, Qhear, Qvoices};
		for(i := 0; i < len entries; i++) {
			if(i >= n.offset) {
				(d, err) := dirgen(entries[i]);
				if(d != nil)
					n.reply <-= (d, err);
			}
		}
	}
	n.reply <-= (nil, nil);
}

# === Main 9P serve loop ===

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver, pidc: chan of int, navops: chan of ref Navop)
{
	pidc <-= sys->pctl(0, nil);

Serve:
	for(;;) {
		gm := <-tchan;
		if(gm == nil)
			break Serve;

		pick m := gm {
		Readerror =>
			break Serve;

		Read =>
			fid := srv.getfid(m.fid);
			if(fid == nil) {
				srv.reply(ref Rmsg.Error(m.tag, "bad fid"));
				continue;
			}

			path := int fid.path;
			case path {
			Qctl =>
				srv.reply(styxservers->readstr(m, readconfig()));
			Qsay =>
				fs := getfidstate(m.fid);
				if(fs.sayresp != nil)
					srv.reply(styxservers->readbytes(m, fs.sayresp));
				else
					srv.reply(styxservers->readstr(m, ""));
			Qhear =>
				# Trigger listening and return transcription
				fs := getfidstate(m.fid);
				if(fs.hearresp == nil) {
					text := dohear();
					fs.hearresp = array of byte text;
				}
				srv.reply(styxservers->readbytes(m, fs.hearresp));
			Qvoices =>
				srv.reply(styxservers->readstr(m, listvoices()));
			* =>
				srv.default(gm);
			}

		Write =>
			fid := srv.getfid(m.fid);
			if(fid == nil) {
				srv.reply(ref Rmsg.Error(m.tag, "bad fid"));
				continue;
			}

			path := int fid.path;
			case path {
			Qctl =>
				result := applyconfig(string m.data);
				srv.reply(ref Rmsg.Write(m.tag, len m.data));
				if(hasprefix(result, "error:"))
					sys->fprint(stderr, "speech9p: %s\n", result);
			Qsay =>
				text := string m.data;
				fs := getfidstate(m.fid);
				fs.sayreq = text;
				# Reply immediately, run TTS in background.
				# dosay() blocks for the full duration of audio playback
				# (e.g. 10-15s for macOS 'say'). Running it inline freezes
				# the serveloop, blocking all other 9P traffic.
				srv.reply(ref Rmsg.Write(m.tag, len m.data));
				spawn asyncsay(fs, strip(text));
			Qhear =>
				# Writing to hear resets/starts a new recording
				# Parse optional duration: "start 10000" = 10 seconds
				fs := getfidstate(m.fid);
				fs.hearresp = nil;
				cmd := strip(string m.data);
				(nc, argv) := sys->tokenize(cmd, " \t");
				if(nc >= 2) {
					dur := int (hd tl argv);
					if(dur > 0 && dur <= 60000)
						hearduration = dur;
				}
				srv.reply(ref Rmsg.Write(m.tag, len m.data));
			* =>
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
			}

		Clunk =>
			fid := srv.getfid(m.fid);
			if(fid != nil)
				delfidstate(m.fid);
			srv.default(gm);

		* =>
			srv.default(gm);
		}
	}
	navops <-= nil;
}
