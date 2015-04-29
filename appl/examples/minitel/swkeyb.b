###
### This data and information is not to be used as the basis of manufacture,
### or be reproduced or copied, or be distributed to another party, in whole
### or in part, without the prior written consent of Lucent Technologies.
###
### (C) Copyright 1997 Lucent Technologies
###
### Written by N. W. Knauft
###
#
# Revisions Copyright © 1998 Vita Nuova Limited.

implement Keyboard;

include "sys.m";
        sys: Sys;

include "draw.m";
        draw: Draw;

include "tk.m";
        tk: Tk;

include "tkclient.m";
        tkclient: Tkclient;

include "swkeyb.m";

#Icon path
ICPATH: con "keybd/";

#Font
FONT: con "/fonts/lucidasans/latin1.7.font";
SPECFONT: con "/fonts/lucidasans/latin1.6.font";

# Dimension constants
KBDWIDTH: con 360;
KBDHEIGHT: con 120;
KEYSIZE: con "19";
KEYSPACE: con 5;
KEYBORDER: con 1;
KEYGAP: con KEYSPACE - (2 * KEYBORDER);
ENDGAP: con 2 - KEYBORDER;

# Row size constants (cumulative)
ROW1: con 14;
ROW2: con 28;
ROW3: con 41;
ROW4: con 53;
NKEYS: con 63;

#Special key number constants
DELKEY: con 13;
TABKEY: con 14;
BACKSLASHKEY: con 27;
CAPSLOCKKEY: con 28 ;
RETURNKEY: con 40;
LSHIFTKEY: con 41;
RSHIFTKEY: con 52;
ESCKEY: con 53;
CTRLKEY: con 54;
METAKEY: con 55;
ALTKEY: con 56;
SPACEKEY: con 57;
ENTERKEY: con 58;
LEFTKEY: con 59;
RIGHTKEY: con 60;
DOWNKEY: con 61;
UPKEY: con 62;

#Special key code constants
CAPSLOCK: con -1 ;
SHIFT: con -2;
CTRL: con -3;
ALT: con -4;
META: con -5;
MAGIC_PREFIX: con 256;
ARROW_OFFSET: con 57344;
ARROW_PREFIX: con ARROW_OFFSET + 18;

#Special key width constants
DELSIZE: con 44;
TABSIZE: con 32;
BACKSLASHSIZE: con 31;
CAPSLOCKSIZE: con 44;
RETURNSIZE: con 43;
LSHIFTSIZE: con 56;
RSHIFTSIZE: con 55;
ESCSIZE: con 21;
CTRLSIZE: con 23;
METASIZE: con 38;
ALTSIZE: con 22;
SPACESIZE: con 100;
ENTERSIZE: con 31;

#Arrow key code constants
UP: con ARROW_PREFIX;
DOWN: con ARROW_PREFIX + 1;
LEFT: con ARROW_PREFIX + 2;
RIGHT: con ARROW_PREFIX + 3;

direction:= array[] of {"up", "down", "left", "right"};
row_dimensions:= array[] of {0, ROW1, ROW2, ROW3, ROW4, NKEYS};

special_keys:= array[] of {
	(DELKEY, DELSIZE),
	(TABKEY, TABSIZE),
	(BACKSLASHKEY, BACKSLASHSIZE),
	(CAPSLOCKKEY, CAPSLOCKSIZE),
	(RETURNKEY, RETURNSIZE),
	(LSHIFTKEY, LSHIFTSIZE),
	(RSHIFTKEY, RSHIFTSIZE),
	(ESCKEY, ESCSIZE),
	(CTRLKEY, CTRLSIZE),
	(METAKEY, METASIZE),
	(ALTKEY, ALTSIZE),
	(SPACEKEY, SPACESIZE),
	(ENTERKEY, ENTERSIZE),
};

keys:= array[] of {
	# Unshifted
	"`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Delete",
	"Tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]", "\\\\",
	"CapLoc", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "\'", "Return",
	"Shift", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "Shift",
	"Esc", "Ctrl", " ", "Alt", " ", "Enter", "<-", "->", "v", "^",
	# Shifted
	"~", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+", "Delete",
	"Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "\\{", "\\}", "|",
	"CapLoc", "A", "S", "D", "F", "G", "H", "J", "K", "L", ":", "\"", "Return",
	"Shift", "Z", "X", "C", "V", "B", "N", "M", "<", ">", "?", "Shift",
	"Esc", "Ctrl", " ", "Alt", " ", "Enter", "<-", "->", "v", "^",
};

