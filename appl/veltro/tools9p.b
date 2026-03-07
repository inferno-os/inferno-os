implement Tools9p;

#
# tools9p - Tool Filesystem Server for Veltro Agent
#
# Registry-based 9P file server. Unlike OODA's tools9p which filters from
# a full list, Veltro's tools9p takes an explicit tool list and ONLY serves
# those tools. If a tool isn't in the registry, it doesn't exist.
#
# This is the "build up" model:
#   - Start with nothing
#   - Only serve what was explicitly requested
#   - No concept of "unavailable" tools
#
# Usage:
#   tools9p read list             # Serve only read and list tools
#   tools9p -D read list find     # With debug tracing
#   tools9p -m /mytool read       # Custom mount point
#
# Filesystem structure:
#   /tool/
#   ├── tools        (r)  List available tool names
#   ├── help         (rw) Write name, read documentation
#   └── <tool>       (rw) Write args, read result (only registered tools)
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

include "tool.m";

include "nsconstruct.m";

Tools9p: module {
	init: fn(nil: ref Draw->Context, nil: list of string);
};

# Qid types for synthetic files
Qroot, Qtools, Qhelp, Qregistry, Qctl, Qpaths: con iota;
Qtoolbase: con 100;  # Tool files start at 100

# Tool info structure
ToolInfo: adt {
	name:    string;         # Tool name (lowercase)
	path:    string;         # Path to .dis module
	mod:     Tool;           # Loaded module (nil if not yet loaded)
	qid:     int;            # Qid for this tool
	result:  array of byte;  # Last execution result
};

stderr: ref Sys->FD;
user: string;
tools: list of ref ToolInfo;     # active (exposed) tools; mutated by serveloop, read by asyncexec (snapshot-safe)
alltools: list of ref ToolInfo;  # pre-loaded inactive tools (available for ctl-add)
extpaths: list of string;  # Extra paths from -p flags (e.g. "/dis/wm")
boundpaths: list of string;  # Paths registered via bindpath ctl command
vers: int;

# Shadow directories for per-invocation namespace restriction
# Must match SHADOW_BASE in nsconstruct.b
SHADOW_BASE: con "/tmp/veltro/.ns/shadow";

# Buffered channel for async shadow dir cleanup; asyncexec sends PID when done
cleanupchan: chan of int;
helpresult: array of byte;  # Last help query result (global, not per-fid)

# Mapping from tool name to .dis path
# Veltro tools are in /dis/veltro/tools/
TOOL_PATHS := array[] of {
	# Core file operations
	("read",    "/dis/veltro/tools/read.dis"),
	("list",    "/dis/veltro/tools/list.dis"),
	("find",    "/dis/veltro/tools/find.dis"),
	("search",  "/dis/veltro/tools/search.dis"),
	("write",   "/dis/veltro/tools/write.dis"),
	("edit",    "/dis/veltro/tools/edit.dis"),
	# Execution
	("exec",    "/dis/veltro/tools/exec.dis"),
	("launch",  "/dis/veltro/tools/launch.dis"),
	("spawn",   "/dis/veltro/tools/spawn.dis"),
	# UI
	("xenith",  "/dis/veltro/tools/xenith.dis"),
	("present", "/dis/veltro/tools/present.dis"),
	("gap",     "/dis/veltro/tools/gap.dis"),
	# New tools (Phase 1c)
	("diff",    "/dis/veltro/tools/diff.dis"),
	("json",    "/dis/veltro/tools/json.dis"),
	("ask",     "/dis/veltro/tools/ask.dis"),
	("http",    "/dis/veltro/tools/http.dis"),
	("git",     "/dis/veltro/tools/git.dis"),
	("grep",    "/dis/veltro/tools/grep.dis"),
	("memory",  "/dis/veltro/tools/memory.dis"),
	("todo",    "/dis/veltro/tools/todo.dis"),
	# Network tools
	("websearch", "/dis/veltro/tools/websearch.dis"),
	("mail",      "/dis/veltro/tools/mail.dis"),
	# Web browsing
	("browse",    "/dis/veltro/tools/browse.dis"),
	("charon",    "/dis/veltro/tools/charon.dis"),
	# GPU inference (requires gpusrv mounted at /mnt/gpu)
	("gpu",     "/dis/veltro/tools/gpu.dis"),
	# Speech tools (require /n/speech via speech9p)
	("say",     "/dis/veltro/tools/say.dis"),
	("hear",    "/dis/veltro/tools/hear.dis"),
	# Vision (local GPU or Anthropic cloud API)
	("vision",  "/dis/veltro/tools/vision.dis"),
	("luciedit", "/dis/veltro/tools/luciedit.dis"),
	("lucishell", "/dis/veltro/tools/lucishell.dis"),
	# Fractal viewer control (requires mand running)
	("fractal", "/dis/veltro/tools/fractal.dis"),
};

