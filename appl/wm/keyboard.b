implement Keybd;

#
# extensive revision of code originally by N. W. Knauft
#
# Copyright © 1997 Lucent Technologies Inc.  All rights reserved.
# Revisions Copyright © 1998 Vita Nuova Limited.  All rights reserved.
# Rewritten code Copyright © 2001 Vita Nuova Holdings Limited.  All rights reserved.
#
# To do:
#	input from file
#	calculate size

include "sys.m";
        sys: Sys;

include "draw.m";
        draw: Draw;
	Rect, Point: import draw;

include "tk.m";
        tk: Tk;

include "tkclient.m";
        tkclient: Tkclient;

include "arg.m";

include "keyboard.m";

Keybd: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

FONT: con "/fonts/lucidasans/boldlatin1.6.font";
SPECFONT: con "/fonts/lucidasans/unicode.6.font";

# size in pixels
#KEYSIZE: con 16;
KEYSIZE: con 13;
KEYSPACE: con 2;
KEYBORDER: con 1;
KEYGAP: con KEYSPACE - (2 * KEYBORDER);
#ENDGAP: con 2 - KEYBORDER;
ENDGAP: con 0;

Key: adt {
	name: string;
	val:	int;
	size:	int;
	x:	list of int;
	on:	int;
};

background: con "#dddddd";

Backspace, Tab, Backslash, CapsLock, Return, Shift, Ctrl, Esc, Alt, Space: con iota;

specials := array[] of {
Backspace =>		Key("<-", '\b', 28, nil, 0),
Tab =>			Key("Tab", '\t', 26, nil, 0),
Backslash =>		Key("\\\\", '\\', KEYSIZE, nil, 0),
CapsLock =>		Key("Caps", Keyboard->Caps, 40, nil, 0),
Return =>			Key("Enter", '\n', 36, nil, 0),
Shift =>			Key("Shift", Keyboard->LShift, 45, nil, 0),
Esc =>			Key("Esc", 8r33, 21, nil, 0),
Ctrl =>			Key("Ctrl", Keyboard->LCtrl, 36, nil, 0),
Alt =>			Key("Alt", Keyboard->LAlt, 22, nil, 0),
Space =>			Key(" ", ' ', 140, nil, 0),
Space+1 =>		Key("Return", '\n', 36, nil, 0),
};

keys:= array[] of {
	# unshifted
	array[] of {
		"Esc", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "\\\\", "`", nil,
		"Tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]", "<-", nil,
		"Ctrl", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'", "Enter", nil,
		"Shift", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "Shift", nil,
		"Caps", "Alt", " ", "Alt", nil,
	},

	# shifted
	array[] of {
		"Esc", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+", "|", "~", nil,
		"Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "\\{", "\\}", "<-", nil,
		"Ctrl", "A", "S", "D", "F", "G", "H", "J", "K", "L", ":", "\"", "Return", nil,
		"Shift", "Z", "X", "C", "V", "B", "N", "M", "<", ">", "?", "Shift", nil,
		"Caps", "Alt", " ", "Alt", nil,
	},
};

