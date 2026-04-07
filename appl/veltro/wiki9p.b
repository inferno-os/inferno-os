implement Wiki9p;

#
# wiki9p - 9P file server for LLM-maintained wiki knowledge bases
#
# "wikia" = wiki agent.  Mounts at /n/wikia to distinguish from
# wikifs itself (the storage layer at /mnt/wiki).
#
# Intelligence layer atop wikifs: ingests sources via LLM, answers
# queries by synthesizing wiki pages, and lints for consistency.
# Designed for both human use (Charon/Lucifer) and agent use (Veltro).
#
# Filesystem structure:
#   /n/wikia/
#   ├── ctl        (rw)  Commands: ingest [path], lint, reset
#   ├── query      (rw)  Write question, read synthesized answer
#   ├── status     (r)   Current state and wiki statistics
#   ├── log        (r)   Append-only operation log
#   └── doc        (r)   Self-describing interface documentation
#
# Dependencies:
#   /mnt/wiki      wikifs must be mounted (storage layer)
#   /n/llm         LLM service must be available (inference)
#
# Sources are bound into the namespace by the caller before
# issuing an ingest command.  They can be anything mountable:
#   bind /n/local/path/to/docs /n/wikia/raw
#   mount tcp!host!styx       /n/wikia/raw
#   mount dbfs                /n/wikia/raw
#
# After ingestion completes, the source can be unmounted.
# The wiki retains the knowledge with citations.
#
# Usage:
#   wiki9p                          # Start with defaults
#   wiki9p -D                       # With 9P debug tracing
#   wiki9p -m /n/wikia              # Custom mount point
#   wiki9p -w /mnt/wiki             # Custom wikifs location
#
# Examples:
#   bind /n/local/research /n/wikia/raw
#   echo 'ingest' > /n/wikia/ctl              # Ingest all sources at /n/wikia/raw
#   echo 'ingest /n/wikia/raw/report.md' > /n/wikia/ctl  # Ingest one file
#   echo 'What are the ITAR risks?' > /n/wikia/query
#   cat /n/wikia/query                         # Read answer
#   echo 'lint' > /n/wikia/ctl                # Health check
#   cat /n/wikia/status                        # Wiki stats
#   cat /n/wikia/log                           # Operation history
#   cat /n/wikia/doc                           # Interface docs
#

include "sys.m";
	sys: Sys;

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

include "daytime.m";
	daytime: Daytime;

include "readdir.m";
	readdir: Readdir;

Wiki9p: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

# Qid layout
Qroot, Qctl, Qquery, Qstatus, Qlog, Qdoc, Qraw: con iota;

# Per-fid state
FidState: adt {
	fid:        int;
	ctlresp:    array of byte;   # Response from last ctl command
	queryreq:   string;          # Question written to query
	queryresp:  array of byte;   # Synthesized answer
};

# Operation state
IDLE, INGESTING, QUERYING, LINTING: con iota;

statenames := array[] of { "idle", "ingesting", "querying", "linting" };
curstate := IDLE;

# Configuration
mountpt := "/n/wikia";
wikidir := "/mnt/wiki";    # Where wikifs is mounted
llmdir := "/n/llm";        # Where llmsrv is mounted

# LLM session
llmsession := -1;           # Session ID from /n/llm/new

# Operation log (kept in memory, served via Qlog)
logbuf := "";
logmax := 64 * 1024;       # Max log size before truncation

# Wiki author identity
author := "wiki9p";

stderr: ref Sys->FD;
user: string;
fidstates: list of ref FidState;

nomod(s: string)
{
	sys->fprint(stderr, "wiki9p: can't load %s: %r\n", s);
	raise "fail:load";
}

