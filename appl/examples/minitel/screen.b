#
# Occasional references are made to sections and tables in the
# France Telecom Minitel specification
#
# Copyright © 1998 Vita Nuova Limited.  All rights reserved.
#

include "mdisplay.m";

disp: MDisplay;

Rect, Point		: import Draw;

# display character sets
videotex, semigraphic, french, american	:import MDisplay;

# display foreground colour attributes
fgBlack, fgBlue, fgRed, fgMagenta,
fgGreen, fgCyan, fgYellow, fgWhite		:import MDisplay;

# display background colour attributes
bgBlack, bgBlue, bgRed, bgMagenta,
bgGreen, bgCyan, bgYellow, bgWhite	:import MDisplay;

fgMask, bgMask : import MDisplay;

# display formatting attributes
attrB, attrW, attrH, attrP, attrF, attrC, attrL, attrD	:import MDisplay;

# Initial attributes - white on black
ATTR0:	con fgWhite|bgBlack&~(attrB|attrW|attrH|attrP|attrF|attrC|attrL|attrD);

# special features
Cursor, Scroll, Insert
	: con (1 << iota);

# Screen states
Sstart, Sss2, Sesc, Srepeat, Saccent, Scsi0, Scsi1, Sus0, Sus1, Sskip,
Siso2022, Siso6429, Stransparent, Sdrcs, Sconceal, Swaitfor
		: con iota;

# Filter states
FSstart, FSesc, FSsep, FS6429, FS2022: con iota;

Screen: adt {
	m:		ref Module;			# common attributes
	ctxt:		ref Draw->Context;
	in:		chan of ref Event;		# from the terminal

	image:	ref Draw->Image;		# Mdisplay image
	dispr40, dispr80: Rect;			# 40 and 80 column display region
	oldtmode:	int;					# old terminal mode
	rows:	int;					# number of screen rows (25 for minitel)
	cols:		int;					# number of screen cols (40 or 80)
	cset:		int;					# current display charset

	pos:		Point;				# current writing position (x:1, y:0)
	attr:		int;					# display attribute set
	spec:	int;					# special features
	savepos:	Point;				# `pos' before moving to row zero
	saveattr:	int;					# `attr' before moving to row zero
	savech:	int;					# last character `Put'
	delimit:	int;					# attr changed, make next space a delimiter
	cursor:	int;					# update cursor soon

	state:	int;					# recogniser state
	a0:		int;					# recogniser arg 0
	a1:		int;					# recogniser arg 1

	fstate: int;						# filter state
	fsaved: array of byte;			# filter `chars so far'
	badp: int;						# filter because of bad parameter

	ignoredata: int;					# ignore data from

	init:		fn(s: self ref Screen, ctxt: ref Draw->Context, r40, r80: Rect);
	reset:	fn(s: self ref Screen);
	run:		fn(s: self ref Screen);
	quit:		fn(s: self ref Screen);
	setmode:	fn(s: self ref Screen, tmode: int);
	runstate:	fn(s: self ref Screen, data: array of byte);
	put:		fn(s: self ref Screen, str: string);
	msg:		fn(s: self ref Screen, str: string);
};

Screen.init(s: self ref Screen, ctxt: ref Draw->Context, r40, r80: Rect)
{
	disp =  load MDisplay MDisplay->PATH;
	if(disp == nil)
		fatal("can't load the display module: "+MDisplay->PATH);

	s.m = ref Module(0, 0);
	s.ctxt = ctxt;
	s.dispr40 = r40;
	s.dispr80 = r80;
	s.oldtmode = -1;
	s.in = chan of ref Event;
	disp->Init(s.ctxt);
	s.reset();
	s.pos = Point(1, 1);
	s.savech = 0;
	s.cursor = 1;
	s.ignoredata = 0;
	s.fstate = FSstart;
}

Screen.reset(s: self ref Screen)
{
	s.setmode(T.mode);
	indicators(s);
	s.state = Sstart;
}

Screen.run(s: self ref Screen)
{
Runloop:
	for(;;) alt {
	ev := <- s.in =>
		pick e := ev {
		Equit =>
			break Runloop;
		Eproto =>
			case e.cmd {
			Creset =>
				s.reset();
			Cproto =>
				case e.a0 {
				START =>
					case e.a1 {
					SCROLLING =>
						s.spec |= Scroll;
					}
				STOP =>
					case e.a1 {
					SCROLLING =>
						s.spec &= ~Scroll;
					}
				MIXED =>
					case e.a1 {
					MIXED1 =>		# videotex -> mixed
						if(T.mode != Mixed)
							s.setmode(Mixed);
						T.mode = Mixed;
					MIXED2 =>		# mixed -> videotex
						if(T.mode != Videotex)
							s.setmode(Videotex);
						T.mode = Videotex;
					}
				}
			Ccursor =>			# update the cursor soon
				s.cursor = 1;
			Cindicators =>
				indicators(s);
			Cscreenoff =>
				s.ignoredata = 1;
				s.state = Sstart;
			Cscreenon =>
				s.ignoredata = 0;
			* => break;
			}
		Edata =>
			if(s.ignoredata)
				continue;
			oldpos := s.pos;
			oldspec := s.spec;
			da := filter(s, e.data);
			while(len da > 0) {
				s.runstate(da[0]); 
				da = da[1:];
			}

			if(s.pos.x != oldpos.x || s.pos.y != oldpos.y || (s.spec&Cursor)^(oldspec&Cursor))
				s.cursor = 1;		
			if(s.cursor) {
				if(s.spec & Cursor)
					disp->Cursor(s.pos);
				else
					disp->Cursor(Point(-1,-1));
				s.cursor = 0;
				refresh();
			} else if(e.from == Mkeyb)
				refresh();
		}
	}
	send(nil);	
}