usage()
{
	sys->fprint(stderr, "Usage: tools9p [-D] [-m mountpoint] [-p path] ... tool [tool ...]\n");
	sys->fprint(stderr, "  -D            Enable 9P debug tracing\n");
	sys->fprint(stderr, "  -m mountpoint Mount point (default: /tool)\n");
	sys->fprint(stderr, "  -p path       Expose extra path to agent namespace (repeatable)\n");
	sys->fprint(stderr, "                e.g. -p /dis/wm exposes /dis/wm/ for GUI app discovery\n");
	sys->fprint(stderr, "\n");
	sys->fprint(stderr, "Available tools:\n");
	sys->fprint(stderr, "  Core:    read, list, find, search, grep, write, edit\n");
	sys->fprint(stderr, "  Execute: exec, launch, spawn\n");
	sys->fprint(stderr, "  UI:      xenith, ask, present, gap\n");
	sys->fprint(stderr, "  Utils:   diff, json, http, git, memory, todo, websearch, mail\n");
	sys->fprint(stderr, "  Vision:  vision, gpu\n");
	raise "fail:usage";
}

nomod(s: string)
{
	sys->fprint(stderr, "tools9p: can't load %s: %r\n", s);
	raise "fail:load";
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

	mountpt := "/tool";

	while((o := arg->opt()) != 0)
		case o {
		'D' =>	styxservers->traceset(1);
		'm' =>	mountpt = arg->earg();
		'p' =>	extpaths = arg->earg() :: extpaths;
		* =>	usage();
		}
	args = arg->argv();
	arg = nil;

	# Remaining args are tool names to register
	if(args == nil)
		usage();  # Need at least one tool

	# Build tool registry from args
	inittools(args);

	if(tools == nil) {
		sys->fprint(stderr, "tools9p: no valid tools specified\n");
		raise "fail:no tools";
	}

	# Clean shadow dirs left by previous session (crash or kill).
	# Current-session dirs are cleaned per-invocation via shadowcleanloop.
	cleanupchan = chan[32] of int;
	cleanshadows();
	spawn shadowcleanloop();

	sys->pctl(Sys->FORKFD, nil);

	user = rf("/dev/user");
	if(user == nil)
		user = "inferno";

	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0) {
		sys->fprint(stderr, "tools9p: can't create pipe: %r\n");
		raise "fail:pipe";
	}

	navops := chan of ref Navop;
	spawn navigator(navops);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big Qroot);
	fds[0] = nil;

	pidc := chan of int;
	mounted := chan[1] of int;
	spawn serveloop(tchan, srv, pidc, navops, mounted);
	<-pidc;

	# Ensure mount point exists
	ensuredir(mountpt);

	if(sys->mount(fds[1], nil, mountpt, Sys->MREPL|Sys->MCREATE, nil) < 0) {
		sys->fprint(stderr, "tools9p: mount failed: %r\n");
		raise "fail:mount";
	}

	# Signal serveloop that mount is complete — safe to FORKNS now
	mounted <-= 1;
}

# Look up tool path by name
toolpath(name: string): string
{
	lname := str->tolower(name);
	for(i := 0; i < len TOOL_PATHS; i++) {
		(n, p) := TOOL_PATHS[i];
		if(n == lname)
			return p;
	}
	return nil;
}

