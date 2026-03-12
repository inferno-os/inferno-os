#
# menu.m — Plan 9 hold-to-show contextual popup menu
#
# UX convention:
#   - Caller detects button-3 DOWN and calls show().
#   - show() draws the menu and blocks reading ptr until button-3 UP.
#   - While held, cursor movement highlights items.
#   - Release over an item → selects it; release outside → -1.
#
# Hybrid UX:
#   - Hold button-3 and release over item → Plan 9 style
#   - Quick right-click → menu stays visible; button-1 selects (macOS style)
#
# For long item lists (>20 or exceeding window height),
# the menu scrolls, showing a subset of items with
# up/down scroll indicators.
#
# Generator support:
#   A Popup created with newgen() stores a generator function
#   that is called at the start of show() to rebuild the Popup's
#   items (and optionally subs) from current application state.
#   This is the Limbo-native equivalent of TK's -postcommand.
#
# Submenu support:
#   Any item can have a child Popup attached via the subs array.
#   When the user hovers over a cascade item, the submenu opens
#   to its right.  Selecting from the submenu sets lastsub to the
#   chosen index within the child; the parent returns the cascade
#   item's index.
#
Menu: module
{
	PATH:	con "/dis/lib/menu.dis";

	# Generator function type: called before show() to populate
	# the Popup.  Sets m.items and optionally m.subs.
	# Receives no other arguments; the caller closes over
	# whatever state it needs.
	Generator: type ref fn(m: ref Popup);

	# Contextual popup menu.
	Popup: adt {
		items:	array of string;
		lasthit: int;		# previous selection (default highlight)
		gen:	Generator;	# if non-nil, called at start of show()
		subs:	array of ref Popup;	# per-item submenus; nil entry = leaf
		lastsub: int;		# submenu selection after show(), or -1

		# Draw menu at position `at`, block on `ptr` until button-3 UP.
		# Returns selected item index (0-based), or -1 if dismissed.
		# For cascade items, lastsub holds the submenu selection.
		# win: the real window image (not a backbuffer).
		# ptr: mouse event channel (typically lucifer's cmouse).
		show:	fn(m: self ref Popup,
			   win: ref Draw->Image,
			   at:  Draw->Point,
			   ptr: chan of ref Draw->Pointer): int;
	};

	# Initialise module state.  Must be called once before new().
	# display and font are the window's display and main UI font.
	init:	fn(display: ref Draw->Display, font: ref Draw->Font);

	# Allocate a Popup with static item labels.
	new:	fn(items: array of string): ref Popup;

	# Allocate a Popup with a generator function.
	# The generator is called at the start of each show() to
	# rebuild items (and optionally subs) from current state.
	newgen:	fn(gen: Generator): ref Popup;
};
