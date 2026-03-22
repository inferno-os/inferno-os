implement Keyring;

#
# keyring - Factotum key manager for Lucifer
#
# A graphical keychain app that reads and manages keys stored in
# /mnt/factotum/ctl.  Provides a non-technical interface for adding,
# viewing, and deleting credentials used by the system (email, LLM
# API keys, authentication, etc.).
#
# The app itself does NOT store keys — factotum is the sole key store.
# This is a GUI front-end to factotum's ctl interface.
#
# Quick-add templates (via context menu):
#   Email Account    — creates service=imap + service=smtp keys
#   API Key          — creates service=<name> key (anthropic, openai, etc.)
#   Login            — generic service/domain/user/password
#   Advanced         — raw attribute editor
#
# Security:
#   The AI (Veltro) can launch this app and tell the user to add keys,
#   but cannot read /mnt/factotum/ctl itself — namespace isolation
#   ensures the AI never sees secrets.
#
# Mouse:
#   Button 1     select key / interact with fields
#   Button 3     context menu (add, delete, refresh)
#
# Keyboard:
#   Tab          cycle focus between fields
#   Enter        save key (in form) / confirm
#   Escape       cancel form / deselect
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

include "menu.m";
	menumod: Menu;
	Popup: import menumod;

include "string.m";
	str: String;

include "lucitheme.m";

include "widget.m";
	widgetmod: Widget;
	Scrollbar, Statusbar, Textfield, Listbox, Button, Kbdfilter: import widgetmod;

Keyring: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

# ── Key representation ────────────────────────────────────────

KeyEntry: adt {
	proto:    string;
	service:  string;
	dom:      string;
	user:     string;
	raw:      string;	# full attribute line from ctl
};

# ── Form modes ────────────────────────────────────────────────

ModeList, ModeEmail, ModeAPI, ModeLogin, ModeWallet, ModeAdvanced: con iota;

# ── State ─────────────────────────────────────────────────────

w: ref Window;
display_g: ref Display;
font: ref Font;
kf: ref Kbdfilter;
sbar: ref Statusbar;
keylist: ref Listbox;
mainmenu: ref Popup;
editmenu: ref Popup;
addmenu: ref Popup;

# Form fields
f_proto:    ref Textfield;
f_service:  ref Textfield;
f_dom:      ref Textfield;
f_user:     ref Textfield;
f_pass:     ref Textfield;
f_raw:      ref Textfield;	# advanced mode raw attrs
btn_save:   ref Button;
btn_delete: ref Button;
btn_cancel: ref Button;

# Colours
bgcolor:   ref Image;
formbg:    ref Image;
divcolor:  ref Image;

# App state
keys:       array of ref KeyEntry;
mode:       int;		# current form mode
formfields: array of ref Textfield;	# fields in current form
focusidx:   int;		# which field has focus
dirty:      int;		# redraw needed

stderr: ref Sys->FD;
themech: chan of int;

# ── Layout constants ─────────────────────────────────────────

