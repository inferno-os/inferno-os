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

include "../tool.m";

ToolLaunch: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
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
		"  Launch clock          — launch by short name\n" +
		"  Launch wm/clock       — launch with wm/ prefix\n" +
		"  Launch /dis/wm/clock  — launch by full path (.dis optional)\n\n" +
		"Confirmed working (draw-based):\n" +
		"  clock, bounce, coffee, colors, date, view, rt, lens\n\n" +
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
			"Try: clock, bounce, coffee, colors, date, view, rt, lens";

	# Resolve and verify
	dispath := "/dis/wm/" + appname + ".dis";
	(ok, nil) := sys->stat(dispath);
	if(ok < 0)
		return "error: " + appname + " not found (tried " + dispath + ")\n" +
			"Use 'Launch list' to see available apps";

	# Signal lucifer's preslaunchpoll goroutine
	pfd := sys->open("/n/pres-launch", Sys->OWRITE);
	if(pfd == nil)
		pfd = sys->create("/tmp/veltro/pres-launch", Sys->OWRITE, 8r644);
	if(pfd == nil)
		return "error: cannot reach presentation zone";

	data := array of byte dispath;
	sys->write(pfd, data, len data);
	pfd = nil;

	return "launched " + appname + " in presentation zone";
}

# List available (non-Tk) apps from /dis/wm/
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

	if(count == 0)
		return "no apps available";
	return sys->sprint("%d apps available:\n%s", count, apps);
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
