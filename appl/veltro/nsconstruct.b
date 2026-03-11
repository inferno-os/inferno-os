implement NsConstruct;

#
# nsconstruct.b - Namespace construction for Veltro agents (v3)
#
# SECURITY MODEL (v3): FORKNS + bind-replace
# ============================================
# Replace NEWNS + sandbox with FORKNS + bind-replace (MREPL).
# restrictdir() is the core primitive:
#   1. Create shadow directory
#   2. Bind allowed items from target into shadow
#   3. Bind shadow over target (MREPL)
# Result: target only shows allowed items. Everything else is invisible.
#
# This is an allowlist operation. No file copying, no sandbox directories,
# no cleanup needed. Capability attenuation is natural: children fork an
# already-restricted namespace and can only narrow further.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "nsconstruct.m";

include "cowfs.m";

# Shadow directories live under /tmp/veltro/.ns/ so they survive
# the /tmp restriction (which allows only "veltro/")
SHADOW_BASE: con "/tmp/veltro/.ns/shadow";
AUDIT_DIR: con "/tmp/veltro/.ns/audit";

# Directory/file permissions
DIR_MODE: con 8r700 | Sys->DMDIR;  # rwx------ directory
FILE_MODE: con 8r600;              # rw------- file

# Per-process shadow sequence counter.
# Combined with PID + millisec to avoid collisions between concurrent goroutines.
# Limbo has no atomic increment, but the ++ is on an int in a single goroutine
# context — callers that may race should coordinate externally.
shadowseq := 0;

# Thread-safe initialization
inited := 0;

init()
{
	if(inited)
		return;

	sys = load Sys Sys->PATH;
	inited = 1;
}

# Core primitive: restrict a directory to only allowed entries
# Creates a shadow dir with only the allowed items, then replaces target
restrictdir(target: string, allowed: list of string, writable: int): string
{
	if(sys == nil)
		init();

	# Create unique shadow dir using PID + sequence + millisec
	# The millisec component prevents collisions from concurrent goroutines
	pid := sys->pctl(0, nil);
	seq := shadowseq++;
	shadowdir := sys->sprint("%s/%d-%d-%d", SHADOW_BASE, pid, seq, sys->millisec());
	err := mkdirp(shadowdir);
	if(err != nil)
		return err;

	for(a := allowed; a != nil; a = tl a) {
		item := hd a;
		# Avoid double-slash when target is "/"
		srcpath: string;
		if(target == "/")
			srcpath = "/" + item;
		else
			srcpath = target + "/" + item;
		dstpath := shadowdir + "/" + item;

		if(target == "/") {
			# Root restriction: skip stat to avoid deadlock on 9P
			# self-mounts like /tool. All root entries are dirs.
			# Bind failures are non-fatal (item may not exist).
			dfd := sys->create(dstpath, Sys->OREAD, DIR_MODE);
			if(dfd != nil)
				dfd = nil;
			sys->bind(srcpath, dstpath, Sys->MREPL);
		} else {
			# Check if source exists and get type
			(ok, dir) := sys->stat(srcpath);
			if(ok < 0)
				continue;  # Skip items that don't exist in target

			# Create mount point matching source type
			if(dir.mode & Sys->DMDIR) {
				dfd := sys->create(dstpath, Sys->OREAD, DIR_MODE);
				if(dfd != nil)
					dfd = nil;
			} else {
				dfd := sys->create(dstpath, Sys->OWRITE, FILE_MODE);
				if(dfd != nil)
					dfd = nil;
			}

			# Bind original into shadow.
			# When the outer target is writable, inner binds also need MCREATE
			# so that file creation inside subdirectories is permitted.
			# Without MCREATE on the inner bind, the kernel returns
			# "mounted directory forbids creation" for any create inside that subdir.
			innerbindflags := Sys->MREPL;
			if(writable)
				innerbindflags |= Sys->MCREATE;
			if(sys->bind(srcpath, dstpath, innerbindflags) < 0)
				return sys->sprint("cannot bind %s: %r", srcpath);
		}
	}

	# Replace target with shadow — only allowed items visible.
	# MCREATE allows file creation at the mount point (needed for /tmp).
	bindflags := Sys->MREPL;
	if(writable)
		bindflags |= Sys->MCREATE;
	if(sys->bind(shadowdir, target, bindflags) < 0)
		return sys->sprint("cannot replace %s: %r", target);

	return nil;
}