DIVIDER_Y_FRAC: con 55;	# list takes 55% of height
FIELD_H: con 0;		# computed from font
FIELD_SPACING: con 4;
FORM_MARGIN: con Widget->FORM_MARGIN;
BTN_W: con 80;
BTN_H: con 0;			# computed from font

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	menumod = load Menu Menu->PATH;
	str = load String String->PATH;
	stderr = sys->fildes(2);

	if(ctxt == nil) {
		sys->fprint(stderr, "keyring: no window context\n");
		raise "fail:no context";
	}

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();
	sys->sleep(100);

	w = wmclient->window(ctxt, "Keyring", Wmclient->Appl);
	display_g = w.display;

	font = Font.open(display_g, "/fonts/combined/unicode.sans.14.font");
	if(font == nil)
		font = Font.open(display_g, "*default*");

	# Load theme colours
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme != nil) {
		th := lucitheme->gettheme();
		bgcolor  = display_g.color(th.editbg);
		formbg   = display_g.color(th.bg);
		divcolor = display_g.color(th.editlineno);
	} else {
		bgcolor  = display_g.color(int 16rFFFDF6FF);
		formbg   = display_g.color(int 16rF5F5F0FF);
		divcolor = display_g.color(int 16rBBBBBBFF);
	}

	# Init widget toolkit and menus
	if(widgetmod == nil)
		widgetmod = load Widget Widget->PATH;
	widgetmod->init(display_g, font);

	if(menumod != nil) {
		menumod->init(display_g, font);
		mainmenu = menumod->new(array[] of {
			"Add Email Account",
			"Add API Key",
			"Add Login",
			"Add Wallet Key",
			"Add Advanced",
			"",
			"Delete Selected",
			"",
			"Refresh",
		});
		addmenu = nil;
	}

	kf = Kbdfilter.new();

	w.reshape(Rect((0, 0), (420, 500)));
	w.startinput("kbd" :: "ptr" :: nil);
	w.onscreen(nil);

	# Initial layout
	mode = ModeList;
	focusidx = -1;
	layoutwidgets();

	# Load keys from factotum
	refreshkeys();
	dirty = 1;

	# Listen for live theme changes
	themech = chan of int;
	spawn themelistener();

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
				layoutwidgets();
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
		<-themech =>
			reloadcolors();
			layoutwidgets();
			dirty = 1;
		}
	}
}

# ── Layout ────────────────────────────────────────────────────