keyvals: array of array of int;
noexit := 0;

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "keyboard: no window context\n");
		raise "fail:bad context";
	}
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	arg := load Arg Arg->PATH;

	taskbar := 0;
	winopts := Tkclient->Hide;
	arg->init(args);
	while ((opt := arg->opt()) != 0) {
		case opt {
		't' =>
			taskbar = 1;
		'e' =>
			noexit = 1;
			winopts = 0;
		* =>
			sys->fprint(sys->fildes(2), "usage: keyboard [-et]\n");
			raise "fail:usage";
		}
	}

	sys->pctl(Sys->NEWPGRP, nil);
	tkclient->init();

	keyvals = array[] of {
		array[len keys[0]] of int,
		array[len keys[1]] of int,
	};
	setindex(keys[0], keyvals[0], specials);
	setindex(keys[1], keyvals[1], specials);


	(t, wcmd) := tkclient->toplevel(ctxt, "", "Kbd", winopts);
	cmd(t, ". configure -bd 0 -relief flat");

	for(i := 0; i < len keys[0]; i++)
		if(keys[0][i] != nil)
			cmd(t, sys->sprint("button .b%d -takefocus 0 -font %s -width %d -height %d -bd %d -activebackground %s -text {%s} -command 'send keypress %d",
				i, FONT, KEYSIZE, KEYSIZE, KEYBORDER, background, keys[0][i], keyvals[0][i]));

	for(i = 0; i < len specials; i++) {
		k := specials[i];
		for(xl := k.x; xl != nil; xl = tl xl)
			cmd(t, sys->sprint(".b%d configure -font %s -width %d", hd xl, SPECFONT, k.size));
	}

	# pack buttons in rows
	i = 0;
	for(j:=0; i < len keys[0]; j++){
		rowf := sys->sprint(".f%d", j);
		cmd(t, "frame "+rowf);
		cmd(t, sys->sprint("frame .pad%d -height %d", j, KEYGAP));
		if(ENDGAP){
			cmd(t, rowf + ".pad -width " + string ENDGAP);
			cmd(t, "pack " + rowf + ".pad -side left");
		}
		for(; keys[0][i] != nil; i++){
			label := keys[0][i];
			expand := label != "\\\\" && len label > 1;
			cmd(t, "pack .b" + string i + " -in "+ rowf + " -side left -fill x -expand "+string expand);
			if(keys[0][i+1] != nil && KEYGAP > 0){
				padf := sys->sprint("%s.pad%d", rowf, i);
				cmd(t, "frame " + padf + " -width " + string KEYGAP);
				cmd(t, "pack " + padf + " -side left");
			}
		}
		if(ENDGAP){
			padf := sys->sprint("%s.pad%d", rowf, i);
			cmd(t, "frame " + padf + " -width " + string ENDGAP);
			cmd(t, "pack " + padf + " -side left");
		}
		i++;
	}
	nrow := j;

	# pack rows in frame
	for(j = 0; j < nrow; j++)
		cmd(t, sys->sprint("pack .f%d .pad%d -fill x -in .", j, j));

	(w, h) := (int cmd(t, ". cget -width"), int cmd(t, ". cget -height"));
	r := t.screenr;
	off := (r.dx()-w)/2;
	cmd(t, sys->sprint(". configure -x %d -y %d", r.min.x+off, r.max.y-h));
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "ptr" :: nil);

	spawn handle_keyclicks(t, wcmd, taskbar);
}

setindex(keys: array of string, keyvals: array of int, spec: array of Key)
{
	for(i := 0; i < len keys; i++){
		if(keys[i] == nil)
			continue;
		val := keys[i][0];
		if(len keys[i] > 1 && val == '\\')
			val = keys[i][1];
		for(j := 0; j < len spec; j++)
			if(spec[j].name == keys[i]){
				if(!inlist(i, spec[j].x))
					spec[j].x = i :: spec[j].x;
				val = spec[j].val;
				break;
			}
		keyvals[i] = val;
	}
}

inlist(i: int, l: list of int): int
{
	for(; l != nil; l = tl l)
		if(hd l == i)
			return 1;
	return 0;
}