# Apply full namespace restriction policy
restrictns(caps: ref Capabilities): string
{
	if(sys == nil)
		init();

	# Set up infrastructure directories first (before any restrictdir calls).
	# These must exist because: (1) restrictdir creates shadow dirs under
	# SHADOW_BASE, and (2) after bind-replace on /tmp, the MREPL mount
	# lacks MCREATE — new subdirectories cannot be created at the mount point.
	# Pre-creating them here ensures they exist as real subdirectories.
	mkdirp("/tmp/veltro");
	mkdirp("/tmp/veltro/scratch");
	mkdirp("/tmp/veltro/memory");
	mkdirp("/tmp/veltro/cow");
	mkdirp(SHADOW_BASE);
	mkdirp(AUDIT_DIR);

	# 1. Restrict /dis to: lib/, veltro/ (plus shell+cmd if exec tool is loaded,
	#    plus any /dis/ subdirectories granted via caps.paths e.g. "/dis/wm")
	disallow := "lib" :: "veltro" :: nil;
	if(inlist("exec", caps.tools) || caps.shellcmds != nil) {
		# exec tool needs sh.dis (shell interpreter) to run commands
		disallow = "sh.dis" :: disallow;
		for(c := caps.shellcmds; c != nil; c = tl c)
			disallow = (hd c) + ".dis" :: disallow;
	}
	# Expose /dis/ subdirectories listed in caps.paths (e.g. "/dis/wm" → "wm")
	for(dp := filterpaths(caps.paths, "/dis/"); dp != nil; dp = tl dp) {
		(first, nil) := splitfirst(hd dp);
		if(first != "" && !inlist(first, disallow))
			disallow = first :: disallow;
	}
	err := restrictdir("/dis", disallow, 0);
	if(err != nil)
		return sys->sprint("restrict /dis: %s", err);

	# 2. If tools specified, restrict /dis/veltro/tools/ to granted tools only
	if(caps.tools != nil) {
		toolallow: list of string;
		for(t := caps.tools; t != nil; t = tl t)
			toolallow = (hd t) + ".dis" :: toolallow;
		err = restrictdir("/dis/veltro/tools", toolallow, 0);
		if(err != nil)
			return sys->sprint("restrict /dis/veltro/tools: %s", err);
	}

	# 3. Restrict /dev to: cons, null, time
	# time is read-only clock; required by daytime->now() for TLS cert validation.
	err = restrictdir("/dev", "cons" :: "null" :: "time" :: nil, 0);
	if(err != nil)
		return sys->sprint("restrict /dev: %s", err);

	# 4-5. Restrict /n to explicitly granted entries only.
	# All /n/ entries are capability-driven — never auto-exposed by existence:
	#   /n/llm    — always granted (core agent service; withheld = non-functional)
	#   /n/mcp    — caps.mcproviders != nil
	#   /n/speech — "/n/speech" in caps.paths
	#   /n/git    — "/n/git" in caps.paths
	#   /n/ui     — "present" in caps.tools
	#   /n/pres-* — caps.xenith != 0
	#   /n/local  — /n/local/ subpaths in caps.paths
	(nok, nil) := sys->stat("/n");
	if(nok >= 0) {
		nallow: list of string;
		uiok := -1;

		# /n/llm — always granted (core LLM access)
		(llmok, nil) := sys->stat("/n/llm");
		if(llmok >= 0)
			nallow = "llm" :: nallow;

		# /n/mcp — only if mc9p providers configured
		if(caps.mcproviders != nil) {
			(mcpok, nil) := sys->stat("/n/mcp");
			if(mcpok >= 0)
				nallow = "mcp" :: nallow;
		}

		# /n/speech — only if explicitly granted via caps.paths
		if(inlist("/n/speech", caps.paths)) {
			(speechok, nil) := sys->stat("/n/speech");
			if(speechok >= 0)
				nallow = "speech" :: nallow;
		}

		# /n/git — only if explicitly granted via caps.paths
		if(inlist("/n/git", caps.paths)) {
			(gitok, nil) := sys->stat("/n/git");
			if(gitok >= 0)
				nallow = "git" :: nallow;
		}

		# /n/ui — only if "present" tool is granted
		# (present and gap tools write to /n/ui/activity/{id}/...)
		if(inlist("present", caps.tools)) {
			(s, nil) := sys->stat("/n/ui");
			if(s >= 0) {
				nallow = "ui" :: nallow;
				uiok = s;
			}
		}

		# /n/pres-* — only if Xenith (GUI) access is granted
		if(caps.xenith) {
			(presok, nil) := sys->stat("/n/pres-clone");
			if(presok >= 0) {
				nallow = "pres-launch" :: nallow;
				nallow = "pres-keyboard" :: nallow;
				nallow = "pres-pointer" :: nallow;
				nallow = "pres-winname" :: nallow;
				nallow = "pres-clone" :: nallow;
			}
		}

		# /n/local — only if /n/local/ subpaths granted via caps.paths
		localpaths := filterpaths(caps.paths, "/n/local/");
		if(localpaths != nil)
			nallow = "local" :: nallow;

		err = restrictdir("/n", nallow, 0);
		if(err != nil)
			return sys->sprint("restrict /n: %s", err);

		# Restrict /n/ui to only /n/ui/activity/ — prevents ctl/catalog access
		if(uiok >= 0) {
			uerr := restrictdir("/n/ui", "activity" :: nil, 0);
			if(uerr != nil)
				return sys->sprint("restrict /n/ui: %s", uerr);
		}

		# Drill down /n/local to only the granted paths
		if(localpaths != nil) {
			lerr := restrictlocal(localpaths, caps.actid);
			if(lerr != nil)
				return sys->sprint("restrict /n/local: %s", lerr);
		}
	}

	# 6. Restrict /lib to: veltro/, certs/
	# certs/ is the TLS root CA store; required by x509->verify_certchain().
	(libok, nil) := sys->stat("/lib");
	if(libok >= 0) {
		err = restrictdir("/lib", "veltro" :: "certs" :: nil, 0);
		if(err != nil)
			return sys->sprint("restrict /lib: %s", err);
	}

	# 7. Restrict /tmp to: veltro/ (shadow dirs are under here).
	# writable=1 so agents can create files under /tmp/veltro/.
	# MCREATE is applied only to /tmp — not to /dis, /lib, /dev, /n, /.
	err = restrictdir("/tmp", "veltro" :: nil, 1);
	if(err != nil)
		return sys->sprint("restrict /tmp: %s", err);

	# 8. Restrict / to only Inferno system directories.
	# The emu's -r. binds #U (project root) onto / with MAFTER,
	# exposing project files (.env, .git, appl/, emu/, ...).
	# restrictdir("/", safe) replaces the root union with a shadow
	# containing only safe entries. Channels are captured at bind time,
	# so kernel device bindings (#c→/dev, #p→/prog) are preserved
	# through the shadow binds.
	safe := "dev" :: "dis" :: "env" :: "fd" ::
		"lib" :: "n" :: "net" :: "net.alt" :: "nvfs" ::
		"prog" :: "tmp" :: "tool" :: nil;
	# Only include /chan (Xenith 9P filesystem) if explicitly granted.
	# /chan exposes ALL window contents — without this gate, any agent
	# could read every open Xenith window regardless of namespace restriction.
	if(caps.xenith)
		safe = "chan" :: safe;

	# Expose additional Inferno root-level directories from caps.paths.
	# e.g. "/appl/veltro" → add "appl" to safe, then restrict /appl to "veltro".
	# Paths under /dis/, /n/, /dev/, /lib/, /tmp/ are already handled above.
	extradirs: list of string;
	for(ep := caps.paths; ep != nil; ep = tl ep) {
		p := hd ep;
		if(len p < 2 || p[0] != '/')
			continue;
		(first, nil) := splitfirst(p[1:]);
		if(first == "")
			continue;
		# Skip top-level dirs already in safe or handled by steps 1–7
		if(inlist(first, safe))
			continue;
		if(!inlist(first, extradirs))
			extradirs = first :: extradirs;
	}
	for(ed := extradirs; ed != nil; ed = tl ed)
		safe = (hd ed) :: safe;

	{
		err = restrictdir("/", safe, 0);
	} exception e {
	"*" =>
		return sys->sprint("restrictdir / exception: %s", e);
	}
	if(err != nil)
		return sys->sprint("restrict /: %s", err);

	# Restrict each extra root-level dir to only the granted sub-paths.
	# e.g. "/appl/veltro" → restrictpath("/appl", "veltro"::nil)
	# This prevents the agent from browsing sibling dirs (e.g. /appl/cmd).
	for(ed = extradirs; ed != nil; ed = tl ed) {
		topdir := "/" + hd ed;
		subpaths := filterpaths(caps.paths, topdir + "/");
		if(subpaths != nil) {
			ederr := restrictpath(topdir, subpaths);
			if(ederr != nil)
				sys->fprint(sys->fildes(2), "nsconstruct: restrict %s: %s\n", topdir, ederr);
		}
	}

	return nil;
}

