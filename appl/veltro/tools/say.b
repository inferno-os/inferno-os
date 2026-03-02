implement ToolSay;

#
# say - Text-to-speech tool for Veltro agent
#
# Speaks text aloud through /dev/audio via the speech9p file server.
# Requires /n/speech to be mounted (run speech9p first).
#
# Usage:
#   say <text>                    # Speak the given text
#   say -v <voice> <text>         # Speak with specific voice
#
# Examples:
#   say Hello, I am Veltro.
#   say -v echo The task is complete.
#   say I found 3 files matching your query.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolSay: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

SPEECH_SAY: con "/n/speech/say";
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
	return "say";
}

doc(): string
{
	return "Say - Speak text aloud (text-to-speech)\n\n" +
		"Usage:\n" +
		"  say <text>                 Speak the given text\n" +
		"  say -v <voice> <text>      Speak with a specific voice\n\n" +
		"Arguments:\n" +
		"  text  - Text to speak aloud\n" +
		"  voice - Voice name (engine-specific)\n\n" +
		"Examples:\n" +
		"  say Hello, I am Veltro.\n" +
		"  say -v echo The task is complete.\n\n" +
		"Requires /n/speech (run speech9p first).\n" +
		"Configure via: echo 'voice <name>' > /n/speech/ctl";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	if(args == nil || len args == 0)
		return "error: usage: say <text>";

	# Parse optional -v flag
	text := args;
	(n, argv) := sys->tokenize(args, " \t");
	if(n >= 3 && hd argv == "-v") {
		argv = tl argv;
		newvoice := hd argv;
		argv = tl argv;

		# Set voice via ctl
		ctlfd := sys->open(SPEECH_CTL, Sys->OWRITE);
		if(ctlfd != nil) {
			cmd := array of byte ("voice " + newvoice);
			sys->write(ctlfd, cmd, len cmd);
		}

		# Rejoin remaining args as text
		text = "";
		for(; argv != nil; argv = tl argv) {
			if(text != "")
				text += " ";
			text += hd argv;
		}
	}

	text = strip(text);
	if(text == "")
		return "error: no text to speak";

	# Check that speech9p is mounted
	(ok, nil) := sys->stat(SPEECH_SAY);
	if(ok < 0)
		return "error: /n/speech not mounted (run speech9p first)";

	# Write text to /n/speech/say — fire and forget.
	# speech9p runs TTS in a background thread; the write returns immediately.
	fd := sys->open(SPEECH_SAY, Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r", SPEECH_SAY);

	data := array of byte text;
	wn := sys->write(fd, data, len data);
	if(wn < 0)
		return sys->sprint("error: write to say failed: %r");

	return "ok";
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
