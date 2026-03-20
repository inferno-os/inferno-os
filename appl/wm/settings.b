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
	Scrollbar, Statusbar, Textfield, Listbox, Button, Label, Checkbox, Radio, RadioGroup, Kbdfilter, LEFT, CENTER: import widgetmod;

Settings: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

# ── Categories ─────────────────────────────────────────────────

CatTheme, CatLLM, CatTools, CatBudget, CatPaths, CatPrompts, CatProfile: con iota;
NCATS: con 7;

catnames := array[] of {
	"Theme",
	"LLM Service",
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
theme_group: ref RadioGroup;
theme_names: array of string;

# LLM panel — local or remote
llm_mode_group: ref RadioGroup;
llm_mode_names := array[] of { "local", "remote" };
llm_mode_labels := array[] of { "Local", "Remote (9P)" };
llm_conn_hdr: ref Label;
llm_backend_group: ref RadioGroup;
llm_backend_names := array[] of { "api", "openai" };
llm_backend_labels := array[] of { "Anthropic API", "Ollama / OpenAI-compatible" };
llm_backend_hdr: ref Label;
llm_url_label: ref Label;
llm_url_tf: ref Textfield;
llm_model_label: ref Label;
llm_model_tf: ref Textfield;
llm_key_label: ref Label;
llm_dial_label: ref Label;
llm_dial_tf: ref Textfield;
llm_apply_btn: ref Button;
llm_save_btn: ref Button;
llm_is_remote: int;
llm_mode_set: int;		# 1 after first layout or click — suppresses config re-read

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

	font = Font.open(display_g, "/fonts/combined/unicode.sans.14.font");
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
	theme_group = nil;
	llm_mode_group = nil;
	llm_conn_hdr = nil;
	llm_backend_group = nil;
	llm_backend_hdr = nil;
	llm_url_label = nil;
	llm_url_tf = nil;
	llm_model_label = nil;
	llm_model_tf = nil;
	llm_key_label = nil;
	llm_dial_label = nil;
	llm_dial_tf = nil;
	llm_apply_btn = nil;
	llm_save_btn = nil;
	# Reset mode tracking when leaving LLM category
	if(category != CatLLM) {
		llm_is_remote = 0;
		llm_mode_set = 0;
	}
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
	CatLLM =>
		layoutllm(cx, cy, cw, fh, bh, ch);
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

	sel := -1;
	for(i := 0; i < len theme_names; i++)
		if(theme_names[i] == current) {
			sel = i;
			break;
		}
	rowh := ch + FIELD_SPACING;
	theme_group = RadioGroup.mk(Point(cx, cy), cw - cx, theme_names, sel, rowh);
}

