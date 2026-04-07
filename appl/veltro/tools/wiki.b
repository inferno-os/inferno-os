implement ToolWiki;

#
# wiki - LLM wiki knowledge base tool for Veltro agent
#
# Provides ingest, query, lint, and status operations against
# the wiki9p file server ("wikia" = wiki agent, mounted at
# /n/wikia).  This is the Phase 1 tool wrapper; eventually
# Veltro will use the /n/wikia filesystem directly.
#
# Usage:
#   wiki ingest                   # Ingest all sources at /n/wikia/raw
#   wiki ingest <path>            # Ingest a specific file or directory
#   wiki query <question>         # Ask a question, get synthesized answer
#   wiki lint                     # Run wiki health check
#   wiki status                   # Show wiki state and stats
#   wiki log                      # Show operation history
#
# Source binding (done before ingest):
#   Veltro or the user binds data into /n/wikia/raw before calling ingest.
#   Sources can be host paths, databases, remote mounts, or other wikis.
#
# Dependencies:
#   /n/wikia   wiki9p must be mounted
#   /mnt/wiki  wikifs must be mounted (wiki9p talks to it)
#   /n/llm     LLM service must be available (wiki9p talks to it)
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolWiki: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

WIKIA_CTL:    con "/n/wikia/ctl";
WIKIA_QUERY:  con "/n/wikia/query";
WIKIA_STATUS: con "/n/wikia/status";
WIKIA_LOG:    con "/n/wikia/log";
WIKIA_DOC:    con "/n/wikia/doc";

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
	return "wiki";
}

doc(): string
{
	return "Wiki - LLM-maintained knowledge base\n\n" +
		"Usage:\n" +
		"  wiki ingest              Ingest all sources bound at /n/wikia/raw\n" +
		"  wiki ingest <path>       Ingest a specific file or path\n" +
		"  wiki query <question>    Ask a question, get answer from wiki\n" +
		"  wiki lint                Run health check on wiki pages\n" +
		"  wiki status              Show current state and statistics\n" +
		"  wiki log                 Show operation history\n\n" +
		"Before ingesting, bind source data:\n" +
		"  bind /n/local/docs /n/wikia/raw\n\n" +
		"The wiki is browsable via Charon at the httpd wiki URL.\n" +
		"Requires /n/wikia (run wiki9p), /mnt/wiki (run wikifs), /n/llm.\n";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	args = strip(args);
	if(args == "")
		return "error: usage: wiki <ingest|query|lint|status|log> [args]";

	# Check that wiki9p is mounted
	(ok, nil) := sys->stat(WIKIA_CTL);
	if(ok < 0)
		return "error: /n/wikia not mounted (run wiki9p first)";

	# Parse command
	(nil, argv) := sys->tokenize(args, " \t");
	if(argv == nil)
		return "error: empty command";

	verb := hd argv;
	argv = tl argv;

	# Rejoin remaining args
	rest := "";
	for(; argv != nil; argv = tl argv) {
		if(rest != "")
			rest += " ";
		rest += hd argv;
	}

	case verb {
	"ingest" =>
		return doingest(rest);
	"query" =>
		return doquery(rest);
	"lint" =>
		return dolint();
	"status" =>
		return dostatus();
	"log" =>
		return dolog();
	* =>
		return "error: unknown command: " + verb +
			"\ncommands: ingest, query, lint, status, log";
	}
}

# Send a command to wiki9p ctl and read the result
doingest(path: string): string
{
	cmd := "ingest";
	if(path != "")
		cmd += " " + path;
	return ctlcmd(cmd);
}

dolint(): string
{
	return ctlcmd("lint");
}

# Write a ctl command, then read back the result
ctlcmd(cmd: string): string
{
	fd := sys->open(WIKIA_CTL, Sys->ORDWR);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r", WIKIA_CTL);

	data := array of byte cmd;
	if(sys->write(fd, data, len data) < 0)
		return sys->sprint("error: write to ctl failed: %r");

	# Read back result (may take a while for ingest/lint)
	return readall(fd);
}

# Write question to query, read answer
doquery(question: string): string
{
	if(question == "")
		return "error: usage: wiki query <question>";

	fd := sys->open(WIKIA_QUERY, Sys->ORDWR);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r", WIKIA_QUERY);

	data := array of byte question;
	if(sys->write(fd, data, len data) < 0)
		return sys->sprint("error: write to query failed: %r");

	return readall(fd);
}

# Read status
dostatus(): string
{
	return readfile(WIKIA_STATUS);
}

# Read log
dolog(): string
{
	return readfile(WIKIA_LOG);
}

# Read an entire file as a string
readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r", path);
	return readall(fd);
}

# Read all available data from an fd
readall(fd: ref Sys->FD): string
{
	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	if(result == "")
		return "(no response)";
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