handle_keyclicks(t: ref Tk->Toplevel, wcmd: chan of string, taskbar: int)
{
	keypress := chan of string;
	tk->namechan(t, keypress, "keypress");

	if(taskbar)
		tkclient->wmctl(t, "task");

	cmd(t,"update");

	collecting := 0;
	collected := "";
	for(;;)alt {
	k := <-keypress =>
		c := int k;
		case c {
		Keyboard->Caps =>
			active(t, Ctrl, 0);
			active(t, Shift, 0);
			active(t, Alt, 0);
			active(t, CapsLock, -1);
			redraw(t);
		Keyboard->LShift =>
			active(t, Shift, -1);
			redraw(t);
		Keyboard->LCtrl =>
			active(t, Alt, 0);
			active(t, Ctrl, -1);
			active(t, Shift, 0);
			redraw(t);
		Keyboard->LAlt =>
			active(t, Alt, -1);
			active(t, Ctrl, 0);
			active(t, Shift, 0);
			redraw(t);
			if(specials[Alt].on){
				collecting = 1;
				collected = "";
			}else
				collecting = 0;
		* =>
			if(collecting){
				collected[len collected] = c;
				c = latin1(collected);
				if(c < -1)
					continue;
				collecting = 0;
				if(c == -1){
					for(i := 0; i < len collected; i++)
						sendkey(t, collected[i]);
					continue;
				}
			}
			show := specials[Ctrl].on | specials[Alt].on | specials[Shift].on;
			if(specials[Ctrl].on)
				c &= 16r1F;
			active(t, Ctrl, 0);
			active(t, Alt, 0);
			active(t, Shift, 0);
			if(show)
				redraw(t);
			sendkey(t, c);
		}
	m := <-t.ctxt.ptr =>
		tk->pointer(t, *m);
	s := <-t.ctxt.ctl or
	s = <-t.wreq or
	s = <-wcmd =>
		if (s == "exit" && noexit)
			s = "task";
		tkclient->wmctl(t, s);
	}
}

sendkey(t: ref Tk->Toplevel, c: int)
{
	sys->fprint(t.ctxt.connfd, "key %d", c);
}

active(t: ref Tk->Toplevel, keyno: int, on: int)
{
	key := specials[keyno:];
	if(on < 0)
		key[0].on ^= 1;
	else
		key[0].on = on;
	for(xl := key[0].x; xl != nil; xl = tl xl){
		col := background;
		if(key[0].on)
			col = "white";
		cmd(t, ".b"+string hd xl+" configure -bg "+col+ " -activebackground "+col);
	}
}

redraw(t: ref Tk->Toplevel)
{
	shifted := specials[Shift].on;
	bank := keys[shifted];
	vals := keyvals[shifted];
	for(i:=0; i<len bank; i++) {
		key := bank[i];
		val := vals[i];
		if(key != nil){
			if(specials[CapsLock].on && len key == 1){
				if(key[0]>='A' && key[0]<='Z')	# true if also shifted
					key[0] += 'a'-'A';
				else if(key[0] >= 'a' && key[0]<='z')
					key[0] += 'A'-'a';
				val = key[0];
			}
			cmd(t, ".b" + string i + " configure -text {" + key + "} -command 'send keypress " + string val);
		}
  	}
	cmd(t, "update");
}