layoutllm(cx, cy, cw, fh, bh, ch: int)
{
	(curmode, curbackend, cururl, curmodel, curdial, haskey) := readllmconfig();
	# On first entry, set mode from config; on re-layout after a radio
	# click, llm_is_remote was already set by clickllm — preserve it.
	if(!llm_mode_set)
		llm_is_remote = curmode == "remote";
	llm_mode_set = 1;
	if(llm_is_remote)
		curmode = "remote";
	else
		curmode = "local";

	rowh := ch + FIELD_SPACING;

	# Section header: Connection
	llm_conn_hdr = Label.mk(Rect((cx, cy), (cw, cy + fh)), "Connection", 1, LEFT);
	cy += fh;

	# Mode group: Local vs Remote
	msel := 0;
	for(i := 0; i < len llm_mode_names; i++)
		if(llm_mode_names[i] == curmode) {
			msel = i;
			break;
		}
	llm_mode_group = RadioGroup.mk(Point(cx, cy), cw - cx, llm_mode_labels, msel, rowh);
	cy += len llm_mode_names * rowh;
	cy += MARGIN;

	if(llm_is_remote) {
		# Remote mode: just a dial address
		llm_dial_label = Label.mk(
			Rect((cx, cy), (cw, cy + fh)),
			"Dial address:", 0, LEFT);
		cy += fh;
		llm_dial_tf = Textfield.mk(
			Rect((cx, cy), (cw, cy + fh)),
			"", 0);
		llm_dial_tf.setval(curdial);
		llm_dial_tf.focused = 1;
		cy += fh + MARGIN;
	} else {
		# Section header: Backend
		llm_backend_hdr = Label.mk(Rect((cx, cy), (cw, cy + fh)), "Backend", 1, LEFT);
		cy += fh;

		# Backend group: Anthropic API vs Ollama/OpenAI
		bsel := 0;
		for(i = 0; i < len llm_backend_names; i++)
			if(llm_backend_names[i] == curbackend) {
				bsel = i;
				break;
			}
		llm_backend_group = RadioGroup.mk(Point(cx, cy), cw - cx, llm_backend_labels, bsel, rowh);
		cy += len llm_backend_names * rowh;
		cy += MARGIN;

		# URL
		llm_url_label = Label.mk(
			Rect((cx, cy), (cw, cy + fh)),
			"Endpoint URL:", 0, LEFT);
		cy += fh;
		llm_url_tf = Textfield.mk(
			Rect((cx, cy), (cw, cy + fh)),
			"", 0);
		llm_url_tf.setval(cururl);
		cy += fh + MARGIN;

		# Model
		llm_model_label = Label.mk(
			Rect((cx, cy), (cw, cy + fh)),
			"Model:", 0, LEFT);
		cy += fh;
		llm_model_tf = Textfield.mk(
			Rect((cx, cy), (cw, cy + fh)),
			"", 0);
		llm_model_tf.setval(curmodel);
		llm_model_tf.focused = 1;
		cy += fh + MARGIN;

		# API key status
		keystatus: string;
		if(haskey)
			keystatus = "API key: configured";
		else
			keystatus = "API key: not set (check factotum or ANTHROPIC_API_KEY)";
		llm_key_label = Label.mk(
			Rect((cx, cy), (cw, cy + fh)),
			keystatus, 0, LEFT);
		cy += fh + MARGIN;
	}

	# Buttons
	llm_apply_btn = Button.mk(
		Rect((cx, cy), (cx + BTN_W, cy + bh)),
		"Apply");
	savew := BTN_W + 40;
	llm_save_btn = Button.mk(
		Rect((cx + BTN_W + MARGIN, cy),
		     (cx + BTN_W + MARGIN + savew, cy + bh)),
		"Save to Profile");
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
			label, 0, LEFT);
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
		"Startup profile: /lib/sh/profile", 0, LEFT);
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
		if(theme_group != nil)
			theme_group.draw(w.image);
	CatLLM =>
		drawllm();
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
		CatLLM =>
			if(llm_is_remote)
				sbar.right = "dial + mount on apply";
			else
				sbar.right = "restart required";
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

drawllm()
{
	if(llm_conn_hdr != nil)
		llm_conn_hdr.draw(w.image);
	if(llm_mode_group != nil)
		llm_mode_group.draw(w.image);
	if(llm_is_remote) {
		if(llm_dial_label != nil)
			llm_dial_label.draw(w.image);
		if(llm_dial_tf != nil)
			llm_dial_tf.draw(w.image);
	} else {
		if(llm_backend_hdr != nil)
			llm_backend_hdr.draw(w.image);
		if(llm_backend_group != nil)
			llm_backend_group.draw(w.image);
		if(llm_url_label != nil)
			llm_url_label.draw(w.image);
		if(llm_url_tf != nil)
			llm_url_tf.draw(w.image);
		if(llm_model_label != nil)
			llm_model_label.draw(w.image);
		if(llm_model_tf != nil)
			llm_model_tf.draw(w.image);
		if(llm_key_label != nil)
			llm_key_label.draw(w.image);
	}
	if(llm_apply_btn != nil)
		llm_apply_btn.draw(w.image);
	if(llm_save_btn != nil)
		llm_save_btn.draw(w.image);
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

	# Route to LLM textfields
	if(category == CatLLM) {
		if(k == '\n') {
			applyllm();
			return;
		}
		if(llm_is_remote) {
			if(llm_dial_tf != nil) {
				llm_dial_tf.key(k);
				dirty = 1;
			}
		} else {
			if(k == '\t') {
				# Toggle focus between URL and model fields
				if(llm_url_tf != nil && llm_model_tf != nil) {
					if(llm_url_tf.focused) {
						llm_url_tf.focused = 0;
						llm_model_tf.focused = 1;
					} else {
						llm_model_tf.focused = 0;
						llm_url_tf.focused = 1;
					}
					dirty = 1;
				}
				return;
			}
			if(llm_url_tf != nil && llm_url_tf.focused) {
				llm_url_tf.key(k);
				dirty = 1;
			} else if(llm_model_tf != nil && llm_model_tf.focused) {
				llm_model_tf.key(k);
				dirty = 1;
			}
		}
		return;
	}

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
	CatLLM =>
		clickllm(ptr);
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
	if(theme_group == nil)
		return;
	i := theme_group.click(ptr.xy);
	if(i >= 0 && i < len theme_names) {
		applytheme(theme_names[i]);
		dirty = 1;
	}
}