layoutwidgets()
{
	wr := w.imager(w.image.r);
	sh := widgetmod->statusheight();
	fh := font.height + 8;	# field height
	bh := font.height + 10;	# button height

	# Status bar at bottom
	sbr := Rect((wr.min.x, wr.max.y - sh), wr.max);
	if(sbar == nil)
		sbar = Statusbar.new(sbr);
	else
		sbar.resize(sbr);

	# Divider: list takes upper portion
	divy := wr.min.y + (wr.dy() - sh) * DIVIDER_Y_FRAC / 100;

	# Listbox: upper area
	listr := Rect(wr.min, (wr.max.x, divy));
	if(keylist == nil)
		keylist = Listbox.mk(listr);
	else
		keylist.resize(listr);

	# Form area: below divider, above status bar
	fx := wr.min.x + FORM_MARGIN;
	fy := divy + FORM_MARGIN + 2;	# +2 for divider line
	fw := wr.max.x - FORM_MARGIN;

	case mode {
	ModeEmail =>
		lw := widgetmod->labelwidth(array[] of {"Server:", "User:", "Password:"});
		f_dom     = Textfield.mk(Rect((fx, fy), (fw, fy + fh)), "Server:", 0);
		f_dom.labelw = lw;
		fy += fh + FIELD_SPACING;
		f_user    = Textfield.mk(Rect((fx, fy), (fw, fy + fh)), "User:", 0);
		f_user.labelw = lw;
		fy += fh + FIELD_SPACING;
		f_pass    = Textfield.mk(Rect((fx, fy), (fw, fy + fh)), "Password:", 1);
		f_pass.labelw = lw;
		fy += fh + FIELD_SPACING;
		formfields = array[] of { f_dom, f_user, f_pass };
	ModeAPI =>
		lw := widgetmod->labelwidth(array[] of {"Service:", "API Key:"});
		f_service = Textfield.mk(Rect((fx, fy), (fw, fy + fh)), "Service:", 0);
		f_service.labelw = lw;
		fy += fh + FIELD_SPACING;
		f_pass    = Textfield.mk(Rect((fx, fy), (fw, fy + fh)), "API Key:", 1);
		f_pass.labelw = lw;
		fy += fh + FIELD_SPACING;
		formfields = array[] of { f_service, f_pass };
	ModeLogin =>
		lw := widgetmod->labelwidth(array[] of {"Service:", "Domain:", "User:", "Password:"});
		f_service = Textfield.mk(Rect((fx, fy), (fw, fy + fh)), "Service:", 0);
		f_service.labelw = lw;
		fy += fh + FIELD_SPACING;
		f_dom     = Textfield.mk(Rect((fx, fy), (fw, fy + fh)), "Domain:", 0);
		f_dom.labelw = lw;
		fy += fh + FIELD_SPACING;
		f_user    = Textfield.mk(Rect((fx, fy), (fw, fy + fh)), "User:", 0);
		f_user.labelw = lw;
		fy += fh + FIELD_SPACING;
		f_pass    = Textfield.mk(Rect((fx, fy), (fw, fy + fh)), "Password:", 1);
		f_pass.labelw = lw;
		fy += fh + FIELD_SPACING;
		formfields = array[] of { f_service, f_dom, f_user, f_pass };
	ModeWallet =>
		lw := widgetmod->labelwidth(array[] of {"Name:", "Chain:", "Key:"});
		f_user    = Textfield.mk(Rect((fx, fy), (fw, fy + fh)), "Name:", 0);
		f_user.labelw = lw;
		fy += fh + FIELD_SPACING;
		f_service = Textfield.mk(Rect((fx, fy), (fw, fy + fh)), "Chain:", 0);
		f_service.labelw = lw;
		fy += fh + FIELD_SPACING;
		f_pass    = Textfield.mk(Rect((fx, fy), (fw, fy + fh)), "Key:", 1);
		f_pass.labelw = lw;
		fy += fh + FIELD_SPACING;
		if(f_service != nil)
			f_service.setval("eth");
		formfields = array[] of { f_user, f_service, f_pass };
	ModeAdvanced =>
		lw := widgetmod->labelwidth(array[] of {"Attrs:", "Secret:"});
		f_raw     = Textfield.mk(Rect((fx, fy), (fw, fy + fh)), "Attrs:", 0);
		f_raw.labelw = lw;
		fy += fh + FIELD_SPACING;
		f_pass    = Textfield.mk(Rect((fx, fy), (fw, fy + fh)), "Secret:", 1);
		f_pass.labelw = lw;
		fy += fh + FIELD_SPACING;
		formfields = array[] of { f_raw, f_pass };
	* =>
		formfields = nil;
	}

	# Buttons below fields
	if(mode != ModeList && formfields != nil) {
		bx := fx;
		btn_save   = Button.mk(Rect((bx, fy), (bx + BTN_W, fy + bh)), "Save");
		bx += BTN_W + FIELD_SPACING;
		btn_cancel = Button.mk(Rect((bx, fy), (bx + BTN_W, fy + bh)), "Cancel");
	} else {
		btn_save = nil;
		btn_cancel = nil;
	}

	# Delete button (always available when a key is selected)
	btn_delete = nil;
	if(mode == ModeList && keylist != nil && keylist.selected >= 0) {
		bx := fx;
		btn_delete = Button.mk(Rect((bx, fy), (bx + BTN_W, fy + bh)), "Delete");
	}

	# Set focus
	if(formfields != nil && len formfields > 0) {
		focusidx = 0;
		setfocus(0);
	} else
		focusidx = -1;
}

setfocus(idx: int)
{
	if(formfields == nil)
		return;
	for(i := 0; i < len formfields; i++)
		formfields[i].focused = 0;
	if(idx >= 0 && idx < len formfields) {
		formfields[idx].focused = 1;
		focusidx = idx;
	}
}

# ── Drawing ───────────────────────────────────────────────────

