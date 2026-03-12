#
# textwidget.m — Text display primitives for Draw-based apps
#
# Reusable building blocks for rendering and interacting with
# text content: tab expansion, word wrapping, selection highlight.
# Complements widget.m (chrome) with text-area internals.
#
# Design principles:
#   - Limbo-native: ADTs and functions, not string commands
#   - Parameterised: tabstop width, font, colours passed in
#   - No hidden state: each ADT instance is self-contained
#   - Flat-drawn: renders directly to Draw images
#   - Composable: use what you need, ignore what you don't
#

Textwidget: module
{
	PATH: con "/dis/lib/textwidget.dis";

	# Initialise module.  Must be called once before use.
	init: fn();

	# ── Tab expansion ─────────────────────────────────────────
	#
	# Tab-aware column arithmetic.  A Tabulator holds the tab
	# width and provides expand/unexpand operations.
	#
	Tabulator: adt {
		tabstop: int;		# tab width in spaces (e.g. 4 or 8)

		# Create a Tabulator with the given tab width.
		new:         fn(tabstop: int): ref Tabulator;

		# Expand tabs to spaces for display.
		expand:      fn(tab: self ref Tabulator, s: string): string;

		# Map an expanded column back to the original string offset.
		# Given a tab-expanded column index, returns the corresponding
		# offset in the original (unexpanded) string.
		unexpandcol: fn(tab: self ref Tabulator, s: string,
			        expcol: int): int;

		# Map an original string offset to the expanded column.
		# Given a character offset in the original string, returns
		# the display column after tab expansion.
		expandedcol: fn(tab: self ref Tabulator, s: string,
			        col: int): int;
	};

	# ── Word wrapping ─────────────────────────────────────────
	#
	# Compute where a line of text wraps at a pixel boundary.
	#

	# wrapend returns the end index (exclusive) of the next wrapped
	# visual chunk starting at position `start` in the (tab-expanded)
	# string `s`, fitting within `maxpx` pixels using `font`.
	# Guarantees at least one character per chunk.
	wrapend: fn(font: ref Draw->Font, s: string,
		    start, maxpx: int): int;

	# ── Selection drawing ─────────────────────────────────────
	#
	# Draw a selection highlight for one visual chunk of a line.
	#

	# drawselection draws the selection background for the visual
	# chunk [cs, ce) of a logical line.  `expanded` is the
	# tab-expanded line.  `selstart_ex` and `selend_ex` are the
	# selection boundaries in expanded-column space.  `textx` and
	# `y` are the screen origin of this chunk.
	drawselection: fn(dst: ref Draw->Image, font: ref Draw->Font,
			  selcolor: ref Draw->Image,
			  expanded: string, cs, ce: int,
			  selstart_ex, selend_ex: int,
			  textx, y, lineheight: int);
};