clickllm(ptr: ref Pointer)
{
	# Mode group: Local / Remote
	if(llm_mode_group != nil && llm_mode_group.contains(ptr.xy)) {
		i := llm_mode_group.click(ptr.xy);
		if(i >= 0) {
			wasremote := llm_is_remote;
			llm_is_remote = i < len llm_mode_names && llm_mode_names[i] == "remote";
			if(wasremote != llm_is_remote)
				layoutcontent();
			dirty = 1;
		}
		return;
	}

	if(llm_is_remote) {
		# Remote mode: dial textfield
		if(llm_dial_tf != nil && llm_dial_tf.contains(ptr.xy)) {
			llm_dial_tf.focused = 1;
			llm_dial_tf.click(ptr.xy);
			dirty = 1;
			return;
		}
	} else {
		# Local mode: backend group, URL, model
		if(llm_backend_group != nil && llm_backend_group.contains(ptr.xy)) {
			i := llm_backend_group.click(ptr.xy);
			if(i >= 0 && i < len llm_backend_names) {
				# Update URL default when switching backend
				if(llm_backend_names[i] == "openai" && llm_url_tf != nil) {
					cur := strip(llm_url_tf.value());
					if(cur == "" || cur == "https://api.anthropic.com")
						llm_url_tf.setval("http://localhost:11434/v1");
				} else if(llm_backend_names[i] == "api" && llm_url_tf != nil) {
					cur := strip(llm_url_tf.value());
					if(cur == "" || cur == "http://localhost:11434/v1")
						llm_url_tf.setval("https://api.anthropic.com");
				}
				dirty = 1;
			}
			return;
		}
		if(llm_url_tf != nil && llm_url_tf.contains(ptr.xy)) {
			if(llm_model_tf != nil)
				llm_model_tf.focused = 0;
			llm_url_tf.focused = 1;
			llm_url_tf.click(ptr.xy);
			dirty = 1;
			return;
		}
		if(llm_model_tf != nil && llm_model_tf.contains(ptr.xy)) {
			if(llm_url_tf != nil)
				llm_url_tf.focused = 0;
			llm_model_tf.focused = 1;
			llm_model_tf.click(ptr.xy);
			dirty = 1;
			return;
		}
	}

	if(llm_apply_btn != nil && llm_apply_btn.contains(ptr.xy)) {
		trackllmapply(ptr);
		return;
	}
	if(llm_save_btn != nil && llm_save_btn.contains(ptr.xy)) {
		trackllmsave(ptr);
		return;
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
	# Write to /n/ui/ctl for live theme switching across all zones.
	# luciuisrv persists the choice to /lib/lucifer/theme/current and
	# broadcasts a "theme <name>" global event so every zone reloads.
	fd := sys->open("/n/ui/ctl", Sys->OWRITE);
	if(fd != nil) {
		cmd := "theme " + name;
		b := array of byte cmd;
		sys->write(fd, b, len b);
		flashstatus("theme set to " + name);
		return;
	}
	# Fallback: write directly (pre-luciuisrv or standalone mode)
	fd = sys->open("/lib/lucifer/theme/current", Sys->OWRITE|Sys->OTRUNC);
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

trackllmapply(nil: ref Pointer)
{
	llm_apply_btn.pressed = 1;
	dirty = 1;
	redraw();
	for(;;) {
		p := <-w.ctxt.ptr;
		if(p == nil || !(p.buttons & 1)) {
			llm_apply_btn.pressed = 0;
			if(p != nil && llm_apply_btn.contains(p.xy))
				applyllm();
			dirty = 1;
			return;
		}
	}
}

trackllmsave(nil: ref Pointer)
{
	llm_save_btn.pressed = 1;
	dirty = 1;
	redraw();
	for(;;) {
		p := <-w.ctxt.ptr;
		if(p == nil || !(p.buttons & 1)) {
			llm_save_btn.pressed = 0;
			if(p != nil && llm_save_btn.contains(p.xy))
				savellmtoprofile();
			dirty = 1;
			return;
		}
	}
}

savellmtoprofile()
{
	# Read current profile
	profile := readfile("/lib/sh/profile");
	if(profile == nil) {
		flashstatus("cannot read /lib/sh/profile");
		return;
	}

	# Build the replacement LLM line
	newline: string;
	if(llm_is_remote) {
		addr := "";
		if(llm_dial_tf != nil)
			addr = strip(llm_dial_tf.value());
		if(len addr == 0) {
			flashstatus("enter a dial address first");
			return;
		}
		newline = "\tmount -A '" + addr + "' /n/llm >[2] /dev/null";
	} else {
		backend := "api";
		if(llm_backend_group != nil) {
			bi := llm_backend_group.selected();
			if(bi >= 0 && bi < len llm_backend_names)
				backend = llm_backend_names[bi];
		}
		url := "";
		if(llm_url_tf != nil)
			url = strip(llm_url_tf.value());
		model := "";
		if(llm_model_tf != nil)
			model = strip(llm_model_tf.value());

		cmd := "\tllmsrv";
		if(backend != "api")
			cmd += " -b " + backend;
		if(backend == "openai" && len url > 0
		   && url != "http://localhost:11434/v1")
			cmd += " -u " + url;
		else if(backend == "api" && len url > 0
			&& url != "https://api.anthropic.com")
			cmd += " -u " + url;
		if(len model > 0 && model != "claude-sonnet-4-5-20250929")
			cmd += " -M " + model;
		cmd += " >[2] /dev/null &";
		newline = cmd;
	}

	# Find and replace the LLM line in the profile.
	# Strategy: look for "# BEGIN LLM" / "# END LLM" markers first
	# (from a previous save), else find the bare llmsrv line.
	BEGIN_MARKER: con "# BEGIN LLM";
	END_MARKER: con "# END LLM";

	out := "";
	found := 0;

	bi := strindex(profile, BEGIN_MARKER);
	if(bi >= 0) {
		ei := strindex(profile[bi:], END_MARKER);
		if(ei >= 0) {
			out = profile[0:bi];
			out += BEGIN_MARKER + "\n" + newline + "\n\t" + END_MARKER;
			after := bi + ei + len END_MARKER;
			while(after < len profile && profile[after] != '\n')
				after++;
			if(after < len profile)
				out += profile[after:];
			found = 1;
		}
	}

	if(!found) {
		# Find the bare "llmsrv" line and wrap it with markers
		lines: list of string;
		rest := profile;
		while(len rest > 0) {
			eol := len rest;
			for(j := 0; j < len rest; j++) {
				if(rest[j] == '\n') {
					eol = j;
					break;
				}
			}
			line: string;
			if(eol < len rest) {
				line = rest[0:eol];
				rest = rest[eol + 1:];
			} else {
				line = rest;
				rest = "";
			}

			trimmed := strip(line);
			if(hassubstr(trimmed, "llmsrv") && !hassubstr(trimmed, "#")) {
				lines = ("\t" + BEGIN_MARKER + "\n" + newline + "\n\t" + END_MARKER) :: lines;
				found = 1;
			} else
				lines = line :: lines;
		}

		if(found) {
			rlines: list of string;
			for(l := lines; l != nil; l = tl l)
				rlines = (hd l) :: rlines;
			out = "";
			for(l = rlines; l != nil; l = tl l) {
				out += hd l;
				if(tl l != nil)
					out += "\n";
			}
		}
	}

	if(!found) {
		flashstatus("could not find llmsrv line in profile");
		return;
	}

	# Write back
	fd := sys->open("/lib/sh/profile", Sys->OWRITE);
	if(fd == nil) {
		flashstatus(sys->sprint("cannot write profile: %r"));
		return;
	}
	b := array of byte out;
	sys->write(fd, b, len b);
	flashstatus("profile updated — takes effect on restart");
}

strindex(s, sub: string): int
{
	slen := len s;
	sublen := len sub;
	if(sublen > slen)
		return -1;
	for(i := 0; i <= slen - sublen; i++) {
		if(s[i:i + sublen] == sub)
			return i;
	}
	return -1;
}

applyllm()
{
	if(llm_is_remote) {
		# Remote mode: dial + mount at /n/llm
		addr := "";
		if(llm_dial_tf != nil)
			addr = strip(llm_dial_tf.value());
		if(len addr == 0) {
			flashstatus("enter a dial address (e.g. tcp!host!5640)");
			return;
		}
		writellmconfig("remote", "", "", "", addr);
		mountremotellm(addr);
		return;
	}

	# Local mode: determine selected backend
	backend := "api";
	if(llm_backend_group != nil) {
		bi := llm_backend_group.selected();
		if(bi >= 0 && bi < len llm_backend_names)
			backend = llm_backend_names[bi];
	}

	url := "";
	if(llm_url_tf != nil)
		url = strip(llm_url_tf.value());
	model := "";
	if(llm_model_tf != nil)
		model = strip(llm_model_tf.value());

	writellmconfig("local", backend, url, model, "");
	flashstatus("LLM config saved — restart llmsrv for backend/URL changes");
}

mountremotellm(addr: string)
{
	# Unmount any existing /n/llm mount first (ignore errors)
	sys->unmount(nil, "/n/llm");

	(ok, c) := sys->dial(addr, nil);
	if(ok < 0) {
		flashstatus(sys->sprint("dial %s failed: %r", addr));
		return;
	}

	n := sys->mount(c.dfd, nil, "/n/llm", Sys->MREPL, "");
	if(n < 0) {
		flashstatus(sys->sprint("mount /n/llm failed: %r"));
		return;
	}

	flashstatus("mounted remote LLM at /n/llm from " + addr);
}

readllmconfig(): (string, string, string, string, string, int)
{
	# Returns (mode, backend, url, model, dial, haskey)
	mode := "local";
	backend := "api";
	url := "https://api.anthropic.com";
	model := "claude-sonnet-4-5-20250929";
	dial := "tcp!hephaestus!5640";
	haskey := 0;

	lines := readlines("/lib/lucifer/llm");
	if(lines != nil) {
		for(i := 0; i < len lines; i++) {
			line := lines[i];
			if(len line > 5 && line[0:5] == "mode=")
				mode = line[5:];
			else if(len line > 8 && line[0:8] == "backend=")
				backend = line[8:];
			else if(len line > 4 && line[0:4] == "url=")
				url = line[4:];
			else if(len line > 6 && line[0:6] == "model=")
				model = line[6:];
			else if(len line > 5 && line[0:5] == "dial=")
				dial = line[5:];
		}
	}

	# Set default URL based on backend if not specified
	if(url == "" || url == "https://api.anthropic.com") {
		if(backend == "openai")
			url = "http://localhost:11434/v1";
		else
			url = "https://api.anthropic.com";
	}

	# Check for API key in factotum
	fd := sys->open("/mnt/factotum/ctl", Sys->OREAD);
	if(fd != nil) {
		buf := array[4096] of byte;
		n := sys->read(fd, buf, len buf);
		if(n > 0) {
			content := string buf[0:n];
			if(hassubstr(content, "anthropic") || hassubstr(content, "llm"))
				haskey = 1;
		}
	}

	return (mode, backend, url, model, dial, haskey);
}

writellmconfig(mode, backend, url, model, dial: string)
{
	fd := sys->create("/lib/lucifer/llm", Sys->OWRITE, 8r666);
	if(fd == nil) {
		# Try creating the directory first
		dfd := sys->create("/lib/lucifer", Sys->OREAD, Sys->DMDIR | 8r777);
		if(dfd != nil)
			dfd = nil;
		fd = sys->create("/lib/lucifer/llm", Sys->OWRITE, 8r666);
	}
	if(fd == nil) {
		flashstatus(sys->sprint("cannot write config: %r"));
		return;
	}
	config := sys->sprint("mode=%s\nbackend=%s\nurl=%s\nmodel=%s\ndial=%s\n",
		mode, backend, url, model, dial);
	b := array of byte config;
	sys->write(fd, b, len b);
}

hassubstr(s, sub: string): int
{
	slen := len s;
	sublen := len sub;
	if(sublen > slen)
		return 0;
	for(i := 0; i <= slen - sublen; i++) {
		if(s[i:i+sublen] == sub)
			return 1;
	}
	return 0;
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