#
# The code makes two assumptions: strlen(ld) is 1 or 2; latintab[i].ld can be a
# prefix of latintab[j].ld only when j<i.
#
Cvlist: adt
{
	ld:	string;	# must be seen before using this conversion
	si:	string;	#  options for last input characters
	so:	string;	# the corresponding Rune for each si entry
};
latintab: array of Cvlist = array[] of {
	(" ", " i",	"␣ı"),
	("!~", "-=~",	"≄≇≉"),
	("!", "!<=>?bmp",	"¡≮≠≯‽⊄∉⊅"),
	("\"*", "IUiu",	"ΪΫϊϋ"),
	("\"", "\"AEIOUYaeiouy",	"¨ÄËÏÖÜŸäëïöüÿ"),
	("$*", "fhk",	"ϕϑϰ"),
	("$", "BEFHILMRVaefglopv",	"ℬℰℱℋℐℒℳℛƲɑℯƒℊℓℴ℘ʋ"),
	("\'\"", "Uu",	"Ǘǘ"),
	("\'", "\'ACEILNORSUYZacegilnorsuyz",	"´ÁĆÉÍĹŃÓŔŚÚÝŹáćéģíĺńóŕśúýź"),
	("*", "*ABCDEFGHIKLMNOPQRSTUWXYZabcdefghiklmnopqrstuwxyz",	"∗ΑΒΞΔΕΦΓΘΙΚΛΜΝΟΠΨΡΣΤΥΩΧΗΖαβξδεφγθικλμνοπψρστυωχηζ"),
	("+", "-O",	"±⊕"),
	(",", ",ACEGIKLNORSTUacegiklnorstu",	"¸ĄÇĘĢĮĶĻŅǪŖŞŢŲąçęģįķļņǫŗşţų"),
	("-*", "l",	"ƛ"),
	("-", "+-2:>DGHILOTZbdghiltuz~",	"∓­ƻ÷→ÐǤĦƗŁ⊖ŦƵƀðǥℏɨłŧʉƶ≂"),
	(".", ".CEGILOZceglz",	"·ĊĖĠİĿ⊙Żċėġŀż"),
	("/", "Oo",	"Øø"),
	("1", "234568",	"½⅓¼⅕⅙⅛"),
	("2", "-35",	"ƻ⅔⅖"),
	("3", "458",	"¾⅗⅜"),
	("4", "5",	"⅘"),
	("5", "68",	"⅚⅝"),
	("7", "8",	"⅞"),
	(":", ")-=",	"☺÷≔"),
	("<!", "=~",	"≨⋦"),
	("<", "-<=>~",	"←«≤≶≲"),
	("=", ":<=>OV",	"≕⋜≡⋝⊜⇒"),
	(">!", "=~",	"≩⋧"),
	(">", "<=>~",	"≷≥»≳"),
	("?", "!?",	"‽¿"),
	("@\'", "\'",	"ъ"),
	("@@", "\'EKSTYZekstyz",	"ьЕКСТЫЗекстыз"),
	("@C", "Hh",	"ЧЧ"),
	("@E", "Hh",	"ЭЭ"),
	("@K", "Hh",	"ХХ"),
	("@S", "CHch",	"ЩШЩШ"),
	("@T", "Ss",	"ЦЦ"),
	("@Y", "AEOUaeou",	"ЯЕЁЮЯЕЁЮ"),
	("@Z", "Hh",	"ЖЖ"),
	("@c", "h",	"ч"),
	("@e", "h",	"э"),
	("@k", "h",	"х"),
	("@s", "ch",	"щш"),
	("@t", "s",	"ц"),
	("@y", "aeou",	"яеёю"),
	("@z", "h",	"ж"),
	("@", "ABDFGIJLMNOPRUVXabdfgijlmnopruvx",	"АБДФГИЙЛМНОПРУВХабдфгийлмнопрувх"),
	("A", "E",	"Æ"),
	("C", "ACU",	"⋂ℂ⋃"),
	("Dv", "Zz",	"Ǆǅ"),
	("D", "-e",	"Ð∆"),
	("G", "-",	"Ǥ"),
	("H", "-H",	"Ħℍ"),
	("I", "-J",	"ƗĲ"),
	("L", "&-Jj|",	"⋀ŁǇǈ⋁"),
	("N", "JNj",	"Ǌℕǋ"),
	("O", "*+-./=EIcoprx",	"⊛⊕⊖⊙⊘⊜ŒƢ©⊚℗®⊗"),
	("P", "P",	"ℙ"),
	("Q", "Q",	"ℚ"),
	("R", "R",	"ℝ"),
	("S", "123S",	"¹²³§"),
	("T", "-u",	"Ŧ⊨"),
	("V", "=",	"⇐"),
	("Y", "R",	"Ʀ"),
	("Z", "-ACSZ",	"Ƶℤ"),
	("^", "ACEGHIJOSUWYaceghijosuwy",	"ÂĈÊĜĤÎĴÔŜÛŴŶâĉêĝĥîĵôŝûŵŷ"),
	("_\"", "AUau",	"ǞǕǟǖ"),
	("_,", "Oo",	"Ǭǭ"),
	("_.", "Aa",	"Ǡǡ"),
	("_", "AEIOU_aeiou",	"ĀĒĪŌŪ¯āēīōū"),
	("`\"", "Uu",	"Ǜǜ"),
	("`", "AEIOUaeiou",	"ÀÈÌÒÙàèìòù"),
	("a", "ben",	"↔æ∠"),
	("b", "()+-0123456789=bknpqru",	"₍₎₊₋₀₁₂₃₄₅₆₇₈₉₌♝♚♞♟♛♜•"),
	("c", "$Oagu",	"¢©∩≅∪"),
	("dv", "z",	"ǆ"),
	("d", "-adegz",	"ð↓‡°†ʣ"),
	("e", "$lmns",	"€⋯—–∅"),
	("f", "a",	"∀"),
	("g", "$-r",	"¤ǥ∇"),
	("h", "-v",	"ℏƕ"),
	("i", "-bfjps",	"ɨ⊆∞ĳ⊇∫"),
	("l", "\"$&\'-jz|",	"“£∧‘łǉ⋄∨"),
	("m", "iou",	"µ∈×"),
	("n", "jo",	"ǌ¬"),
	("o", "AOUaeiu",	"Å⊚Ůåœƣů"),
	("p", "Odgrt",	"℗∂¶∏∝"),
	("r", "\"\'O",	"”’®"),
	("s", "()+-0123456789=abnoprstu",	"⁽⁾⁺⁻⁰ⁱ⁲⁳⁴⁵⁶⁷⁸⁹⁼ª⊂ⁿº⊃√ß∍∑"),
	("t", "-efmsu",	"ŧ∃∴™ς⊢"),
	("u", "-AEGIOUaegiou",	"ʉĂĔĞĬŎŬ↑ĕğĭŏŭ"),
	("v\"", "Uu",	"Ǚǚ"),
	("v", "ACDEGIKLNORSTUZacdegijklnorstuz",	"ǍČĎĚǦǏǨĽŇǑŘŠŤǓŽǎčďěǧǐǰǩľňǒřšťǔž"),
	("w", "bknpqr",	"♗♔♘♙♕♖"),
	("x", "O",	"⊗"),
	("y", "$",	"¥"),
	("z", "-",	"ƶ"),
	("|", "Pp|",	"Þþ¦"),
	("~!", "=",	"≆"),
	("~", "-=AINOUainou~",	"≃≅ÃĨÑÕŨãĩñõũ≈"),
};

