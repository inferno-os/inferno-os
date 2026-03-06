implement ToolLaunch;

#
# launch - Launch a GUI app in the presentation zone
#
# Launches a /dis/wm/* program in lucifer's presentation zone.
# Accepts short name, wm/ prefix, or full path — all equivalent:
#   Launch clock
#   Launch wm/clock
#   Launch /dis/wm/clock.dis
#
# Usage:
#   Launch list         — list available apps
#   Launch <appname>    — launch app in presentation zone
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolLaunch: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

UI_MOUNT: con "/n/ui";

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
	return "launch";
}

doc(): string
{
	return "Launch - Launch a GUI app in the presentation zone\n\n" +
		"Usage:\n" +
		"  Launch list           — show available apps\n" +
		"  Launch xenith         — launch Xenith text environment\n" +
		"  Launch clock          — launch by short name\n" +
		"  Launch wm/clock       — launch with wm/ prefix\n" +
		"  Launch /dis/wm/clock  — launch by full path (.dis optional)\n\n" +
		"Confirmed working (draw-based, /dis/wm/):\n" +
		"  clock, bounce, coffee, colors, date, view, rt, lens, luciedit\n\n" +
		"Also available (full environments, /dis/):\n" +
		"  xenith                — Xenith text environment (Acme-like)\n\n" +
		"Not available (require Tk, which is not built in):\n" +
		"  task, edit, about, tetris, sh, ftree, deb\n\n" +
		"Returns 'launched <name> in presentation zone' on success.";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	# Strip leading/trailing whitespace
	while(len args > 0 && (args[0] == ' ' || args[0] == '\t'))
		args = args[1:];
	while(len args > 0 && (args[len args - 1] == ' ' || args[len args - 1] == '\t' || args[len args - 1] == '\n'))
		args = args[0:len args - 1];

	if(args == "" || args == "list")
		return listapps();

	# Take first word as app argument
	apparg := args;
	for(i := 0; i < len apparg; i++) {
		if(apparg[i] == ' ' || apparg[i] == '\t') {
			apparg = apparg[0:i];
			break;
		}
	}

	# Normalize to bare app name:
	#   /dis/wm/clock.dis  →  clock
	#   /dis/wm/clock      →  clock
	#   wm/clock           →  clock
	#   clock              →  clock
	appname := apparg;
	if(len appname > 8 && appname[0:8] == "/dis/wm/")
		appname = appname[8:];
	else if(len appname > 3 && appname[0:3] == "wm/")
		appname = appname[3:];
	# Strip any remaining path separators
	for(j := len appname - 1; j >= 0; j--) {
		if(appname[j] == '/') {
			appname = appname[j+1:];
			break;
		}
	}
	# Strip .dis suffix
	if(len appname > 4 && appname[len appname - 4:] == ".dis")
		appname = appname[0:len appname - 4];

	if(appname == "")
		return "error: usage: Launch <appname> or Launch list";

	# Reject Tk-dependent apps (Tk is not built into this emu)
	if(istk(appname))
		return "error: " + appname + " requires Tk which is not available.\n" +
			"Try: clock, bounce, coffee, colors, date, view, rt, lens, xenith";

	# Reject names containing path separators — belt-and-suspenders guard
	# against any normalization gaps that could reach outside /dis/wm/.
	for(pi := 0; pi < len appname; pi++) {
		if(appname[pi] == '/') {
			return "error: app name may not contain '/'";
		}
	}

	# Resolve the .dis path.
	# /dis/wm/ is the primary pool of launchable WM apps.
	# Apps outside /dis/wm/ must be explicitly whitelisted here; no generic
	# directory search is performed to prevent an agent from reaching
	# arbitrary /dis/*.dis files by guessing names.
	dispath := "/dis/wm/" + appname + ".dis";
	(ok, nil) := sys->stat(dispath);
	if(ok < 0) {
		# Check explicit whitelist for apps that live outside /dis/wm/.
		dispath = extraapp(appname);
		if(dispath == "")
			return "error: " + appname + " not found\n" +
				"Use 'Launch list' to see available apps";
	}

	# Register app with luciuisrv via presentation/ctl
	actid := currentactid();
	if(actid < 0)
		return "error: cannot reach presentation zone (is luciuisrv running?)";

	pctl := sys->sprint("%s/activity/%d/presentation/ctl", UI_MOUNT, actid);

	# Build the create command.
	# For xenith: pass -c 1 (single-column, fits presentation zone) and -E (embedded flag
	# so xenith skips killprocs on exit). Also pass -t dark if brimstone theme is active.
	cmd: string;
	if(appname == "xenith") {
		xenithargs := "-c 1 -E";
		theme := readfile("/lib/lucifer/theme/current");
		if(theme != nil)
			theme = strip(theme);
		# Brimstone is the dark theme (and the default when no theme file exists).
		# Halo and other light themes use xenith's default Acme colour scheme.
		if(theme == nil || theme == "" || theme == "brimstone")
			xenithargs += " -t dark";
		cmd = sys->sprint("create id=%s type=app dis=%s label=%s data=%s",
			appname, dispath, appname, xenithargs);
	} else
		cmd = sys->sprint("create id=%s type=app dis=%s label=%s", appname, dispath, appname);
	fd := sys->open(pctl, Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("error: cannot open presentation/ctl: %r");
	b := array of byte cmd;
	sys->write(fd, b, len b);
	fd = nil;

	# Center the new app tab
	fd = sys->open(pctl, Sys->OWRITE);
	if(fd != nil) {
		b = array of byte ("center id=" + appname);
		sys->write(fd, b, len b);
		fd = nil;
	}

	return "launched " + appname + " in presentation zone";
}

# Read current activity ID from namespace
currentactid(): int
{
	s := readfile(UI_MOUNT + "/activity/current");
	if(s == nil)
		return -1;
	s = strip(s);
	(n, nil) := str->toint(s, 10);
	return n;
}

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}

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

