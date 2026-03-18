implement Settings;

#
# settings - System preferences for Lucifer
#
# A graphical settings app that provides a non-technical interface
# for configuring: theme, tool budget, active tools, namespace
# paths, agent prompts, and startup profile.
#
# Configuration reads/writes:
#   Theme:        /lib/lucifer/theme/current (persistent, live)
#   Tool budget:  /tool/budget + /tool/ctl budget-add/budget-remove (live, ephemeral)
#   Active tools: /tool/tools + /tool/ctl add/remove (live, ephemeral)
#   Paths:        /tool/paths + /tool/ctl bindpath/unbindpath (live, ephemeral)
#   Prompts:      /lib/veltro/meta.txt, /lib/veltro/agents/task.txt (persistent)
#   Profile:      /lib/sh/profile (persistent, restart required)
#
# Settings marked "restart required" flash a warning in the status bar.
#
# Mouse:
#   Button 1     select / toggle / interact
#   Button 3     context menu (future)
#
# Keyboard:
#   Tab          cycle focus between fields
#   Enter        confirm / apply
#   Escape       cancel edits
#   Ctrl-Q       quit
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Image, Point, Rect, Pointer: import draw;

include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

include "string.m";
	str: String;

include "lucitheme.m";

include "widget.m";
	widgetmod: Widget;
	Scrollbar, Statusbar, Textfield, Listbox, Button, Label, Checkbox, Radio, Kbdfilter: import widgetmod;

Settings: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

# ── Categories ─────────────────────────────────────────────────

CatTheme, CatTools, CatBudget, CatPaths, CatPrompts, CatProfile: con iota;
NCATS: con 6;

catnames := array[] of {
	"Theme",
	"Initial Active Tools",
	"Delegatable Tools",
	"Namespace Paths",
	"Agent Prompts",
	"Startup Profile",
};

# ── State ──────────────────────────────────────────────────────

w: ref Window;
display_g: ref Display;
font: ref Font;
kf: ref Kbdfilter;
sbar: ref Statusbar;
catlist: ref Listbox;
category: int;		# current category index

# Colours
bgcolor:   ref Image;
divcolor:  ref Image;

# Theme panel
theme_radios: array of ref Radio;
theme_names:  array of string;

# Tools panel
tool_checks:  array of ref Checkbox;
tool_names:   array of string;

# Budget panel
budget_checks: array of ref Checkbox;
budget_names:  array of string;

# Paths panel
path_list: ref Listbox;
path_add_tf: ref Textfield;
path_add_btn: ref Button;
path_rm_btn:  ref Button;

# Prompts panel
prompt_labels: array of ref Label;
prompt_btns:   array of ref Button;
prompt_files := array[] of {
	("/lib/veltro/meta.txt", "Meta Agent Prompt"),
	("/lib/veltro/agents/task.txt", "Task Agent Prompt"),
};

# Profile panel
profile_label: ref Label;
profile_btn:   ref Button;

dirty: int;
stderr: ref Sys->FD;

# ── Layout constants ─────────────────────────────────────────