# row0 indicators	(1.2.2)
indicators(s: ref Screen)
{
	col: int;
	ch: string;

	attr := fgWhite|bgBlack;
	case T.state {
	Local =>
		ch = "F";
	Connecting =>
		ch = "C";
		attr |= attrF;
	Online =>
		ch = "C";
	}
	if(s.cols == 40) {
		col = 39;
		attr |= attrP;
	} else
		col = 77;
	disp->Put(ch, Point(col, 0), videotex, attr, 0);
}

Screen.setmode(s: self ref Screen, tmode: int)
{
	dispr: Rect;
	delims: int;
	ulheight: int;
	s.rows = 25;
	s.spec = 0;
	s.attr = s.saveattr = ATTR0;
	s.delimit = 0;
	s.pos = s.savepos = Point(-1, -1);
	s.cursor = 1;
	case tmode {
	Videotex =>
		s.cset = videotex;
		s.cols = 40;
		dispr = s.dispr40;
		delims = 1;
		ulheight = 2;
		s.pos = Point(1,1);
		s.spec &= ~Cursor;
	Mixed =>
#		s.cset  = french;
		s.cset  = videotex;
		s.cols = 80;
		dispr = s.dispr80;
		delims = 0;
		ulheight = 1;
		s.spec |= Scroll;
		s.pos = Point(1, 1);
	Ascii =>
		s.cset = french;
		s.cols = 80;
		dispr = s.dispr80;
		delims = 0;
		ulheight = 1;
	};
	if(tmode != s.oldtmode) {
		(nil, s.image) = disp->Mode(((0,0),(0,0)), 0, 0, 0, 0, nil);
		T.layout(s.cols);
		fontpath := sprint("/fonts/minitel/f%dx%d", s.cols, s.rows);
		(nil, s.image) = disp->Mode(dispr, s.cols, s.rows, ulheight, delims, fontpath);
		T.setkbmode(tmode);
	}
	disp->Reveal(0);	# concealing enabled (1.2.2)
	disp->Cursor(Point(-1,-1));
	s.oldtmode = tmode;
}

Screen.quit(nil: self ref Screen)
{
	disp->Quit();
}

Screen.runstate(s: self ref Screen, data: array of byte)
{
	while(len data > 0)
		case T.mode {
		Videotex =>
			data = vstate(s, data);
		Mixed =>
			data = mstate(s, data);
		Ascii =>
			data = astate(s, data);
		};
}

# process a byte from set C0
vc0(s: ref Screen, ch: int)
{
	case ch {
#	SOH =>							# not in spec, wait for 16r04
#		s.a0 = 16r04;
#		s.state = Swaitfor;
	SS2 =>
		s.state = Sss2;
	SYN =>
		s.state = Sss2;					# not in the spec, but acts like SS2
	ESC =>
		s.state = Sesc;
	SO =>
		s.cset = semigraphic;
		s.attr &= ~(attrH|attrW|attrP);	# 1.2.4.2
		s.attr &= ~attrL;				# 1.2.4.3
	SI =>
		s.cset = videotex;
		s.attr &= ~attrL;				# 1.2.4.3
		s.attr &= ~(attrH|attrW|attrP);			# some servers seem to assume this too
	SEP or SS3 =>					# 1.2.7
		s.state = Sskip;
	BS =>
		if(s.pos.x == 1) {
			if(s.pos.y == 0)
				break;
			if(s.pos.y == 1)
				s.pos.y = s.rows - 1;
			else
				s.pos.y -= 1;
			s.pos.x = s.cols;
		} else
			s.pos.x -= 1;
	HT =>
		if(s.pos.x == s.cols) {
			if(s.pos.y == 0)
				break;
			if(s.pos.y == s.rows - 1)
				s.pos.y = 1;
			else
				s.pos.y += 1;
			s.pos.x = 1;
		} else
			s.pos.x += 1;
	LF =>
		if(s.pos.y == s.rows - 1)
			if(s.spec&Scroll)
				scroll(1, 1);
			else
				s.pos.y = 1;
		else if(s.pos.y == 0) {		# restore attributes on leaving row zero
			s.pos = s.savepos;
			s.attr = s.saveattr;
		} else
			s.pos.y += 1;
	VT =>
		if(s.pos.y == 1)
			if(s.spec&Scroll)
				scroll(1, -1);
			else
				s.pos.y = s.rows - 1;
		else if(s.pos.y == 0)
			break;
		else
			s.pos.y -= 1;
	CR =>
		s.pos.x = 1;
	CAN =>
		cols := s.cols - s.pos.x + 1;
		disp->Put(dup(' ', cols), Point(s.pos.x,s.pos.y), s.cset, s.attr, 0);
	US =>
		# expect US row, col
		s.state = Sus0;
	FF =>
		s.cset = videotex;
		s.attr = ATTR0;
		s.pos = Point(1,1);
		s.spec &= ~Cursor;
		s.cursor = 1;
		clear(s);
	RS =>
		s.cset = videotex;
		s.attr = ATTR0;
		s.pos = Point(1,1);
		s.spec &= ~Cursor;
		s.cursor = 1;
	CON =>
		s.spec |= Cursor;
		s.cursor = 1;
	COFF =>
		s.spec &= ~Cursor;
		s.cursor = 1;
	REP =>
		# repeat
		s.state = Srepeat;
	NUL =>
		# padding character - ignore, but may appear anywhere
		;
	BEL =>
		# ah ...
		;
	}
}