# Filter paths that start with a given prefix, stripping the prefix.
# E.g., filterpaths(("/n/local/Users/pdfinn/tmp"::nil), "/n/local/")
# returns ("Users/pdfinn/tmp"::nil)
filterpaths(paths: list of string, prefix: string): list of string
{
	result: list of string;
	plen := len prefix;
	for(; paths != nil; paths = tl paths) {
		p := hd paths;
		if(len p > plen && p[0:plen] == prefix)
			result = p[plen:] :: result;
	}
	return result;
}

# Restrict /n/local to only the granted host paths.
# Each path is relative to /n/local/ (e.g., "Users/pdfinn/tmp").
# Drills down component by component using restrictdir().
# If actid >= 0, overlay each leaf path with cowfs.
restrictlocal(paths: list of string, actid: int): string
{
	err := restrictpath("/n/local", paths);
	if(err != nil)
		return err;

	# If actid >= 0, overlay each leaf path with cowfs
	if(actid < 0)
		return nil;

	cowfs := load Cowfs Cowfs->PATH;
	if(cowfs == nil)
		return sys->sprint("cannot load cowfs: %r");

	seq := 0;
	for(p := paths; p != nil; p = tl p) {
		fullpath := "/n/local/" + hd p;
		overlaydir := sys->sprint("/tmp/veltro/cow/%d-%d", actid, seq);
		seq++;
		merr := mkdirp(overlaydir);
		if(merr != nil)
			return sys->sprint("cowfs overlay %s: %s", overlaydir, merr);

		(mntfd, cerr) := cowfs->start(fullpath, overlaydir);
		if(cerr != nil)
			return sys->sprint("cowfs %s: %s", fullpath, cerr);

		if(sys->mount(mntfd, nil, fullpath, Sys->MREPL, nil) < 0)
			return sys->sprint("cowfs mount %s: %r", fullpath);
	}
	return nil;
}