CAT_WIDTH_FRAC: con 30;	# category list takes 30% of width
MARGIN: con 8;
FIELD_H: con 0;		# computed from font
FIELD_SPACING: con 4;
CHECK_H: con 0;		# computed from font
BTN_W: con 100;
BTN_H: con 0;

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	str = load String String->PATH;
	stderr = sys->fildes(2);

	if(ctxt == nil) {
		sys->fprint(stderr, "settings: no window context\n");
		raise "fail:no context";
	}

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();
	sys->sleep(100);

	w = wmclient->window(ctxt, "Settings", Wmclient->Appl);
	display_g = w.display;

	font = Font.open(display_g, "/fonts/combined/unicode.14.font");
	if(font == nil)
		font = Font.open(display_g, "/fonts/10646/9x15/9x15.font");
	if(font == nil)
		font = Font.open(display_g, "*default*");

	# Load theme colours
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme != nil) {
		th := lucitheme->gettheme();
		bgcolor  = display_g.color(th.editbg);
		divcolor = display_g.color(th.editlineno);
	} else {
		bgcolor  = display_g.color(int 16rFFFDF6FF);
		divcolor = display_g.color(int 16rBBBBBBFF);
	}

	# Init widget toolkit
	if(widgetmod == nil)
		widgetmod = load Widget Widget->PATH;
	widgetmod->init(display_g, font);

	kf = Kbdfilter.new();

	w.reshape(Rect((0, 0), (520, 420)));
	w.startinput("kbd" :: "ptr" :: nil);
	w.onscreen(nil);

	category = CatTheme;
	layoutall();
	loadcategory();
	dirty = 1;

	# Main event loop
	for(;;) {
		if(dirty) {
			redraw();
			dirty = 0;
		}
		alt {
		ctl := <-w.ctl or
		ctl = <-w.ctxt.ctl =>
			if(ctl == nil)
				;
			else if(ctl[0] == '!') {
				w.wmctl(ctl);
				layoutall();
				dirty = 1;
			} else
				w.wmctl(ctl);
		k := <-w.ctxt.kbd =>
			handlekey(k);
		ptr := <-w.ctxt.ptr =>
			if(ptr == nil)
				;
			else if(w.pointer(*ptr))
				;
			else
				handleptr(ptr);
		}
	}
}

# ── Layout ────────────────────────────────────────────────────

layoutall()
{
	wr := w.imager(w.image.r);
	sh := widgetmod->statusheight();

	# Status bar at bottom
	sbr := Rect((wr.min.x, wr.max.y - sh), wr.max);
	if(sbar == nil)
		sbar = Statusbar.new(sbr);
	else
		sbar.resize(sbr);

	# Category list on left
	catw := wr.dx() * CAT_WIDTH_FRAC / 100;
	catr := Rect(wr.min, (wr.min.x + catw, wr.max.y - sh));
	if(catlist == nil) {
		catlist = Listbox.mk(catr);
		catlist.setitems(catnames);
		catlist.selected = category;
	} else
		catlist.resize(catr);

	# Content area: right of divider, above status bar
	layoutcontent();
}

# Layout the right-hand content pane for the current category.
layoutcontent()
{
	wr := w.imager(w.image.r);
	sh := widgetmod->statusheight();
	catw := wr.dx() * CAT_WIDTH_FRAC / 100;
	# Content area starts after category list + divider
	cx := wr.min.x + catw + 2;
	cy := wr.min.y + MARGIN;
	cw := wr.max.x - MARGIN;
	cbottom := wr.max.y - sh - MARGIN;

	fh := font.height + 8;
	bh := font.height + 10;
	ch := font.height + 6;	# checkbox row height

	# Clear old panel state
	theme_radios = nil;
	tool_checks = nil;
	budget_checks = nil;
	path_list = nil;
	path_add_tf = nil;
	path_add_btn = nil;
	path_rm_btn = nil;
	prompt_labels = nil;
	prompt_btns = nil;
	profile_label = nil;
	profile_btn = nil;

	case category {
	CatTheme =>
		layouttheme(cx, cy, cw, ch);
	CatTools =>
		layouttools(cx, cy, cw, cbottom, ch);
	CatBudget =>
		layoutbudget(cx, cy, cw, cbottom, ch);
	CatPaths =>
		layoutpaths(cx, cy, cw, cbottom, fh, bh);
	CatPrompts =>
		layoutprompts(cx, cy, cw, fh, bh);
	CatProfile =>
		layoutprofile(cx, cy, cw, bh);
	}
}

layouttheme(cx, cy, cw, ch: int)
{
	theme_names = readthemes();
	current := readcurrenttheme();

	theme_radios = array[len theme_names] of ref Radio;
	for(i := 0; i < len theme_names; i++) {
		sel := 0;
		if(theme_names[i] == current)
			sel = 1;
		theme_radios[i] = Radio.mk(
			Rect((cx, cy), (cw, cy + ch)),
			theme_names[i], sel);
		cy += ch + FIELD_SPACING;
	}
}

