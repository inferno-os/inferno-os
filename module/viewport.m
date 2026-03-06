#
# Viewport - Shared pan/scroll/drag logic for content viewers
#
# Provides a View state object and pure functions for managing
# a scrollable, pannable content area.  Used by both Xenith and
# Lucifer's presentation zone (lucipres) so the logic lives in
# one place.
#
# The caller owns the rendering; this module only manages offsets
# and reports boundary conditions (e.g., "scroll past bottom"
# → caller can advance to next page).
#

Viewport: module {
	PATH: con "/dis/lib/viewport.dis";

	# View holds the pan state and dimensions for one content area.
	# All values are in pixels.
	View: adt {
		panx:     int;   # horizontal offset into content
		pany:     int;   # vertical offset into content
		contentw: int;   # total content width
		contenth: int;   # total content height
		vieww:    int;   # visible viewport width
		viewh:    int;   # visible viewport height
	};

	# Create a new zeroed View.
	new: fn(): ref View;

	# Set content and viewport dimensions.  Clamps offsets.
	setbounds: fn(v: ref View, cw, ch, vw, vh: int);

	# Clamp pan offsets to valid range [0..max].
	clamp: fn(v: ref View);

	# Max pan offsets (content minus viewport, floored at 0).
	maxpanx: fn(v: ref View): int;
	maxpany: fn(v: ref View): int;

	# Scroll vertically by 'step' pixels.
	#   dir < 0: scroll up (content moves down)
	#   dir > 0: scroll down (content moves up)
	# Returns:
	#   0  = scrolled normally
	#  -1  = was already at top and tried to scroll up
	#   1  = was already at bottom and tried to scroll down
	# The boundary return lets the caller trigger page navigation.
	scrolly: fn(v: ref View, dir: int, step: int): int;

	# Scroll horizontally (same semantics as scrolly).
	scrollx: fn(v: ref View, dir: int, step: int): int;

	# Default scroll step: ~3 lines of a 14pt font, or 20% of
	# viewport height, whichever is larger.  Provides consistent
	# feel across viewers.
	scrollstep: fn(viewh: int): int;

	# Apply a drag delta from an initial pan position.
	# startpx/startpy are the pan values at drag start.
	# dx/dy are mouse displacement (start - current).
	# Updates v.panx/v.pany and clamps.
	drag: fn(v: ref View, startpx, startpy, dx, dy: int);

	# Reset pan to origin.
	reset: fn(v: ref View);
};
