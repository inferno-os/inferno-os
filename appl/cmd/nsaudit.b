implement Nsaudit;

#
# nsaudit - namespace syntactic analysis
#
# Advisory linter for agent capability configurations.  Reads a caps
# directory (same shape as a live /tool mount), loads the per-tool
# authority manifest and the rule set, computes the authority inventory,
# applies rules, and prints a report.
#
# This tool enforces nothing.  The namespace is still what restricts the
# agent at runtime -- nsconstruct->restrictns(), FORKNS, NODEVS, cowfs,
# wallet9p per-transaction gating.  nsaudit is a pre-flight review:
# given this config, what will the resulting capabilities let the agent
# do, and is that what you wanted?
#
# Modes:
#   nsaudit DIR                  full report for the caps at DIR
#   nsaudit DIR PATH             is PATH reachable under caps at DIR
#   nsaudit -d DIRA DIRB         diff authorities between two caps dirs
#   nsaudit -m DIR [PATH]        machine-readable ndb output
#   nsaudit -m -d DIRA DIRB      machine-readable diff
#
# Input format: DIR is a directory of scalar files (one value per file
# or one value per line), mirroring what tools9p exposes at /tool:
#   DIR/tools                    one tool name per line
#   DIR/paths                    one path grant per line
#   DIR/meta/role                "toplevel" or "child"
#   DIR/meta/xenith              "1" or "0"
#   DIR/meta/actid               integer
#   DIR/meta/nodevs              "set" or "unset"
#
# Manifest format: ndb attribute files at
#   /lib/veltro/nsaudit/authorities/<tool>
#   /lib/veltro/nsaudit/rules/<rule>
# Parsed via the Attrdb module.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "attrdb.m";
	attrdb: Attrdb;
	Attr, Tuples, Dbentry, Db: import attrdb;

include "arg.m";

Nsaudit: module
{
	init:	fn(nil: ref Draw->Context, args: list of string);
};

AUTHORITIES_DIR: con "/lib/veltro/nsaudit/authorities";
RULES_DIR:       con "/lib/veltro/nsaudit/rules";

# Always-on filesystem paths granted by nsconstruct->restrictns()
# regardless of caps.  Kept in sync with the policy in nsconstruct.b.
ALWAYS_READS := array[] of {
	"/dis/lib", "/dis/veltro",
	"/dev/cons", "/dev/null", "/dev/time",
	"/lib/certs",
	"/tmp/veltro",
};

# Caps parsed from a caps directory.
Caps: adt {
	dir:       string;
	tools:     list of string;
	paths:     list of string;
	role:      string;    # "toplevel" | "child"
	xenith:    int;
	actid:     int;
	nodevs:    string;    # "set" | "unset"
};

# Per-tool manifest entry loaded from the authorities dir.
ToolInfo: adt {
	name:         string;
	description:  string;
	authorities:  list of string;
	irreversible: list of string;
	notes:        string;
};

# Rule loaded from the rules dir.
Rule: adt {
	name:     string;
	severity: string;  # "high" | "medium" | "info"
	require:  list of string;  # all must match
	andone:   list of string;  # at least one must match (optional)
	message:  string;
	fix:      string;
};

# Authority inventory computed from a Caps + manifest.
Inventory: adt {
	caps:         ref Caps;
	auths:        list of string;        # distinct authority axes present
	reads_fs:     list of string;        # paths
	writes_fs:    list of string;        # paths
	writes_durable: list of string;      # paths not under /tmp/veltro and actid<0
	sources:      list of (string, string); # (authority, source description)
};

# Rule evaluation result.
Finding: adt {
	rule:    ref Rule;
	matched: int;
};

usage()
{
	sys->fprint(sys->fildes(2),
		"usage: nsaudit [-m] DIR\n" +
		"       nsaudit [-m] DIR PATH\n" +
		"       nsaudit [-m] -d DIRA DIRB\n" +
		"see nsaudit(1) for details\n");
	raise "fail:usage";
}

