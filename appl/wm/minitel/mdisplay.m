#
# Minitel display handling module
# 
# © 1998 Vita Nuova Limited.  All rights reserved.
#

MDisplay: module
{

	PATH:	con "/dis/wm/minitel/mdisplay.dis";

	# Available character sets
	videotex, semigraphic, french, american : con iota;

	# Fill() attributes bit mask
	#
	# DL CFPH WBbb bfff
	#
	# D		= Delimiter		(set "serial" attributes for rest of line)
	# L		= Lining			(underlined text & "separated" graphics)
	# C		= Concealing
	# F		= Flashing
	# P		= polarity			(1 = "inverse")
	# H		= double height
	# W		= double width		(set H+W for double size)
	# B		= bright			(0: fgwhite=lt.grey, 1: fgwhite=white)
	# bbb	= background colour
	# fff		= foreground colour

	fgBase	: con 8r001;
	bgBase	: con 8r010;
	attrBase	: con 8r100;

	fgMask	: con 8r007;
	bgMask	: con 8r070;
	attrMask	: con ~0 ^ (fgMask | bgMask);

	fgBlack, fgBlue, fgRed, fgMagenta,
	fgGreen, fgCyan, fgYellow, fgWhite : con iota * fgBase;

	bgBlack, bgBlue, bgRed, bgMagenta,
	bgGreen, bgCyan, bgYellow, bgWhite : con iota * bgBase;

	attrB, attrW, attrH, attrP, attrF, attrC, attrL, attrD : con attrBase << iota;

	#
	# Init (ctxt) : string
	# 	performs general module initialisation
	# 	creates the display window of size/position r using the
	#	given display context.
	# 	spawns refresh thread
	# 	returns reason for error, or nil on success
	#
	# Mode(rect, width, height, ulheight, delims, fontpath) : (string, ref Draw->Image)
	# 	set/reset display to given rectangle and character grid size
	#	ulheight == underline height from bottom of character cell
	#	if delims != 0 then "field" attrs for Put() are derived from
	#	preceding delimiter otherwise Put() attrs are taken as is
	#
	#  	load fonts:
	#		<fontpath>		videotex
	#		<fontpath>w		videotex double width
	#		<fontpath>h		videotex double height
	#		<fontpath>s		videotex double size
	#		<fontpath>g1		videotex semigraphics
	#		<fontpath>fr		french character set
	#		<fontpath>usa		american character set
	# 	Note:
	#	charset g2 is not directly supported, instead the symbols
	#	of g2 that do not appear in g0 (standard videotex charset)
	#	are available in videotex font using unicode char codes.
	#	Therefore controlling s/w must map g2 codes to unicode.
	#
	# Cursor(pt)
	#	move cursor to given position
	#	row number (y) is 0 based
	#	column number (x) is 1 based
	#	move cursor off-screen to hide
	#
	# Put(str, pt, charset, attr, insert)
	#	render string str at position pt in the given character set
	#	using specified attributes.
	#	if insert is non-zero,  all characters from given position to end
	#	of line are moved right by len str positions.
	#
	# Scroll(topline, nlines)
	#	move the whole displayby nlines (+ve = scroll up).
	#	exposed lines of display are set to spaces rendered with
	#	the current mode attribute flags.
	#	scroll region is from topline to bottom of display
	#
	# Reveal(reveal)
	#	reveal/hide all chars affected by Concealing attribute.
	#
	# Refresh()
	#	force screen update
	#
	# GetWord(pt) : string
	#	returns on-screen word at given graphics co-ords
	#	returns nil if blank or semigraphic charset at location
	#
	# Quit()
	#	undo Init()
	

	Init		: fn (ctxt : ref Draw->Context) : string;
	Mode	: fn (r : Draw->Rect, width, height, ulh, attr : int, fontpath : string) : (string, ref Draw->Image);
	Cursor	: fn (pt : Draw->Point);
	Put		: fn (str : string, pt : Draw->Point, chset, attr, insert : int);
	Scroll	: fn (topline, nlines : int);
	Reveal	: fn (reveal : int);
	Refresh	: fn ();
	GetWord	: fn (gfxpt : Draw->Point) : string;
	Quit		: fn ();
};
