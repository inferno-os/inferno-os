implement WmAppsTest;

#
# wm_apps_test - Regression tests for WM app naming and loading
#
# Verifies that the WM apps (shell, editor, fractals) exist under
# their correct names, load without link typecheck errors, and that
# the old names (lucishell, edit, luciedit) are gone.
#
# IMPORTANT: This test deliberately avoids passing module functions
# as function references (ref fn).  The Limbo compiler includes
# referenced functions in every module type descriptor in the same
# compilation unit, which poisons load-time link checks for any
# external module loaded later.  This is the same bug that broke
# shell.b when it used menumod->newgen(menuitems) — the menuitems
# function leaked into the Sh type descriptor, causing
#   load Command "/dis/sh.dis"
# to fail with:
#   link typecheck Sh->menuitems() 0/...
#
# To avoid this, each test is called directly (no ref fn dispatch).
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

include "sh.m";

WmAppsTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/wm_apps_test.b";

passed := 0;
failed := 0;
skipped := 0;

# Direct test runner — no ref fn parameter
dotest(t: ref T, ok: int)
{
	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

# Helper: check if a file exists
fileexists(path: string): int
{
	(ok, nil) := sys->stat(path);
	return ok >= 0;
}

GuiApp: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

WidgetCheck: module {
	PATH: con "/dis/lib/widget.dis";
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	# ── NewAppsExist ──
	{
		t := testing->newTsrc("NewAppsExist", SRCFILE);
		t.assert(fileexists("/dis/wm/shell.dis"), "dis/wm/shell.dis exists");
		t.assert(fileexists("/dis/wm/editor.dis"), "dis/wm/editor.dis exists");
		t.assert(fileexists("/dis/wm/fractals.dis"), "dis/wm/fractals.dis exists");
		dotest(t, 0);
	}

	# ── OldNamesRemoved ──
	{
		t := testing->newTsrc("OldNamesRemoved", SRCFILE);
		t.assert(!fileexists("/dis/wm/lucishell.dis"), "lucishell.dis removed");
		t.assert(!fileexists("/dis/wm/luciedit.dis"), "luciedit.dis removed");
		t.assert(!fileexists("/dis/wm/edit.dis"), "wm/edit.dis removed (renamed to editor.dis)");
		dotest(t, 0);
	}

	# ── ShellLoads ──
	{
		t := testing->newTsrc("ShellLoads", SRCFILE);
		mod := load GuiApp "/dis/wm/shell.dis";
		if(mod == nil) {
			err := sys->sprint("%r");
			t.fatal("shell.dis failed to load: " + err);
		} else
			t.log("shell.dis loaded OK");
		dotest(t, 0);
	}

	# ── EditorLoads ──
	{
		t := testing->newTsrc("EditorLoads", SRCFILE);
		mod := load GuiApp "/dis/wm/editor.dis";
		if(mod == nil) {
			err := sys->sprint("%r");
			t.fatal("editor.dis failed to load: " + err);
		} else
			t.log("editor.dis loaded OK");
		dotest(t, 0);
	}

	# ── FractalsLoads ──
	{
		t := testing->newTsrc("FractalsLoads", SRCFILE);
		mod := load GuiApp "/dis/wm/fractals.dis";
		if(mod == nil) {
			err := sys->sprint("%r");
			t.fatal("fractals.dis failed to load: " + err);
		} else
			t.log("fractals.dis loaded OK");
		dotest(t, 0);
	}

	# ── ShellCanLoadSh ──
	# Critical regression: verifies shell.dis doesn't pollute Sh type.
	{
		t := testing->newTsrc("ShellCanLoadSh", SRCFILE);
		if(!fileexists("/dis/sh.dis")) {
			t.skip("sh.dis not found");
		} else {
			shellmod := load GuiApp "/dis/wm/shell.dis";
			if(shellmod == nil) {
				err := sys->sprint("%r");
				t.fatal("cannot load shell.dis: " + err);
			} else {
				sh := load Command "/dis/sh.dis";
				if(sh == nil) {
					err := sys->sprint("%r");
					t.fatal("sh.dis failed to load after shell.dis: " + err);
				} else
					t.log("sh.dis loaded OK (no type pollution from shell.dis)");
			}
		}
		dotest(t, 0);
	}

	# ── EditToolSeparate ──
	{
		t := testing->newTsrc("EditToolSeparate", SRCFILE);
		t.assert(fileexists("/dis/veltro/tools/edit.dis"),
			"veltro edit tool exists");
		t.assert(fileexists("/dis/wm/editor.dis"),
			"wm editor app exists");
		dotest(t, 0);
	}

	# ── LaunchPaths ──
	{
		t := testing->newTsrc("LaunchPaths", SRCFILE);
		t.assert(fileexists("/dis/wm/shell.dis"),
			"launch 'shell' resolves");
		t.assert(fileexists("/dis/wm/editor.dis"),
			"launch 'editor' resolves");
		t.assert(fileexists("/dis/wm/fractals.dis"),
			"launch 'fractals' resolves");
		t.assert(fileexists("/dis/wm/clock.dis"),
			"launch 'clock' resolves");
		dotest(t, 0);
	}

	# ── WidgetLoads ──
	{
		t := testing->newTsrc("WidgetLoads", SRCFILE);
		w := load WidgetCheck WidgetCheck->PATH;
		if(w == nil) {
			err := sys->sprint("%r");
			t.fatal("widget.dis failed to load: " + err);
		} else
			t.log("widget.dis loaded OK");
		dotest(t, 0);
	}

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