#
# Given 5 characters k[0]..k[4], find the rune or return -1 for failure.
#
unicode(k: string): int
{
	c := 0;
	for(i:=1; i<5; i++){
		r := k[i];
		c <<= 4;
		if('0'<=r && r<='9')
			c += r-'0';
		else if('a'<=r && r<='f')
			c += 10 + r-'a';
		else if('A'<=r && r<='F')
			c += 10 + r-'A';
		else
			return -1;
	}
	return c;
}

#
# Given n characters k[0]..k[n-1], find the corresponding rune or return -1 for
# failure, or something < -1 if n is too small.  In the latter case, the result
# is minus the required n.
#
latin1(k: string): int
{
	n := len k;
	if(k[0] == 'X' || n>1 && k[0] == 'x' && k[1]!='O')	# 'x' to avoid having to Shift as well
		if(n>=5)
			return unicode(k);
		else
			return -5;
	for(i := 0; i < len latintab; i++){
		l := latintab[i];
		if(k[0] == l.ld[0]){
			if(n == 1)
				return -2;
			c := 0;
			if(len l.ld == 1)
				c = k[1];
			else if(l.ld[1] != k[1])
				continue;
			else if(n == 2)
				return -3;
			else
				c = k[2];
			for(p:=0; p < len l.si; p++)
				if(l.si[p] == c && p < len l.so)
					return l.so[p];
			return -1;
		}
	}
	return -1;
}

cmd(top: ref Tk->Toplevel, c: string): string
{
	e := tk->cmd(top, c);
	if (e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "keyboard: tk error on '%s': %s\n", c, e);
	return e;
}