# Machine-readable mode flag, set in init() and read by runReport/runReach/runDiff.
machine := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		fatal(sys->sprint("cannot load %s: %r", Bufio->PATH));
	attrdb = load Attrdb Attrdb->PATH;
	if(attrdb == nil)
		fatal(sys->sprint("cannot load %s: %r", Attrdb->PATH));
	e := attrdb->init();
	if(e != nil)
		fatal("attrdb init: " + e);

	arg := load Arg Arg->PATH;
	if(arg == nil)
		fatal(sys->sprint("cannot load %s: %r", Arg->PATH));
	arg->init(args);
	arg->setusage("nsaudit [-dm] DIR [PATH]");
	diffmode := 0;
	while((o := arg->opt()) != 0)
		case o {
		'd' =>	diffmode = 1;
		'm' =>	machine = 1;
		* =>	usage();
		}
	args = arg->argv();

	if(diffmode) {
		if(len args != 2)
			usage();
		dirA := hd args;
		dirB := hd tl args;
		runDiff(dirA, dirB);
		return;
	}

	if(args == nil)
		usage();
	dir := hd args;
	args = tl args;
	caps := parseCaps(dir);
	tools := loadTools(caps.tools);
	inv := buildInventory(caps, tools);

	if(args != nil) {
		runReach(inv, hd args);
		return;
	}

	runReport(inv, loadRules());
}

#
# Caps parsing: read scalar files from a caps directory.
#

parseCaps(dir: string): ref Caps
{
	(ok, d) := sys->stat(dir);
	if(ok < 0 || (d.mode & Sys->DMDIR) == 0)
		fatal(sys->sprint("not a directory: %s", dir));

	c := ref Caps;
	c.dir = dir;
	c.role = "toplevel";
	c.nodevs = "unset";
	c.actid = -1;
	c.xenith = 0;

	c.tools = readLines(dir + "/tools");
	c.paths = readLines(dir + "/paths");

	role := readScalar(dir + "/meta/role");
	if(role != "")
		c.role = role;
	x := readScalar(dir + "/meta/xenith");
	if(x == "1")
		c.xenith = 1;
	a := readScalar(dir + "/meta/actid");
	if(a != "")
		c.actid = int a;
	n := readScalar(dir + "/meta/nodevs");
	if(n != "")
		c.nodevs = n;

	return c;
}

readLines(path: string): list of string
{
	b := bufio->open(path, Bufio->OREAD);
	if(b == nil)
		return nil;
	out: list of string;
	while((line := b.gets('\n')) != nil) {
		s := trim(line);
		if(s == "" || s[0] == '#')
			continue;
		out = s :: out;
	}
	# Reverse to preserve file order.
	r: list of string;
	for(; out != nil; out = tl out)
		r = hd out :: r;
	return r;
}

readScalar(path: string): string
{
	b := bufio->open(path, Bufio->OREAD);
	if(b == nil)
		return "";
	line := b.gets('\n');
	return trim(line);
}

trim(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n' || s[j-1] == '\r'))
		j--;
	return s[i:j];
}

#
# Manifest loading: one ndb file per tool under AUTHORITIES_DIR.
#

loadTools(names: list of string): list of ref ToolInfo
{
	out: list of ref ToolInfo;
	for(; names != nil; names = tl names) {
		t := loadOneTool(hd names);
		if(t != nil)
			out = t :: out;
	}
	# Reverse to preserve input order.
	r: list of ref ToolInfo;
	for(; out != nil; out = tl out)
		r = hd out :: r;
	return r;
}

loadOneTool(name: string): ref ToolInfo
{
	path := AUTHORITIES_DIR + "/" + name;
	db := Db.open(path);
	if(db == nil) {
		sys->fprint(sys->fildes(2),
			"nsaudit: no manifest entry for tool %q (%s)\n", name, path);
		sys->fprint(sys->fildes(2),
			"\tadd %s/%s or remove the tool from caps.tools\n",
			AUTHORITIES_DIR, name);
		raise "fail:missing-manifest";
	}
	(e, nil) := db.find(nil, "tool");
	if(e == nil) {
		sys->fprint(sys->fildes(2),
			"nsaudit: manifest %s is missing 'tool' attribute\n", path);
		raise "fail:bad-manifest";
	}
	t := ref ToolInfo;
	t.name = e.findfirst("tool");
	t.description = e.findfirst("description");
	t.authorities = splitws(e.findfirst("authorities"));
	t.irreversible = splitws(e.findfirst("irreversible"));
	t.notes = e.findfirst("notes");
	return t;
}