layouttools(cx, cy, cw, cbottom, ch: int)
{
	# Read all known tools from registry (space-separated)
	# and active tools from /tool/tools (newline-separated)
	active := readlines("/tool/tools");
	all := readtokens("/tool/_registry");
	if(all == nil || len all == 0)
		all = active;

	tool_names = all;
	n := len all;
	tool_checks = array[n] of ref Checkbox;
	for(i := 0; i < n; i++) {
		if(cy + ch > cbottom)
			break;
		checked := inlist(all[i], active);
		tool_checks[i] = Checkbox.mk(
			Rect((cx, cy), (cw, cy + ch)),
			all[i], checked);
		cy += ch + FIELD_SPACING;
	}
}

layoutbudget(cx, cy, cw, cbottom, ch: int)
{
	# Read current budget (newline-separated) and all known tools (space-separated)
	budgeted := readlines("/tool/budget");
	all := readtokens("/tool/_registry");
	if(all == nil || len all == 0)
		all = budgeted;

	budget_names = all;
	n := len all;
	budget_checks = array[n] of ref Checkbox;
	for(i := 0; i < n; i++) {
		if(cy + ch > cbottom)
			break;
		checked := inlist(all[i], budgeted);
		budget_checks[i] = Checkbox.mk(
			Rect((cx, cy), (cw, cy + ch)),
			all[i], checked);
		cy += ch + FIELD_SPACING;
	}
}

layoutpaths(cx, cy, cw, cbottom, fh, bh: int)
{
	# Path list (takes most of the space)
	listh := cbottom - cy - fh - bh - MARGIN * 2;
	if(listh < fh * 3)
		listh = fh * 3;
	listr := Rect((cx, cy), (cw, cy + listh));
	path_list = Listbox.mk(listr);
	paths := readlines("/tool/paths");
	if(paths != nil)
		path_list.setitems(paths);
	cy += listh + MARGIN;

	# Add path textfield + button
	btnw := 60;
	path_add_tf = Textfield.mk(
		Rect((cx, cy), (cw - btnw - FIELD_SPACING, cy + fh)),
		"Path: ", 0);
	path_add_tf.focused = 1;
	path_add_btn = Button.mk(
		Rect((cw - btnw, cy), (cw, cy + bh)),
		"Bind");
	cy += fh + FIELD_SPACING;

	path_rm_btn = Button.mk(
		Rect((cx, cy), (cx + btnw, cy + bh)),
		"Unbind");
}

layoutprompts(cx, cy, cw, fh, bh: int)
{
	n := len prompt_files;
	prompt_labels = array[n] of ref Label;
	prompt_btns = array[n] of ref Button;
	for(i := 0; i < n; i++) {
		(nil, label) := prompt_files[i];
		prompt_labels[i] = Label.mk(
			Rect((cx, cy), (cw, cy + fh)),
			label, 0);
		cy += fh;
		prompt_btns[i] = Button.mk(
			Rect((cx, cy), (cx + BTN_W + 20, cy + bh)),
			"Open in Editor");
		cy += bh + MARGIN;
	}
}

layoutprofile(cx, cy, cw, bh: int)
{
	fh := font.height + 8;
	profile_label = Label.mk(
		Rect((cx, cy), (cw, cy + fh)),
		"Startup profile: /lib/sh/profile", 0);
	cy += fh + FIELD_SPACING;
	profile_btn = Button.mk(
		Rect((cx, cy), (cx + BTN_W + 20, cy + bh)),
		"Open in Editor");
}

# ── Data loading ──────────────────────────────────────────────

loadcategory()
{
	# Category-specific data load (layout already done)
}

readthemes(): array of string
{
	fd := sys->open("/lib/lucifer/theme", Sys->OREAD);
	if(fd == nil)
		return array[] of { "brimstone", "halo" };

	names: list of string;
	n := 0;
	for(;;) {
		(count, dirs) := sys->dirread(fd);
		if(count <= 0)
			break;
		for(i := 0; i < count; i++) {
			nm := dirs[i].name;
			if(nm == "current")
				continue;
			names = nm :: names;
			n++;
		}
	}
	if(n == 0)
		return array[] of { "brimstone", "halo" };

	result := array[n] of string;
	for(j := n - 1; j >= 0; j--) {
		result[j] = hd names;
		names = tl names;
	}
	return result;
}