# Recursively restrict a directory to only the granted subpaths.
# paths are relative to dir (e.g., "pdfinn/tmp" relative to "/n/local/Users").
# At each level, extracts unique first components as the allowlist,
# then recurses for deeper components.
restrictpath(dir: string, paths: list of string): string
{
	# Pass 1: collect unique first components
	allow: list of string;
	for(p := paths; p != nil; p = tl p) {
		(first, nil) := splitfirst(hd p);
		if(!inlist(first, allow))
			allow = first :: allow;
	}

	# Restrict this level (read-only — /n/local paths are read-only by default)
	err := restrictdir(dir, allow, 0);
	if(err != nil)
		return err;

	# Pass 2: for each first component, collect subpaths and recurse
	for(a := allow; a != nil; a = tl a) {
		name := hd a;
		subpaths: list of string;
		for(q := paths; q != nil; q = tl q) {
			(first, rest) := splitfirst(hd q);
			if(first == name && rest != "")
				subpaths = rest :: subpaths;
		}
		if(subpaths != nil) {
			serr := restrictpath(dir + "/" + name, subpaths);
			if(serr != nil)
				return serr;
		}
	}

	return nil;
}

# Check if string is in a list
inlist(s: string, l: list of string): int
{
	for(; l != nil; l = tl l)
		if(hd l == s)
			return 1;
	return 0;
}