splitws(s: string): list of string
{
	out: list of string;
	i := 0;
	n := len s;
	while(i < n) {
		while(i < n && (s[i] == ' ' || s[i] == '\t'))
			i++;
		if(i >= n)
			break;
		j := i;
		while(j < n && s[j] != ' ' && s[j] != '\t')
			j++;
		out = s[i:j] :: out;
		i = j;
	}
	r: list of string;
	for(; out != nil; out = tl out)
		r = hd out :: r;
	return r;
}

#
# Inventory: union tool authorities, derive path/meta authorities,
# and record source provenance for each axis.
#

buildInventory(caps: ref Caps, tools: list of ref ToolInfo): ref Inventory
{
	inv := ref Inventory;
	inv.caps = caps;

	# Always-on filesystem reads.
	for(i := 0; i < len ALWAYS_READS; i++) {
		inv.reads_fs = ALWAYS_READS[i] :: inv.reads_fs;
		inv.sources = ("reads_fs:" + ALWAYS_READS[i], "always-on") :: inv.sources;
	}

	# Per-tool authorities.
	for(tl1 := tools; tl1 != nil; tl1 = tl tl1) {
		t := hd tl1;
		for(al := t.authorities; al != nil; al = tl al) {
			a := hd al;
			if(!contains(inv.auths, a))
				inv.auths = a :: inv.auths;
			inv.sources = (a, "via tool " + t.name) :: inv.sources;

			# Filesystem axes also contribute path grants.
			if(a == "reads_fs") {
				for(pl := caps.paths; pl != nil; pl = tl pl)
					if(!contains(inv.reads_fs, hd pl))
						inv.reads_fs = hd pl :: inv.reads_fs;
			}
			if(a == "writes_fs") {
				for(pl := caps.paths; pl != nil; pl = tl pl)
					if(!contains(inv.writes_fs, hd pl))
						inv.writes_fs = hd pl :: inv.writes_fs;
			}
		}
	}

	# Always-on /tmp/veltro is writable, reversibly (ephemeral).
	if(!contains(inv.writes_fs, "/tmp/veltro")) {
		inv.writes_fs = "/tmp/veltro" :: inv.writes_fs;
		inv.sources = ("writes_fs:/tmp/veltro", "always-on ephemeral") :: inv.sources;
	}

	# writes_fs_durable = writes_fs entries that are not /tmp/veltro
	# and are not covered by cowfs (actid >= 0 covers /n/local/*).
	for(wl := inv.writes_fs; wl != nil; wl = tl wl) {
		p := hd wl;
		if(prefix(p, "/tmp/veltro"))
			continue;
		if(caps.actid >= 0 && prefix(p, "/n/local"))
			continue;
		inv.writes_durable = p :: inv.writes_durable;
	}
	if(inv.writes_durable != nil && !contains(inv.auths, "writes_fs_durable"))
		inv.auths = "writes_fs_durable" :: inv.auths;

	# Kernel device attach: role=toplevel and nodevs=unset => unrestricted.
	# role=child and nodevs=unset => subagent missing NODEVS (flagged by rule).
	if(caps.nodevs == "unset" && caps.role == "toplevel") {
		if(!contains(inv.auths, "attaches_device"))
			inv.auths = "attaches_device" :: inv.auths;
		inv.sources = ("attaches_device", "role=toplevel, nodevs=unset") :: inv.sources;
	}

	# Xenith grants sends_ui and window access.
	if(caps.xenith) {
		if(!contains(inv.auths, "sends_ui"))
			inv.auths = "sends_ui" :: inv.auths;
		if(!contains(inv.auths, "reads_windows"))
			inv.auths = "reads_windows" :: inv.auths;
		inv.sources = ("sends_ui", "caps.xenith=1") :: inv.sources;
	}

	return inv;
}

contains(l: list of string, s: string): int
{
	for(; l != nil; l = tl l)
		if(hd l == s)
			return 1;
	return 0;
}

prefix(s, p: string): int
{
	if(len s < len p)
		return 0;
	return s[0:len p] == p;
}

#
# Rule loading and evaluation.
#