readcurrenttheme(): string
{
	s := readfile("/lib/lucifer/theme/current");
	if(s == nil)
		return "brimstone";
	return strip(s);
}

readlines(path: string): array of string
{
	s := readfile(path);
	if(s == nil)
		return nil;
	# Tokenize on newlines
	lines: list of string;
	n := 0;
	while(len s > 0) {
		eol := len s;
		for(i := 0; i < len s; i++) {
			if(s[i] == '\n') {
				eol = i;
				break;
			}
		}
		line := s[0:eol];
		if(eol < len s)
			s = s[eol + 1:];
		else
			s = "";
		line = strip(line);
		if(len line > 0) {
			lines = line :: lines;
			n++;
		}
	}
	if(n == 0)
		return nil;
	result := array[n] of string;
	for(j := n - 1; j >= 0; j--) {
		result[j] = hd lines;
		lines = tl lines;
	}
	return result;
}

# Read space-or-newline separated tokens from a file.
# /tool/_registry returns space-separated on one line.
readtokens(path: string): array of string
{
	s := readfile(path);
	if(s == nil)
		return nil;
	(nil, toks) := sys->tokenize(s, " \t\n");
	if(toks == nil)
		return nil;
	# Count
	n := 0;
	for(t := toks; t != nil; t = tl t)
		n++;
	result := array[n] of string;
	i := 0;
	for(t = toks; t != nil; t = tl t)
		result[i++] = hd t;
	return result;
}

inlist(s: string, arr: array of string): int
{
	if(arr == nil)
		return 0;
	for(i := 0; i < len arr; i++)
		if(arr[i] == s)
			return 1;
	return 0;
}

# ── Drawing ───────────────────────────────────────────────────

redraw()
{
	if(w.image == nil)
		return;
	wr := w.imager(w.image.r);

	# Clear
	w.image.draw(wr, bgcolor, nil, Point(0, 0));

	# Category list
	if(catlist != nil)
		catlist.draw(w.image);

	# Vertical divider
	catw := wr.dx() * CAT_WIDTH_FRAC / 100;
	dvx := wr.min.x + catw;
	sh := widgetmod->statusheight();
	w.image.draw(Rect((dvx, wr.min.y), (dvx + 2, wr.max.y - sh)),
		     divcolor, nil, Point(0, 0));

	# Content
	case category {
	CatTheme =>
		drawradios(theme_radios);
	CatTools =>
		drawchecks(tool_checks);
	CatBudget =>
		drawchecks(budget_checks);
	CatPaths =>
		drawpaths();
	CatPrompts =>
		drawprompts();
	CatProfile =>
		drawprofile();
	}

	# Status bar
	if(sbar != nil) {
		sbar.left = catnames[category];
		case category {
		CatTheme =>
			sbar.right = "restart for full effect";
		CatTools =>
			sbar.right = "applied immediately";
		CatBudget =>
			sbar.right = "applied immediately";
		CatPaths =>
			sbar.right = "applied immediately";
		CatPrompts =>
			sbar.right = "takes effect next session";
		CatProfile =>
			sbar.right = "restart required";
		}
		sbar.draw(w.image);
	}

	w.image.flush(Draw->Flushnow);
}

drawradios(radios: array of ref Radio)
{
	if(radios == nil)
		return;
	for(i := 0; i < len radios; i++)
		if(radios[i] != nil)
			radios[i].draw(w.image);
}

drawchecks(checks: array of ref Checkbox)
{
	if(checks == nil)
		return;
	for(i := 0; i < len checks; i++)
		if(checks[i] != nil)
			checks[i].draw(w.image);
}