redraw()
{
	if(w.image == nil)
		return;
	wr := w.imager(w.image.r);

	# Clear background
	w.image.draw(wr, bgcolor, nil, Point(0, 0));

	# Listbox
	if(keylist != nil)
		keylist.draw(w.image);

	# Divider line and form area background
	sh := widgetmod->statusheight();
	divy := wr.min.y + (wr.dy() - sh) * DIVIDER_Y_FRAC / 100;
	w.image.draw(Rect((wr.min.x, divy), (wr.max.x, divy + 2)),
		     divcolor, nil, Point(0, 0));
	w.image.draw(Rect((wr.min.x, divy + 2), (wr.max.x, wr.max.y - sh)),
		     formbg, nil, Point(0, 0));

	# Form fields
	if(formfields != nil) {
		for(i := 0; i < len formfields; i++)
			formfields[i].draw(w.image);
	}

	# Buttons
	if(btn_save != nil)
		btn_save.draw(w.image);
	if(btn_cancel != nil)
		btn_cancel.draw(w.image);
	if(btn_delete != nil)
		btn_delete.draw(w.image);

	# Status bar
	if(sbar != nil) {
		nk := 0;
		if(keys != nil)
			nk = len keys;
		sbar.left = sys->sprint("%d key%s", nk, plural(nk));
		case mode {
		ModeList =>
			sbar.right = "B3: menu";
		* =>
			sbar.right = "Tab: next field";
		}
		sbar.draw(w.image);
	}

	w.image.flush(Draw->Flushnow);
}

plural(n: int): string
{
	if(n == 1)
		return "";
	return "s";
}

# ── Keyboard handling ─────────────────────────────────────────

handlekey(rawkey: int)
{
	k := kf.filter(rawkey);
	if(k < 0)
		return;

	# Ctrl-Q: quit
	if(k == 'q' - 'a' + 1) {
		cleanup();
		return;
	}

	# Escape: cancel form or deselect
	if(k == 27) {
		if(mode != ModeList) {
			mode = ModeList;
			layoutwidgets();
			dirty = 1;
		} else if(keylist != nil && keylist.selected >= 0) {
			keylist.selected = -1;
			layoutwidgets();
			dirty = 1;
		}
		return;
	}

	# Tab: cycle focus
	if(k == '\t') {
		if(formfields != nil && len formfields > 0) {
			focusidx = (focusidx + 1) % len formfields;
			setfocus(focusidx);
			dirty = 1;
		}
		return;
	}

	# Enter: save (if in form mode)
	if(k == '\n' && mode != ModeList) {
		savekey();
		return;
	}

	# Delete key in list mode: delete selected
	if(k == 16rFF9F && mode == ModeList) {
		deleteselected();
		return;
	}

	# Route to focused field
	if(formfields != nil && focusidx >= 0 && focusidx < len formfields) {
		formfields[focusidx].key(k);
		dirty = 1;
	}
}

# ── Pointer handling ──────────────────────────────────────────