loadRules(): list of ref Rule
{
	fd := sys->open(RULES_DIR, Sys->OREAD);
	if(fd == nil) {
		sys->fprint(sys->fildes(2), "nsaudit: cannot open %s: %r\n", RULES_DIR);
		return nil;
	}
	out: list of ref Rule;
	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			name := dirs[i].name;
			if(name[0] == '.' || name[0] == '#')
				continue;
			r := loadOneRule(RULES_DIR + "/" + name);
			if(r != nil)
				out = r :: out;
		}
	}
	return out;
}

loadOneRule(path: string): ref Rule
{
	db := Db.open(path);
	if(db == nil)
		return nil;
	(e, nil) := db.find(nil, "rule");
	if(e == nil)
		return nil;
	r := ref Rule;
	r.name = e.findfirst("rule");
	r.severity = e.findfirst("severity");
	r.require = splitws(e.findfirst("require"));
	r.andone = splitws(e.findfirst("andone"));
	r.message = e.findfirst("message");
	r.fix = e.findfirst("fix");
	return r;
}

evaluateRules(inv: ref Inventory, rules: list of ref Rule): list of ref Finding
{
	out: list of ref Finding;
	for(; rules != nil; rules = tl rules) {
		r := hd rules;
		m := evaluateOne(inv, r);
		out = ref Finding(r, m) :: out;
	}
	r: list of ref Finding;
	for(; out != nil; out = tl out)
		r = hd out :: r;
	return r;
}

evaluateOne(inv: ref Inventory, r: ref Rule): int
{
	# "require" is AND-of-all.
	for(rl := r.require; rl != nil; rl = tl rl) {
		if(!conditionTrue(inv, hd rl))
			return 0;
	}
	# "andone" (if non-empty) is OR-of-any.
	if(r.andone != nil) {
		any := 0;
		for(al := r.andone; al != nil; al = tl al) {
			if(conditionTrue(inv, hd al)) {
				any = 1;
				break;
			}
		}
		if(!any)
			return 0;
	}
	return 1;
}

# A condition is one of:
#   role=toplevel, role=child                  caps role match
#   nodevs=set, nodevs=unset                   caps nodevs match
#   has_tool_<name>                            tool present in caps.tools
#   <authority_name>                           authority present in inv.auths
conditionTrue(inv: ref Inventory, cond: string): int
{
	if(prefix(cond, "role=")) {
		want := cond[5:];
		return inv.caps.role == want;
	}
	if(prefix(cond, "nodevs=")) {
		want := cond[7:];
		return inv.caps.nodevs == want;
	}
	if(prefix(cond, "has_tool_")) {
		want := cond[9:];
		return contains(inv.caps.tools, want);
	}
	return contains(inv.auths, cond);
}

#
# Report modes.
#

runReport(inv: ref Inventory, rules: list of ref Rule)
{
	stdout := sys->fildes(1);
	if(machine) {
		runReportMachine(stdout, inv, rules);
		return;
	}
	sys->fprint(stdout, "nsaudit: %s (role=%s, nodevs=%s, actid=%d, xenith=%d)\n\n",
		inv.caps.dir, inv.caps.role, inv.caps.nodevs, inv.caps.actid, inv.caps.xenith);

	sys->fprint(stdout, "authorities\n");
	for(al := inv.auths; al != nil; al = tl al)
		sys->fprint(stdout, "  %s\n", hd al);

	if(inv.reads_fs != nil) {
		sys->fprint(stdout, "\nreads_fs\n");
		for(rl := inv.reads_fs; rl != nil; rl = tl rl)
			sys->fprint(stdout, "  %s\n", hd rl);
	}
	if(inv.writes_fs != nil) {
		sys->fprint(stdout, "\nwrites_fs\n");
		for(wl := inv.writes_fs; wl != nil; wl = tl wl) {
			p := hd wl;
			tag := "";
			if(prefix(p, "/tmp/veltro"))
				tag = " [ephemeral]";
			else if(inv.caps.actid >= 0 && prefix(p, "/n/local"))
				tag = sys->sprint(" [cowfs actid=%d]", inv.caps.actid);
			else
				tag = " [DURABLE]";
			sys->fprint(stdout, "  %s%s\n", p, tag);
		}
	}

	findings := evaluateRules(inv, rules);
	nhigh := 0;
	sys->fprint(stdout, "\nviolations\n");
	any := 0;
	for(fl := findings; fl != nil; fl = tl fl) {
		f := hd fl;
		if(!f.matched)
			continue;
		any = 1;
		if(f.rule.severity == "high")
			nhigh++;
		sys->fprint(stdout, "  [%s] %s\n", f.rule.severity, f.rule.name);
		sys->fprint(stdout, "    %s\n", f.rule.message);
		if(f.rule.fix != "")
			sys->fprint(stdout, "    fix: %s\n", f.rule.fix);
	}
	if(!any)
		sys->fprint(stdout, "  (none)\n");

	if(nhigh > 0)
		raise "fail:high-violations";
}