drawpaths()
{
	if(path_list != nil)
		path_list.draw(w.image);
	if(path_add_tf != nil)
		path_add_tf.draw(w.image);
	if(path_add_btn != nil)
		path_add_btn.draw(w.image);
	if(path_rm_btn != nil)
		path_rm_btn.draw(w.image);
}

drawprompts()
{
	if(prompt_labels != nil)
		for(i := 0; i < len prompt_labels; i++)
			if(prompt_labels[i] != nil)
				prompt_labels[i].draw(w.image);
	if(prompt_btns != nil)
		for(j := 0; j < len prompt_btns; j++)
			if(prompt_btns[j] != nil)
				prompt_btns[j].draw(w.image);
}

drawprofile()
{
	if(profile_label != nil)
		profile_label.draw(w.image);
	if(profile_btn != nil)
		profile_btn.draw(w.image);
}

# ── Keyboard handling ─────────────────────────────────────────

handlekey(rawkey: int)
{
	k := kf.filter(rawkey);
	if(k < 0)
		return;

	# Ctrl-Q: quit
	if(k == 'q' - 'a' + 1) {
		exit;
		return;
	}

	# Escape: deselect
	if(k == 27)
		return;

	# Route to paths textfield if active
	if(category == CatPaths && path_add_tf != nil) {
		if(k == '\n') {
			dobindpath();
			return;
		}
		path_add_tf.key(k);
		dirty = 1;
	}
}

# ── Pointer handling ──────────────────────────────────────────

handleptr(ptr: ref Pointer)
{
	# Scrollbar tracking must be checked FIRST — before the button filter.
	# track() needs to see button-release events (buttons==0) to clear
	# the active drag state.  Without this, a scrollbar drag that starts
	# inside Listbox.click() can never be cancelled, permanently stealing
	# all subsequent B1 clicks.
	if(catlist != nil && catlist.scroll != nil && catlist.scroll.isactive()) {
		newo := catlist.scroll.track(ptr);
		if(newo >= 0) {
			catlist.top = newo;
			dirty = 1;
		}
		return;
	}

	if(!(ptr.buttons & 1) && !(ptr.buttons & (8|16)))
		return;

	# Scroll wheel anywhere
	if(ptr.buttons & (8|16)) {
		if(catlist != nil && catlist.contains(ptr.xy)) {
			catlist.wheel(ptr.buttons);
			dirty = 1;
			return;
		}
		if(category == CatPaths && path_list != nil && path_list.contains(ptr.xy)) {
			path_list.wheel(ptr.buttons);
			dirty = 1;
			return;
		}
		return;
	}

	if(!(ptr.buttons & 1))
		return;

	# Category list click
	if(catlist != nil && catlist.contains(ptr.xy)) {
		sel := catlist.click(ptr.xy);
		if(sel >= 0 && sel != category) {
			category = sel;
			layoutcontent();
			dirty = 1;
		}
		return;
	}

	# Content area clicks
	case category {
	CatTheme =>
		clicktheme(ptr);
	CatTools =>
		clicktools(ptr);
	CatBudget =>
		clickbudget(ptr);
	CatPaths =>
		clickpaths(ptr);
	CatPrompts =>
		clickprompts(ptr);
	CatProfile =>
		clickprofile(ptr);
	}
}

clicktheme(ptr: ref Pointer)
{
	if(theme_radios == nil)
		return;
	for(i := 0; i < len theme_radios; i++) {
		if(theme_radios[i] != nil && theme_radios[i].contains(ptr.xy)) {
			# Mutual exclusion: deselect all, select this one
			for(j := 0; j < len theme_radios; j++)
				theme_radios[j].selected = 0;
			theme_radios[i].selected = 1;
			applytheme(theme_names[i]);
			dirty = 1;
			return;
		}
	}
}

clicktools(ptr: ref Pointer)
{
	if(tool_checks == nil)
		return;
	for(i := 0; i < len tool_checks; i++) {
		if(tool_checks[i] != nil && tool_checks[i].contains(ptr.xy)) {
			tool_checks[i].toggle();
			applytool(tool_names[i], tool_checks[i].value());
			dirty = 1;
			return;
		}
	}
}