keyvals:= array[] of {
	# Unshifted
	'`', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', '\b',
	'\t', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\\',
	CAPSLOCK, 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '\n',
	SHIFT, 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', SHIFT,
	27, CTRL, META, ALT, 32, '\n', LEFT, RIGHT, DOWN, UP,
	# Shifted
	'~', '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', '\b',
	'\t', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', '|',
	CAPSLOCK, 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '\n',
	SHIFT, 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', SHIFT,
	27, CTRL, META, ALT, 32, '\n', LEFT, RIGHT, DOWN, UP,
};

rowlayout := array[] of {
	"frame .f1",
	"frame .f2",
	"frame .f3",
	"frame .f4",
	"frame .f5",
	"frame .dummy0 -height " + string (ENDGAP),
	"frame .dummy1 -height " + string KEYGAP,
	"frame .dummy2 -height " + string KEYGAP,
	"frame .dummy3 -height " + string KEYGAP,
	"frame .dummy4 -height " + string KEYGAP,
	"frame .dummy5 -height " + string (ENDGAP + 1),
};

# Move key flags
move_key_enabled := 0;
meta_active := 0;

# Create keyboard widget, spawn keystroke handler
initialize(t: ref Tk->Toplevel, ctxt : ref Draw->Context, dot: string): chan of string
{
	return chaninit(t, ctxt, dot, chan of string);
}

chaninit(t: ref Tk->Toplevel, ctxt : ref Draw->Context, dot: string, rc: chan of string): chan of string
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;

	tkclient->init();

	tk->cmd(t, "frame " + dot + " -bd 2 -relief raised -width " + string KBDWIDTH 
		+ " -height " + string KBDHEIGHT);
	tkcmds(t, rowlayout);

	for(i := 0; i < NKEYS; i++) {
		tk->cmd(t, "button .b" + string i + " -font " + FONT + " -width " + KEYSIZE
		    + " -height " + KEYSIZE + " -bd " + string KEYBORDER);

		tk->cmd(t, ".b" + string i + " configure -text {" + keys[i] +
					"} -command 'send keypress " + string keyvals[i]);
	}

	for(i = 0; i < len special_keys; i++) {
		(keynum, keysize) := special_keys[i];
		tk->cmd(t, ".b" + string keynum + " configure -font " + SPECFONT + " -width " + string keysize);
	}

	tk->cmd(t, "image create bitmap Capslock_on -file " + ICPATH + "capson.bit -maskfile " + ICPATH + "capson.bit");
	tk->cmd(t, "image create bitmap Capslock_off -file " + ICPATH + "capsoff.bit -maskfile " + ICPATH + "capsoff.bit");
	tk->cmd(t, "image create bitmap Left_arrow -file " + ICPATH + "larrow.bit -maskfile " + ICPATH + "larrow.bit");
	tk->cmd(t, "image create bitmap Right_arrow -file " + ICPATH + "rarrow.bit -maskfile " + ICPATH + "rarrow.bit");
	tk->cmd(t, "image create bitmap Down_arrow -file " + ICPATH + "darrow.bit -maskfile " + ICPATH + "darrow.bit");
	tk->cmd(t, "image create bitmap Up_arrow -file " + ICPATH + "uarrow.bit -maskfile " + ICPATH + "uarrow.bit");
	tk->cmd(t, "image create bitmap Move_on -file " + ICPATH + "moveon.bit -maskfile " + ICPATH + "moveon.bit");
	tk->cmd(t, "image create bitmap Move_off -file " + ICPATH + "moveoff.bit -maskfile " + ICPATH + "moveoff.bit");
	tk->cmd(t, "image create bitmap None -file " + ICPATH + "none.bit -maskfile " + ICPATH + "none.bit");
	tk->cmd(t, ".b" + string CAPSLOCKKEY + " configure -image Capslock_off");
	tk->cmd(t, ".b" + string LEFTKEY + " configure -image Left_arrow");
	tk->cmd(t, ".b" + string RIGHTKEY + " configure -image Right_arrow");
	tk->cmd(t, ".b" + string DOWNKEY + " configure -image Down_arrow");
	tk->cmd(t, ".b" + string UPKEY + " configure -image Up_arrow");

	for(j:=1; j < len row_dimensions; j++) {
		rowstart := row_dimensions[j-1];
		rowend := row_dimensions[j];
		for(i=rowstart; i<rowend; i++) {
			if (i == rowstart) {
				tk->cmd(t, "frame .f" + string j + ".dummy -width " + string ENDGAP);
				tk->cmd(t, "pack .f" + string j + ".dummy -side left");
			}
			tk->cmd(t, "pack .b" + string i + " -in .f" + string j + " -side left");
			if (i == rowend-1)
				tk->cmd(t, "frame .f" + string j + ".dummy" + string i + " -width " + string ENDGAP);
			else
				tk->cmd(t, "frame .f" + string j + ".dummy" + string i + " -width " + string KEYGAP);
			tk->cmd(t, "pack .f" + string j + ".dummy" + string i + " -side left");
		}
	}

	tk->cmd(t, "pack .dummy0 .f1 .dummy1 .f2 .dummy2 .f3 .dummy3 .f4 .dummy4 .f5 .dummy5 -in " + dot);
	tk->cmd(t,"update");

	key := chan of string;
	spawn handle_keyclicks(t, ctxt, key, rc);
	return key;
}