# process a byte from the set c1 - introduced by the ESC character
vc1(s: ref Screen, ch: int)
{
	if(ISC0(ch)) {
		s.state = Sstart;
		vc0(s, ch);
		return;
	}
	if(ch >= 16r20 && ch <= 16r2f) {
		if(ch == 16r25)
			s.state = Stransparent;
		else if(ch == 16r23)
			s.state = Sconceal;
		else
			s.state = Siso2022;
		s.a0 = s.a1 = 0;
		return;
	}

	fg := bg := -1;
	case ch {
	16r35 or
	16r36 or
	16r37 =>
		s.state = Sskip;				# skip next char unless C0
		return;
		
	16r5b =>						# CSI sequence
		s.a0 = s.a1 = 0;
		if(s.pos.y > 0)				# 1.2.5.2
			s.state = Scsi0;
		return;

	# foreground colour	
	16r40 =>	fg = fgBlack;
	16r41 =>	fg = fgRed;
	16r42 =>	fg = fgGreen;
	16r43 =>	fg = fgYellow;
	16r44 =>	fg = fgBlue;
	16r45 =>	fg = fgMagenta;
	16r46 =>	fg = fgCyan;
	16r47 =>	fg = fgWhite;

	# background colour
	16r50 =>	bg = bgBlack;
	16r51 =>	bg = bgRed;
	16r52 =>	bg = bgGreen;
	16r53 =>	bg = bgYellow;
	16r54 =>	bg = bgBlue;
	16r55 =>	bg = bgMagenta;
	16r56 =>	bg = bgCyan;
	16r57 =>	bg = bgWhite;

	# flashing
	16r48 =>	s.attr |= attrF;
	16r49 =>	s.attr &= ~attrF;

	# conceal (serial attribute)
	16r58 =>	s.attr |= attrC;
			s.delimit = 1;
	16r5f =>	s.attr &= ~attrC;
			s.delimit = 1;

	# start lining (+separated graphics) (serial attribute)
	16r5a =>	s.attr |= attrL;
			s.delimit = 1;
	16r59 =>	s.attr &= ~attrL;
			s.delimit = 1;

	# reverse polarity
	16r5d =>	s.attr |= attrP;
	16r5c =>	s.attr &= ~attrP;

	# normal size
	16r4c =>
		s.attr &= ~(attrW|attrH);

	# double height
	16r4d =>
		if(s.pos.y < 2)
			break;
		s.attr &= ~(attrW|attrH);
		s.attr |= attrH;

	# double width
	16r4e =>
		if(s.pos.y < 1)
			break;
		s.attr &= ~(attrW|attrH);
		s.attr |= attrW;

	# double size
	16r4f =>
		if(s.pos.y < 2)
			break;
		s.attr |= (attrW|attrH);
	}
	if(fg >= 0) {
		s.attr &= ~fgMask;
		s.attr |= fg;
	}
	if(bg >= 0) {
		s.attr &= ~bgMask;
		s.attr |= bg;
		s.delimit = 1;
	}
	s.state = Sstart;
}


# process a SS2 character
vss2(s: ref Screen, ch: int)
{
	if(ISC0(ch)) {
		s.state = Sstart;
		vc0(s, ch);
		return;
	}
	case ch {
	16r41 or	# grave				# 5.1.2 
	16r42 or	# acute
	16r43 or	# circumflex
	16r48 or	# umlaut
	16r4b =>	# cedilla
		s.a0 = ch;
		s.state = Saccent;
		return;
	16r23 =>	ch = '£';				# Figure 2.8
	16r24 =>	ch = '$';
	16r26 =>	ch = '#';
	16r27 =>	ch = '§';
	16r2c =>	ch = 16rc3;	# '←';
	16r2d =>	ch = 16rc0;	# '↑';
	16r2e =>	ch = 16rc4;	# '→';
	16r2f =>	ch = 16rc5;	# '↓';
	16r30 =>	ch = '°';
	16r31 =>	ch = '±';
	16r38 =>	ch = '÷';
	16r3c =>	ch = '¼';
	16r3d =>	ch = '½';
	16r3e =>	ch = '¾';
	16r7a =>	ch = 'œ';
	16r6a =>	ch = 'Œ';
	16r7b =>	ch = 'ß';
	}
	s.put(tostr(ch));
	s.savech = ch;
	s.state = Sstart;
}

# process CSI functions
vcsi(s: ref Screen, ch: int)
{
	case s.state {
	Scsi0 =>
		case ch {
		# move cursor up n rows, stop at top of screen
		'A' =>
			s.pos.y -= s.a0;
			if(s.pos.y < 1)
				s.pos.y = 1;

		# move cursor down n rows, stop at bottom of screen
		'B' =>
			s.pos.y += s.a0;
			if(s.pos.y >= s.rows)
				s.pos.y = s.rows - 1;

		# move cursor n columns right, stop at edge of screen
		'C' =>
			s.pos.x += s.a0;
			if(s.pos.x > s.cols)
				s.pos.x = s.cols;

		# move cursor n columns left, stop at edge of screen
		'D' =>
			s.pos.x -= s.a0;
			if(s.pos.x < 1)
				s.pos.x = 1;

		# direct cursor addressing
		';' =>	
			s.state = Scsi1;
			return;

		'J' =>
			case s.a0 {
			# clears from the cursor to the end of the screen inclusive
			0 =>
				rowclear(s.pos.y, s.pos.x, s.cols);
				for(r:=s.pos.y+1; r<s.rows; r++)
					rowclear(r, 1, s.cols);
			# clears from the beginning of the screen to the cursor inclusive
			1 =>
				for(r:=1; r<s.pos.y; r++)
					rowclear(r, 1, s.cols);
				rowclear(s.pos.y, 1, s.pos.x);
			# clears the entire screen
			2 =>
				clear(s);
			}

		'K' => 
			case s.a0 {
			# clears from the cursor to the end of the row
			0 =>	rowclear(s.pos.y, s.pos.x, s.cols);

			# clears from the start of the row to the cursor
			1 => rowclear(s.pos.y, 1, s.pos.x);

			# clears the entire row in which the cursor is positioned
			2 => rowclear(s.pos.y, 1, s.cols);
			}

		# deletes n characters from cursor position
		'P' =>
			rowclear(s.pos.y, s.pos.x, s.pos.x+s.a0-1);

		# inserts n characters from cursor position
		'@' =>
			disp->Put(dup(' ', s.a0), Point(s.pos.x,s.pos.y), s.cset, s.attr, 1);

		# starts cursor insert mode
		'h' =>
			if(s.a0 == 4)
				s.spec |= Insert;

		'l' =>		# ends cursor insert mode
			if(s.a0 == 4)
				s.spec &= ~Insert;

		# deletes n rows from cursor row
		'M' =>
			scroll(s.pos.y, s.a0);

	 	# inserts n rows from cursor row
		'L' =>
			scroll(s.pos.y, -1*s.a0);
		}
		s.state = Sstart;
	Scsi1 =>
		case ch {
		# direct cursor addressing
		'H' =>
			if(s.a0 > 0 && s.a0 < s.rows && s.a1 > 0 && s.a1 <= s.cols)
				s.pos = Point(s.a1, s.a0);
		}
		s.state = Sstart;
	}
}

