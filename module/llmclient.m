#
# llmclient.m - LLM API client module interface
#
# Provides HTTP-based access to LLM APIs (Anthropic Messages API and
# OpenAI-compatible Chat Completions API) with streaming support.
#
# Used by llmsrv.b to make API calls from the Styx server.
#

Llmclient: module
{
	PATH: con "/dis/lib/llmclient.dis";

	# Message in conversation history
	LlmMessage: adt {
		role:    string;  # "user", "assistant", "system"
		content: string;  # text content (always set)
		sc:      string;  # structured content JSON (tool turns only, "" otherwise)
	};

	# Tool definition
	ToolDef: adt {
		name:        string;
		description: string;
		inputschema: string;  # JSON string of input_schema object
	};

	# Tool result submitted back to the LLM
	ToolResult: adt {
		tooluseid: string;
		content:   string;
	};

	# All parameters for a single API call (CSP - no shared state)
	AskRequest: adt {
		messages:       list of ref LlmMessage;
		prompt:         string;   # empty when toolresults set
		model:          string;
		temperature:    real;
		systemprompt:   string;
		thinkingtokens: int;      # 0=disabled, -1=max, >0=budget
		prefill:        string;
		tooldefs:       list of ref ToolDef;    # nil = text-only mode
		toolresults:    list of ref ToolResult;  # nil = normal prompt
		streamch:       chan of string;          # non-nil enables streaming
	};

	# Response from an API call
	AskResponse: adt {
		response:       string;  # formatted text or STOP:/TOOL: response
		structuredjson: string;  # JSON content blocks for history replay
		tokens:         int;     # total tokens (input + output)
	};

	# Initialize the module
	init:           fn();

	# Anthropic Messages API backend
	# apiurl is typically "api.anthropic.com"
	askanthropic:   fn(apikey, apiurl: string, req: ref AskRequest): (ref AskResponse, string);

	# OpenAI-compatible Chat Completions API backend
	# baseurl includes /v1 (e.g. "http://localhost:11434/v1")
	askopenai:      fn(baseurl, apikey: string, req: ref AskRequest): (ref AskResponse, string);

	# Parse TOOL_RESULTS wire format into ToolResult list
	parsetoolresults: fn(text: string): (list of ref ToolResult, string);

	# Extract plain text from STOP:-formatted response
	extracttextcontent: fn(response: string): string;

	# Build JSON conversation history from message list
	messagesjson:   fn(msgs: list of ref LlmMessage): string;

	# JSON escape helper
	jsonescapestr:  fn(s: string): string;
};
