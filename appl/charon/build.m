Build: module
{
PATH: con "/dis/charon/build.dis";

# Item layout is dictated by desire to have all but formfield and table
# items allocated in one piece.
# Also aiming for the 128-byte allocation quantum, which means
# keeping the total size at 17 32-bit words, including pick tag.
Item: adt
{
	next:		cyclic ref Item;	# successor in list of items
	width:	int;			# width in pixels (0 for floating items)
	height:	int;			# height in pixels
	ascent:	int;			# ascent (from top to baseline) in pixels
	anchorid:	int;			# if nonzero, which anchor we're in
	state:	int;			# flags and values (see below)
	genattr:	ref Genattr;	# generic attributes and events

	pick {
		Itext =>
			s: string;		# the characters
			fnt: int;		# style*NumSize+size (see font stuff, below)
			fg: int;		# Pixel (color) for text
			voff: byte;		# Voffbias+vertical offset from baseline, in pixels (+ve == down)
			ul: byte;		# ULnone, ULunder, or ULmid
		Irule =>
			align: byte;	# alignment spec
			noshade: byte;	# if true, don't shade
			size: int;		# size attr (rule height)
			wspec: Dimen;	# width spec
		Iimage =>
			imageid: int;		# serial no. of image within its doc
			ci: ref CharonUtils->CImage;		# charon image (has src, actual width, height)
			imwidth: int;		# spec width (actual, if no spec)
			imheight: int;		# spec height (actual, if no spec)
			altrep: string;		# alternate representation, in absence of image
			map: ref Map;		# if non-nil, client side map
			name: string;		# name attribute
			ctlid: int;			# if animated
			align: byte;		# vertical alignment
			hspace: byte;		# in pixels; buffer space on each side
			vspace: byte;		# in pixels; buffer space on top and bottom
			border: byte;		# in pixels: border width to draw around image
		Iformfield =>
			formfield: ref Formfield;
		Itable =>
			table: ref Table;
		Ifloat =>
			item: ref Item;		# content of float
			x: int;			# x coord of top (from right, if Aright)
			y: int;			# y coord of top
			side: byte;			# margin it floats to: Aleft or Aright
			infloats: byte;		# true if this has been added to a lay.floats
		Ispacer =>
			spkind: int;		# ISPnone, etc.
			fnt: int;			# font number
		Ibox =>
			content: cyclic ref Item;	# child items
			cstyle: ref ComputedStyle;	# computed CSS properties
			layid: int;			# sublayout id
	}

	newtext: fn(s: string, fnt, fg, voff: int, ul: byte) : ref Item;
	newrule: fn(align: byte, size, noshade: int, wspec: Dimen) : ref Item;
	newimage: fn(di: ref Docinfo, src: ref Url->Parsedurl, lowsrc: ref Url->Parsedurl, altrep: string,
		align: byte, width, height, hspace, vspace, border, ismap, isbkg: int,
		map: ref Map, name: string, genattr: ref Genattr) : ref Item;
	newformfield: fn(ff: ref Formfield) : ref Item;
	newtable: fn(t: ref Table) : ref Item;
	newfloat: fn(i: ref Item, side: byte) : ref Item;
	newspacer: fn(spkind, font: int) : ref Item;
	newbox: fn(content: ref Item, cs: ref ComputedStyle) : ref Item;

	revlist: fn(itl: list of ref Item) : list of ref Item;
	print: fn(it: self ref Item);
	printlist: fn(items: self ref Item, msg: string);
};

# Item state flags and value fields
IFbrk:		con (1<<31);	# forced break before this item
IFbrksp:		con (1<<30);	# add 1 line space to break (IFbrk set too)
IFnobrk:		con (1<<29);	# break not allowed before this item
IFcleft:		con (1<<28);	# clear left floats (IFbrk set too)
IFcright:		con (1<<27);	# clear right floats (IFbrk set too)
IFwrap:		con (1<<26);	# in a wrapping (non-pre) line
IFhang:		con (1<<25);	# in a hanging (into left indent) item
IFrjust:		con (1<<24);	# right justify current line
IFcjust:		con (1<<23);	# center justify current line
IFsmap:		con (1<<22);	# image is server-side map
IFbkg:		con (1<<21);	# Item.image is a background image
IFindentshift:	con 8;
IFindentmask:	con (255<<IFindentshift);	# current indent, in tab stops
IFhangmask:	con 255;	# current hang into left indent, in 1/10th tabstops

Voffbias:	con 128;

# Spacer kinds.  ISPnull has 0 height and width,
# ISPvline has height/ascent of current font
# ISPhspace has width of space in current font
# ISPgeneral used for other purposes (e.g. between list markers and list).
ISPnull, ISPvline, ISPhspace, ISPgeneral: con iota;

# Generic attributes and events (not many elements will have any of these set)
Genattr: adt
{
	id: string;			# document-wide unique id
	class: string;		# space-separated list of classes
	style: string;		# associated style info
	title: string;		# advisory title
	events: list of Lex->Attr;	# attid will be Aonblur, etc., value is script
	evmask: int;		# Aonblur|Aonfocus, etc. when present
};

# Parsed CSS style properties from inline style="" or <style> blocks
STYLNONE: con -1;		# "not set" sentinel for int style properties
DSPNORMAL: con 0;		# display: normal (default)
DSPNONE: con 1;		# display: none
DSPBLOCK: con 2;		# display: block
DSPINLINE: con 3;		# display: inline
DSPINLINEBLOCK: con 4;	# display: inline-block
DSPLISTITEM: con 5;		# display: list-item
DSPTABLE: con 6;		# display: table
DSPTABLEROW: con 7;		# display: table-row
DSPTABLECELL: con 8;		# display: table-cell
DSPTABLECAPTION: con 9;	# display: table-caption

# Border styles
BSnone, BSsolid, BSdotted, BSdashed, BSdouble, BSgroove, BSridge, BSinset, BSoutset: con byte iota;

# Position types
POSstatic, POSrelative: con byte iota;

# Float types
FLnone, FLleft, FLright: con byte iota;

# Clear types
CLnone, CLleft, CLright, CLboth: con byte iota;

# White-space types
WSnormal, WSpre, WSnowrap, WS_prewrap: con byte iota;

# Text-transform types
TTnone, TTuppercase, TTlowercase, TTcapitalize: con byte iota;

# Overflow types
OVvisible, OVhidden, OVscroll, OVauto: con byte iota;

# List-style-position types
LSPoutside, LSPinside: con byte iota;

# Visibility types
VISvisible, VIShidden, VIScollapse: con byte iota;

StyleInfo: adt
{
	color: int;		# text color, STYLNONE if not set
	bgcolor: int;		# background color, STYLNONE if not set
	halign: byte;		# text-align (Aleft, etc.), Anone if not set
	fontstyle: int;		# FntR/FntI/FntB/FntT, STYLNONE if not set
	fontsize: int;		# Tiny..Verylarge, STYLNONE if not set
	ul: int;		# ULnone/ULunder/ULmid, STYLNONE if not set
	display: int;		# DSPNORMAL or DSPNONE
};

# Extended CSS computed style for HTML 4.01 box model
ComputedStyle: adt
{
	# Text (overlaps with StyleInfo for compatibility)
	color: int;			# text color, STYLNONE if not set
	bgcolor: int;			# background color, STYLNONE if not set
	halign: byte;			# text-align, Anone if not set
	fontstyle: int;			# FntR/FntI/FntB/FntT, STYLNONE if not set
	fontsize: int;			# Tiny..Verylarge, STYLNONE if not set
	ul: int;			# ULnone/ULunder/ULmid, STYLNONE if not set
	display: int;			# DSPNORMAL..DSPTABLECAPTION

	# Box model
	margin: array of int;		# [top, right, bottom, left] in pixels; STYLNONE = not set
	padding: array of int;		# [top, right, bottom, left] in pixels
	border_width: array of int;	# [top, right, bottom, left] in pixels
	border_style: array of byte;	# [top, right, bottom, left] BSnone..BSoutset
	border_color: array of int;	# [top, right, bottom, left] colors

	# Dimensions
	width: Dimen;			# element width
	height: Dimen;			# element height
	min_width: Dimen;		# minimum width
	max_width: Dimen;		# maximum width
	min_height: Dimen;		# minimum height
	max_height: Dimen;		# maximum height

	# Text properties
	white_space: byte;		# WSnormal..WS_prewrap
	text_transform: byte;		# TTnone..TTcapitalize
	line_height: int;		# line height in pixels, STYLNONE if not set
	text_indent: int;		# first-line indent in pixels
	letter_spacing: int;		# extra spacing between letters, STYLNONE if not set
	word_spacing: int;		# extra spacing between words, STYLNONE if not set
	vertical_align: byte;		# Anone, Atop, Amiddle, etc.

	# List
	list_style_type: byte;		# LTdisc, LTsquare, etc.
	list_style_position: byte;	# LSPoutside or LSPinside

	# Table
	border_collapse: byte;		# 0=separate, 1=collapse
	border_spacing: int;		# spacing between cells in pixels
	empty_cells: byte;		# 0=show, 1=hide
	table_layout: byte;		# 0=auto, 1=fixed

	# Positioning
	position: byte;			# POSstatic or POSrelative
	float_: byte;			# FLnone, FLleft, FLright
	clear: byte;			# CLnone..CLboth
	rel_top: int;			# relative position offset top
	rel_left: int;			# relative position offset left

	# Other
	overflow: byte;			# OVvisible..OVauto
	visibility: byte;		# VISvisible..VIScollapse

	new: fn() : ref ComputedStyle;
	tostyleinfo: fn(cs: self ref ComputedStyle) : StyleInfo;
	fromstyleinfo: fn(si: StyleInfo) : ref ComputedStyle;
	hasboxmodel: fn(cs: self ref ComputedStyle) : int;
};

# Element context for CSS selector matching
ElementCtx: adt
{
	tag: int;				# tag number (LX->Ta, etc.)
	id: string;				# element id attribute
	class: string;			# element class attribute
	parent: cyclic ref ElementCtx;	# parent element
	child_index: int;			# index among siblings

	new: fn(tag: int, id, class: string, parent: ref ElementCtx) : ref ElementCtx;
};

# CSS stylesheet store -- replaces simple tag-indexed array
StyleStore: adt
{
	sheets: list of ref Stylesheet;		# parsed stylesheets in document order
	tagstyles: array of ref StyleInfo;	# legacy tag-indexed styles (fallback)

	new: fn() : ref StyleStore;
	addsheet: fn(ss: self ref StyleStore, sheet: ref Stylesheet);
	match: fn(ss: self ref StyleStore, el: ref ElementCtx) : ref ComputedStyle;
};

# CSS Stylesheet and related types (mirrors css.m for storage)
Stylesheet: adt
{
	rules: list of ref StyleRule;	# flattened rules from parsed CSS
};

StyleRule: adt
{
	specificity: int;		# CSS specificity for cascade ordering
	selectors: list of ref SelectorPart;	# selector chain
	property: string;		# CSS property name
	value: string;			# CSS property value string
	important: int;			# !important flag
};

SelectorPart: adt
{
	stype: int;			# SPelement, SPclass, etc.
	name: string;			# tag name, class name, or id
	combinator: int;		# 0=subject, ' '=descendant, '>'=child, '+'=adjacent
};

# Selector part types
SPelement, SPclass, SPid, SPpseudo, SPany: con iota;


# Formfield Item: a field from a form

# form field types (ints because often case on them)
Ftext, Fpassword, Fcheckbox, Fradio, Fsubmit, Fhidden, Fimage,
		Freset, Ffile, Fbutton, Fselect, Ftextarea: con iota;

Formfield: adt
{
	ftype: int;		# Ftext, Fpassword, etc.
	fieldid: int;		# serial no. of field within its form
	form: cyclic ref Form;	# containing form
	name: string;		# name attr
	value: string;		# value attr
	size: int;			# size attr
	maxlength: int;		# maxlength attr
	rows: int;			# rows attr
	cols: int;			# cols attr
	flags: byte;		# FFchecked, etc.
	options: list of ref Option;	# for Fselect fields
	image: cyclic ref Item;	# image item, for Fimage fields
	ctlid: int;			# identifies control for this field in layout
	events: list of Lex->Attr;	# same as genattr.events of containing item
	evmask: int;

	new: fn(ftype, fieldid: int, form: ref Form, name, value: string, size, maxlength: int) : ref Formfield;
};

# Form flags
FFchecked: con byte (1<<7);
FFmultiple: con byte (1<<6);

# Option holds info about an option in a "select" form field
Option: adt {
	selected: int;		# true if selected initially
	value: string;		# value attr
	display: string;	# display string
	optgroup: string;	# optgroup label, or nil
};

# Form holds info about a form
Form: adt
{
	formid: int;		# serial no. of form within its doc
	name: string;		# name or id attr (netscape uses name, HTML 4.0 uses id)
	action: ref Url->Parsedurl;		# action attr
	target: string;		# target attribute
	method: int;		# HGet or HPost
	events: list of Lex->Attr;	# attid will be Aonreset or Aonsubmit
	evmask: int;
	nfields: int;		# number of fields
	fields: cyclic list of ref Formfield;	# field's forms, in input order
	state: int;			# see Form states enum

	new: fn(formid: int, name: string, action: ref Url->Parsedurl, target: string, method: int, events: list of Lex->Attr) : ref Form;
};

# Form states
FormBuild,					# seen <FORM>
FormDone,					# seen </FORM>
FormTransferred : con iota;		# tx'd to javascript

# Flags used in various table structures
TFparsing:	con byte (1<<7);
TFnowrap:	con byte (1<<6);
TFisth:		con byte (1<<5);

# A Table Item is for a table.
Table: adt
{
	tableid: int;			# serial no. of table within its doc
	nrow: int;			# total number of rows
	ncol: int;			# total number of columns
	ncell: int;			# total number of cells
	align: Align;			# alignment spec for whole table
	width: Dimen;			# width spec for whole table
	border: int;			# border attr
	cellspacing: int;		# cellspacing attr
	cellpadding: int;		# cellpadding attr
	border_collapse: byte;		# 0=separate (default), 1=collapse
	border_spacing: int;		# CSS border-spacing (overrides cellspacing when set)
	empty_cells: byte;		# 0=show (default), 1=hide
	table_layout: byte;		# 0=auto (default), 1=fixed
	background: Background;	# table background
	caption: cyclic ref Item;	# linked list of Items, giving caption
	caption_place: byte;		# Atop or Abottom
	caption_lay: int;		# identifies layout of caption
	currows: cyclic list of ref Tablerow;	# during parsing
	cols: array of Tablecol;		# column specs
	rows: cyclic array of ref Tablerow;	# row specs
	cells: cyclic list of ref Tablecell;		# the unique cells
	totw: int;					# total width
	toth: int;					# total height
	caph: int;					# caption height
	availw: int;				# used for previous 3 sizes
	grid: cyclic array of array of ref Tablecell;
	tabletok: ref Lex->Token;		# token that started the table
	flags: byte;				# Lchanged

	new: fn(tableid: int, align: Align, width: Dimen,
		border, cellspacing, cellpadding: int, bg: Background, tok: ref Lex->Token) : ref Table;
};

# A table column info
Tablecol: adt
{
	width: int;
	align: Align;
	pos: Draw->Point;
};

# A table row spec
Tablerow: adt
{
	cells: cyclic list of ref Tablecell;
	height: int;
	ascent: int;
	align: Align;
	background: Background;
	pos: Draw->Point;
	flags: byte;		# 0 or TFparsing

	new: fn(align: Align, bg: Background, flags: byte) : ref Tablerow;
};

# A Tablecell is one cell of a table.
# It may span multiple rows and multiple columns.
# The (row,col) given indexes upper left corner of cell.
# Try to keep this under 17 words long.
Tablecell: adt
{
	cellid: int;			# serial no. of cell within table
	content: cyclic ref Item;	# contents before layout
	layid: int;			# identifies layout of cell
	rowspan: int;		# number of rows spanned by this cell
	colspan: int;		# number of cols spanned by this cell
	align: Align;		# alignment spec
	flags: byte;		# TFparsing, TFnowrap, TFisth
	wspec: Dimen;		# suggested width
	hspec: int;			# suggested height
	background: Background;	# cell background
	minw: int;			# minimum possible width
	maxw: int;		# maximum width
	ascent: int;
	row: int;
	col: int;
	pos: Draw->Point;		# nw corner of cell contents, in cell

	new: fn(cellid, rowspan, colspan: int, align: Align, wspec: Dimen,
			hspec: int, bg: Background, flags: byte) : ref Tablecell;
};

# Align holds both a vertical and a horizontal alignment.
# Usually not all are possible in a given context.
# Anone means no dimension was specified

# alignment types
Anone, Aleft, Acenter, Aright, Ajustify, Achar, Atop, Amiddle, Abottom, Abaseline: con byte iota;

Align: adt
{
	halign: byte;		# one of Anone, Aleft, etc.
	valign: byte;		# one of Anone, Atop, etc.
};

# A Dimen holds a dimension specification, especially for those
# cases when a number can be followed by a % or a * to indicate
# percentage of total or relative weight.
# Dnone means no dimension was specified

# Dimen
# To fit in a word, use top bits to identify kind, rest for value
Dnone:	con 0;
Dpixels:	con 1<<29;
Dpercent:	con 2<<29;
Drelative:	con 3<<29;
Dkindmask:	con 3<<29;
Dspecmask:	con ~Dkindmask;

Dimen: adt
{
	kindspec: int;	# kind | spec

	kind: fn(d: self Dimen) : int;
	spec: fn(d: self Dimen) : int;

	make: fn(kind, spec: int) : Dimen;
};


# Anchor is for info about hyperlinks that go somewhere
Anchor: adt
{
	index: int;			# serial no. of anchor within its doc
	name: string;		# name attr
	href: ref Url->Parsedurl;	# href attr
	target: string;		# target attr
	events: list of Lex->Attr;	# same as genattr.events of containing items
	evmask: int;
};

# DestAnchor is for info about hyperlinks that are destinations
DestAnchor: adt
{
	index: int;		# serial no. of anchor within its doc
	name: string;		# name attr
	item: ref Item;		# the destination
};

# Maps (client side)
Map: adt
{
	name: string;		# map name
	areas: list of Area;	# hotzones

	new: fn(name: string) : ref Map;
};

Area: adt
{
	shape: string;		# rect, circle, or poly
	href: ref Url->Parsedurl;		# associated hypertext link
	target: string;			# associated target frame
	coords: array of Dimen;	# coords for shape
};

# Background is either an image or a color.
# If both are set, the image has precedence.
Background: adt
{
	image: ref Item.Iimage;	# with state |= IFbkg
	color: int;			# RGB in lower 3 bytes
};

# Font styles
FntR, FntI, FntB, FntT, NumStyle: con iota;

# Font sizes
Tiny, Small, Normal, Large, Verylarge, NumSize: con iota;

NumFnt: con (NumStyle*NumSize);
DefFnt: con (FntR*NumSize+Normal);

# Lines are needed through some text items, for underlining or strikethrough
ULnone, ULunder, ULmid: con byte iota;

# List number types
LTdisc, LTsquare, LTcircle, LT1, LTa, LTA, LTi, LTI: con byte iota;

# Kidinfo flags
FRnoresize, FRnoscroll, FRhscroll, FRvscroll, FRhscrollauto, FRvscrollauto: con (1<<iota);

# Information about child frame or frameset
Kidinfo: adt {
	isframeset: int;

	# fields for "frame"
	src: ref Url->Parsedurl;		# only nil if a "dummy" frame or this is frameset
	name: string;			# always non-empty if this isn't frameset
	marginw: int;
	marginh: int;
	framebd: int;
	flags: int;
	
	# fields for "frameset"
	rows: array of Dimen;
	cols: array of Dimen;
	kidinfos: cyclic list of ref Kidinfo;

	new: fn(isframeset: int) : ref Kidinfo;
};

# Document info (global information about HTML page)
Docinfo: adt {
	# stuff from HTTP headers, doc head, and body tag
	src: ref Url->Parsedurl;			# original source of doc
	base: ref Url->Parsedurl;			# base URL of doc
	referrer: ref Url->Parsedurl;			# JavaScript document.referrer
	doctitle: string;				# from <title> element
	background: Background;	# background specification
	backgrounditem: ref Item;	# Image Item for doc background image, or nil
	text: int;					# doc foreground (text) color
	link: int;					# unvisited hyperlink color
	vlink: int;					# visited hyperlink color
	alink: int;					# highlighting hyperlink color
	target: string;				# target frame default
	refresh: string;				# content of <http-equiv=Refresh ...>
	chset: string;				# charset encoding
	lastModified: string;				# last-modified time
	scripttype: int;				# CU->TextJavascript, etc.
	hasscripts: int;				# true if scripts used
	events: list of Lex->Attr;			# event handlers
	evmask: int;
	kidinfo: ref Kidinfo;			# if a frameset
	frameid: int;				# id of document frame

	# info needed to respond to user actions
	anchors: list of ref Anchor;	# info about all href anchors
	dests: list of ref DestAnchor;	# info about all destination anchors
	forms: list of ref Form;		# info about all forms
	tables: list of ref Table;		# info about all tables
	maps: list of ref Map;		# info about all maps
	images: list of ref Item;		# all image items in doc

	new: fn() : ref Docinfo;
	reset: fn(f: self ref Docinfo);
};

# Parsing stuff

# Parsing state
Pstate: adt {
	skipping: int;			# true when we shouldn't add items
	skipwhite: int;			# true when we should strip leading space
	curfont: int;			# font index for current font
	curfg: int;				# current foreground color
	curbg: Background;		# current background
	curvoff: int;			# current baseline offset
	curul: byte;			# current underline/strike state
	curjust: byte;			# current justify state
	curanchor: int;			# current (href) anchor id (if in one), or 0
	curstate: int;			# current value of item state
	literal: int;				# current literal state
	inpar: int;				# true when in a paragraph-like construct
	adjsize: int;			# current font size adjustment
	items: ref Item;			# dummy head of item list we're building
	lastit: ref Item;			# tail of item list we're building
	prelastit: ref Item;		# item before lastit
	fntstylestk: list of int;		# style stack
	fntsizestk: list of int;		# size stack
	fgstk: list of int;			# text color stack
	ulstk: list of byte;		# underline stack
	voffstk: list of int;		# vertical offset stack
	listtypestk: list of byte;	# list type stack
	listcntstk: list of int;		# list counter stack
	juststk: list of byte;		# justification stack
	hangstk: list of int;		# hanging stack
	stylestk: list of int;		# CSS style change stack (bitmasks from applystyle)
	boxstk: list of ref BoxCtx;	# stack of open CSS box model elements

	new: fn() : ref Pstate;
};

# Context for an open CSS box model element (div, blockquote, etc.)
BoxCtx: adt
{
	splicepoint: ref Item;		# item before the box content started
	cs: ref ComputedStyle;		# computed style for the box
};


# A source of Items (resulting of HTML parsing).
# After calling new with a ByteSource (which is past 'gethdr' stage),
# call getitems repeatedly until get nil.  Errors are signalled by exceptions.
# Possible exceptions raised:
#	EXInternal		(start, getitems)
#	exGeterror	(getitems)
#	exAbort		(getitems)
ItemSource: adt
{
	ts: ref Lex->TokenSource;	# source of tokens
	mtype: int;			# media type (TextHtml or TextPlain)
	doc: ref Docinfo;		# global information about page
	frame: ref Layout->Frame;	# containing frame
	psstk: list of ref Pstate;	# local parsing state stack
	nforms: int;			# used to make formids
	ntables: int;			# used to make tableids
	nanchors: int;			# used to make anchor ids
	nframes: int;			# used to make names for frames
	curform: ref Form;		# current form (if in one)
	curmap: ref Map;		# current map (if in one)
	tabstk: list of ref Table;	# table stack
	kidstk: list of ref Kidinfo;	# kidinfo stack
	reqdurl: ref Url->Parsedurl;
	reqddata: array of byte;
	toks: array of ref Lex->Token;
	tagstyles: array of ref StyleInfo;	# CSS rules from <style> blocks, indexed by tag
	styles: ref StyleStore;			# CSS stylesheet store (class/id selectors)
	elemstk: list of ref ElementCtx;	# element context stack for CSS matching
	instyle: int;				# true when inside <style> block
	styletext: string;			# accumulates text inside <style> block

	new: fn(bs: ref CharonUtils->ByteSource, f: ref Layout->Frame, mtype: int) : ref ItemSource;
	getitems: fn(is: self ref ItemSource) : ref Item;
};

init: fn(cu: CharonUtils);
trim_white: fn(data: string): string;
parsestyle: fn(s: string) : StyleInfo;
newcstyle: fn() : ref ComputedStyle;
};