# Screen state - Videotex mode
vstate(s: ref Screen, data: array of byte): array of byte
{
	i: int;
	for(i = 0; i < len data; i++) {
		ch := int data[i];
		
		if(debug['s']) {
			cs:="";
			if(s.cset==videotex) cs = "v"; else cs="s";
			fprint(stderr, "vstate %d, %ux (%c) %.4ux %.4ux %s (%d,%d)\n", s.state, ch, ch, s.attr, s.spec, cs, s.pos.y, s.pos.x);
		}
		case s.state {
		Sstart =>
			if(ISG0(ch) || ch == SP) {
				n := 0;
				str := "";
				while(i < len data) {
					ch = int data[i];
					if(ISG0(ch) || ch == SP)
						str[n++] = int data[i++];
					else {
						i--;
						break;
					}
				}
				if(n > 0) {
					if(debug['s'])
						fprint(stderr, "vstate puts(%s)\n", str);
					s.put(str);
					s.savech = str[n-1];
				}
			} else if(ISC0(ch))
				vc0(s, ch);
			else if(ch == DEL) {
				if(s.cset == semigraphic)
					ch = 16r5f;
				s.put(tostr(ch));
				s.savech = ch;
			}
		Sss2 =>
			if(ch == NUL)			# 1.2.6.1
				continue;
			if(s.cset == semigraphic)	# 1.2.3.4
				continue;
			vss2(s, ch);
		Sesc =>
			if(ch == NUL)
				continue;
			vc1(s, ch);
		Srepeat =>
			# byte from `columns' 4 to 7 gives repeat count on 6 bits
			# of the last `Put' character
			if(ch == NUL)
				continue;
			if(ISC0(ch)) {
				s.state = Sstart;
				vc0(s, ch);
				break;
			}
			if(ch >= 16r40 && ch <= 16r7f)
				s.put(dup(s.savech, (ch-16r40))); 
			s.state = Sstart;
		Saccent =>
			case s.a0 {
			16r41 =>	# grave
				case ch {
				'a' =>	ch = 'à';
				'e' =>	ch = 'è';
				'u' =>	ch = 'ù';
				}
			16r42 =>	# acute
				case ch {
				'e' =>	ch = 'é';
				}
			16r43 =>	# circumflex
				case ch {
				'a' =>	ch = 'â';
				'e' =>	ch = 'ê';
				'i' =>		ch = 'î';
				'o' =>	ch = 'ô';
				'u' =>	ch = 'û';
				}
			16r48 =>	# umlaut
				case ch {
				'a' =>	ch = 'ä';
				'e' =>	ch = 'ë';
				'i' =>		ch = 'ï';
				'o' =>	ch = 'ö';
				'u' =>	ch = 'ü';
				}
			16r4b =>	# cedilla
				case ch {
				'c' =>	ch = 'ç';
				}
			}
			s.put(tostr(ch));
			s.savech = ch;
			s.state = Sstart;
		Scsi0 =>
			if(ch >= 16r30 && ch <= 16r39) {
				s.a0 *= 10;
				s.a0 += (ch - 16r30);
			} else if((ch >= 16r20 && ch <= 16r29) || (ch >= 16r3a && ch <= 16r3f)) {	# 1.2.7
				s.a0 = 0;
				s.state = Siso6429;
			} else
				vcsi(s, ch);
		Scsi1 =>
			if(ch >= 16r30 && ch <= 16r39) {
				s.a1 *= 10;
				s.a1 += (ch - 16r30);
			} else
				vcsi(s, ch);
		Sus0 =>
			if(ch == 16r23) {		# start DRCS definition
				s.state = Sdrcs;
				s.a0 = 0;
				break;
			}
			if(ch >= 16r40 && ch < 16r80)
				s.a0 = (ch - 16r40);
			else if(ch >= 16r30 && ch <= 16r32)
				s.a0 = (ch - 16r30);
			else
				s.a0 = -1;
			s.state = Sus1;
		Sus1 =>
			if(ch >= 16r40 && ch < 16r80)
				s.a1 = (ch - 16r40);
			else if(ch >= 16r30 && ch <= 16r39) {
				s.a1 = (ch - 16r30);
				s.a0 = s.a0*10 + s.a1;	# shouldn't be used any more
				s.a1 = 1;
			} else
				s.a1 = -1;
			# US row, col : this is how you get to row zero
			if(s.a0 >= 0 && s.a0 < s.rows && s.a1 > 0 && s.a1 <= s.cols) {
				if(s.a0 == 0 && s.pos.y > 0) {
					s.savepos = s.pos;
					s.saveattr = s.attr;
				}
				s.pos = Point(s.a1, s.a0);
				s.delimit = 0;		# 1.2.5.3, don't reset serial attributes
				s.attr = ATTR0;
				s.cset = videotex;
			}
			s.state = Sstart;
		Sskip =>
			# swallow the next character unless from C0
			s.state = Sstart;
			if(ISC0(ch))
				vc0(s, ch);
		Swaitfor =>
			# ignore characters until the character in a0 inclusive
			if(ch == s.a0)
				s.state = Sstart;
		Siso2022 =>
			# 1.2.7
			# swallow (upto) 3 characters from column 2,
			# then 1 character from columns 3 to 7
			if(ch == NUL)
				continue;
			if(ISC0(ch)) {
				s.state = Sstart;
				vc0(s, ch);
				break;
			}
			s.a0++;
			if(s.a0 <= 3) {
				if(ch >= 16r20 && ch <= 16r2f)
					break;
			}
			if (s.a0 <= 4 && ch >= 16r30 && ch <= 16r7f) {
					s.state = Sstart;
					break;
			}
			s.state = Sstart;
			s.put(tostr(DEL));
		Siso6429 =>
			# 1.2.7
			# swallow characters from column 3,
			# or column 2, then 1 from column 4 to 7
			if(ISC0(ch)) {
				s.state = Sstart;
				vc0(s, ch);
				break;
			}
			if(ch >= 16r20 && ch <= 16r3f)
					break;
			if(ch >= 16r40 && ch <= 16r7f) {
				s.state = Sstart;
				break;
			}
			s.state = Sstart;	
			s.put(tostr(DEL));
		Stransparent =>
			# 1.2.7
			# ignore all codes until ESC, 25, 40 or ESC, 2F, 3F
			# progress in s.a0 and s.a1
			match := array [] of {
					array [] of { ESC,	16r25,	16r40 },
					array [] of { ESC,	16r2f,	16r3f },
			};
			if(ch == ESC) {
				s.a0 = s.a1 = 1;
				break;
			}
			if(ch == match[0][s.a0])
				s.a0++;
			else
				s.a0 = 0;
			if(ch == match[1][s.a1])
				s.a1++;
			else
				s.a1 = 0;
			if(s.a0 == 3 || s.a1 == 3)
				s.state = Sstart;
		Sdrcs =>
			if(s.a0 > 0) {			# fixed number of bytes to skip in a0
				s.a0--;
				if(s.a0 == 0) {
					s.state = Sstart;
					break;
				}
			} else if(ch == US)		# US XX YY - end of DRCS
				s.state = Sus0;
			else if(ch == 16r20)	# US 23 20 20 20 4[23] 49
				s.a0 = 4;
		Sconceal =>
			# 1.2.4.4
			# ESC 23 20 58 - Conceal fields
			# ESC 23 20 5F - Reveal fields
			# ESC 23 21 XX - Filter
			# progress in s.a0
			case s.a0 {
			0 =>
				if(ch == 16r20 || ch == 16r21)
					s.a0 = ch;
			16r20 =>
				case ch {
				16r58 =>
					disp->Reveal(0);
					disp->Refresh();
				16r5f =>
					disp->Reveal(1);
					disp->Refresh();
				}
				s.state = Sstart;
			16r21 =>
				s.state = Sstart;
			}
		}
	}
	if (i < len data)
		return data[i:];
	else
		return nil;
}