# List available (non-Tk) apps from /dis/wm/ plus known top-level apps.
listapps(): string
{
	fd := sys->open("/dis/wm", Sys->OREAD);
	if(fd == nil)
		return "error: cannot open /dis/wm";

	apps := "";
	count := 0;
	for(;;) {
		(n, dir) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			nm := dir[i].name;
			if(len nm <= 4 || nm[len nm - 4:] != ".dis")
				continue;
			nm = nm[0:len nm - 4];
			if(istk(nm))
				continue;
			if(count > 0)
				apps += "\n";
			apps += "  " + nm;
			count++;
		}
	}

	# Also list whitelisted apps that live outside /dis/wm/.
	# This mirrors extraapp() — both must stay in sync.
	extra := array[] of {
		("xenith", "/dis/xenith/xenith.dis"),
	};
	for(i := 0; i < len extra; i++) {
		(nm, path) := extra[i];
		(ok, nil) := sys->stat(path);
		if(ok < 0)
			continue;
		if(count > 0)
			apps += "\n";
		apps += "  " + nm;
		count++;
	}

	if(count == 0)
		return "no apps available";
	return sys->sprint("%d apps available:\n%s", count, apps);
}

# Explicit whitelist of apps that live outside /dis/wm/.
# Returns the full .dis path for known safe apps, or "" if not listed.
# Add entries here only after confirming the app implements GuiApp and is safe
# to run in lucifer's presentation zone.
extraapp(name: string): string
{
	# Each entry: (short-name, absolute-dis-path)
	# To add a new app: add a row here, review the .dis for GuiApp interface.
	# Note: paths must be under a /dis/ subdirectory (not top-level /dis/*.dis)
	# so they are visible in the tool's restricted namespace when that
	# subdirectory is listed in caps.paths (e.g. "/dis/xenith" → /dis/xenith/).
	apps := array[] of {
		("xenith", "/dis/xenith/xenith.dis"),
	};
	for(i := 0; i < len apps; i++) {
		(nm, path) := apps[i];
		if(nm == name) {
			(ok, nil) := sys->stat(path);
			if(ok >= 0)
				return path;
			return "";	# whitelisted but not installed
		}
	}
	return "";
}

# Returns 1 if the app requires Tk (not available in this build)
istk(name: string): int
{
	tkapps := array[] of {
		"task", "edit", "about", "tetris", "sh", "ftree", "deb", "wm",
	};
	for(i := 0; i < len tkapps; i++) {
		if(name == tkapps[i])
			return 1;
	}
	return 0;
}
