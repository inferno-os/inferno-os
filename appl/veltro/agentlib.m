#
# agentlib.m - Shared agent library for Veltro
#
# Common functions used by veltro.b (single-shot agent) and repl.b
# (interactive REPL). Handles LLM session management, prompt building,
# response parsing, and tool execution via the /tool 9P filesystem.
#
# NOTE: Include sys.m before including this file (needed for Sys->FD type).
#

AgentLib: module {
	PATH: con "/dis/veltro/agentlib.dis";

	STREAM_THRESHOLD: con 4096;

	init: fn();
	setverbose: fn(v: int);

	# LLM session management
	createsession: fn(): string;
	setprefillpath: fn(path, prefill: string);
	queryllmfd: fn(fd: ref Sys->FD, prompt: string): string;
	setsystemprompt: fn(path, prompt: string);

	# Prompt building
	discovernamespace: fn(): string;
	buildsystemprompt: fn(ns: string): string;
	loadreminders: fn(toollist: list of string): string;
	loadtooldocs: fn(toollist: list of string): string;
	defaultsystemprompt: fn(): string;

	# Response parsing
	parseaction: fn(response: string): (string, string);
	parseactions: fn(response: string): list of (string, string);
	parseheredoc: fn(args: string, lines: list of string): (string, list of string);
	collectsaytext: fn(first: string, lines: list of string): string;
	stripmarkdown: fn(s: string): string;
	stripaction: fn(response: string): string;

	# Tool execution (9P)
	calltool: fn(tool, args: string): string;
	writescratch: fn(content: string, step: int): string;

	# Native tool_use protocol (Anthropic JSON API)
	buildtooldefs: fn(toollist: list of string): string;
	initsessiontools: fn(id: string, toollist: list of string);
	parsellmresponse: fn(response: string): (string, list of (string, string, string), string);
	buildtoolresults: fn(results: list of (string, string)): string;

	# Utilities
	readfile: fn(path: string): string;
	pathexists: fn(path: string): int;
	ensuredir: fn(path: string);
	strip: fn(s: string): string;
	contains: fn(s, sub: string): int;
	hasprefix: fn(s, prefix: string): int;
	splitfirst: fn(s: string): (string, string);
	truncate: fn(s: string, max: int): string;
	findheredoc: fn(s: string): int;
};