# Screen state - Mixed mode
mstate(s: ref Screen, data: array of byte): array of byte
{
	i: int;
Stateloop:
	for(i = 0; i < len data; i++) {
		ch := int data[i];
		
		if(debug['s']) {
			cs:="";
			if(s.cset==videotex) cs = "v"; else cs="s";
			fprint(stderr, "mstate %d, %ux (%c) %.4ux %.4ux %s (%d,%d)\n", s.state, ch, ch, s.attr, s.fstate, cs, s.pos.y, s.pos.x);
		}
		case s.state {
		Sstart =>
			if(ISG0(ch) || ch == SP) {
				n := 0;
				str := "";
				while(i < len data) {
					ch = int data[i];
					if(ISG0(ch) || ch == SP)
						str[n++] = int data[i++];
					else {
						i--;
						break;
					}
				}
				if(n > 0) {
					if(debug['s'])
						fprint(stderr, "mstate puts(%s)\n", str);
					s.put(str);
					s.savech = str[n-1];
				}
			} else if(ISC0(ch))
				mc0(s, ch);
			else if(ch == DEL) {
				if(s.cset == semigraphic)
					ch = 16r5f;
				s.put(tostr(ch));
				s.savech = ch;
			}
		Sesc =>
			if(ch == NUL)
				continue;
			mc1(s, ch);
		Scsi0 =>
			if(ch >= 16r30 && ch <= 16r39) {
				s.a0 *= 10;
				s.a0 += (ch - 16r30);
			} else if(ch == '?') {
				s.a0 = '?';
			} else 
				mcsi(s, ch);
			if(T.mode != Mixed)	# CSI ? { changes to Videotex mode
				break Stateloop;
		Scsi1 =>
			if(ch >= 16r30 && ch <= 16r39) {
				s.a1 *= 10;
				s.a1 += (ch - 16r30);
			} else
				mcsi(s, ch);
		Sus0 =>
			if(ch >= 16r40 && ch < 16r80)
				s.a0 = (ch - 16r40);
			else if(ch >= 16r30 && ch <= 16r32)
				s.a0 = (ch - 16r30);
			else
				s.a0 = -1;
			s.state = Sus1;
		Sus1 =>
			if(ch >= 16r40 && ch < 16r80)
				s.a1 = (ch - 16r40);
			else if(ch >= 16r30 && ch <= 16r39) {
				s.a1 = (ch - 16r30);
				s.a0 = s.a0*10 + s.a1;	# shouldn't be used any more
				s.a1 = 1;
			} else
				s.a1 = -1;
			# US row, col : this is how you get to row zero
			if(s.a0 >= 0 && s.a0 < s.rows && s.a1 > 0 && s.a1 <= s.cols) {
				if(s.a0 == 0 && s.pos.y > 0) {
					s.savepos = s.pos;
					s.saveattr = s.attr;
				}
				s.pos = Point(s.a1, s.a0);
				s.delimit = 0;		# 1.2.5.3, don't reset serial attributes
				s.attr = ATTR0;
				s.cset = videotex;
			}
			s.state = Sstart;
		Siso6429 =>
			# 1.2.7
			# swallow characters from column 3,
			# or column 2, then 1 from column 4 to 7
			if(ISC0(ch)) {
				s.state = Sstart;
				mc0(s, ch);
				break;
			}
			if(ch >= 16r20 && ch <= 16r3f)
					break;
			if(ch >= 16r40 && ch <= 16r7f) {
				s.state = Sstart;
				break;
			}
			s.state = Sstart;	
			s.put(tostr(DEL));
		}
	}
	if (i < len data)
		return data[i:];
	else
		return nil;
	return nil;
}