tkcmds(t: ref Tk->Toplevel, cmds: array of string)
{
	for(i := 0; i < len cmds; i++)
		tk->cmd(t, cmds[i]);
}

# Process key clicks and hand keycodes off to Tk
handle_keyclicks(t: ref Tk->Toplevel, ctxt : ref Draw->Context, sc, rc: chan of string)
{
	keypress := chan of string;
	tk->namechan(t, keypress, "keypress");

	minitel := 0;
	caps_locked := 0;
	shifted := 0;
	ctrl_active := 0;
	alt_active := 0;

Work:
	for(;;){
		alt {
		k := <-keypress =>
			(n, cmdstr) := sys->tokenize(k, " \t\n");
			keycode := int hd cmdstr;
			case keycode {
			    CAPSLOCK =>
				redisplay_keyboard(t, minitel, caps_locked ^= 1, caps_locked);
				shifted = 0;
				ctrl_active = 0;
				alt_active = 0;
			    SHIFT =>
				redisplay_keyboard(t, minitel, (shifted ^= 1) ^ caps_locked, caps_locked);
			    CTRL =>
				ctrl_active ^= 1;
				if (shifted) {
					redisplay_keyboard(t, minitel, caps_locked, caps_locked);
					shifted = 0;
				}
				alt_active = 0;
			    ALT =>
				alt_active ^= 1;
				if (shifted) {
					redisplay_keyboard(t, minitel, caps_locked, caps_locked);
					shifted = 0;
				}
				ctrl_active = 0;
			    META =>
				if (move_key_enabled) {
					if (meta_active ^= 1)
						tk->cmd(t, ".b" + string METAKEY + " configure -image Move_on");
					else
						tk->cmd(t, ".b" + string METAKEY + " configure -image Move_off");
				}
				redisplay_keyboard(t, minitel, caps_locked, caps_locked);
				shifted = 0;
				ctrl_active = 0;
				alt_active = 0;
			    * =>
				if (ctrl_active) {
					keycode &= 16r1F;
					ctrl_active = 0;
				} else if (alt_active) {
					keycode += MAGIC_PREFIX;
					alt_active = 0;
				}
				if (meta_active && UP <= keycode && keycode <= RIGHT) {
					spawn send_move_msg(direction[keycode - ARROW_PREFIX], sc);
				} else 
					tk->keyboard(t, keycode);
				if (shifted) {
					redisplay_keyboard(t, minitel, caps_locked, caps_locked);
					shifted = 0;
				}
			}
		s := <-rc =>
			case s {
			"kill" =>
				break Work;
			"minitel" =>
				if (!minitel) {
					minitel = 1;
					redisplay_keyboard(t, minitel, shifted, caps_locked);
				}
			"standard" =>
				if (minitel) {
					minitel = 0;
					redisplay_keyboard(t, minitel, shifted, caps_locked);
				}
			}
		}
	}
}

send_move_msg(dir: string, ch: chan of string)
{
	ch <-= dir;
}


# Redisplay keyboard to reflect current state (shifted or unshifted)
redisplay_keyboard(t: ref Tk->Toplevel, minitel, shifted, caps_locked: int)
{
	base: int;

	if (shifted)
		base = NKEYS;
	else
		base = 0;

	for(i:=0; i<NKEYS; i++) {
		n := base + i;
		val := keyvals[n];
		key := keys[n];
		if (minitel) {
			if (val >= int 'A' && val <= int 'Z') {
				key = keys[n-NKEYS];
			} else if (val >= int 'a' && val <= int 'z') {
				key = keys[n+NKEYS];
			}
		 }
	
		tk->cmd(t, ".b" + string i + " configure -text {" + key
       			     + "} -command 'send keypress " + string val);
  	}
	if (caps_locked)
		tk->cmd(t, ".b" + string CAPSLOCKKEY + " configure -image Capslock_on");
	else
		tk->cmd(t, ".b" + string CAPSLOCKKEY + " configure -image Capslock_off");
	tk->cmd(t, "update");
}