handleptr(ptr: ref Pointer)
{
	if(ptr.buttons & 4) {
		# Button 3: context menu
		# In form mode with a focused field, show edit menu
		if(mode != ModeList && formfields != nil && focusidx >= 0) {
			if(editmenu == nil && menumod != nil) {
				editmenu = menumod->new(array[] of {
					"Paste",
					"Copy",
					"Cut",
				});
			}
			if(editmenu != nil) {
				sel := editmenu.show(w.image, ptr.xy, w.ctxt.ptr);
				handleeditmenu(sel);
			}
		} else if(mainmenu != nil) {
			sel := mainmenu.show(w.image, ptr.xy, w.ctxt.ptr);
			handlemenu(sel);
		}
		return;
	}

	if(!(ptr.buttons & 1))
		return;

	# Scrollbar tracking
	if(keylist != nil && keylist.scroll != nil && keylist.scroll.isactive()) {
		newo := keylist.scroll.track(ptr);
		if(newo >= 0) {
			keylist.top = newo;
			dirty = 1;
		}
		return;
	}

	# Check buttons
	if(btn_save != nil && btn_save.contains(ptr.xy)) {
		btn_save.pressed = 1;
		dirty = 1;
		# Wait for release
		for(;;) {
			p := <-w.ctxt.ptr;
			if(p == nil || !(p.buttons & 1)) {
				btn_save.pressed = 0;
				if(p != nil && btn_save.contains(p.xy))
					savekey();
				dirty = 1;
				return;
			}
		}
	}

	if(btn_cancel != nil && btn_cancel.contains(ptr.xy)) {
		btn_cancel.pressed = 1;
		dirty = 1;
		for(;;) {
			p := <-w.ctxt.ptr;
			if(p == nil || !(p.buttons & 1)) {
				btn_cancel.pressed = 0;
				if(p != nil && btn_cancel.contains(p.xy)) {
					mode = ModeList;
					layoutwidgets();
				}
				dirty = 1;
				return;
			}
		}
	}

	if(btn_delete != nil && btn_delete.contains(ptr.xy)) {
		btn_delete.pressed = 1;
		dirty = 1;
		for(;;) {
			p := <-w.ctxt.ptr;
			if(p == nil || !(p.buttons & 1)) {
				btn_delete.pressed = 0;
				if(p != nil && btn_delete.contains(p.xy))
					deleteselected();
				dirty = 1;
				return;
			}
		}
	}

	# Check listbox
	if(keylist != nil && keylist.contains(ptr.xy)) {
		sel := keylist.click(ptr.xy);
		if(sel >= 0) {
			mode = ModeList;
			layoutwidgets();
		}
		dirty = 1;
		return;
	}

	# Check form fields
	if(formfields != nil) {
		for(i := 0; i < len formfields; i++) {
			if(formfields[i].contains(ptr.xy)) {
				setfocus(i);
				formfields[i].click(ptr.xy);
				dirty = 1;
				return;
			}
		}
	}

	# Wheel scroll
	if(ptr.buttons & (8 | 16)) {
		if(keylist != nil) {
			keylist.wheel(ptr.buttons);
			dirty = 1;
		}
	}
}

handlemenu(sel: int)
{
	case sel {
	0 =>	# Add Email Account
		mode = ModeEmail;
		layoutwidgets();
		dirty = 1;
	1 =>	# Add API Key
		mode = ModeAPI;
		layoutwidgets();
		if(f_service != nil)
			f_service.setval("anthropic");
		dirty = 1;
	2 =>	# Add Login
		mode = ModeLogin;
		layoutwidgets();
		dirty = 1;
	3 =>	# Add Wallet Key
		mode = ModeWallet;
		layoutwidgets();
		dirty = 1;
	4 =>	# Add Advanced
		mode = ModeAdvanced;
		layoutwidgets();
		dirty = 1;
	6 =>	# Delete Selected
		deleteselected();
	8 =>	# Refresh
		refreshkeys();
		dirty = 1;
	}
}

handleeditmenu(sel: int)
{
	if(formfields == nil || focusidx < 0 || focusidx >= len formfields)
		return;
	tf := formfields[focusidx];
	case sel {
	0 =>	# Paste
		tf.key(22);	# Ctrl-V
		dirty = 1;
	1 =>	# Copy
		tf.key(3);	# Ctrl-C
	2 =>	# Cut
		tf.key(24);	# Ctrl-X
		dirty = 1;
	}
}

# ── Factotum interaction ──────────────────────────────────────

refreshkeys()
{
	fd := sys->open("/mnt/factotum/ctl", Sys->OREAD);
	if(fd == nil) {
		sbar.left = "factotum not available";
		keys = nil;
		updatelist();
		return;
	}

	buf := array[8192] of byte;
	all := "";
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		all += string buf[0:n];
	}

	# Parse lines
	klist: list of ref KeyEntry;
	nk := 0;
	s := all;
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

		# Skip "key " prefix if present
		if(len line > 4 && line[0:4] == "key ")
			line = line[4:];

		if(len line == 0)
			continue;

		ke := parsekeyline(line);
		klist = ke :: klist;
		nk++;
	}

	# Reverse into array
	keys = array[nk] of ref KeyEntry;
	for(j := nk - 1; j >= 0; j--) {
		keys[j] = hd klist;
		klist = tl klist;
	}

	updatelist();
}