# process a byte from set C0 - Mixed mode
mc0(s: ref Screen, ch: int)
{
	case ch {
	ESC =>
		s.state = Sesc;
	SO =>
#		s.cset = french;
		;
	SI =>
#		s.cset = american;
		;
	BS =>
		if(s.pos.x > 1)
			s.pos.x -= 1;
	HT =>
		s.pos.x += 8;
		if(s.pos.x > s.cols)
			s.pos.x = s.cols;
	LF or VT or FF =>
		if(s.pos.y == s.rows - 1)
			if(s.spec&Scroll)
				scroll(1, 1);
			else
				s.pos.y = 1;
		else if(s.pos.y == 0) {		# restore attributes on leaving row zero
			if(ch == LF) {		# 4.5
				s.pos = s.savepos;
				s.attr = s.saveattr;
			}
		} else
			s.pos.y += 1;
	CR =>
		s.pos.x = 1;
	CAN or SUB =>	# displays the error symbol - filled in rectangle
		disp->Put(dup(16r5f, 1), Point(s.pos.x,s.pos.y), s.cset, s.attr, 0);
	NUL =>
		# padding character - ignore, but may appear anywhere
		;
	BEL =>
		# ah ...
		;
	XON =>	# screen copying
		;
	XOFF =>	# screen copying
		;
	US =>
		# expect US row, col
		s.state = Sus0;
	}
}

# process a byte from the set c1 - introduced by the ESC character - Mixed mode
mc1(s: ref Screen, ch: int)
{
	if(ISC0(ch)) {
		s.state = Sstart;
		mc0(s, ch);
		return;
	}
	case ch {
	16r5b =>						# CSI sequence
		s.a0 = s.a1 = 0;
		if(s.pos.y > 0)				# 1.2.5.2
			s.state = Scsi0;
		return;

	16r44 or						# IND like LF
	16r45 =>						# NEL like CR LF
		if(ch == 16r45)
			s.pos.x = 1;
		if(s.pos.y == s.rows - 1)
			if(s.spec&Scroll)
				scroll(1, 1);
			else
				s.pos.y = 1;
		else if(s.pos.y == 0) {		# restore attributes on leaving row zero
			s.pos = s.savepos;
			s.attr = s.saveattr;
		} else
			s.pos.y += 1;
	16r4d =>						# RI
		if(s.pos.y == 1)
			if(s.spec&Scroll)
				scroll(1, -1);
			else
				s.pos.y = s.rows - 1;
		else if(s.pos.y == 0)
			break;
		else
			s.pos.y -= 1;
	}
	s.state = Sstart;
}


# process CSI functions - Mixed mode
mcsi(s: ref Screen, ch: int)
{
	case s.state {
	Scsi0 =>
		case ch {
		# move cursor up n rows, stop at top of screen
		'A' =>
			if(s.a0 == 0)
				s.a0 = 1;
			s.pos.y -= s.a0;
			if(s.pos.y < 1)
				s.pos.y = 1;

		# move cursor down n rows, stop at bottom of screen
		'B' =>
			if(s.a0 == 0)
				s.a0 = 1;
			s.pos.y += s.a0;
			if(s.pos.y >= s.rows)
				s.pos.y = s.rows - 1;

		# move cursor n columns right, stop at edge of screen
		'C' =>
			if(s.a0 == 0)
				s.a0 = 1;
			s.pos.x += s.a0;
			if(s.pos.x > s.cols)
				s.pos.x = s.cols;

		# move cursor n columns left, stop at edge of screen
		'D' =>
			if(s.a0 == 0)
				s.a0 = 1;
			s.pos.x -= s.a0;
			if(s.pos.x < 1)
				s.pos.x = 1;

		# second parameter
		';' =>	
			s.state = Scsi1;
			return;

		'J' =>
			case s.a0 {
			# clears from the cursor to the end of the screen inclusive
			0 =>
				rowclear(s.pos.y, s.pos.x, s.cols);
				for(r:=s.pos.y+1; r<s.rows; r++)
					rowclear(r, 1, s.cols);
			# clears from the beginning of the screen to the cursor inclusive
			1 =>
				for(r:=1; r<s.pos.y; r++)
					rowclear(r, 1, s.cols);
				rowclear(s.pos.y, 1, s.pos.x);
			# clears the entire screen
			2 =>
				clear(s);
			}

		'K' => 
			case s.a0 {
			# clears from the cursor to the end of the row
			0 =>	rowclear(s.pos.y, s.pos.x, s.cols);

			# clears from the start of the row to the cursor
			1 => rowclear(s.pos.y, 1, s.pos.x);

			# clears the entire row in which the cursor is positioned
			2 => rowclear(s.pos.y, 1, s.cols);
			}

		# inserts n characters from cursor position
		'@' =>
			disp->Put(dup(' ', s.a0), Point(s.pos.x,s.pos.y), s.cset, s.attr, 1);

		# starts cursor insert mode
		'h' =>
			if(s.a0 == 4)
				s.spec |= Insert;

		'l' =>		# ends cursor insert mode
			if(s.a0 == 4)
				s.spec &= ~Insert;

	 	# inserts n rows from cursor row
		'L' =>
			scroll(s.pos.y, -1*s.a0);
			s.pos.x = 1;

		# deletes n rows from cursor row
		'M' =>
			scroll(s.pos.y, s.a0);
			s.pos.x = 1;

		# deletes n characters from cursor position
		'P' =>
			rowclear(s.pos.y, s.pos.x, s.pos.x+s.a0-1);

		# select Videotex mode
		'{' =>
			if(s.a0 == '?') {
				T.mode = Videotex;
				s.setmode(T.mode);
			}

		# display attributes
		'm' =>
			case s.a0 {
			0 =>		s.attr &= ~(attrL|attrF|attrP|attrB);
			1 =>		s.attr |= attrB;
			4 =>		s.attr |= attrL;
			5 =>		s.attr |= attrF;
			7 =>		s.attr |= attrP;
			22 =>	s.attr &= ~attrB;
			24 =>	s.attr &= ~attrL;
			25 =>	s.attr &= ~attrF;
			27 =>	s.attr &= ~attrP;
			}
		# direct cursor addressing
		'H' =>
			if(s.a0 == 0)
				s.a0 = 1;
			if(s.a1 == 0)
				s.a1 = 1;
			if(s.a0 > 0 && s.a0 < s.rows && s.a1 > 0 && s.a1 <= s.cols)
				s.pos = Point(s.a1, s.a0);
		}
		s.state = Sstart;
	Scsi1 =>
		case ch {
		# direct cursor addressing
		'H' =>
			if(s.a0 == 0)
				s.a0 = 1;
			if(s.a1 == 0)
				s.a1 = 1;
			if(s.a0 > 0 && s.a0 < s.rows && s.a1 > 0 && s.a1 <= s.cols)
				s.pos = Point(s.a1, s.a0);
		}
		s.state = Sstart;
	}
}