# Initialize tool registry from argument list
inittools(args: list of string)
{
	tools = nil;
	vers = 0;
	qid := Qtoolbase;

	for(; args != nil; args = tl args) {
		name := str->tolower(hd args);
		path := toolpath(name);
		if(path == nil) {
			sys->fprint(stderr, "tools9p: unknown tool '%s', skipping\n", name);
			continue;
		}

		# Check for duplicates
		if(findtool(name) != nil)
			continue;

		ti := ref ToolInfo(name, path, nil, qid, nil);
		tools = ti :: tools;
		qid++;
	}

	# Reverse to maintain argument order
	rev: list of ref ToolInfo;
	for(t := tools; t != nil; t = tl t)
		rev = hd t :: rev;
	tools = rev;

	# Pre-load all tool modules now, before namespace restriction.
	# Tools like exec need to load sh.dis which won't be visible
	# after restrictns() restricts /dis. Loading eagerly here ensures
	# all tool dependencies are resolved while /dis is unrestricted.
	for(t = tools; t != nil; t = tl t) {
		ti := hd t;
		err := loadtool(ti);
		if(err != nil)
			sys->fprint(stderr, "tools9p: warning: %s\n", err);
	}

	# Pre-load ALL remaining known tools into alltools (inactive pool).
	# This must happen before namespace restriction so /dis is accessible.
	# Later ctl-add can activate these without needing to load new modules.
	alltools = nil;
	for(i := 0; i < len TOOL_PATHS; i++) {
		(pnm, ppath) := TOOL_PATHS[i];
		if(findtool(pnm) != nil)  # already in active set
			continue;
		ati := ref ToolInfo(pnm, ppath, nil, 0, nil);
		loadtool(ati);  # ignore error (hardware tools may not load)
		alltools = ati :: alltools;
	}
}

# Find tool by name
findtool(name: string): ref ToolInfo
{
	lname := str->tolower(name);
	for(t := tools; t != nil; t = tl t) {
		ti := hd t;
		if(ti.name == lname)
			return ti;
	}
	return nil;
}

# Find tool by qid
findtoolbyqid(qid: int): ref ToolInfo
{
	for(t := tools; t != nil; t = tl t) {
		ti := hd t;
		if(ti.qid == qid)
			return ti;
	}
	return nil;
}

# Find tool in inactive pool (alltools)
findalltool(name: string): ref ToolInfo
{
	lname := str->tolower(name);
	for(t := alltools; t != nil; t = tl t) {
		ti := hd t;
		if(ti.name == lname)
			return ti;
	}
	return nil;
}

# Move a tool from alltools to the active set; return nil on success or error string
ctladd(name: string): string
{
	lname := str->tolower(name);
	if(findtool(lname) != nil)
		return nil;  # already active
	ti := findalltool(lname);
	if(ti == nil)
		return "unknown tool: " + name;
	if(ti.mod == nil)
		return "tool module not loaded: " + name;
	# Assign new qid (max current + 1, monotonically increasing)
	maxqid := Qtoolbase - 1;
	for(qt := tools; qt != nil; qt = tl qt)
		if((hd qt).qid > maxqid)
			maxqid = (hd qt).qid;
	ti.qid = maxqid + 1;
	# Remove from alltools
	newlist: list of ref ToolInfo;
	for(at := alltools; at != nil; at = tl at)
		if((hd at).name != ti.name)
			newlist = hd at :: newlist;
	alltools = newlist;
	tools = ti :: tools;
	vers++;
	return nil;
}

# Move a tool from the active set back to alltools (deactivate)
ctlremove(name: string)
{
	lname := str->tolower(name);
	newlist: list of ref ToolInfo;
	for(t := tools; t != nil; t = tl t) {
		ti := hd t;
		if(ti.name == lname) {
			ti.qid = 0;
			alltools = ti :: alltools;
		} else
			newlist = hd t :: newlist;
	}
	tools = newlist;
	vers++;
}

# Load tool module if not already loaded
# Note: tool exec is now async (spawned), but in practice each tool is
# only invoked by one agent at a time, so no lock is needed.
loadtool(ti: ref ToolInfo): string
{
	if(ti.mod != nil)
		return nil;

	ti.mod = load Tool ti.path;
	if(ti.mod == nil)
		return sys->sprint("cannot load tool %s: %r", ti.name);

	# Initialize the tool module
	err := ti.mod->init();
	if(err != nil)
		return sys->sprint("cannot init tool %s: %s", ti.name, err);

	return nil;
}

strlist_contains(l: list of string, s: string): int
{
	for(; l != nil; l = tl l)
		if(hd l == s)
			return 1;
	return 0;
}

