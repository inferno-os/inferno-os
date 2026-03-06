#
# lucitheme.m — Lucifer theme module interface
#
# Reads a colour palette from Plan 9–style flat files in
# /lib/lucifer/theme/.  Each key is a lowercase name, each
# value a 6-digit hex RGB string (alpha is always FF).
#
# Active theme is selected by /lib/lucifer/theme/current
# which contains a single theme name (e.g. "brimstone").
#
# Users can create custom themes by adding files to this
# directory.  Missing keys fall back to Brimstone defaults.
#

Lucitheme: module
{
	PATH: con "/dis/lib/lucitheme.dis";

	Theme: adt {
		# --- Core UI ---
		bg:           int;
		border:       int;
		header:       int;
		accent:       int;
		text:         int;
		text2:        int;
		dim:          int;
		label:        int;

		# --- Conversation zone ---
		human:        int;
		veltro:       int;
		input:        int;
		cursor:       int;

		# --- Status / semantic ---
		red:          int;
		green:        int;
		yellow:       int;
		progbg:       int;
		progfg:       int;

		# --- Code blocks ---
		codebg:       int;

		# --- Context menu ---
		menubg:       int;
		menuborder:   int;
		menuhilit:    int;
		menutext:     int;
		menudim:      int;

		# --- Editor ---
		editbg:       int;
		edittext:     int;
		editcursor:   int;
		editlineno:   int;
		editstatus:   int;
		editstattext: int;
		editscroll:   int;
		editthumb:    int;

		# --- Mermaid diagrams ---
		diagbg:       int;
		diagnode:     int;
		diagborder:   int;
		diagtext:     int;
		diagtext2:    int;
		diagacc:      int;
		diaggreen:    int;
		diagred:      int;
		diagyellow:   int;
		diaggrid:     int;
		pie0:         int;
		pie1:         int;
		pie2:         int;
		pie3:         int;
		pie4:         int;
		pie5:         int;
		pie6:         int;
		pie7:         int;
	};

	# Load the currently active theme.
	# Reads /lib/lucifer/theme/current for the theme name,
	# then reads /lib/lucifer/theme/<name>.
	# Falls back to Brimstone defaults for missing keys or on error.
	load: fn(): ref Theme;

	# Return built-in Brimstone (dark) defaults.
	brimstone: fn(): ref Theme;
};