parsekeyline(line: string): ref KeyEntry
{
	ke := ref KeyEntry("", "", "", "", line);

	# Tokenize on spaces, respecting quotes
	s := line;
	while(len s > 0) {
		# Skip whitespace
		while(len s > 0 && (s[0] == ' ' || s[0] == '\t'))
			s = s[1:];
		if(len s == 0)
			break;

		# Extract token
		tok: string;
		if(s[0] == '\'') {
			# Quoted token
			s = s[1:];
			end := 0;
			for(end = 0; end < len s; end++)
				if(s[end] == '\'')
					break;
			tok = s[0:end];
			if(end < len s)
				s = s[end + 1:];
			else
				s = "";
		} else {
			end := 0;
			for(end = 0; end < len s; end++)
				if(s[end] == ' ' || s[end] == '\t')
					break;
			tok = s[0:end];
			s = s[end:];
		}

		# Parse name=value or name? or !name?
		nm := tok;
		val := "";
		for(i := 0; i < len tok; i++) {
			if(tok[i] == '=') {
				nm = tok[0:i];
				val = tok[i + 1:];
				break;
			}
		}

		# Strip leading ! for secret attrs
		rnm := nm;
		if(len rnm > 0 && rnm[0] == '!')
			rnm = rnm[1:];

		case rnm {
		"proto" =>
			ke.proto = val;
		"service" =>
			ke.service = val;
		"dom" =>
			ke.dom = val;
		"user" =>
			ke.user = val;
		}
	}

	return ke;
}

updatelist()
{
	if(keylist == nil)
		return;
	if(keys == nil || len keys == 0) {
		keylist.setitems(array[] of { "(no keys — right-click to add)" });
		return;
	}
	items := array[len keys] of string;
	for(i := 0; i < len keys; i++)
		items[i] = keylabel(keys[i]);
	keylist.setitems(items);
}

keylabel(ke: ref KeyEntry): string
{
	s := "";
	if(ke.proto != nil && len ke.proto > 0)
		s += ke.proto;
	else
		s += "?";

	if(ke.service != nil && len ke.service > 0)
		s += "  " + ke.service;

	if(ke.dom != nil && len ke.dom > 0)
		s += "  " + ke.dom;

	if(ke.user != nil && len ke.user > 0)
		s += "  user=" + ke.user;

	return s;
}