# Generate list of bound paths (newline-separated for /tool/paths)
genpathlist(): string
{
	result := "";
	for(p := boundpaths; p != nil; p = tl p) {
		if(result != "")
			result += "\n";
		result += hd p;
	}
	return result;
}

# Generate list of tool names (newline-separated for /tool/tools)
gentoollist(): string
{
	result := "";
	for(t := tools; t != nil; t = tl t) {
		ti := hd t;
		if(result != "")
			result += "\n";
		result += ti.name;
	}
	return result;
}

# Generate registry list (space-separated for /_registry)
# Used by spawn.b to validate tools without causing deadlock
genregistrylist(): string
{
	result := "";
	for(t := tools; t != nil; t = tl t) {
		ti := hd t;
		if(result != "")
			result += " ";
		result += ti.name;
	}
	return result;
}

# Get documentation for a tool
# First tries /lib/veltro/tools/<name>.txt, then falls back to module doc()
gettooldoc(name: string): string
{
	ti := findtool(name);
	if(ti == nil)
		return "error: unknown tool: " + name;

	# Try file-based documentation first
	docpath := "/lib/veltro/tools/" + ti.name + ".txt";
	doc := readfile(docpath);
	if(doc != nil && len doc > 0)
		return doc;

	# Fallback to module doc()
	err := loadtool(ti);
	if(err != nil)
		return "error: " + err;

	return ti.mod->doc();
}

# Read entire file contents (for documentation files)
readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;

	content := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		content += string buf[0:n];
	}
	if(content == "")
		return nil;
	return content;
}

# Execute a tool with arguments
exectool(name, args: string): string
{
	ti := findtool(name);
	if(ti == nil)
		return "error: unknown tool: " + name;

	err := loadtool(ti);
	if(err != nil)
		return "error: " + err;

	return ti.mod->exec(args);
}

# Async wrapper: runs tool execution in a spawned thread so the
# serveloop continues processing 9P messages while the tool runs.
# The Styx reply is sent from this thread when execution completes.
# Namespace restriction is applied HERE (not in serveloop) so each
# invocation uses the current boundpaths at call time — essential for
# paths bound via the GUI after the server was already running.
asyncexec(srv: ref Styxserver, tag: int, count: int, ti: ref ToolInfo, data: string)
{
	mypid := sys->pctl(0, nil);
	applynsrestriction();
	result := exectool(ti.name, data);
	ti.result = array of byte result;
	srv.reply(ref Rmsg.Write(tag, count));
	# Signal cleanup goroutine to remove this invocation's shadow dirs.
	# Non-blocking: if buffer is full, drop (dirs cleaned at next startup).
	alt {
		cleanupchan <-= mypid => ;
		* => ;
	}
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

# Remove one shadow dir and its one-level-deep placeholder entries.
# From the parent namespace (no FORKNS), the shadow dir's children are empty
# placeholder dirs/files — the bind mounts over them exist only in child
# goroutine namespaces and are invisible here.
removeshadowdir(dir: string)
{
	fd := sys->open(dir, Sys->OREAD);
	if(fd != nil) {
		for(;;) {
			(n, entries) := sys->dirread(fd);
			if(n <= 0)
				break;
			for(i := 0; i < n; i++)
				sys->remove(dir + "/" + entries[i].name);
		}
		fd = nil;
	}
	sys->remove(dir);
}

# Remove all shadow dirs created by a specific PID.
# Named SHADOW_BASE/PID-SEQ; we match by "PID-" prefix.
removepidshadows(pid: int)
{
	fd := sys->open(SHADOW_BASE, Sys->OREAD);
	if(fd == nil)
		return;
	prefix := sys->sprint("%d-", pid);
	plen := len prefix;
	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			name := dirs[i].name;
			if(len name >= plen && name[0:plen] == prefix)
				removeshadowdir(SHADOW_BASE + "/" + name);
		}
	}
	fd = nil;
}

# Remove ALL shadow dirs — used at startup to clear previous session's dirs.
cleanshadows()
{
	fd := sys->open(SHADOW_BASE, Sys->OREAD);
	if(fd == nil)
		return;
	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			name := dirs[i].name;
			if(name != "." && name != "..")
				removeshadowdir(SHADOW_BASE + "/" + name);
		}
	}
	fd = nil;
}

