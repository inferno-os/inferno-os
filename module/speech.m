#
# speech.m - Speech synthesis and recognition interface
#
# Defines the abstract interface for TTS and STT engines.
# Engines implement this interface to provide platform-specific
# speech capabilities through a uniform API.
#
# The speech9p file server uses these interfaces to bridge
# between 9P file operations and actual speech engines.
#
# Engine selection is done at runtime via the ctl file:
#   echo 'engine cmd' > /n/speech/ctl     # Host command backend
#   echo 'engine api' > /n/speech/ctl     # HTTP API backend
#

Speech: module {
	PATH: con "/dis/lib/speech.dis";

	# Engine capabilities
	CAPTTS: con 1;   # Can synthesize speech
	CAPSTT: con 2;   # Can recognize speech

	# Audio format for exchange between engine and file server
	AudioFmt: adt {
		rate:     int;     # Sample rate in Hz (e.g. 16000, 22050, 24000)
		chans:    int;     # Number of channels (1=mono, 2=stereo)
		bits:     int;     # Bits per sample (8, 16)
		enc:      string;  # Encoding: "pcm", "ulaw", "alaw"
	};

	# Engine configuration
	Config: adt {
		engine:   string;  # Engine name: "cmd", "api"
		voice:    string;  # Voice identifier (engine-specific)
		lang:     string;  # Language code (e.g. "en", "es", "fr")
		apiurl:   string;  # API endpoint URL (for api engine)
		apikey:   string;  # API key (for api engine)
		cmdtts:   string;  # Host TTS command (for cmd engine)
		cmdstt:   string;  # Host STT command (for cmd engine)
		infmt:    ref AudioFmt;  # Input audio format (for STT)
		outfmt:   ref AudioFmt;  # Output audio format (from TTS)
	};

	# Result from a TTS operation
	TTSResult: adt {
		audio:  array of byte;  # Raw PCM audio data
		fmt:    ref AudioFmt;   # Format of the audio data
		err:    string;         # Error message or nil
	};

	# Result from an STT operation
	STTResult: adt {
		text:   string;  # Recognized text
		err:    string;  # Error message or nil
	};

	# TTS engine interface
	TTSEngine: adt {
		name:       fn(e: self ref TTSEngine): string;
		caps:       fn(e: self ref TTSEngine): int;
		configure:  fn(e: self ref TTSEngine, cfg: ref Config): string;
		voices:     fn(e: self ref TTSEngine): list of string;
		synthesize: fn(e: self ref TTSEngine, text: string): ref TTSResult;
	};

	# STT engine interface
	STTEngine: adt {
		name:       fn(e: self ref STTEngine): string;
		caps:       fn(e: self ref STTEngine): int;
		configure:  fn(e: self ref STTEngine, cfg: ref Config): string;
		recognize:  fn(e: self ref STTEngine, audio: array of byte, fmt: ref AudioFmt): ref STTResult;
	};

	# Module-level functions
	init:        fn(): string;
	defaultfmt:  fn(): ref AudioFmt;
	fmtstr:      fn(fmt: ref AudioFmt): string;
	parsefmt:    fn(s: string): ref AudioFmt;
};