usage()
{
	sys->fprint(stderr, "Usage: wiki9p [-D] [-m mountpoint] [-w wikidir]\n");
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

	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		nomod(Daytime->PATH);

	readdir = load Readdir Readdir->PATH;
	if(readdir == nil)
		nomod(Readdir->PATH);

	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	arg->init(args);

	while((o := arg->opt()) != 0)
		case o {
		'D' =>	styxservers->traceset(1);
		'm' =>	mountpt = arg->earg();
		'w' =>	wikidir = arg->earg();
		* =>	usage();
		}
	arg = nil;

	sys->pctl(Sys->FORKFD, nil);

	user = rf("/dev/user");
	if(user == nil)
		user = "inferno";

	# Ensure raw source bind point exists
	ensuredir(mountpt);
	rawpath := mountpt + "/raw";
	ensuredir(rawpath);

	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0) {
		sys->fprint(stderr, "wiki9p: can't create pipe: %r\n");
		raise "fail:pipe";
	}

	navops := chan of ref Navop;
	spawn navigator(navops);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big Qroot);
	fds[0] = nil;

	pidc := chan of int;
	spawn serveloop(tchan, srv, pidc, navops);
	<-pidc;

	if(sys->mount(fds[1], nil, mountpt, Sys->MREPL|Sys->MCREATE, nil) < 0) {
		sys->fprint(stderr, "wiki9p: mount failed: %r\n");
		raise "fail:mount";
	}

	appendlog("started", "wiki9p mounted at " + mountpt);
}

# ===================================================================
# LLM interaction via /n/llm filesystem
# ===================================================================

# Open (or reuse) an LLM session and send a prompt, return response
llmask(systemprompt, prompt: string): string
{
	# Allocate session if needed
	if(llmsession < 0) {
		s := rf(llmdir + "/new");
		if(s == nil)
			return "error: cannot open LLM session (is llmsrv mounted at " + llmdir + "?)";
		llmsession = int strip(s);

		# Configure session
		sdir := llmdir + "/" + string llmsession;
		wf(sdir + "/system", systemprompt);
	}

	# Write prompt, read response
	sdir := llmdir + "/" + string llmsession;
	wf(sdir + "/ask", prompt);

	resp := rf(sdir + "/ask");
	if(resp == nil)
		return "error: LLM ask failed";
	return resp;
}

# Close the LLM session
llmclose()
{
	if(llmsession >= 0) {
		sdir := llmdir + "/" + string llmsession;
		wf(sdir + "/ctl", "close");
		llmsession = -1;
	}
}

# ===================================================================
# Wiki operations via /mnt/wiki filesystem (wikifs)
# ===================================================================

# Read a wiki page's raw content by page number
wikiread(num: int): string
{
	name := wikipagename(num);
	if(name == nil)
		return nil;
	return rf(wikidir + "/" + name + "/current");
}

# Read a wiki page by name (with underscore substitution)
wikireadname(name: string): string
{
	for(i := 0; i < len name; i++)
		if(name[i] == ' ')
			name[i] = '_';
	return rf(wikidir + "/" + name + "/current");
}

# Write a new wiki page (or update existing) via wikifs /new protocol
wikiwrite(title, comment, content: string): int
{
	fd := sys->open(wikidir + "/new", Sys->ORDWR);
	if(fd == nil) {
		sys->fprint(stderr, "wiki9p: cannot open %s/new: %r\n", wikidir);
		return -1;
	}

	# Write header: title, metadata, then content
	# D0 = new page (wikifs uses this for version tracking)
	hdr := title + "\n";
	hdr += "D0\n";
	hdr += "A" + author + "\n";
	if(comment != nil)
		hdr += "C" + comment + "\n";
	hdr += "\n";

	# Content is written as-is; wikifs adds # prefixes internally
	sys->fprint(fd, "%s%s", hdr, content);

	# Zero-length write signals end-of-page
	buf := array[1] of byte;
	n := sys->write(fd, buf, 0);
	if(n < 0) {
		sys->fprint(stderr, "wiki9p: write to wiki failed: %r\n");
		return -1;
	}

	# Seek to start before reading back the canonical page name
	sys->seek(fd, big 0, Sys->SEEKSTART);
	rbuf := array[512] of byte;
	n = sys->read(fd, rbuf, len rbuf);
	if(n > 0)
		return 0;
	return -1;
}

# List all wiki pages (read the map file)
wikimap(): list of (int, string)
{
	content := rf(wikidir + "/map");
	if(content == nil) {
		# No map file — try listing directory
		return wikimapfromdir();
	}
	pages: list of (int, string);
	(nil, lines) := sys->tokenize(content, "\n");
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		(n, toks) := sys->tokenize(line, " \t");
		if(n >= 2) {
			num := int hd toks;
			name := hd tl toks;
			pages = (num, name) :: pages;
		}
	}
	return pages;
}