# Screen state - ASCII mode
astate(nil: ref Screen, nil: array of byte): array of byte
{
	return nil;
}

# Put a string in the current attributes to the current writing position
Screen.put(s: self ref Screen, str: string)
{
	while((l := len str) > 0) {
		n := s.cols - s.pos.x + 1;		# characters that will fit on this row
		if(s.attr & attrW) {
			if(n > 1)				# fit normal width character in last column
				n /= 2;
		}
		if(n > l)
			n = l;
		if(s.delimit) {		# set delimiter bit on 1st space (if any)
			for(i:=0; i<n; i++)
				if(str[i] == ' ')
					break;
			if(i > 0) {
				disp->Put(str[0:i], s.pos, s.cset, s.attr, s.spec&Insert);
				incpos(s, i);
			}
			if(i < n) {
				if(debug['s']) {
					cs:="";
					if(s.cset==videotex) cs = "v"; else cs="s";
					fprint(stderr, "D %ux %s\n", s.attr|attrD, cs);
				}
				disp->Put(tostr(str[i]), s.pos, s.cset, s.attr|attrD, s.spec&Insert);
				incpos(s, 1);
				s.delimit = 0;
				# clear serial attributes once used
				# hang onto background attribute - needed for semigraphics
				case s.cset {
				videotex =>
					s.attr &= ~(attrL|attrC);
				semigraphic =>
					s.attr &= ~(attrC);
				}
			}
			if(i < n-1) {
				disp->Put(str[i+1:n], s.pos, s.cset, s.attr, s.spec&Insert);
				incpos(s, n-(i+1));
			}
		} else {
			disp->Put(str[0:n], s.pos, s.cset, s.attr, s.spec&Insert);
			incpos(s, n);
		}
		if(n < len str)
			str = str[n:];
		else
			str = nil;
	}
#	if(T.state == Local || T.spec&Echo)
#		refresh();
}

# increment the current writing position by `n' cells.
# caller must ensure that `n' characters can fit
incpos(s: ref Screen, n: int)
{
	if(s.attr & attrW)
		s.pos.x += 2*n;
	else
		s.pos.x += n;
	if(s.pos.x > s.cols)
		if(s.pos.y == 0)			# no wraparound from row zero
			s.pos.x = s.cols;
		else {
			s.pos.x = 1;
			if(s.pos.y == s.rows - 1 && s.spec&Scroll) {
				if(s.attr & attrH) {
					scroll(1, 2);
				} else {
					scroll(1, 1);
					rowclear(s.pos.y, 1, s.cols);
				}
			} else {
				if(s.attr & attrH)
					s.pos.y += 2;
				else
					s.pos.y += 1;
				if(s.pos.y >= s.rows)
					s.pos.y -= (s.rows-1);
			}
		}
}

# clear row `r' from `first' to `last' column inclusive
rowclear(r, first, last: int)
{
	# 16r5f is the semi-graphic black rectangle
	disp->Put(dup(16r5f, last-first+1), Point(first,r), semigraphic, fgBlack, 0);
#	disp->Put(dup(' ', last-first+1), Point(first,r), S.cset, fgBlack, 0);
}

clear(s: ref Screen)
{
	for(r:=1; r<s.rows; r++)
		rowclear(r, 1, s.cols);
}

# called to suggest a display update
refresh()
{
	disp->Refresh();
}

# scroll the screen
scroll(topline, nlines: int)
{
	disp->Scroll(topline, nlines);
	disp->Refresh();
}

# filter the specified ISO6429 and ISO2022 codes from the screen input
# TODO: filter some ISO2022 sequences
filter(s: ref Screen, data: array of byte): array of array of byte
{
	case T.mode {
	Videotex =>
		return vfilter(s, data);
	Mixed =>
		return mfilter(s, data);
	Ascii =>
		return afilter(s, data);
	}
	return nil;
}

