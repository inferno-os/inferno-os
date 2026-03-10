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

		# Create a scrollbar for the given rectangle.
		new:     fn(r: Draw->Rect): ref Scrollbar;

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