# Fallback: list wiki pages from directory entries
wikimapfromdir(): list of (int, string)
{
	(dirs, n) := readdir->init(wikidir, Readdir->NAME);
	pages: list of (int, string);
	for(i := 0; i < n; i++) {
		d := dirs[i];
		if((d.mode & Sys->DMDIR) && d.name != "." && d.name != "..") {
			# Skip non-page directories
			if(d.name == "new" || d.name == "map")
				continue;
			pages = (i, d.name) :: pages;
		}
	}
	return pages;
}

# Get page name from number via map
wikipagename(num: int): string
{
	pages := wikimap();
	for(; pages != nil; pages = tl pages) {
		(n, name) := hd pages;
		if(n == num)
			return name;
	}
	return nil;
}

# ===================================================================
# Ingest: read sources, create wiki pages via LLM
# ===================================================================

INGEST_SYSTEM_PROMPT: con
	"You are a wiki knowledge base agent. Your task is to read source documents " +
	"and create structured wiki pages from them.\n\n" +
	"For each source, produce:\n" +
	"1. A SUMMARY page capturing the key points, conclusions, and data\n" +
	"2. Updates to any existing CONCEPT or ENTITY pages that are affected\n" +
	"3. New CONCEPT or ENTITY pages for important topics not yet in the wiki\n\n" +
	"Format your output as a sequence of page operations, one per page:\n\n" +
	"===PAGE===\n" +
	"TITLE: <page title>\n" +
	"COMMENT: <brief description of change>\n" +
	"TYPE: source|concept|entity|synthesis\n" +
	"---\n" +
	"<page content using wiki markup>\n\n" +
	"Wiki markup rules:\n" +
	"- Blank line = new paragraph\n" +
	"- ALL CAPS paragraph = section heading\n" +
	"- Line starting with * = bullet item\n" +
	"- Line starting with ! = preformatted/code\n" +
	"- [link text] = wiki link to another page\n" +
	"- [text | url] = external link\n\n" +
	"Always cite which source document the information came from.\n" +
	"Cross-reference related wiki pages using [page name] links.\n" +
	"Be thorough but concise. Prefer structured data over prose.\n";

doingest(path: string): string
{
	curstate = INGESTING;

	# Determine what to ingest
	sources: list of string;
	if(path == nil || path == "" || path == "all")
		sources = listsources(mountpt + "/raw");
	else
		sources = path :: nil;

	if(sources == nil) {
		curstate = IDLE;
		return "error: no sources found (bind sources to " + mountpt + "/raw first)";
	}

	nsrc := 0;
	npages := 0;
	errors := "";

	# Get current wiki state for context
	wikicontext := buildwikicontext();

	for(; sources != nil; sources = tl sources) {
		src := hd sources;
		appendlog("ingest", "reading " + src);

		content := readfile(src);
		if(content == nil) {
			errors += "cannot read " + src + "\n";
			continue;
		}

		# Build prompt with source content and existing wiki context
		prompt := "EXISTING WIKI PAGES:\n" + wikicontext + "\n\n" +
			"SOURCE DOCUMENT (from " + src + "):\n" + content + "\n\n" +
			"Create wiki pages from this source. Reference existing pages where relevant. " +
			"If a concept or entity page already exists, output an updated version.";

		resp := llmask(INGEST_SYSTEM_PROMPT, prompt);
		if(hasprefix(resp, "error:")) {
			errors += src + ": " + resp + "\n";
			continue;
		}

		# Parse LLM response and write pages to wikifs
		n := writepages(resp, src);
		npages += n;
		nsrc++;

		appendlog("ingest", sys->sprint("created %d pages from %s", n, src));

		# Update context for next source (pages compound)
		wikicontext = buildwikicontext();
	}

	llmclose();
	curstate = IDLE;

	result := sys->sprint("ingested %d sources, created/updated %d pages", nsrc, npages);
	if(errors != "")
		result += "\nerrors:\n" + errors;

	appendlog("ingest", result);
	return result;
}

# Build a summary of current wiki contents for LLM context
buildwikicontext(): string
{
	pages := wikimap();
	if(pages == nil)
		return "(empty wiki)";

	context := "";
	for(; pages != nil; pages = tl pages) {
		(num, name) := hd pages;
		content := wikiread(num);
		if(content == nil)
			continue;
		# Include title and first few lines as context
		title := "";
		summary := "";
		nlines := 0;
		for(i := 0; i < len content; i++) {
			if(content[i] == '\n') {
				if(title == "")
					title = content[0:i];
				nlines++;
				if(nlines >= 5) {
					summary = content[0:i];
					break;
				}
			}
		}
		if(summary == "")
			summary = content;
		context += "- [" + name + "]: " + summary + "\n";
	}
	return context;
}

