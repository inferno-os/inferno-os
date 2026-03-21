#
# widget.m — Native Limbo widget toolkit
#
# Composable, theme-driven, flat-drawn UI widgets for Lucifer apps.
# The app owns the window; widgets are helpers, not managers.
#
# Design principles:
#   - Limbo-native: ADTs, not string commands
#   - Channel-composable: fits into alt{} event loops
#   - Flat-drawn: modern subdued aesthetic
#   - Theme-driven: colours from lucitheme, apps don't override
#   - Minimal: load as needed, not a monolithic runtime
#   - AI-transparent: widgets are visual chrome for the human;
#     the AI sees content (text, cursor, viewport), not scrollbar
#     positions or button states
#
# Scroll conventions (macOS-primary, Plan 9-compatible):
#   B1 click above/below thumb — page up/down
#   B1 drag on thumb — continuous tracking
#   B2 click anywhere — absolute position jump (Plan 9 bonus)
#   Scroll wheel (button 8/16) — step up/down
#

Widget: module
{
	PATH: con "/dis/lib/widget.dis";

	# Initialise module.  Must be called once before creating widgets.
	# Loads theme colours; font is used for status bar text.
	init: fn(display: ref Draw->Display, font: ref Draw->Font);

	# Reload colours from current theme (e.g. after theme switch).
	retheme: fn(display: ref Draw->Display);

	# Scrollbar width in pixels.
	scrollwidth: fn(): int;

	# Status bar height in pixels (font.height + padding).
	statusheight: fn(): int;

	# Compute aligned label width for a group of text fields.
	# Returns the width of the widest label plus gap, suitable
	# for setting Textfield.labelw on each field in the group.
	labelwidth: fn(labels: array of string): int;

	# ── Key constants ─────────────────────────────────────────
	#
	# Standard Inferno keyboard codes for special keys.
	# Shared by all Draw-based apps (editor, shell, etc.).
	#
	Khome:   con 16rFF61;
	Kend:    con 16rFF57;
	Kup:     con 16rFF52;
	Kdown:   con 16rFF54;
	Kleft:   con 16rFF51;
	Kright:  con 16rFF53;
	Kpgup:   con 16rFF55;
	Kpgdown: con 16rFF56;
	Kdel:    con 16rFF9F;
	Kins:    con 16rFF63;
	Kbs:     con 8;
	Kesc:    con 27;

	# ── Kbdfilter ─────────────────────────────────────────────
	#
	# Decodes ANSI escape sequences from hosted keyboard input
	# into Inferno key constants.  Each instance maintains its
	# own state machine, so multiple apps can decode independently.
	#
	# Usage:
	#   kf := Kbdfilter.new();
	#   ...
	#   key := kf.filter(rawkey);
	#   if(key >= 0)
	#       handlekey(key);
	#
	Kbdfilter: adt {
		state: int;		# escape decode state (0 = ground)
		arg:   int;		# numeric argument accumulator

		# Create a new keyboard filter in ground state.
		new:    fn(): ref Kbdfilter;

		# Filter a raw key code.  Returns the decoded key,
		# or -1 if the character is part of an incomplete
		# escape sequence.  Inferno key codes (>= 0xFF00)
		# pass through unchanged.
		filter: fn(kf: self ref Kbdfilter, c: int): int;
	};

	# ── Scrollbar ──────────────────────────────────────────────
	#
	# Flat, subdued scrollbar.  Operates on abstract units —
	# the app decides what total/visible/origin mean (lines,
	# pixels, characters).
	#
	# Scroll behaviour:
	#   B1 above/below thumb → page up/down
	#   B1 on thumb + drag   → continuous tracking
	#   B2 click             → absolute position jump
	#   Wheel (button 8/16)  → step up/down
	#
	# The scrollbar tracks drag state internally.  Typical usage:
	#
	#   if(sb.isactive()) {
	#       newo := sb.track(p);
	#       if(newo >= 0) { origin = newo; redraw(); }
	#   } else if(scrollr.contains(p.xy) && (p.buttons & 3)) {
	#       newo := sb.event(p);
	#       if(newo >= 0) { origin = newo; redraw(); }
	#   }
	#
	Scrollbar: adt {
		r:       Draw->Rect;    # scrollbar rectangle on screen
		total:   int;           # total content units
		visible: int;           # visible content units
		origin:  int;           # current top/left position
		vert:    int;           # 1 = vertical, 0 = horizontal

		# Create a scrollbar for the given rectangle.
		# vert: 1 for vertical (default), 0 for horizontal.
		new:     fn(r: Draw->Rect, vert: int): ref Scrollbar;

		# Draw the scrollbar into dst.
		# Caller must update total/visible/origin before calling.
		draw:    fn(sb: self ref Scrollbar, dst: ref Draw->Image);

		# Update rectangle (e.g. on window resize).
		resize:  fn(sb: self ref Scrollbar, r: Draw->Rect);

		# Handle a pointer event (B1 or B2 down).
		# Returns new origin, or -1 if not consumed.
		# If B1 lands on the thumb, starts internal drag state.
		event:   fn(sb: self ref Scrollbar,
			    p: ref Draw->Pointer): int;

		# Continue tracking while a drag or B2 hold is active.
		# Call on every pointer event while isactive() is true.
		# Returns new origin, or -1 if drag ended (button up).
		track:   fn(sb: self ref Scrollbar,
			    p: ref Draw->Pointer): int;

		# Query whether a drag/track is in progress.
		isactive: fn(sb: self ref Scrollbar): int;

		# Wheel scroll.  button is 8 (up) or 16 (down).
		# step is units to scroll (e.g. 3 for lines).
		# Returns new clamped origin.
		wheel:   fn(sb: self ref Scrollbar,
			    button: int, step: int): int;
	};

	# ── Textfield ──────────────────────────────────────────────
	#
	# Single-line text input field with optional label and
	# secret mode (shows dots instead of characters).
	#
	# The field handles its own cursor, selection, and key
	# events.  The caller is responsible for routing keyboard
	# focus to exactly one Textfield at a time.
	#
	# Usage:
	#   tf := Textfield.mk(r, "Password", 1);
	#   ...
	#   if(tf.contains(p.xy)) { focused = tf; }
	#   rc := tf.key(k);   # 1 = Enter pressed
	#
	Textfield: adt {
		r:       Draw->Rect;    # field rectangle (includes label)
		text:    string;        # current value
		cursor:  int;           # cursor position in text
		secret:  int;           # 1 = show dots instead of chars
		focused: int;           # 1 = has keyboard focus
		label:   string;        # label drawn to the left
		labelw:  int;           # fixed label width (0 = auto from font)

		# Create a text field for the given rectangle.
		# label: text drawn before the input area.
		# secret: 1 for password fields.
		mk:      fn(r: Draw->Rect, label: string, secret: int): ref Textfield;

		# Draw the field into dst.
		draw:    fn(tf: self ref Textfield, dst: ref Draw->Image);

		# Update rectangle (e.g. on window resize).
		resize:  fn(tf: self ref Textfield, r: Draw->Rect);

		# Handle a key press.
		# Returns 1 if Enter was pressed, 0 otherwise.
		key:     fn(tf: self ref Textfield, c: int): int;

		# Handle a pointer click (for cursor placement).
		click:   fn(tf: self ref Textfield, p: Draw->Point);

		# Test whether a point is inside the field.
		contains: fn(tf: self ref Textfield, p: Draw->Point): int;

		# Get/set the current text value.
		value:   fn(tf: self ref Textfield): string;
		setval:  fn(tf: self ref Textfield, s: string);
	};

	# ── Listbox ────────────────────────────────────────────────
	#
	# Scrollable single-selection list.  Each item is a single
	# line of text.  Click to select; the caller reads .selected
	# to know which item is highlighted (-1 = none).
	#
	# Usage:
	#   lb := Listbox.mk(r);
	#   lb.setitems(arr);
	#   ...
	#   if(lb.contains(p.xy)) { sel := lb.click(p.xy); }
	#   lb.draw(dst);
	#
	Listbox: adt {
		r:        Draw->Rect;    # list rectangle (excludes scrollbar)
		items:    array of string;
		selected: int;           # selected index (-1 = none)
		top:      int;           # scroll offset (first visible item)
		scroll:   ref Scrollbar; # attached scrollbar

		# Create a listbox for the given rectangle.
		mk:       fn(r: Draw->Rect): ref Listbox;

		# Draw the list into dst.
		draw:     fn(lb: self ref Listbox, dst: ref Draw->Image);

		# Update rectangle (e.g. on window resize).
		resize:   fn(lb: self ref Listbox, r: Draw->Rect);

		# Handle a pointer click.  Returns the newly selected index.
		click:    fn(lb: self ref Listbox, p: Draw->Point): int;

		# Handle mouse wheel.  Returns new top.
		wheel:    fn(lb: self ref Listbox, button: int): int;

		# Test whether a point is inside the listbox area
		# (including its scrollbar).
		contains: fn(lb: self ref Listbox, p: Draw->Point): int;

		# Replace the item list.  Resets selection to -1.
		setitems: fn(lb: self ref Listbox, items: array of string);

		# Number of visible rows that fit.
		visible:  fn(lb: self ref Listbox): int;
	};

	# ── Button ─────────────────────────────────────────────────
	#
	# Simple clickable button with a text label.
	#
	Button: adt {
		r:       Draw->Rect;    # button rectangle
		label:   string;        # button text
		pressed: int;           # 1 while pointer is held down on it

		# Create a button.
		mk:      fn(r: Draw->Rect, label: string): ref Button;

		# Draw the button into dst.
		draw:    fn(b: self ref Button, dst: ref Draw->Image);

		# Update rectangle.
		resize:  fn(b: self ref Button, r: Draw->Rect);

		# Test whether a point is inside the button.
		contains: fn(b: self ref Button, p: Draw->Point): int;
	};

	# ── Label ──────────────────────────────────────────────────
	#
	# Static text display.  No interaction — just themed text
	# for section headers, descriptions, and captions.
	#
	# Alignment constants for Label.
	LEFT:   con 0;
	CENTER: con 1;

	Label: adt {
		r:     Draw->Rect;    # label rectangle
		text:  string;        # display text
		dim:   int;           # 1 = dim/secondary colour, 0 = normal
		align: int;           # LEFT or CENTER

		# Create a label.
		# dim: 1 for secondary/description text, 0 for normal.
		# align: LEFT (0) or CENTER (1).
		mk:    fn(r: Draw->Rect, text: string, dim: int, align: int): ref Label;

		# Draw the label into dst.
		draw:  fn(l: self ref Label, dst: ref Draw->Image);

		# Update rectangle.
		resize: fn(l: self ref Label, r: Draw->Rect);

		# Set display text.
		settext: fn(l: self ref Label, s: string);
	};

	# ── Checkbox ───────────────────────────────────────────────
	#
	# Toggle control with a text label.  Click to toggle.
	# The box is drawn to the left of the label text.
	#
	# Usage:
	#   cb := Checkbox.mk(r, "Enable feature", 0);
	#   ...
	#   if(cb.contains(p.xy)) { cb.toggle(); redraw(); }
	#
	Checkbox: adt {
		r:       Draw->Rect;    # full rectangle (box + label)
		label:   string;        # text label
		checked: int;           # 1 = checked, 0 = unchecked

		# Create a checkbox.
		mk:      fn(r: Draw->Rect, label: string, checked: int): ref Checkbox;

		# Draw the checkbox into dst.
		draw:    fn(cb: self ref Checkbox, dst: ref Draw->Image);

		# Update rectangle.
		resize:  fn(cb: self ref Checkbox, r: Draw->Rect);

		# Toggle checked state.
		toggle:  fn(cb: self ref Checkbox);

		# Test whether a point is inside the checkbox area.
		contains: fn(cb: self ref Checkbox, p: Draw->Point): int;

		# Get current state.
		value:   fn(cb: self ref Checkbox): int;
	};

	# ── Radio ──────────────────────────────────────────────────
	#
	# Radio button — circle indicator with a text label.
	# Visually distinct from Checkbox (circle vs square).
	# The caller manages mutual exclusion (uncheck others),
	# or use RadioGroup below for automatic management.
	#
	Radio: adt {
		r:        Draw->Rect;    # full rectangle (circle + label)
		label:    string;        # text label
		selected: int;           # 1 = selected, 0 = unselected

		# Create a radio button.
		mk:       fn(r: Draw->Rect, label: string, selected: int): ref Radio;

		# Draw the radio button into dst.
		draw:     fn(rb: self ref Radio, dst: ref Draw->Image);

		# Update rectangle.
		resize:   fn(rb: self ref Radio, r: Draw->Rect);

		# Test whether a point is inside the radio area.
		contains: fn(rb: self ref Radio, p: Draw->Point): int;
	};

	# ── RadioGroup ─────────────────────────────────────────────
	#
	# Manages a set of mutually exclusive Radio buttons.
	# Handles hit testing and automatic deselection when a
	# new button is clicked.  Simplifies the common pattern
	# where the caller previously had to deselect all buttons
	# manually.
	#
	# Usage:
	#   rg := RadioGroup.mk(Point(cx, cy), width, labels, sel, rowh);
	#   ...
	#   if(rg.contains(p.xy)) {
	#       i := rg.click(p.xy);
	#       if(i >= 0) { handleselection(i); redraw(); }
	#   }
	#   rg.draw(dst);
	#
	RadioGroup: adt {
		buttons: array of ref Radio;

		# Create a group.
		# origin: top-left of first button.
		# width:  horizontal extent of each button row.
		# labels: array of label strings (one per button).
		# sel:    initially selected index (-1 = none).
		# rowh:   height per row (button rect height; include
		#         inter-button spacing here for natural gaps).
		mk:       fn(origin: Draw->Point, width: int,
			        labels: array of string, sel: int,
			        rowh: int): ref RadioGroup;

		# Draw all buttons.
		draw:     fn(rg: self ref RadioGroup, dst: ref Draw->Image);

		# Handle a pointer click.  Deselects all buttons, selects
		# the hit one, and returns its index.
		# Returns -1 if no button was hit.
		click:    fn(rg: self ref RadioGroup, p: Draw->Point): int;

		# Return the index of the currently selected button (-1 = none).
		selected: fn(rg: self ref RadioGroup): int;

		# Programmatically select a button by index.
		# Pass -1 to deselect all.
		select:   fn(rg: self ref RadioGroup, idx: int);

		# Recompute button rectangles after a resize.
		# Parameters match those of mk().
		resize:   fn(rg: self ref RadioGroup, origin: Draw->Point,
			        width: int, rowh: int);

		# Bounding rectangle of the entire group.
		bounds:   fn(rg: self ref RadioGroup): Draw->Rect;

		# Test whether a point is inside any button in the group.
		contains: fn(rg: self ref RadioGroup, p: Draw->Point): int;
	};

	# ── Statusbar ──────────────────────────────────────────────
	#
	# Horizontal info bar at the bottom of a window.  Displays
	# left-aligned and right-aligned text, with an optional
	# inline text-input mode (find, goto line, URL entry, etc.).
	#
	Statusbar: adt {
		r:       Draw->Rect;    # status bar rectangle
		left:    string;        # left-aligned text
		right:   string;        # right-aligned text
		prompt:  string;        # nil = display mode; non-nil = input prompt
		buf:     string;        # input buffer when prompting
		leftcolor: ref Draw->Image;  # override left text colour (nil = default)

		# Create a status bar for the given rectangle.
		new:     fn(r: Draw->Rect): ref Statusbar;

		# Draw the status bar into dst.
		draw:    fn(sb: self ref Statusbar, dst: ref Draw->Image);

		# Update rectangle (e.g. on window resize).
		resize:  fn(sb: self ref Statusbar, r: Draw->Rect);

		# Handle a key press in input mode.
		# Returns:
		#   ( 1, value) — Enter pressed, input accepted
		#   (-1, nil)   — Escape pressed, input cancelled
		#   ( 0, nil)   — key consumed, still editing
		# In display mode (prompt==nil), returns (-1, nil).
		key:     fn(sb: self ref Statusbar, c: int): (int, string);
	};
};