runReach(inv: ref Inventory, path: string)
{
	stdout := sys->fildes(1);
	reach := matchesAny(inv.reads_fs, path);
	writ := matchesAny(inv.writes_fs, path);

	if(machine) {
		runReachMachine(stdout, inv, path, reach, writ);
		return;
	}
	sys->fprint(stdout, "nsaudit: reach %s\n\n", path);
	if(reach != "") {
		sys->fprint(stdout, "  reads_fs:  yes  via %s\n", reach);
	} else {
		sys->fprint(stdout, "  reads_fs:  no\n");
		closest := closestPrefix(inv.reads_fs, path);
		if(closest != "")
			sys->fprint(stdout, "    closest granted read: %s\n", closest);
		else
			sys->fprint(stdout, "    no granted read prefixes this path\n");
	}
	if(writ != "") {
		tag := "";
		if(prefix(writ, "/tmp/veltro"))
			tag = " (ephemeral)";
		else if(inv.caps.actid >= 0 && prefix(writ, "/n/local"))
			tag = sys->sprint(" (cowfs actid=%d, reversible)", inv.caps.actid);
		else
			tag = " (DURABLE)";
		sys->fprint(stdout, "  writes_fs: yes  via %s%s\n", writ, tag);
	} else {
		sys->fprint(stdout, "  writes_fs: no\n");
	}
}

# Return the list entry that prefixes path, or "".
matchesAny(l: list of string, path: string): string
{
	for(; l != nil; l = tl l) {
		p := hd l;
		if(prefix(path, p))
			return p;
	}
	return "";
}

# Return the longest prefix of path that appears in l, or "".
closestPrefix(l: list of string, path: string): string
{
	best := "";
	for(; l != nil; l = tl l) {
		p := hd l;
		# Find longest p such that path starts with a prefix of p.
		minlen := len p;
		if(len path < minlen)
			minlen = len path;
		i := 0;
		while(i < minlen && p[i] == path[i])
			i++;
		if(i > len best)
			best = p[0:i];
	}
	return best;
}

runDiff(dirA, dirB: string)
{
	stdout := sys->fildes(1);
	capsA := parseCaps(dirA);
	capsB := parseCaps(dirB);
	toolsA := loadTools(capsA.tools);
	toolsB := loadTools(capsB.tools);
	invA := buildInventory(capsA, toolsA);
	invB := buildInventory(capsB, toolsB);

	if(machine) {
		runDiffMachine(stdout, dirA, dirB, invA, invB);
		return;
	}
	sys->fprint(stdout, "nsaudit diff: %s -> %s\n\n", dirA, dirB);

	sys->fprint(stdout, "authorities removed\n");
	any := 0;
	for(al := invA.auths; al != nil; al = tl al) {
		if(!contains(invB.auths, hd al)) {
			sys->fprint(stdout, "  - %s\n", hd al);
			any = 1;
		}
	}
	if(!any)
		sys->fprint(stdout, "  (none)\n");

	sys->fprint(stdout, "\nauthorities added\n");
	any = 0;
	for(al = invB.auths; al != nil; al = tl al) {
		if(!contains(invA.auths, hd al)) {
			sys->fprint(stdout, "  + %s\n", hd al);
			any = 1;
		}
	}
	if(!any)
		sys->fprint(stdout, "  (none)\n");
}