# Parse LLM response into page operations and write to wikifs
writepages(resp, source: string): int
{
	count := 0;
	# Split on ===PAGE=== markers
	rest := resp;
	for(;;) {
		idx := strindex(rest, "===PAGE===");
		if(idx < 0)
			break;
		rest = rest[idx + 10:];

		# Parse header
		title := "";
		comment := "";
		(nil, lines) := sys->tokenize(rest, "\n");
		content := "";
		inbody := 0;

		for(; lines != nil; lines = tl lines) {
			line := hd lines;
			if(inbody) {
				# Check for next page marker
				if(hasprefix(line, "===PAGE==="))
					break;
				content += line + "\n";
			} else if(line == "---") {
				inbody = 1;
			} else if(hasprefix(line, "TITLE: ")) {
				title = line[7:];
			} else if(hasprefix(line, "COMMENT: ")) {
				comment = line[9:];
			}
			# TYPE is informational; we don't use it structurally
		}

		if(title != "" && content != "") {
			if(comment == "")
				comment = "Ingested from " + source;
			if(wikiwrite(title, comment, content) >= 0)
				count++;
		}
	}
	return count;
}

# ===================================================================
# Query: synthesize answers from wiki pages via LLM
# ===================================================================

QUERY_SYSTEM_PROMPT: con
	"You are a wiki knowledge base assistant. Answer questions by synthesizing " +
	"information from the wiki pages provided.\n\n" +
	"Rules:\n" +
	"- Always cite which wiki page(s) your answer draws from using [page name]\n" +
	"- If the wiki doesn't contain enough information, say so clearly\n" +
	"- Be precise and structured; prefer bullet points for multi-part answers\n" +
	"- If your answer reveals a gap or contradiction in the wiki, note it\n";

doquery(question: string): string
{
	curstate = QUERYING;

	# Read all wiki pages for context
	context := buildwikifullcontext();
	if(context == "")
		context = "(wiki is empty)";

	prompt := "WIKI CONTENTS:\n" + context + "\n\n" +
		"QUESTION: " + question + "\n\n" +
		"Answer the question using the wiki contents. Cite your sources.";

	resp := llmask(QUERY_SYSTEM_PROMPT, prompt);

	llmclose();
	curstate = IDLE;

	appendlog("query", question);
	return resp;
}

# Full wiki contents for query context
buildwikifullcontext(): string
{
	pages := wikimap();
	if(pages == nil)
		return "";

	context := "";
	for(; pages != nil; pages = tl pages) {
		(num, name) := hd pages;
		content := wikiread(num);
		if(content == nil)
			continue;
		context += "=== " + name + " ===\n" + content + "\n\n";
	}
	return context;
}

# ===================================================================
# Lint: check wiki health via LLM
# ===================================================================

LINT_SYSTEM_PROMPT: con
	"You are a wiki quality auditor. Review the wiki pages and identify:\n" +
	"1. CONTRADICTIONS between pages\n" +
	"2. STALE claims that may need updating\n" +
	"3. ORPHAN pages with no inbound links\n" +
	"4. GAPS — concepts mentioned but lacking their own page\n" +
	"5. MISSING cross-references between related pages\n\n" +
	"Format as a structured report with sections for each category.\n" +
	"For each finding, reference the specific page(s) involved.\n";

dolint(): string
{
	curstate = LINTING;

	context := buildwikifullcontext();
	if(context == "")
		return "wiki is empty, nothing to lint";

	prompt := "WIKI CONTENTS:\n" + context + "\n\n" +
		"Audit this wiki. Report all issues found.";

	resp := llmask(LINT_SYSTEM_PROMPT, prompt);

	# Write lint report as a wiki page
	wikiwrite("Wiki Lint Report", "Automated lint check", resp);

	llmclose();
	curstate = IDLE;

	appendlog("lint", "completed");
	return resp;
}

# ===================================================================
# Source listing
# ===================================================================

