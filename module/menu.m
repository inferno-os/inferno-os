#
# menu.m — Plan 9 hold-to-show contextual popup menu
#
# UX convention:
#   - Caller detects button-3 DOWN and calls show().
#   - show() draws the menu and blocks reading ptr until button-3 UP.
#   - While held, cursor movement highlights items.
#   - Release over an item → selects it; release outside → -1.
#
Menu: module
{
	PATH:	con "/dis/lib/menu.dis";

	# Contextual popup menu.
	Popup: adt {
		items:	array of string;

		# Draw menu at position `at`, block on `ptr` until button-3 UP.
		# Returns selected item index (0-based), or -1 if dismissed.
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

	# Allocate a Popup with the given item labels.
	new:	fn(items: array of string): ref Popup;
};