# Split a path into first component and rest.
# "Users/pdfinn/tmp" → ("Users", "pdfinn/tmp")
# "tmp" → ("tmp", "")
splitfirst(p: string): (string, string)
{
	for(i := 0; i < len p; i++) {
		if(p[i] == '/')
			return (p[0:i], p[i+1:]);
	}
	return (p, "");
}

# Emit namespace manifest for the UI to display.
# Writes to /tmp/veltro/.ns/manifest — one entry per line:
#   path=/dev/time label=System Clock perm=ro
# Must be called AFTER restrictns() from the restricted namespace
# so stat checks reflect exactly what the agent can access.
emitmanifest(caps: ref Capabilities)
{
	if(sys == nil)
		init();

	mkdirp("/tmp/veltro/.ns");

	fd := sys->create("/tmp/veltro/.ns/manifest", Sys->OWRITE, FILE_MODE);
	if(fd == nil)
		return;

	# Infrastructure paths — always checked
	infra := array[] of {
		# (path, label, default-perm)
		("/dev/time",      "System Clock",     "ro"),
		("/dev/cons",      "Console",          "rw"),
		("/dev/null",      "Null Device",      "rw"),
		("/lib/certs",     "Certificates",     "ro"),
		("/lib/veltro",    "Veltro Config",    "ro"),
		("/dis/veltro",    "Veltro Tools",     "ro"),
		("/tmp/veltro",    "Veltro Workspace", "rw"),
	};

	for(i := 0; i < len infra; i++) {
		(path, label, perm) := infra[i];
		(ok, nil) := sys->stat(path);
		if(ok >= 0)
			sys->fprint(fd, "path=%s label=%s perm=%s\n", path, label, perm);
	}

	# /n entries — capability-driven
	nentries := array[] of {
		("/n/llm",    "LLM Service",      "rw"),
		("/n/mcp",    "MCP Providers",    "rw"),
		("/n/speech", "Speech",           "rw"),
		("/n/git",    "Git",              "rw"),
		("/n/ui",     "UI Service",       "rw"),
	};

	for(i = 0; i < len nentries; i++) {
		(path, label, perm) := nentries[i];
		(ok, nil) := sys->stat(path);
		if(ok >= 0)
			sys->fprint(fd, "path=%s label=%s perm=%s\n", path, label, perm);
	}

	# /n/local subpaths from caps.paths
	localpaths := filterpaths(caps.paths, "/n/local/");
	for(lp := localpaths; lp != nil; lp = tl lp) {
		fullpath := "/n/local/" + hd lp;
		(ok, nil) := sys->stat(fullpath);
		perm := "ro";
		if(caps.actid >= 0)
			perm = "cow";  # copy-on-write overlay
		if(ok >= 0)
			sys->fprint(fd, "path=%s label=%s perm=%s\n", fullpath, hd lp, perm);
	}

	# Xenith-related entries
	if(caps.xenith) {
		xpaths := array[] of {
			("/chan",          "Xenith Windows",  "rw"),
		};
		for(i = 0; i < len xpaths; i++) {
			(path, label, perm) := xpaths[i];
			(ok, nil) := sys->stat(path);
			if(ok >= 0)
				sys->fprint(fd, "path=%s label=%s perm=%s\n", path, label, perm);
		}
	}

	# Extra root-level dirs from caps.paths (e.g. /appl/veltro)
	for(ep := caps.paths; ep != nil; ep = tl ep) {
		p := hd ep;
		if(len p < 2 || p[0] != '/')
			continue;
		# Skip paths handled above
		(first, nil) := splitfirst(p[1:]);
		if(first == "dis" || first == "dev" || first == "lib" ||
		   first == "tmp" || first == "n")
			continue;
		(ok, nil) := sys->stat(p);
		if(ok >= 0)
			sys->fprint(fd, "path=%s label=%s perm=ro\n", p, p[1:]);
	}

	fd = nil;
}