# List all readable files under a path
listsources(path: string): list of string
{
	(dirs, n) := readdir->init(path, Readdir->NAME);
	sources: list of string;
	for(i := 0; i < n; i++) {
		d := dirs[i];
		fullpath := path + "/" + d.name;
		if(d.mode & Sys->DMDIR) {
			# Recurse into subdirectories
			subsrc := listsources(fullpath);
			for(; subsrc != nil; subsrc = tl subsrc)
				sources = hd subsrc :: sources;
		} else {
			sources = fullpath :: sources;
		}
	}
	return sources;
}

# ===================================================================
# Status
# ===================================================================

readstatus(): string
{
	s := "state: " + statenames[curstate] + "\n";
	s += "wikifs: " + wikidir + "\n";
	s += "llm: " + llmdir + "\n";
	s += "mountpoint: " + mountpt + "\n";

	# Count wiki pages
	pages := wikimap();
	npages := 0;
	for(p := pages; p != nil; p = tl p)
		npages++;
	s += "pages: " + string npages + "\n";

	# Check if raw sources are bound
	(rawdirs, nraw) := readdir->init(mountpt + "/raw", Readdir->NONE);
	if(nraw > 0) {
		s += "raw sources: " + string nraw + " entries\n";
		for(i := 0; i < nraw && i < 10; i++)
			s += "  " + rawdirs[i].name + "\n";
		if(nraw > 10)
			s += "  ... and " + string (nraw - 10) + " more\n";
	} else
		s += "raw sources: (none bound)\n";

	return s;
}

# ===================================================================
# Self-describing documentation
# ===================================================================

DOCTEXT: con
	"wiki9p - LLM-maintained wiki knowledge base (\"wikia\" = wiki agent)\n" +
	"\n" +
	"FILESYSTEM\n" +
	"\n" +
	"  ctl      Read/write. Write commands, read results.\n" +
	"           Commands:\n" +
	"             ingest          Ingest all sources at /n/wikia/raw\n" +
	"             ingest <path>   Ingest a specific file\n" +
	"             lint            Run wiki health check\n" +
	"             reset           Close LLM session\n" +
	"\n" +
	"  query    Read/write. Write a question, read the answer.\n" +
	"           The answer is synthesized from wiki pages via LLM\n" +
	"           with citations back to source pages.\n" +
	"\n" +
	"  status   Read-only. Current state and wiki statistics.\n" +
	"\n" +
	"  log      Read-only. Chronological operation history.\n" +
	"\n" +
	"  doc      Read-only. This documentation.\n" +
	"\n" +
	"  raw/     Bind point for source data. Bind or mount any\n" +
	"           data source here before running ingest:\n" +
	"             bind /n/local/docs /n/wikia/raw\n" +
	"             mount tcp!host!styx /n/wikia/raw\n" +
	"           Sources can be unmounted after ingestion.\n" +
	"\n" +
	"DEPENDENCIES\n" +
	"\n" +
	"  /mnt/wiki   wikifs must be mounted (page storage)\n" +
	"  /n/llm      LLM service must be available\n" +
	"\n" +
	"The wiki is browsable via Charon at the httpd URL\n" +
	"serving wikifs.  wiki9p provides the intelligence;\n" +
	"wikifs provides the storage and web presentation.\n";

# ===================================================================
# Logging
# ===================================================================

appendlog(op, msg: string)
{
	now := daytime->now();
	entry := sys->sprint("[%d] %s: %s\n", now, op, msg);
	logbuf += entry;

	# Truncate if too large
	if(len logbuf > logmax)
		logbuf = logbuf[len logbuf - logmax/2:];

	sys->fprint(stderr, "wiki9p: %s: %s\n", op, msg);
}

# ===================================================================
# ctl command dispatch
# ===================================================================

handlectl(cmd: string): string
{
	cmd = strip(cmd);
	if(cmd == "")
		return "error: empty command";

	(nil, argv) := sys->tokenize(cmd, " \t");
	if(argv == nil)
		return "error: empty command";

	verb := hd argv;
	argv = tl argv;

	case verb {
	"ingest" =>
		path := "";
		if(argv != nil)
			path = hd argv;
		return doingest(path);
	"lint" =>
		return dolint();
	"reset" =>
		llmclose();
		return "ok: session closed";
	* =>
		return "error: unknown command: " + verb +
			"\ncommands: ingest [path], lint, reset";
	}
}