clickbudget(ptr: ref Pointer)
{
	if(budget_checks == nil)
		return;
	for(i := 0; i < len budget_checks; i++) {
		if(budget_checks[i] != nil && budget_checks[i].contains(ptr.xy)) {
			budget_checks[i].toggle();
			applybudget(budget_names[i], budget_checks[i].value());
			dirty = 1;
			return;
		}
	}
}

clickpaths(ptr: ref Pointer)
{
	if(path_list != nil && path_list.contains(ptr.xy)) {
		path_list.click(ptr.xy);
		dirty = 1;
		return;
	}
	if(path_add_btn != nil && path_add_btn.contains(ptr.xy)) {
		trackbutton(path_add_btn, ptr);
		return;
	}
	if(path_rm_btn != nil && path_rm_btn.contains(ptr.xy)) {
		trackbutton(path_rm_btn, ptr);
		return;
	}
	if(path_add_tf != nil && path_add_tf.contains(ptr.xy)) {
		path_add_tf.click(ptr.xy);
		dirty = 1;
		return;
	}
}

clickprompts(ptr: ref Pointer)
{
	if(prompt_btns == nil)
		return;
	for(i := 0; i < len prompt_btns; i++) {
		if(prompt_btns[i] != nil && prompt_btns[i].contains(ptr.xy)) {
			trackpromptbtn(i, ptr);
			return;
		}
	}
}

clickprofile(ptr: ref Pointer)
{
	if(profile_btn != nil && profile_btn.contains(ptr.xy)) {
		trackprofilebtn(ptr);
		return;
	}
}

# ── Button tracking (hold-to-confirm pattern) ────────────────

trackbutton(btn: ref Button, nil: ref Pointer)
{
	btn.pressed = 1;
	dirty = 1;
	redraw();
	for(;;) {
		p := <-w.ctxt.ptr;
		if(p == nil || !(p.buttons & 1)) {
			btn.pressed = 0;
			if(p != nil && btn.contains(p.xy)) {
				if(btn == path_add_btn)
					dobindpath();
				else if(btn == path_rm_btn)
					dounbindpath();
			}
			dirty = 1;
			return;
		}
	}
}

trackpromptbtn(idx: int, nil: ref Pointer)
{
	btn := prompt_btns[idx];
	btn.pressed = 1;
	dirty = 1;
	redraw();
	for(;;) {
		p := <-w.ctxt.ptr;
		if(p == nil || !(p.buttons & 1)) {
			btn.pressed = 0;
			if(p != nil && btn.contains(p.xy)) {
				(path, nil) := prompt_files[idx];
				openineditor(path);
			}
			dirty = 1;
			return;
		}
	}
}

trackprofilebtn(nil: ref Pointer)
{
	profile_btn.pressed = 1;
	dirty = 1;
	redraw();
	for(;;) {
		p := <-w.ctxt.ptr;
		if(p == nil || !(p.buttons & 1)) {
			profile_btn.pressed = 0;
			if(p != nil && profile_btn.contains(p.xy)) {
				openineditor("/lib/sh/profile");
				flashstatus("restart required for profile changes");
			}
			dirty = 1;
			return;
		}
	}
}

# ── Actions ───────────────────────────────────────────────────

applytheme(name: string)
{
	fd := sys->open("/lib/lucifer/theme/current", Sys->OWRITE);
	if(fd == nil) {
		flashstatus(sys->sprint("error: %r"));
		return;
	}
	b := array of byte name;
	sys->write(fd, b, len b);
	flashstatus("theme set to " + name + " — restart for full effect");
}

applytool(name: string, active: int)
{
	cmd: string;
	if(active)
		cmd = "add " + name;
	else
		cmd = "remove " + name;
	writectl("/tool/ctl", cmd);
}

applybudget(name: string, enabled: int)
{
	cmd: string;
	if(enabled)
		cmd = "budget-add " + name;
	else
		cmd = "budget-remove " + name;
	writectl("/tool/ctl", cmd);
}