# Goroutine: drains cleanupchan and removes shadow dirs for each completed
# asyncexec invocation.  Runs in the unrestricted parent namespace so it can
# reach SHADOW_BASE regardless of what child goroutines have restricted.
shadowcleanloop()
{
	for(;;) {
		pid := <-cleanupchan;
		if(pid < 0)
			break;
		removepidshadows(pid);
	}
}

# Ensure a directory exists
ensuredir(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil)
		return;

	# Try to create parent first
	for(i := len path - 1; i > 0; i--) {
		if(path[i] == '/') {
			ensuredir(path[0:i]);
			break;
		}
	}

	# Create this directory
	fd = sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
	if(fd == nil)
		sys->fprint(stderr, "tools9p: cannot create directory %s: %r\n", path);
}

# Apply namespace restriction in serveloop thread.
# Called after mount() completes so FORKNS captures /tool.
applynsrestriction()
{
	nsconstruct := load NsConstruct NsConstruct->PATH;
	if(nsconstruct == nil)
		return;
	nsconstruct->init();
	sys->pctl(Sys->FORKNS, nil);
	# Grant /chan access only if the xenith tool was registered.
	# Without this, the restricted namespace hides /chan entirely,
	# so even the xenith tool can't read other windows.
	hasxenith := 0;
	if(findtool("xenith") != nil)
		hasxenith = 1;
	# Build registered tool name list for namespace restriction.
	# Passing caps.tools lets restrictns() apply the security model:
	#   - sh.dis bound to /dis when exec is in the list (step 1)
	#   - /dis/veltro/tools restricted to registered .dis files (step 2)
	# sh.dis appears ONLY if exec was explicitly passed by the caller.
	toolnames: list of string = nil;
	for(t := tools; t != nil; t = tl t)
		toolnames = (hd t).name :: toolnames;
	# Merge extpaths (from -p flags) and boundpaths (from runtime bindpath ctl).
	# Called per-invocation from asyncexec(), so boundpaths always reflects
	# the current state — paths bound via the GUI after startup are captured.
	allpaths := extpaths;
	for(bp := boundpaths; bp != nil; bp = tl bp)
		if(!strlist_contains(allpaths, hd bp))
			allpaths = (hd bp) :: allpaths;
	# Auto-grant /n/speech when say or hear tool is registered.
	# speech9p mounts /n/speech in the shared namespace; without this,
	# restrictns() hides it entirely and say/hear tools fail silently.
	if(findtool("say") != nil || findtool("hear") != nil)
		if(!strlist_contains(allpaths, "/n/speech"))
			allpaths = "/n/speech" :: allpaths;
	caps := ref NsConstruct->Capabilities(
		toolnames, allpaths, nil, nil, nil, nil, 0, hasxenith, -1
	);
	{
		nserr := nsconstruct->restrictns(caps);
		if(nserr != nil)
			sys->fprint(stderr, "tools9p: restrictns failed: %s\n", nserr);
	} exception e {
	"*" =>
		sys->fprint(stderr, "tools9p: restrictns exception: %s\n", e);
	}
}

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver, pidc: chan of int, navops: chan of ref Navop, mounted: chan of int)
{
	pidc <-= sys->pctl(Sys->NEWFD, 1::2::srv.fd.fd::nil);

	restricted := 0;

Serve:
	while((gm := <-tchan) != nil) {
		# Wait for mount completion before allowing tool invocations.
		# Restriction is applied per-invocation in asyncexec() so that
		# paths bound after startup are always captured at call time.
		if(!restricted) {
			alt {
			<-mounted =>
				restricted = 1;
			* =>
				;  # Mount not ready yet, continue serving
			}
		}

		pick m := gm {
		Readerror =>
			sys->fprint(stderr, "tools9p: fatal read error: %s\n", m.error);
			break Serve;

		Open =>
			c := srv.getfid(m.fid);
			if(c == nil) {
				srv.open(m);
				break;
			}

			mode := styxservers->openmode(m.mode);
			if(mode < 0) {
				srv.reply(ref Rmsg.Error(m.tag, Ebadarg));
				break;
			}

			# Clear any previous result data
			c.data = nil;

			qid := Qid(c.path, 0, c.qtype);
			c.open(mode, qid);
			srv.reply(ref Rmsg.Open(m.tag, qid, srv.iounit()));

		Read =>
			(c, err) := srv.canread(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, err));
				break;
			}

			if(c.qtype & Sys->QTDIR) {
				srv.read(m);  # navigator handles directory reads
				break;
			}

			qtype := TYPE(c.path);

			case qtype {
			Qtools =>
				# List all tool names
				data := array of byte gentoollist();
				srv.reply(styxservers->readbytes(m, data));

			Qhelp =>
				# Return last help query result (stored globally so
				# separate write/read fids see the same data)
				if(helpresult == nil)
					helpresult = array of byte ("Write a tool name to get documentation.\nAvailable: " + gentoollist());
				srv.reply(styxservers->readbytes(m, helpresult));

			Qregistry =>
				# Return space-separated list of tool names
				# This is a synchronous read that doesn't go through 9P message queue,
				# avoiding deadlock when spawn.b validates tools
				data := array of byte genregistrylist();
				srv.reply(styxservers->readbytes(m, data));

			Qctl =>
				srv.reply(styxservers->readbytes(m, array of byte ""));

			Qpaths =>
				srv.reply(styxservers->readbytes(m, array of byte genpathlist()));

			* =>
				# Tool files - return buffered result
				if(qtype >= Qtoolbase) {
					ti := findtoolbyqid(qtype);
					if(ti == nil) {
						srv.reply(ref Rmsg.Error(m.tag, Enotfound));
						break;
					}
					if(ti.result == nil)
						ti.result = array of byte "error: no result (write arguments first)";
					srv.reply(styxservers->readbytes(m, ti.result));
				} else {
					srv.reply(ref Rmsg.Error(m.tag, Eperm));
				}
			}

		Write =>
			(c, merr) := srv.canwrite(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, merr));
				break;
			}

			qtype := TYPE(c.path);
			data := string m.data;

			# Strip trailing newline
			if(len data > 0 && data[len data - 1] == '\n')
				data = data[0:len data - 1];

			case qtype {
			Qhelp =>
				# Write tool name, store documentation globally
				# (so a different fid's read sees it)
				doc := gettooldoc(data);
				helpresult = array of byte doc;
				srv.reply(ref Rmsg.Write(m.tag, len m.data));

			Qctl =>
				# Dynamic tool management: "add <name>" or "remove <name>"
				# Namespace path management: "bindpath <path>" or "unbindpath <path>"
				if(len data > 4 && data[0:4] == "add ") {
					cerr := ctladd(data[4:]);
					if(cerr != nil)
						srv.reply(ref Rmsg.Error(m.tag, cerr));
					else
						srv.reply(ref Rmsg.Write(m.tag, len m.data));
				} else if(len data > 7 && data[0:7] == "remove ") {
					ctlremove(data[7:]);
					srv.reply(ref Rmsg.Write(m.tag, len m.data));
				} else if(len data > 9 && data[0:9] == "bindpath ") {
					p := data[9:];
					if(!strlist_contains(boundpaths, p))
						boundpaths = p :: boundpaths;
					srv.reply(ref Rmsg.Write(m.tag, len m.data));
				} else if(len data > 11 && data[0:11] == "unbindpath ") {
					p := data[11:];
					nl: list of string;
					for(bl := boundpaths; bl != nil; bl = tl bl)
						if(hd bl != p)
							nl = hd bl :: nl;
					boundpaths = nl;
					srv.reply(ref Rmsg.Write(m.tag, len m.data));
				} else {
					srv.reply(ref Rmsg.Error(m.tag, "usage: add|remove <tool> or bindpath|unbindpath <path>"));
				}

			* =>
				# Tool files - execute asynchronously to avoid blocking serveloop.
				# Long-running tools (e.g. spawn with multi-step LLM) can take
				# tens of seconds. Running them inline blocks ALL 9P traffic,
				# which starves Xenith's row.qlock and freezes the UI.
				# The Write reply is deferred until exec completes, so the
				# client still sees blocking semantics — but the serveloop
				# remains free to service other fids.
				if(qtype >= Qtoolbase) {
					ti := findtoolbyqid(qtype);
					if(ti == nil) {
						srv.reply(ref Rmsg.Error(m.tag, Enotfound));
						break;
					}
					spawn asyncexec(srv, m.tag, len m.data, ti, data);
				} else {
					srv.reply(ref Rmsg.Error(m.tag, Eperm));
				}
			}

		Clunk =>
			srv.clunk(m);

		Remove =>
			srv.remove(m);

		* =>
			srv.default(gm);
		}
	}
	navops <-= nil;  # shut down navigator
}