# ===================================================================
# Per-fid state management
# ===================================================================

getfidstate(fid: int): ref FidState
{
	for(l := fidstates; l != nil; l = tl l) {
		if((hd l).fid == fid)
			return hd l;
	}
	fs := ref FidState(fid, nil, "", nil);
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

# ===================================================================
# 9P Navigator
# ===================================================================

navigator(navops: chan of ref Navop)
{
	while((m := <-navops) != nil) {
		pick n := m {
		Stat =>
			n.reply <-= dirgen(int n.path);
		Walk =>
			walkto(n);
		Readdir =>
			doreaddir(n, int n.path);
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
		"query" =>
			n.path = big Qquery;
			n.reply <-= dirgen(int n.path);
		"status" =>
			n.path = big Qstatus;
			n.reply <-= dirgen(int n.path);
		"log" =>
			n.path = big Qlog;
			n.reply <-= dirgen(int n.path);
		"doc" =>
			n.path = big Qdoc;
			n.reply <-= dirgen(int n.path);
		"raw" =>
			n.path = big Qraw;
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
	Qquery =>
		d.name = "query";
		d.mode = 8r666;
	Qstatus =>
		d.name = "status";
		d.mode = 8r444;
	Qlog =>
		d.name = "log";
		d.mode = 8r444;
	Qdoc =>
		d.name = "doc";
		d.mode = 8r444;
	Qraw =>
		d.name = "raw";
		d.mode = Sys->DMDIR | 8r777;
		d.qid.qtype = Sys->QTDIR;
	* =>
		return (nil, Enotfound);
	}

	d.qid.path = big path;
	return (d, nil);
}

doreaddir(n: ref Navop.Readdir, path: int)
{
	case path {
	Qroot =>
		entries := array[] of {Qctl, Qquery, Qstatus, Qlog, Qdoc, Qraw};
		for(i := 0; i < len entries; i++) {
			if(i >= n.offset) {
				(d, err) := dirgen(entries[i]);
				if(d != nil)
					n.reply <-= (d, err);
			}
		}
	Qraw =>
		;  # raw/ is a bind point; contents come from whatever is bound there
	}
	n.reply <-= (nil, nil);
}

# ===================================================================
# Main 9P serve loop
# ===================================================================

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
				fs := getfidstate(m.fid);
				if(fs.ctlresp != nil)
					srv.reply(styxservers->readbytes(m, fs.ctlresp));
				else
					srv.reply(styxservers->readstr(m, ""));
			Qquery =>
				fs := getfidstate(m.fid);
				if(fs.queryresp != nil)
					srv.reply(styxservers->readbytes(m, fs.queryresp));
				else
					srv.reply(styxservers->readstr(m, ""));
			Qstatus =>
				srv.reply(styxservers->readstr(m, readstatus()));
			Qlog =>
				srv.reply(styxservers->readstr(m, logbuf));
			Qdoc =>
				srv.reply(styxservers->readstr(m, DOCTEXT));
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
				cmd := string m.data;
				srv.reply(ref Rmsg.Write(m.tag, len m.data));
				fs := getfidstate(m.fid);
				# Run command asynchronously to avoid blocking serveloop
				spawn asyncctl(fs, cmd);
			Qquery =>
				question := strip(string m.data);
				srv.reply(ref Rmsg.Write(m.tag, len m.data));
				fs := getfidstate(m.fid);
				fs.queryreq = question;
				spawn asyncquery(fs, question);
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

# Async wrappers to keep serveloop responsive

asyncctl(fs: ref FidState, cmd: string)
{
	result := handlectl(cmd);
	fs.ctlresp = array of byte result;
}

asyncquery(fs: ref FidState, question: string)
{
	result := doquery(question);
	fs.queryresp = array of byte result;
}

# ===================================================================
# Utility functions
# ===================================================================

# Read a file fully
rf(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return nil;
	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	return result;
}

# Read a potentially large file
readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	return result;
}

# Write a string to a file
wf(path, data: string): int
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return -1;
	b := array of byte data;
	return sys->write(fd, b, len b);
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

# Find substring index
strindex(s, sub: string): int
{
	if(len sub > len s)
		return -1;
	for(i := 0; i <= len s - len sub; i++) {
		if(s[i:i+len sub] == sub)
			return i;
	}
	return -1;
}