# Verify namespace matches expected security policy
# Checks both positive (expected paths accessible) and negative
# (dangerous paths inaccessible) assertions.
verifyns(expected: list of string): string
{
	if(sys == nil)
		init();

	# Note: We do NOT grep /prog/$pid/ns (the mount table) for path
	# strings like "/n/local" or "#U". After bind-replace, the mount
	# table retains historical entries masked by later MREPL binds.
	# For example, "bind '#U*' /n/local" persists even though
	# restrictdir("/n", ...) hides /n/local. The stat() checks below
	# are the only reliable accessibility test after bind-replace.

	# Negative assertions: verify dangerous paths are NOT accessible
	dangerous := array[] of {
		"/n/local",
		"/.env",
		"/.git",
		"/CLAUDE.md",
	};
	for(i := 0; i < len dangerous; i++) {
		(dok, nil) := sys->stat(dangerous[i]);
		if(dok >= 0)
			return sys->sprint("violation: %s still accessible", dangerous[i]);
	}

	# Positive assertions: verify expected paths are accessible
	for(e := expected; e != nil; e = tl e) {
		path := hd e;
		(ok, nil) := sys->stat(path);
		if(ok < 0)
			return sys->sprint("expected path missing: %s", path);
	}

	return nil;
}

# Emit audit log of namespace restriction operations
emitauditlog(id: string, ops: list of string)
{
	if(sys == nil)
		init();

	mkdirp(AUDIT_DIR);

	auditpath := AUDIT_DIR + "/" + id + ".ns";
	fd := sys->create(auditpath, Sys->OWRITE, FILE_MODE);
	if(fd == nil)
		return;

	sys->fprint(fd, "# Veltro Namespace Audit (v3)\n# ID: %s\n\n", id);

	# Write operations in reverse order (oldest first)
	revops: list of string;
	for(; ops != nil; ops = tl ops)
		revops = hd ops :: revops;
	for(; revops != nil; revops = tl revops)
		sys->fprint(fd, "%s\n", hd revops);

	# Dump current namespace state
	pid := sys->pctl(0, nil);
	nscontent := readfile(sys->sprint("/prog/%d/ns", pid));
	if(nscontent != "")
		sys->fprint(fd, "\n# Current namespace:\n%s", nscontent);

	fd = nil;
}

# Helper: create directory with parents
mkdirp(path: string): string
{
	if(sys == nil)
		init();

	# Check if already exists
	(ok, nil) := sys->stat(path);
	if(ok >= 0)
		return nil;

	# Create parent directories first
	err := mkparent(path);
	if(err != nil)
		return err;

	fd := sys->create(path, Sys->OREAD, DIR_MODE);
	if(fd == nil)
		return sys->sprint("cannot create %s: %r", path);
	fd = nil;
	return nil;
}

# Helper: create parent directory
mkparent(path: string): string
{
	parent := "";
	for(i := len path - 1; i > 0; i--) {
		if(path[i] == '/') {
			parent = path[0:i];
			break;
		}
	}

	if(parent == "" || parent == "/")
		return nil;

	return mkdirp(parent);
}

# Helper: read file contents
readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return "";

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

# Clean up shadow directories for the current process
cleanup()
{
	if(sys == nil)
		init();

	pid := sys->pctl(0, nil);
	prefix := sys->sprint("%d-", pid);

	fd := sys->open(SHADOW_BASE, Sys->OREAD);
	if(fd == nil)
		return;

	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			name := dirs[i].name;
			if(len name >= len prefix && name[0:len prefix] == prefix) {
				# Remove shadow directory contents then directory itself
				rmdir(SHADOW_BASE + "/" + name);
			}
		}
	}
}

# Helper: recursively remove a directory and its contents
rmdir(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil) {
		for(;;) {
			(n, dirs) := sys->dirread(fd);
			if(n <= 0)
				break;
			for(i := 0; i < n; i++) {
				child := path + "/" + dirs[i].name;
				if(dirs[i].mode & Sys->DMDIR)
					rmdir(child);
				else
					sys->remove(child);
			}
		}
		fd = nil;
	}
	sys->remove(path);
}

# Helper: check if string contains substring
contains(s, sub: string): int
{
	if(len sub > len s)
		return 0;
	for(i := 0; i <= len s - len sub; i++) {
		if(s[i:i+len sub] == sub)
			return 1;
	}
	return 0;
}