dir(qid: Sys->Qid, name: string, length: big, perm: int): ref Sys->Dir
{
	d := ref sys->zerodir;
	d.qid = qid;
	if(qid.qtype & Sys->QTDIR)
		perm |= Sys->DMDIR;
	d.mode = perm;
	d.name = name;
	d.uid = user;
	d.gid = user;
	d.length = length;
	return d;
}

dirgen(p: big): (ref Sys->Dir, string)
{
	qtype := TYPE(p);

	case qtype {
	Qroot =>
		return (dir(Qid(p, vers, Sys->QTDIR), "/", big 0, 8r755), nil);

	Qtools =>
		return (dir(Qid(p, vers, Sys->QTFILE), "tools", big 0, 8r444), nil);

	Qhelp =>
		return (dir(Qid(p, vers, Sys->QTFILE), "help", big 0, 8r644), nil);

	Qregistry =>
		return (dir(Qid(p, vers, Sys->QTFILE), "_registry", big 0, 8r444), nil);

	Qctl =>
		return (dir(Qid(p, vers, Sys->QTFILE), "ctl", big 0, 8r644), nil);

	Qpaths =>
		return (dir(Qid(p, vers, Sys->QTFILE), "paths", big 0, 8r444), nil);
	}

	# Check if it's a tool file
	if(qtype >= Qtoolbase) {
		ti := findtoolbyqid(qtype);
		if(ti != nil)
			return (dir(Qid(p, vers, Sys->QTFILE), ti.name, big 0, 8r644), nil);
	}

	return (nil, Enotfound);
}