dobindpath()
{
	if(path_add_tf == nil)
		return;
	path := strip(path_add_tf.value());
	if(len path == 0)
		return;
	writectl("/tool/ctl", "bindpath " + path);
	path_add_tf.setval("");
	# Refresh path list
	paths := readlines("/tool/paths");
	if(path_list != nil && paths != nil)
		path_list.setitems(paths);
	dirty = 1;
}

dounbindpath()
{
	if(path_list == nil || path_list.selected < 0)
		return;
	if(path_list.items == nil || path_list.selected >= len path_list.items)
		return;
	# Path entries may have " ro"/" rw" suffix — extract just the path
	entry := path_list.items[path_list.selected];
	(path, nil) := str->splitl(entry, " \t");
	if(path == nil || len path == 0)
		path = entry;
	writectl("/tool/ctl", "unbindpath " + path);
	# Refresh
	paths := readlines("/tool/paths");
	if(paths != nil)
		path_list.setitems(paths);
	else
		path_list.setitems(array[0] of string);
	dirty = 1;
}

openineditor(path: string)
{
	# Check if the file is accessible first
	(ok, nil) := sys->stat(path);
	if(ok < 0) {
		flashstatus(path + " not accessible — check namespace paths");
		sys->fprint(stderr, "settings: stat %s failed: %r\n", path);
		return;
	}

	# Write to presentation ctl to launch editor with the file.
	# /tool/activity exists only in agent namespaces; from a GUI app
	# launched by lucifer we read /n/ui/activity/current instead.
	actid := readfile("/n/ui/activity/current");
	if(actid == nil) {
		flashstatus("cannot reach presentation zone — is luciuisrv running?");
		sys->fprint(stderr, "settings: cannot read /n/ui/activity/current\n");
		return;
	}
	aid := strip(actid);
	pctl := sys->sprint("/n/ui/activity/%s/presentation/ctl", aid);
	sys->fprint(stderr, "settings: openineditor %s → pctl=%s\n", path, pctl);

	# Kill existing editor first (ignore error — may not exist)
	fd := sys->open(pctl, Sys->OWRITE);
	if(fd == nil) {
		flashstatus("cannot open presentation ctl — launch from Lucifer");
		sys->fprint(stderr, "settings: cannot open %s: %r\n", pctl);
		return;
	}
	kb := array of byte "kill id=editor";
	kn := sys->write(fd, kb, len kb);
	sys->fprint(stderr, "settings: kill id=editor → %d\n", kn);
	fd = nil;

	# Small delay for kill to propagate
	sys->sleep(100);

	# Create editor artifact with file path as data
	fd = sys->open(pctl, Sys->OWRITE);
	if(fd == nil) {
		flashstatus("cannot open presentation ctl");
		sys->fprint(stderr, "settings: cannot reopen %s: %r\n", pctl);
		return;
	}
	cmd := sys->sprint("create id=editor type=app dis=/dis/wm/editor.dis label=editor data=%s", path);
	b := array of byte cmd;
	n := sys->write(fd, b, len b);
	sys->fprint(stderr, "settings: create → %d (%s)\n", n, cmd);
	fd = nil;
	if(n < 0) {
		flashstatus(sys->sprint("editor launch failed: %r"));
		return;
	}

	# Center the editor tab
	fd = sys->open(pctl, Sys->OWRITE);
	if(fd != nil) {
		b = array of byte "center id=editor";
		cn := sys->write(fd, b, len b);
		sys->fprint(stderr, "settings: center id=editor → %d\n", cn);
		fd = nil;
	}

	flashstatus("opened " + path + " in editor");
}

# ── Helpers ───────────────────────────────────────────────────

writectl(path, cmd: string)
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil) {
		flashstatus(sys->sprint("error: %r"));
		return;
	}
	b := array of byte cmd;
	n := sys->write(fd, b, len b);
	if(n < 0)
		flashstatus(sys->sprint("error: %r"));
}

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[4096] of byte;
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

flashstatus(msg: string)
{
	if(sbar != nil) {
		sbar.left = msg;
		dirty = 1;
	}
}