# filter the specified ISO6429 and ISO2022 codes from the screen input
vfilter(s: ref Screen, data: array of byte): array of array of byte
{
	ba := array [0] of array of byte;
	changed := 0;

	d0 := 0;
	for(i:=0; i<len data; i++) {
		ch := int data[i];
		case s.fstate {
		FSstart =>
			if(ch == ESC) {
				s.fstate = FSesc;
				changed = 1;
				if(i > d0)
					ba = dappend(ba, data[d0:i]);
				d0 = i+1;
			}
		FSesc =>
			d0 = i+1;
			changed = 1;
			if(ch == '[') {
				s.fstate = FS6429;
				s.fsaved = array [0] of byte;
				s.badp = 0;
#			} else if(ch == 16r20) {
#				s.fstate = FS2022;
#				s.fsaved = array [0] of byte;
				s.badp = 0;
			} else if(ch == ESC) {
				ba = dappend(ba, array [] of { byte ESC });
				s.fstate = FSesc;
			} else {
				# false alarm - don't filter
				ba = dappend(ba, array [] of { byte ESC, byte ch });
				s.fstate = FSstart;
			}
		FS6429 =>	# filter out invalid CSI sequences
			d0 = i+1;
			changed = 1;
			if(ch >= 16r20 && ch <= 16r3f) {
				if((ch < 16r30 || ch > 16r39) && ch != ';')
					s.badp = 1;
				a := array [len s.fsaved + 1] of byte;
				a[0:] = s.fsaved[0:];
				a[len a - 1] = byte ch;
				s.fsaved = a;
			} else {
				valid := 1;
				case  ch {
				'A' =>	;
				'B' =>	;
				'C' =>	;
				'D' =>	;
				'H' =>	;	
				'J' =>		;
				'K' =>	; 
				'P' =>	;
				'@' =>	;
				'h' =>	;
				'l' =>		;	
				'M' =>	;
				'L' =>	;
				* =>
					valid = 0;
				}
				if(s.badp)
					valid = 0;
				if(debug['f'])
					fprint(stderr, "vfilter %d: %s%c\n", valid, string s.fsaved, ch);
				if(valid) {		# false alarm - don't filter
					ba = dappend(ba, array [] of { byte ESC, byte '[' });
					ba = dappend(ba, s.fsaved);
					ba = dappend(ba, array [] of { byte ch } );
				}
				s.fstate = FSstart;
			} 
		FS2022 =>	;
		}
	}
	if(changed) {
		if(i > d0)
			ba = dappend(ba, data[d0:i]);
		return ba;
	}
	return array [] of { data };
}

# filter the specified ISO6429 and ISO2022 codes from the screen input - Videotex
mfilter(s: ref Screen, data: array of byte): array of array of byte
{
	ba := array [0] of array of byte;
	changed := 0;

	d0 := 0;
	for(i:=0; i<len data; i++) {
		ch := int data[i];
		case s.fstate {
		FSstart =>
			case ch {
			ESC =>
				s.fstate = FSesc;
				changed = 1;
				if(i > d0)
					ba = dappend(ba, data[d0:i]);
				d0 = i+1;
			SEP =>
				s.fstate = FSsep;
				changed = 1;
				if(i > d0)
					ba = dappend(ba, data[d0:i]);
				d0 = i+1;
			}
		FSesc =>
			d0 = i+1;
			changed = 1;
			if(ch == '[') {
				s.fstate = FS6429;
				s.fsaved = array [0] of byte;
				s.badp = 0;
			} else if(ch == ESC) {
				ba = dappend(ba, array [] of { byte ESC });
				s.fstate = FSesc;
			} else {
				# false alarm - don't filter
				ba = dappend(ba, array [] of { byte ESC, byte ch });
				s.fstate = FSstart;
			}
		FSsep =>
			d0 = i+1;
			changed = 1;
			if(ch == ESC) {
				ba = dappend(ba, array [] of { byte SEP });
				s.fstate = FSesc;
			} else if(ch == SEP) {
				ba = dappend(ba, array [] of { byte SEP });
				s.fstate = FSsep;
			} else {
				if(ch >= 16r00 && ch <= 16r1f)
					ba = dappend(ba, array [] of { byte SEP , byte ch });
				# consume the character
				s.fstate = FSstart;
			}
		FS6429 =>	# filter out invalid CSI sequences
			d0 = i+1;
			changed = 1;
			if(ch >= 16r20 && ch <= 16r3f) {
				if((ch < 16r30 || ch > 16r39) && ch != ';' && ch != '?')
					s.badp = 1;
				a := array [len s.fsaved + 1] of byte;
				a[0:] = s.fsaved[0:];
				a[len a - 1] = byte ch;
				s.fsaved = a;
			} else {
				valid := 1;
				case  ch {
				'm' =>	;
				'A' =>	;
				'B' =>	;
				'C' =>	;
				'D' =>	;
				'H' =>	;
				'J' =>		;
				'K' =>	; 
				'@' =>	;
				'h' =>	;
				'l' =>		;	
				'L' =>	;
				'M' =>	;
				'P' =>	;
				'{' =>	# allow CSI ? {
					n := len s.fsaved;
					if(n == 0 || s.fsaved[n-1] != byte '?')
						s.badp = 1;
				* =>
					valid = 0;
				}
				if(s.badp)	# only decimal params
					valid = 0;
				if(debug['f'])
					fprint(stderr, "mfilter %d: %s%c\n", valid, string s.fsaved, ch);
				if(valid) {		# false alarm - don't filter
					ba = dappend(ba, array [] of { byte ESC, byte '[' });
					ba = dappend(ba, s.fsaved);
					ba = dappend(ba, array [] of { byte ch } );
				}
				s.fstate = FSstart;
			} 
		FS2022 =>	;
		}
	}
	if(changed) {
		if(i > d0)
			ba = dappend(ba, data[d0:i]);
		return ba;
	}
	return array [] of { data };
}

# filter the specified ISO6429 and ISO2022 codes from the screen input - Videotex
afilter(nil: ref Screen, data: array of byte): array of array of byte
{
	return array [] of { data };
}

# append to an array of array of byte
dappend(ba: array of array of byte, b: array of byte): array of array of byte
{
	l := len ba;
	na := array [l+1] of array of byte;
	na[0:] = ba[0:];
	na[l] = b;
	return na;
}

# Put a diagnostic string to row 0
Screen.msg(s: self ref Screen, str: string)
{
	blank := string array [s.cols -4] of {* => byte ' '};
	n := len str;
	if(n > s.cols - 4)
		n = s.cols - 4;
	disp->Put(blank, Point(1, 0), videotex, 0, 0);
	if(str != nil)
		disp->Put(str[0:n], Point(1, 0), videotex, fgWhite|attrB, 0);
	disp->Refresh();
}