navigator(navops: chan of ref Navop)
{
	while((m := <-navops) != nil) {
		pick n := m {
		Stat =>
			n.reply <-= dirgen(n.path);

		Walk =>
			qtype := TYPE(n.path);

			case qtype {
			Qroot =>
				case n.name {
				".." =>
					;  # stay at root
				"tools" =>
					n.path = big Qtools;
				"help" =>
					n.path = big Qhelp;
				"_registry" =>
					n.path = big Qregistry;
				"ctl" =>
					n.path = big Qctl;
				"paths" =>
					n.path = big Qpaths;
				* =>
					# Check if it's a registered tool name
					ti := findtool(n.name);
					if(ti == nil) {
						n.reply <-= (nil, Enotfound);
						continue;
					}
					n.path = big ti.qid;
				}
				n.reply <-= dirgen(n.path);

			* =>
				n.reply <-= (nil, "not a directory");
			}

		Readdir =>
			qtype := TYPE(m.path);

			case qtype {
			Qroot =>
				# Root contains: tools, help, _registry, and all registered tool files
				i := n.offset;
				count := n.count;

				# Entry 0: tools
				if(i == 0 && count > 0) {
					n.reply <-= dirgen(big Qtools);
					count--;
					i++;
				}

				# Entry 1: help
				if(i <= 1 && count > 0) {
					n.reply <-= dirgen(big Qhelp);
					count--;
					i++;
				}

				# Entry 2: _registry
				if(i <= 2 && count > 0) {
					n.reply <-= dirgen(big Qregistry);
					count--;
					i++;
				}

				# Entry 3: ctl
				if(i <= 3 && count > 0) {
					n.reply <-= dirgen(big Qctl);
					count--;
					i++;
				}

				# Entry 4: paths
				if(i <= 4 && count > 0) {
					n.reply <-= dirgen(big Qpaths);
					count--;
					i++;
				}

				# Remaining entries: registered tool files
				idx := 0;
				for(t := tools; t != nil && count > 0; t = tl t) {
					ti := hd t;
					if(i <= 5 + idx) {
						n.reply <-= dirgen(big ti.qid);
						count--;
					}
					idx++;
				}

				n.reply <-= (nil, nil);

			* =>
				n.reply <-= (nil, "not a directory");
			}
		}
	}
}

# Extract type from path
TYPE(path: big): int
{
	return int path & 16rFFFF;
}