savekey()
{
	attrs := "";

	case mode {
	ModeEmail =>
		dom := f_dom.value();
		user := f_user.value();
		pass := f_pass.value();
		if(dom == "" || user == "" || pass == "") {
			flashstatus("error: fill all fields");
			return;
		}
		# Create two keys: imap and smtp
		imapkey := sys->sprint("key proto=pass service=imap dom=%s user=%s !password=%s",
				       dom, user, pass);
		smtpkey := sys->sprint("key proto=pass service=smtp dom=%s user=%s !password=%s",
				       dom, user, pass);
		if(writectl(imapkey) < 0)
			return;
		if(writectl(smtpkey) < 0)
			return;
		writectl("sync");	# persist to keyfile/secstore
		flashstatus("added email keys");
		mode = ModeList;
		layoutwidgets();
		refreshkeys();
		dirty = 1;
		return;

	ModeAPI =>
		svc := f_service.value();
		pass := f_pass.value();
		if(svc == "" || pass == "") {
			flashstatus("error: fill all fields");
			return;
		}
		attrs = sys->sprint("key proto=pass service=%s !password=%s", svc, pass);

	ModeLogin =>
		svc := f_service.value();
		dom := "";
		if(f_dom != nil)
			dom = f_dom.value();
		user := f_user.value();
		pass := f_pass.value();
		if(svc == "" || user == "" || pass == "") {
			flashstatus("error: fill service, user, and password");
			return;
		}
		attrs = "key proto=pass";
		attrs += " service=" + svc;
		if(dom != "")
			attrs += " dom=" + dom;
		attrs += " user=" + user;
		attrs += " !password=" + pass;

	ModeWallet =>
		wname := f_user.value();
		chain := f_service.value();
		wkey := f_pass.value();
		if(wname == "" || chain == "" || wkey == "") {
			flashstatus("error: fill all fields");
			return;
		}
		# Build wallet key: proto=pass service=wallet-{chain}-{name} user=key !password={hex}
		svc := "wallet-" + chain + "-" + wname;
		attrs = sys->sprint("key proto=pass service=%s user=key !password=%s", svc, wkey);

	ModeAdvanced =>
		raw := f_raw.value();
		pass := f_pass.value();
		if(raw == "") {
			flashstatus("error: enter attributes");
			return;
		}
		# Auto-add proto=pass if no proto= specified
		if(!strcontains(raw, "proto="))
			raw = "proto=pass " + raw;
		attrs = "key " + raw;
		if(pass != "")
			attrs += " !password=" + pass;
	}

	if(attrs != "") {
		if(writectl(attrs) < 0)
			return;
		writectl("sync");	# persist to keyfile/secstore
		flashstatus("key added");
		mode = ModeList;
		layoutwidgets();
		refreshkeys();
		dirty = 1;
	}
}

writectl(cmd: string): int
{
	fd := sys->open("/mnt/factotum/ctl", Sys->OWRITE);
	if(fd == nil) {
		msg := sys->sprint("error: %r");
		flashstatus(msg);
		sys->fprint(stderr, "keyring: %s\n", msg);
		return -1;
	}
	b := array of byte cmd;
	n := sys->write(fd, b, len b);
	if(n < 0) {
		msg := sys->sprint("error: %r");
		flashstatus(msg);
		sys->fprint(stderr, "keyring: %s\n", msg);
		return -1;
	}
	return 0;
}

deleteselected()
{
	if(keylist == nil || keylist.selected < 0)
		return;
	if(keys == nil || keylist.selected >= len keys)
		return;

	ke := keys[keylist.selected];

	# Build delkey command from public attributes
	cmd := "delkey";
	if(ke.proto != "")
		cmd += " proto=" + ke.proto;
	if(ke.service != "")
		cmd += " service=" + ke.service;
	if(ke.dom != "")
		cmd += " dom=" + ke.dom;
	if(ke.user != "")
		cmd += " user=" + ke.user;

	if(writectl(cmd) < 0)
		return;
	writectl("sync");	# persist to keyfile/secstore

	flashstatus("key deleted");
	refreshkeys();
	layoutwidgets();
	dirty = 1;
}

flashstatus(msg: string)
{
	if(sbar != nil) {
		sbar.left = msg;
		dirty = 1;
	}
}

themelistener()
{
	fd := sys->open("/n/ui/event", Sys->OREAD);
	if(fd == nil)
		return;
	buf := array[256] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		ev := string buf[0:n];
		if(len ev >= 6 && ev[0:6] == "theme ")
			alt { themech <-= 1 => ; * => ; }
	}
}

reloadcolors()
{
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme != nil) {
		th := lucitheme->gettheme();
		bgcolor  = display_g.color(th.editbg);
		formbg   = display_g.color(th.bg);
		divcolor = display_g.color(th.editlineno);
	}
	widgetmod->retheme(display_g);
	if(menumod != nil)
		menumod->init(display_g, font);
}

strcontains(s, sub: string): int
{
	ls := len s;
	lsub := len sub;
	if(lsub > ls)
		return 0;
	for(i := 0; i <= ls - lsub; i++)
		if(s[i:i+lsub] == sub)
			return 1;
	return 0;
}

cleanup()
{
	sys->fprint(stderr, "");	# nop to suppress warning
	exit;
}
