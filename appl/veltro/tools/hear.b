implement ToolHear;

#
# hear - Speech-to-text tool for Veltro agent
#
# Listens via /dev/audio and returns transcribed text via the
# speech9p file server. Requires /n/speech to be mounted.
#
# Usage:
#   hear                          # Listen and transcribe (default 5s)
#   hear <duration_ms>            # Listen for specified duration
#
# Examples:
#   hear                          # Listen for 5 seconds
#   hear 10000                    # Listen for 10 seconds
#
# The tool writes a start command to /n/speech/hear, then reads
# back the transcribed text. The speech9p server handles the
# actual recording and STT engine interaction.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolHear: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

SPEECH_HEAR: con "/n/speech/hear";
SPEECH_CTL: con "/n/speech/ctl";

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";
	return nil;
}

name(): string
{
	return "hear";
}

doc(): string
{
	return "Hear - Listen and transcribe speech (speech-to-text)\n\n" +
		"Usage:\n" +
		"  hear                       Listen and transcribe (default 5s)\n" +
		"  hear <duration_ms>         Listen for specified duration\n\n" +
		"Arguments:\n" +
		"  duration_ms - Recording duration in milliseconds (default: 5000)\n\n" +
		"Examples:\n" +
		"  hear                       Listen for 5 seconds\n" +
		"  hear 10000                 Listen for 10 seconds\n\n" +
		"Requires /n/speech (run speech9p first).\n" +
		"Configure STT engine via: echo 'engine api' > /n/speech/ctl";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	# Check that speech9p is mounted
	(ok, nil) := sys->stat(SPEECH_HEAR);
	if(ok < 0)
		return "error: /n/speech not mounted (run speech9p first)";

	# Parse optional duration
	duration := "5000";
	args = strip(args);
	if(args != "") {
		d := int args;
		if(d > 0 && d <= 60000)
			duration = string d;
		else if(d > 60000)
			return "error: duration must be <= 60000ms (60 seconds)";
	}

	# Write start command to /n/speech/hear to begin recording
	fd := sys->open(SPEECH_HEAR, Sys->ORDWR);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r", SPEECH_HEAR);

	# Write triggers a new recording
	cmd := array of byte ("start " + duration);
	wn := sys->write(fd, cmd, len cmd);
	if(wn < 0)
		return sys->sprint("error: write to hear failed: %r");

	# Read transcription result
	sys->seek(fd, big 0, Sys->SEEKSTART);
	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}

	if(result == "")
		return "(no speech detected)";

	return result;
}

# Strip leading/trailing whitespace
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