#
# Machine-readable mode: ndb records, one per entry, blank lines between
# records. Each section is a distinct kind, distinguished by the first
# attribute: nsaudit=caps, authority=..., reads_fs=..., writes_fs=...,
# violation=..., reach=...
#
# This format is parseable by attrdb(2) and by any shell tool that
# reads attr=value files. It is the stable machine interface.
#

mquote(s: string): string
{
	# Quote a value for ndb. If it contains whitespace or quotes, wrap
	# in single quotes and escape embedded quotes as ''.
	need := 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c == ' ' || c == '\t' || c == '\n' || c == '=' || c == '\'') {
			need = 1;
			break;
		}
	}
	if(!need)
		return s;
	r := "'";
	for(j := 0; j < len s; j++) {
		c := s[j];
		if(c == '\'')
			r += "''";
		else if(c == '\n')
			r += " ";
		else
			r[len r] = c;
	}
	r += "'";
	return r;
}

runReportMachine(stdout: ref Sys->FD, inv: ref Inventory, rules: list of ref Rule)
{
	c := inv.caps;
	sys->fprint(stdout, "nsaudit=caps\tdir=%s\trole=%s\tnodevs=%s\tactid=%d\txenith=%d\n",
		mquote(c.dir), c.role, c.nodevs, c.actid, c.xenith);

	for(al := inv.auths; al != nil; al = tl al)
		sys->fprint(stdout, "authority=%s\n", hd al);

	for(rl := inv.reads_fs; rl != nil; rl = tl rl)
		sys->fprint(stdout, "reads_fs=%s\n", mquote(hd rl));

	for(wl := inv.writes_fs; wl != nil; wl = tl wl) {
		p := hd wl;
		tag := "durable";
		if(prefix(p, "/tmp/veltro"))
			tag = "ephemeral";
		else if(c.actid >= 0 && prefix(p, "/n/local"))
			tag = "cowfs";
		sys->fprint(stdout, "writes_fs=%s\treversibility=%s\n",
			mquote(p), tag);
	}

	findings := evaluateRules(inv, rules);
	nhigh := 0;
	for(fl := findings; fl != nil; fl = tl fl) {
		f := hd fl;
		if(!f.matched)
			continue;
		if(f.rule.severity == "high")
			nhigh++;
		sys->fprint(stdout,
			"violation=%s\tseverity=%s\tmessage=%s\tfix=%s\n",
			f.rule.name,
			f.rule.severity,
			mquote(f.rule.message),
			mquote(f.rule.fix));
	}

	if(nhigh > 0)
		raise "fail:high-violations";
}

runReachMachine(stdout: ref Sys->FD, inv: ref Inventory, path, reach, writ: string)
{
	sys->fprint(stdout, "reach=%s\tdir=%s\n", mquote(path), mquote(inv.caps.dir));
	if(reach != "")
		sys->fprint(stdout, "reads_fs=yes\tvia=%s\n", mquote(reach));
	else
		sys->fprint(stdout, "reads_fs=no\n");
	if(writ != "") {
		tag := "durable";
		if(prefix(writ, "/tmp/veltro"))
			tag = "ephemeral";
		else if(inv.caps.actid >= 0 && prefix(writ, "/n/local"))
			tag = "cowfs";
		sys->fprint(stdout, "writes_fs=yes\tvia=%s\treversibility=%s\n",
			mquote(writ), tag);
	} else {
		sys->fprint(stdout, "writes_fs=no\n");
	}
}

runDiffMachine(stdout: ref Sys->FD, dirA, dirB: string, invA, invB: ref Inventory)
{
	sys->fprint(stdout, "nsaudit=diff\tfrom=%s\tto=%s\n",
		mquote(dirA), mquote(dirB));
	for(al := invA.auths; al != nil; al = tl al) {
		a := hd al;
		if(!contains(invB.auths, a))
			sys->fprint(stdout, "removed=%s\n", a);
	}
	for(al = invB.auths; al != nil; al = tl al) {
		a := hd al;
		if(!contains(invA.auths, a))
			sys->fprint(stdout, "added=%s\n", a);
	}
}

#
# Error plumbing.
#

fatal(msg: string)
{
	if(sys != nil)
		sys->fprint(sys->fildes(2), "nsaudit: %s\n", msg);
	raise "fail:fatal";
}
