implement Mermaid;

#
# mermaid.b — Native Mermaid diagram renderer for Inferno/Limbo
#
# Renders Mermaid syntax to Draw->Image using only Inferno drawing
# primitives.  No floating point in layout.  No external dependencies.
#
# Supported types: flowchart/graph, pie, sequenceDiagram, gantt, xychart-beta, classDiagram, stateDiagram-v2, erDiagram, mindmap, timeline, gitGraph, quadrantChart, journey, requirementDiagram, block-beta
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Image, Point, Rect: import draw;

include "math.m";
	math: Math;

include "mermaid.m";

# ═══════════════════════════════════════════════════════════════════════════════
# Layout constants
# ═══════════════════════════════════════════════════════════════════════════════

HPAD:		con 14;		# node: horizontal text padding
VPAD:		con 7;		# node: vertical text padding
MINNODEW:	con 64;		# minimum node width
MINNODEH:	con 28;		# minimum node height
VGAP:		con 40;		# gap between layers (TD) / columns (LR)
HGAP:		con 18;		# gap between nodes in the same layer
MARGIN:		con 22;		# outer margin around diagram
AHEADLEN:	con 10;		# arrowhead length (pixels)
AHEADW:		con 6;		# arrowhead half-width

# Sequence diagram
SEQ_COLW:	con 140;	# centre-to-centre column spacing
SEQ_BOXW:	con 110;	# participant box width
SEQ_BOXH:	con 26;		# participant box height
SEQ_ROWH:	con 38;		# row height per message

# Gantt
GNT_ROWH:	con 26;		# task row height
GNT_LBLW:	con 150;	# left label column width
GNT_HDRY:	con 32;		# date header height
GNT_SECTH:	con 20;		# section title height

# XY chart
XY_AXISW:	con 50;		# left axis width
XY_AXISH:	con 28;		# bottom axis height
XY_PLOTH:	con 180;	# plot area height

# Default width when caller passes 0
DEFWIDTH:	con 800;

# ═══════════════════════════════════════════════════════════════════════════════
# Diagram type IDs
# ═══════════════════════════════════════════════════════════════════════════════

DT_FLOW:	con 0;
DT_PIE:		con 1;
DT_SEQ:		con 2;
DT_GANTT:	con 3;
DT_XY:		con 4;
DT_CLASS:	con 5;
DT_STATE:	con 6;
DT_ER:		con 7;
DT_MINDMAP:	con 8;
DT_TIMELINE:	con 9;
DT_GIT:		con 10;
DT_QUADRANT:	con 11;
DT_JOURNEY:	con 12;
DT_REQMT:	con 13;
DT_BLOCK:	con 14;
DT_UNKNOWN:	con 99;

# Flowchart direction
DIRN_TD:	con 0;
DIRN_LR:	con 1;
DIRN_BT:	con 2;
DIRN_RL:	con 3;

# Node shapes
SH_RECT:	con 0;		# [label]
SH_ROUND:	con 1;		# (label)
SH_DIAMOND:	con 2;		# {label}
SH_CIRCLE:	con 3;		# ((label))
SH_STADIUM:	con 4;		# ([label])
SH_HEX:		con 5;		# {{label}}
SH_SUBR:	con 6;		# [[label]]
SH_FLAG:	con 7;		# >label]

# Edge styles
ES_SOLID:	con 0;		# -->
ES_DASH:	con 1;		# -.->
ES_THICK:	con 2;		# ==>
ES_LINE:	con 3;		# --- (no arrowhead)

# Sequence message types
SM_SOLID:	con 0;		# ->>
SM_DASH:	con 1;		# -->>

# Class relationship types
CR_INHERIT:	con 0;
CR_COMPOSE:	con 1;
CR_AGGR:	con 2;
CR_ASSOC:	con 3;
CR_DEP:		con 4;
CR_REAL:	con 5;

# Requirement node types
RN_REQ:		con 0;
RN_ELEM:	con 1;

# ═══════════════════════════════════════════════════════════════════════════════
# Data structures
# ═══════════════════════════════════════════════════════════════════════════════

FCNode: adt {
	id:	string;
	label:	string;
	shape:	int;
	# layout (filled by layout pass)
	layer:	int;
	col:	int;
	x:	int;		# centre pixel x
	y:	int;		# centre pixel y
	w:	int;		# pixel width
	h:	int;		# pixel height
};

FCEdge: adt {
	src:	string;
	dst:	string;
	label:	string;
	style:	int;
	arrow:	int;		# 1 = has arrowhead at dst
};

FCGraph: adt {
	dir:	int;
	title:	string;
	nodes:	list of ref FCNode;
	nnodes:	int;
	edges:	list of ref FCEdge;
	nedges:	int;
};

PieSlice: adt {
	label:	string;
	value:	int;		# ×1024 fixed-point
};

PieChart: adt {
	title:	string;
	showdata: int;
	slices:	list of ref PieSlice;
	nslices: int;
};

SeqPart: adt {
	id:	string;
	alias:	string;
	idx:	int;
};

SeqMsg: adt {
	from:	string;
	dst:	string;
	text:	string;
	mtype:	int;		# SM_SOLID or SM_DASH
	isnote:	int;		# 1 = Note annotation
	notetext: string;
};

SeqDiag: adt {
	parts:	list of ref SeqPart;
	nparts:	int;
	msgs:	list of ref SeqMsg;
	nmsgs:	int;
};

GTask: adt {
	section: string;
	label:	string;
	id:	string;
	crit:	int;
	active:	int;
	done:	int;
	after:	string;
	startday: int;		# days since 2000-01-01
	durdays:  int;
};

GanttChart: adt {
	title:	string;
	tasks:	list of ref GTask;
	ntasks:	int;
	minday:	int;
	maxday:	int;
};

XYSeries: adt {
	isbar:	int;		# 1=bar, 0=line
	vals:	array of int;	# ×1024 fixed-point
	nvals:	int;
};

XYChart: adt {
	title:	string;
	xlabels: array of string;
	nxlbl:	int;
	ylower:	int;		# ×1024
	yupper:	int;		# ×1024
	series:	list of ref XYSeries;
};

# ─── classDiagram ────────────────────────────────────────────────────────────

ClassMember: adt {
	vis:		string;
	name:		string;
	ismethod:	int;
};

ClassNode: adt {
	id:		string;
	label:		string;
	members:	list of ref ClassMember;
	nmembers:	int;
	x:		int;
	y:		int;
	w:		int;
	h:		int;
};

ClassRel: adt {
	src:		string;
	dst:		string;
	label:		string;
	rtype:		int;
};

ClassDiag: adt {
	title:		string;
	nodes:		list of ref ClassNode;
	nnodes:		int;
	rels:		list of ref ClassRel;
	nrels:		int;
};

# ─── erDiagram ────────────────────────────────────────────────────────────────

ERAttr: adt {
	atype:		string;
	name:		string;
};

EREntity: adt {
	id:		string;
	attrs:		list of ref ERAttr;
	nattrs:		int;
	x:		int;
	y:		int;
	w:		int;
	h:		int;
};

ERRel: adt {
	src:		string;
	dst:		string;
	label:		string;
	card:		string;
};

ERDiag: adt {
	title:		string;
	entities:	list of ref EREntity;
	nentities:	int;
	rels:		list of ref ERRel;
	nrels:		int;
};

# ─── mindmap ──────────────────────────────────────────────────────────────────

MMNode: adt {
	id:		int;
	label:		string;
	depth:		int;
	parent:		int;
	x:		int;
	y:		int;
	w:		int;
	h:		int;
};

# ─── timeline ─────────────────────────────────────────────────────────────────

TLEvent: adt {
	label:		string;
};

TLPeriod: adt {
	label:		string;
	events:		list of ref TLEvent;
	nevents:	int;
};

# ─── gitGraph ─────────────────────────────────────────────────────────────────

GitCommit: adt {
	id:		string;
	label:		string;
	branch:		string;
	ismerge:	int;
	parent:		string;
	x:		int;
	y:		int;
};

# ─── quadrantChart ────────────────────────────────────────────────────────────

QPoint: adt {
	label:		string;
	qx:		int;
	qy:		int;
};

# ─── journey ──────────────────────────────────────────────────────────────────

JTask: adt {
	label:		string;
	score:		int;
	actors:		string;
};

JSection: adt {
	label:		string;
	tasks:		list of ref JTask;
	ntasks:		int;
};

# ─── requirementDiagram ───────────────────────────────────────────────────────

ReqNode: adt {
	id:		string;
	name:		string;
	ntype:		int;
	rid:		string;
	text:		string;
	risk:		string;
	verify:		string;
	etype:		string;
	x:		int;
	y:		int;
	w:		int;
	h:		int;
};

ReqRel: adt {
	src:		string;
	dst:		string;
	rtype:		string;
};

ReqDiag: adt {
	title:		string;
	nodes:		list of ref ReqNode;
	nnodes:		int;
	rels:		list of ref ReqRel;
	nrels:		int;
};

# ─── block-beta ───────────────────────────────────────────────────────────────

BlockNode: adt {
	id:		string;
	label:		string;
	cols:		int;
	x:		int;
	y:		int;
	w:		int;
	h:		int;
};

# ═══════════════════════════════════════════════════════════════════════════════
# Module state
# ═══════════════════════════════════════════════════════════════════════════════

mdisp:	ref Display;
mfont:	ref Font;
mofont:	ref Font;
mmath:	Math;		# for pie sector trig

# Color images (allocated in init)
cbg:	ref Image;	# background
cnode:	ref Image;	# node fill
cbord:	ref Image;	# node border / edge
ctext:	ref Image;	# primary text
ctext2:	ref Image;	# secondary text
cacc:	ref Image;	# accent (arrows, active)
cgreen:	ref Image;	# done / ok
cred:	ref Image;	# critical / error
cyel:	ref Image;	# warning
cgrid:	ref Image;	# axis grid lines
csect:	ref Image;	# section title bar
cwhite:	ref Image;	# white

# Pie / XY series palette (8 entries)
cpie:	array of ref Image;


# ═══════════════════════════════════════════════════════════════════════════════
# init
# ═══════════════════════════════════════════════════════════════════════════════

init(d: ref Display, mainfont: ref Font, monofont: ref Font)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	mmath = load Math Math->PATH;
	mdisp = d;
	mfont = mainfont;
	mofont = monofont;
	if(mfont == nil)
		mfont = Font.open(d, "*default*");
	if(mofont == nil)
		mofont = mfont;

	cbg    = d.color(int 16r1E1E2EFF);
	cnode  = d.color(int 16r313244FF);
	cbord  = d.color(int 16r89B4FAFF);
	ctext  = d.color(int 16rCDD6F4FF);
	ctext2 = d.color(int 16r8B949EFF);
	cacc   = d.color(int 16r89B4FAFF);
	cgreen = d.color(int 16rA6E3A1FF);
	cred   = d.color(int 16rF38BA8FF);
	cyel   = d.color(int 16rF9E2AFFF);
	cgrid  = d.color(int 16r45475AFF);
	csect  = d.color(int 16r45475AFF);
	cwhite = d.color(int 16rCDD6F4FF);

	cpie = array[8] of ref Image;
	cpie[0] = d.color(int 16r89B4FAFF);	# blue
	cpie[1] = d.color(int 16rA6E3A1FF);	# green
	cpie[2] = d.color(int 16rF9E2AFFF);	# yellow
	cpie[3] = d.color(int 16rF38BA8FF);	# red
	cpie[4] = d.color(int 16rCBA6F7FF);	# mauve
	cpie[5] = d.color(int 16r94E2D5FF);	# teal
	cpie[6] = d.color(int 16rFAB387FF);	# peach
	cpie[7] = d.color(int 16r89DCEBFF);	# sky
}

# ═══════════════════════════════════════════════════════════════════════════════
# render — main dispatcher
# ═══════════════════════════════════════════════════════════════════════════════

render(syntax: string, width: int): (ref Draw->Image, string)
{
	if(mdisp == nil)
		return (nil, "mermaid: not initialized — call init() first");
	if(width <= 0)
		width = DEFWIDTH;

	lines := splitlines(syntax);
	dtype := detecttype(lines);

	img: ref Image;
	err: string;
	{
		case dtype {
		DT_FLOW =>
			(img, err) = renderflow(lines, width);
		DT_PIE =>
			(img, err) = renderpie(lines, width);
		DT_SEQ =>
			(img, err) = renderseq(lines, width);
		DT_GANTT =>
			(img, err) = rendergantt(lines, width);
		DT_XY =>
			(img, err) = renderxy(lines, width);
		DT_CLASS =>
			(img, err) = renderclass(lines, width);
		DT_STATE =>
			(img, err) = renderstate(lines, width);
		DT_ER =>
			(img, err) = renderer(lines, width);
		DT_MINDMAP =>
			(img, err) = rendermindmap(lines, width);
		DT_TIMELINE =>
			(img, err) = rendertimeline(lines, width);
		DT_GIT =>
			(img, err) = rendergitgraph(lines, width);
		DT_QUADRANT =>
			(img, err) = renderquadrant(lines, width);
		DT_JOURNEY =>
			(img, err) = renderjourney(lines, width);
		DT_REQMT =>
			(img, err) = renderreqmt(lines, width);
		DT_BLOCK =>
			(img, err) = renderblock(lines, width);
		* =>
			return rendererror("Unsupported diagram type", width);
		}
	} exception e {
	"*" =>
		return (nil, "mermaid: " + e);
	}

	if(err != nil)
		return rendererror(err, width);
	return (img, nil);
}

# ═══════════════════════════════════════════════════════════════════════════════
# Diagram type detection
# ═══════════════════════════════════════════════════════════════════════════════

detecttype(lines: list of string): int
{
	for(l := lines; l != nil; l = tl l) {
		s := trimstr(hd l);
		if(s == "" || hasprefix(s, "%%"))
			continue;
		sl := tolower(s);
		if(hasprefix(sl, "graph ") || hasprefix(sl, "graph\t") ||
				hasprefix(sl, "flowchart ") || hasprefix(sl, "flowchart\t"))
			return DT_FLOW;
		if(hasprefix(sl, "pie"))
			return DT_PIE;
		if(hasprefix(sl, "sequencediagram"))
			return DT_SEQ;
		if(hasprefix(sl, "gantt"))
			return DT_GANTT;
		if(hasprefix(sl, "xychart"))
			return DT_XY;
		if(hasprefix(sl, "classdiagram"))
			return DT_CLASS;
		if(hasprefix(sl, "statediagram"))
			return DT_STATE;
		if(hasprefix(sl, "erdiagram"))
			return DT_ER;
		if(hasprefix(sl, "mindmap"))
			return DT_MINDMAP;
		if(hasprefix(sl, "timeline"))
			return DT_TIMELINE;
		if(hasprefix(sl, "gitgraph"))
			return DT_GIT;
		if(hasprefix(sl, "quadrantchart"))
			return DT_QUADRANT;
		if(hasprefix(sl, "journey"))
			return DT_JOURNEY;
		if(hasprefix(sl, "requirementdiagram"))
			return DT_REQMT;
		if(hasprefix(sl, "block-beta"))
			return DT_BLOCK;
		break;
	}
	return DT_UNKNOWN;
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── FLOWCHART ────────────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

parseflow(lines: list of string): ref FCGraph
{
	g := ref FCGraph(DIRN_TD, "", nil, 0, nil, 0);
	# Parse direction from first line
	for(l := lines; l != nil; l = tl l) {
		s := trimstr(hd l);
		if(s == "" || hasprefix(s, "%%")) continue;
		sl := tolower(s);
		i := 0;
		if(hasprefix(sl, "flowchart ") || hasprefix(sl, "flowchart\t"))
			i = 10;
		else if(hasprefix(sl, "graph ") || hasprefix(sl, "graph\t"))
			i = 6;
		if(i > 0) {
			while(i < len sl && (sl[i] == ' ' || sl[i] == '\t'))
				i++;
			dir := sl[i:];
			if(hasprefix(dir, "lr"))  g.dir = DIRN_LR;
			else if(hasprefix(dir, "bt")) g.dir = DIRN_BT;
			else if(hasprefix(dir, "rl")) g.dir = DIRN_RL;
			else g.dir = DIRN_TD;
		}
		break;
	}

	for(l = lines; l != nil; l = tl l) {
		s := trimstr(hd l);
		if(s == "" || hasprefix(s, "%%")) continue;
		sl := tolower(s);
		# Skip keywords
		if(hasprefix(sl, "graph ") || hasprefix(sl, "graph\t") ||
				hasprefix(sl, "flowchart ") || hasprefix(sl, "flowchart\t") ||
				hasprefix(sl, "subgraph") || s == "end" ||
				hasprefix(sl, "classdef") || hasprefix(sl, "class ") ||
				hasprefix(sl, "style ") || hasprefix(sl, "linkstyle") ||
				hasprefix(sl, "click "))
			continue;
		parseflowline(s, g);
	}
	return g;
}

parseflowline(line: string, g: ref FCGraph)
{
	id1, lbl1, id2, lbl2, elabel: string;
	sh1, sh2, estyle, ehasarrow, ni: int;
	i := 0;
	n := len line;
	while(i < n && (line[i] == ' ' || line[i] == '\t'))
		i++;
	if(i >= n)
		return;

	# Parse first node
	(id1, lbl1, sh1, ni) = parsefcnode(line, i);
	i = ni;
	if(id1 == "")
		return;
	addnode(g, id1, lbl1, sh1);

	# Parse edge(s) and subsequent nodes
	for(;;) {
		while(i < n && (line[i] == ' ' || line[i] == '\t'))
			i++;
		if(i >= n)
			break;

		(estyle, ehasarrow, elabel, ni) = parseedgeop(line, i);
		i = ni;
		if(estyle < 0)
			break;

		while(i < n && (line[i] == ' ' || line[i] == '\t'))
			i++;
		if(i >= n)
			break;

		(id2, lbl2, sh2, ni) = parsefcnode(line, i);
		i = ni;
		if(id2 == "")
			break;
		addnode(g, id2, lbl2, sh2);
		addedge(g, id1, id2, elabel, estyle, ehasarrow);
		id1 = id2;
	}
}

# Parse a node expression at position i; return (id, label, shape, new_i)
parsefcnode(s: string, i: int): (string, string, int, int)
{
	n := len s;
	while(i < n && (s[i] == ' ' || s[i] == '\t'))
		i++;
	if(i >= n)
		return ("", "", SH_RECT, i);

	# Read node ID
	idstart := i;
	while(i < n && s[i] != '[' && s[i] != '(' && s[i] != '{' &&
			s[i] != '>' && s[i] != ' ' && s[i] != '\t' &&
			s[i] != '-' && s[i] != '=' && s[i] != '|' &&
			s[i] != '&' && s[i] != ';')
		i++;
	id := s[idstart:i];
	if(id == "")
		return ("", "", SH_RECT, i);

	while(i < n && (s[i] == ' ' || s[i] == '\t'))
		i++;

	if(i >= n || s[i] == '-' || s[i] == '=' || s[i] == '&' || s[i] == ';')
		return (id, id, SH_RECT, i);

	shape := SH_RECT;
	label := id;

	case s[i] {
	'[' =>
		# Check [[subroutine]] or [regular]
		if(i+1 < n && s[i+1] == '[') {
			i += 2;
			(label, i) = readuntil(s, i, ']');
			if(i+1 < n && s[i+1] == ']') i += 2;
			else if(i < n && s[i] == ']') i++;
			shape = SH_SUBR;
		} else {
			i++;
			(label, i) = readuntil(s, i, ']');
			if(i < n && s[i] == ']') i++;
			shape = SH_RECT;
		}
	'(' =>
		# ((circle)) or ([stadium]) or (round)
		if(i+1 < n && s[i+1] == '(') {
			i += 2;
			(label, i) = readuntil(s, i, ')');
			if(i+1 < n && s[i+1] == ')') i += 2;
			else if(i < n && s[i] == ')') i++;
			shape = SH_CIRCLE;
		} else if(i+1 < n && s[i+1] == '[') {
			i += 2;
			(label, i) = readuntil(s, i, ']');
			# expect ])
			if(i < n && s[i] == ']') i++;
			if(i < n && s[i] == ')') i++;
			shape = SH_STADIUM;
		} else {
			i++;
			(label, i) = readuntil(s, i, ')');
			if(i < n && s[i] == ')') i++;
			shape = SH_ROUND;
		}
	'{' =>
		# {{hex}} or {diamond}
		if(i+1 < n && s[i+1] == '{') {
			i += 2;
			(label, i) = readuntil(s, i, '}');
			if(i+1 < n && s[i+1] == '}') i += 2;
			else if(i < n && s[i] == '}') i++;
			shape = SH_HEX;
		} else {
			i++;
			(label, i) = readuntil(s, i, '}');
			if(i < n && s[i] == '}') i++;
			shape = SH_DIAMOND;
		}
	'>' =>
		i++;
		(label, i) = readuntil(s, i, ']');
		if(i < n && s[i] == ']') i++;
		shape = SH_FLAG;
	}
	return (id, label, shape, i);
}

# Parse edge operator at position i; return (style, hasarrow, label, new_i)
parseedgeop(s: string, i: int): (int, int, string, int)
{
	n := len s;
	while(i < n && (s[i] == ' ' || s[i] == '\t'))
		i++;
	if(i >= n)
		return (-1, 0, "", i);

	style := -1;
	hasarrow := 1;
	label := "";

	# Match edge patterns
	if(i+3 <= n && s[i:i+3] == "==>") {
		style = ES_THICK; i += 3;
	} else if(i+4 <= n && s[i:i+4] == "-.->") {
		style = ES_DASH; i += 4;
	} else if(i+3 <= n && s[i:i+3] == "-.-") {
		style = ES_DASH; hasarrow = 0; i += 3;
	} else if(i+3 <= n && s[i:i+3] == "-->") {
		style = ES_SOLID; i += 3;
	} else if(i+3 <= n && s[i:i+3] == "---") {
		style = ES_LINE; hasarrow = 0; i += 3;
	} else if(i+2 <= n && s[i:i+2] == "--") {
		# --text-->: scan for -->
		j := i + 2;
		for(; j < n && s[j] != '-'; j++)
			;
		if(j+2 < n && s[j:j+3] == "-->") {
			label = trimstr(s[i+2:j]);
			style = ES_SOLID; i = j + 3;
		} else {
			style = ES_SOLID; i = j;
			if(i < n && s[i] == '>') { i++; }
		}
	}

	if(style < 0)
		return (-1, 0, "", i);

	# Check for inline label: -->|text|
	while(i < n && (s[i] == ' ' || s[i] == '\t'))
		i++;
	if(i < n && s[i] == '|' && label == "") {
		i++;
		(label, i) = readuntil(s, i, '|');
		if(i < n && s[i] == '|') i++;
	}
	return (style, hasarrow, label, i);
}

addnode(g: ref FCGraph, id, label: string, shape: int)
{
	for(nl := g.nodes; nl != nil; nl = tl nl)
		if((hd nl).id == id) {
			# Update label/shape only if we have more info
			n := hd nl;
			if(n.label == n.id && label != id)
				n.label = label;
			if(n.shape == SH_RECT && shape != SH_RECT)
				n.shape = shape;
			return;
		}
	node := ref FCNode(id, label, shape, 0, 0, 0, 0, 0, 0);
	g.nodes = node :: g.nodes;
	g.nnodes++;
}

addedge(g: ref FCGraph, src, dst, label: string, style, arrow: int)
{
	e := ref FCEdge(src, dst, label, style, arrow);
	g.edges = e :: g.edges;
	g.nedges++;
}

# ─── Flowchart layout ─────────────────────────────────────────────────────────

layoutflow(g: ref FCGraph, imgw: int)
{
	j, k: int;
	nl: list of ref FCNode;
	el: list of ref FCEdge;
	if(g.nnodes == 0)
		return;

	nodes := revnodes(g.nodes);
	edges := revedges(g.edges);

	# Compute node pixel dimensions
	for(nl = nodes; nl != nil; nl = tl nl) {
		nd := hd nl;
		tw := mfont.width(nd.label);
		nd.w = tw + 2*HPAD;
		if(nd.w < MINNODEW) nd.w = MINNODEW;
		nd.h = mfont.height + 2*VPAD;
		if(nd.h < MINNODEH) nd.h = MINNODEH;
		# Diamond/hex need more room
		if(nd.shape == SH_DIAMOND || nd.shape == SH_HEX) {
			nd.w = nd.w * 3 / 2;
			nd.h = nd.h * 3 / 2;
		}
		if(nd.shape == SH_CIRCLE) {
			d := nd.w;
			if(nd.h > d) d = nd.h;
			nd.w = d; nd.h = d;
		}
	}

	# Build in-degree table (index by node list position)
	na := nodestoarray(nodes, g.nnodes);
	indeg := array[g.nnodes] of {* => 0};

	for(el = edges; el != nil; el = tl el) {
		e := hd el;
		for(j = 0; j < g.nnodes; j++)
			if(na[j].id == e.dst) {
				indeg[j]++;
				break;
			}
	}

	# BFS longest-path layering (Kahn's algorithm with cyclic-component restart)
	# Each node is enqueued at most once (tracked by queued[]).
	# When the queue empties, seed one unvisited node and re-drain.
	# This bounds qtail <= g.nnodes regardless of cycle structure.
	layer := array[g.nnodes] of {* => -1};
	queue := array[g.nnodes] of int;
	queued := array[g.nnodes] of {* => 0};
	qhead := 0; qtail := 0;
	indeg2 := array[g.nnodes] of {* => 0};
	for(j = 0; j < g.nnodes; j++)
		indeg2[j] = indeg[j];

	for(j = 0; j < g.nnodes; j++)
		if(indeg2[j] == 0) {
			layer[j] = 0;
			queue[qtail++] = j;
			queued[j] = 1;
		}

	for(;;) {
		while(qhead < qtail) {
			u := queue[qhead++];
			# Propagate to successors
			for(el = edges; el != nil; el = tl el) {
				e := hd el;
				if(na[u].id != e.src) continue;
				for(j = 0; j < g.nnodes; j++) {
					if(na[j].id != e.dst) continue;
					if(layer[u] + 1 > layer[j])
						layer[j] = layer[u] + 1;
					indeg2[j]--;
					if(indeg2[j] == 0 && !queued[j]) {
						queue[qtail++] = j;
						queued[j] = 1;
					}
					break;
				}
			}
		}
		# Seed one unvisited node for cyclic components; re-drain
		found := 0;
		for(j = 0; j < g.nnodes; j++)
			if(!queued[j]) {
				layer[j] = 0;
				queue[qtail++] = j;
				queued[j] = 1;
				found = 1;
				break;
			}
		if(found == 0) break;
	}

	# Count layers and max column per layer
	nlayers := 0;
	for(j = 0; j < g.nnodes; j++)
		if(layer[j] + 1 > nlayers) nlayers = layer[j] + 1;

	# Assign column positions within each layer (order of BFS discovery)
	col := array[g.nnodes] of {* => 0};
	colcount := array[nlayers] of {* => 0};
	for(j = 0; j < g.nnodes; j++) {
		l := layer[j];
		if(l < 0) l = 0;
		col[j] = colcount[l]++;
	}

	# Compute pixel dimensions per layer
	maxnodeh := 0;
	maxnodew := 0;
	for(nl = nodes; nl != nil; nl = tl nl) {
		nd := hd nl;
		if(nd.h > maxnodeh) maxnodeh = nd.h;
		if(nd.w > maxnodew) maxnodew = nd.w;
	}

	# Image width: accommodate the widest layer
	maxcols := 0;
	for(k = 0; k < nlayers; k++)
		if(colcount[k] > maxcols) maxcols = colcount[k];
	layerw := maxcols * (maxnodew + HGAP) - HGAP;
	iw := layerw + 2 * MARGIN;
	if(iw < imgw) iw = imgw;

	# Assign pixel coordinates
	for(j = 0; j < g.nnodes; j++) {
		l := layer[j];
		if(l < 0) l = 0;
		c := col[j];
		cnt := colcount[l];
		# Centre this layer within image
		lw := cnt * (maxnodew + HGAP) - HGAP;
		startx := (iw - lw) / 2;

		nd := na[j];
		if(g.dir == DIRN_LR || g.dir == DIRN_RL) {
			# LR: layers go left→right, nodes stack top→bottom
			if(g.dir == DIRN_RL)
				nd.x = iw - MARGIN - l * (maxnodew + VGAP) - maxnodew/2;
			else
				nd.x = MARGIN + l * (maxnodew + VGAP) + maxnodew/2;
			lh := cnt * (maxnodeh + HGAP) - HGAP;
			ih := lh + 2 * MARGIN;
			starty := (ih - lh) / 2;
			nd.y = starty + c * (maxnodeh + HGAP) + maxnodeh/2;
		} else {
			# TD or BT
			if(g.dir == DIRN_BT)
				nd.y = 2*MARGIN + (nlayers - 1 - l) * (maxnodeh + VGAP) + maxnodeh/2;
			else
				nd.y = MARGIN + l * (maxnodeh + VGAP) + maxnodeh/2;
			nd.x = startx + c * (maxnodew + HGAP) + maxnodew/2;
		}
		nd.layer = layer[j];
		nd.col = col[j];
	}
}

# Compute flow diagram image dimensions
flowimgdims(g: ref FCGraph, imgw: int): (int, int)
{
	if(g.nnodes == 0)
		return (imgw, 100);

	na := nodestoarray(g.nodes, g.nnodes);
	maxx := 0; maxy := 0;
	for(j := 0; j < g.nnodes; j++) {
		nd := na[j];
		rx := nd.x + nd.w/2 + MARGIN;
		ry := nd.y + nd.h/2 + MARGIN;
		if(rx > maxx) maxx = rx;
		if(ry > maxy) maxy = ry;
	}
	if(maxx < imgw) maxx = imgw;
	return (maxx, maxy);
}

# ─── Flowchart renderer ───────────────────────────────────────────────────────

renderflow(lines: list of string, width: int): (ref Image, string)
{
	k: int;
	g := parseflow(lines);
	if(g.nnodes == 0)
		return rendererror("empty flowchart", width);

	# Reverse lists to preserve declaration order
	g.nodes = revnodes(g.nodes);
	g.edges = revedges(g.edges);
	layoutflow(g, width);
	(iw, ih) := flowimgdims(g, width);

	img := mdisp.newimage(Rect((0,0),(iw,ih)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil)
		return (nil, "cannot allocate image");
	img.draw(img.r, cbg, nil, (0,0));

	na := nodestoarray(g.nodes, g.nnodes);
	ea := edgestoarray(g.edges, g.nedges);

	# Draw edges first (behind nodes)
	for(k = 0; k < g.nedges; k++) {
		e := ea[k];
		src := findnode(na, g.nnodes, e.src);
		dst := findnode(na, g.nnodes, e.dst);
		if(src == nil || dst == nil) continue;
		drawfcedge(img, src, dst, e, g.dir);
	}

	# Draw nodes on top
	for(k = 0; k < g.nnodes; k++)
		drawfcnode(img, na[k]);

	return (img, nil);
}

drawfcnode(img: ref Image, nd: ref FCNode)
{
	cx := nd.x; cy := nd.y;
	hw := nd.w / 2; hh := nd.h / 2;
	r := Rect((cx-hw, cy-hh), (cx+hw, cy+hh));

	case nd.shape {
	SH_RECT or SH_SUBR or SH_FLAG =>
		img.draw(r, cnode, nil, (0,0));
		drawrectrect(img, r, cbord);
		if(nd.shape == SH_SUBR) {
			# double vertical bars on left/right
			img.draw(Rect((r.min.x+4, r.min.y), (r.min.x+6, r.max.y)), cbord, nil, (0,0));
			img.draw(Rect((r.max.x-6, r.min.y), (r.max.x-4, r.max.y)), cbord, nil, (0,0));
		}
	SH_ROUND or SH_STADIUM =>
		img.draw(r, cnode, nil, (0,0));
		drawroundrect(img, r, cbord);
	SH_DIAMOND =>
		drawdiamond(img, cx, cy, nd.w, nd.h, cnode, cbord);
	SH_CIRCLE =>
		rad := hw;
		if(hh < rad) rad = hh;
		img.fillellipse(Point(cx,cy), rad, rad, cnode, Point(0,0));
		img.ellipse(Point(cx,cy), rad, rad, 0, cbord, Point(0,0));
	SH_HEX =>
		drawhex(img, cx, cy, nd.w, nd.h, cnode, cbord);
	* =>
		img.draw(r, cnode, nil, (0,0));
		drawrectrect(img, r, cbord);
	}

	# Label
	lw := mfont.width(nd.label);
	lx := cx - lw/2;
	ly := cy - mfont.height/2;
	img.text(Point(lx, ly), ctext, Point(0,0), mfont, nd.label);
}

drawfcedge(img: ref Image, src, dst: ref FCNode, e: ref FCEdge, dir: int)
{
	sp := Point(0,0);

	# Connection points depend on layout direction
	p0, p1: Point;
	if(dir == DIRN_LR) {
		p0 = Point(src.x + src.w/2, src.y);
		p1 = Point(dst.x - dst.w/2, dst.y);
	} else if(dir == DIRN_RL) {
		p0 = Point(src.x - src.w/2, src.y);
		p1 = Point(dst.x + dst.w/2, dst.y);
	} else if(dir == DIRN_BT) {
		p0 = Point(src.x, src.y - src.h/2);
		p1 = Point(dst.x, dst.y + dst.h/2);
	} else {
		# TD (default)
		p0 = Point(src.x, src.y + src.h/2);
		p1 = Point(dst.x, dst.y - dst.h/2);
	}

	col := cbord;
	thick := 0;
	if(e.style == ES_THICK) thick = 1;

	# Choose route: straight if aligned, orthogonal bend otherwise
	if(dir == DIRN_LR || dir == DIRN_RL) {
		if(p0.y == p1.y) {
			drawedgeseg(img, p0, p1, e.style, col, thick);
		} else {
			mid := (p0.x + p1.x) / 2;
			drawedgeseg(img, p0, Point(mid, p0.y), e.style, col, thick);
			drawedgeseg(img, Point(mid, p0.y), Point(mid, p1.y), e.style, col, thick);
			drawedgeseg(img, Point(mid, p1.y), p1, e.style, col, thick);
		}
	} else {
		if(p0.x == p1.x) {
			drawedgeseg(img, p0, p1, e.style, col, thick);
		} else {
			mid := (p0.y + p1.y) / 2;
			drawedgeseg(img, p0, Point(p0.x, mid), e.style, col, thick);
			drawedgeseg(img, Point(p0.x, mid), Point(p1.x, mid), e.style, col, thick);
			drawedgeseg(img, Point(p1.x, mid), p1, e.style, col, thick);
		}
	}

	# Arrowhead at p1
	if(e.arrow) {
		adir := 0;
		if(dir == DIRN_LR) adir = 1;
		else if(dir == DIRN_RL) adir = 3;
		else if(dir == DIRN_BT) adir = 2;
		else adir = 0;
		drawarrowhead(img, p1, adir, col);
	}

	# Edge label at midpoint of middle segment
	if(e.label != "") {
		mx := (p0.x + p1.x) / 2;
		my := (p0.y + p1.y) / 2 - mfont.height - 2;
		lw := mfont.width(e.label);
		img.draw(Rect((mx-lw/2-2, my-1), (mx+lw/2+2, my+mfont.height+1)),
			cnode, nil, (0,0));
		img.text(Point(mx-lw/2, my), ctext2, Point(0,0), mfont, e.label);
	}
	sp = sp;	# suppress unused warning
}

drawedgeseg(img: ref Image, p0, p1: Point, style: int, col: ref Image, thick: int)
{
	if(style == ES_DASH) {
		dashedline(img, p0, p1, col);
		return;
	}
	img.line(p0, p1, Draw->Endsquare, Draw->Endsquare, thick, col, Point(0,0));
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── PIE CHART ────────────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

# Draw a filled pie sector as a polygon.
# startdeg and phideg use Limbo arc convention: degrees CCW from 3-o'clock.
# phideg < 0 → clockwise sweep.
piesector(img: ref Image, cx, cy, r: int, col: ref Image, startdeg, phideg: int)
{
	aphideg := phideg;
	if(aphideg < 0) aphideg = -aphideg;
	nsegs := aphideg / 5 + 2;
	if(nsegs < 3) nsegs = 3;
	if(nsegs > 73) nsegs = 73;
	pts := array[nsegs + 2] of Point;
	pts[0] = Point(cx, cy);
	# π via atan2 — avoids broken DEFF real-constant pool (canontod LP64 bug)
	pi := mmath->atan2(real 0, real (-1));
	d2r := pi / real 180;
	for(k := 0; k <= nsegs; k++) {
		adeg := startdeg + k * phideg / nsegs;
		arad := real adeg * d2r;
		pts[k + 1] = Point(cx + int(real r * mmath->cos(arad)),
		                   cy - int(real r * mmath->sin(arad)));
	}
	img.fillpoly(pts, ~0, col, Point(0, 0));
}

parsepiechart(lines: list of string): ref PieChart
{
	p := ref PieChart("", 0, nil, 0);
	for(l := lines; l != nil; l = tl l) {
		s := trimstr(hd l);
		if(s == "" || hasprefix(s, "%%")) continue;
		sl := tolower(s);
		if(hasprefix(sl, "pie")) {
			rest := trimstr(s[3:]);
			rsl := tolower(rest);
			if(hasprefix(rsl, "showdata")) {
				p.showdata = 1;
				rest = trimstr(rest[8:]);
				rsl = tolower(rest);
			}
			if(hasprefix(rsl, "title "))
				p.title = trimstr(rest[6:]);
			continue;
		}
		if(hasprefix(sl, "title ")) {
			p.title = trimstr(s[6:]);
			continue;
		}
		# "label" : value
		if(len s < 3) continue;
		if(s[0] != '"') continue;
		j := 1;
		for(; j < len s && s[j] != '"'; j++)
			;
		if(j >= len s) continue;
		lbl := s[1:j];
		j++;
		while(j < len s && (s[j] == ' ' || s[j] == '\t' || s[j] == ':'))
			j++;
		if(j >= len s) continue;
		val := parsenum(trimstr(s[j:]));
		slice := ref PieSlice(lbl, val);
		p.slices = slice :: p.slices;
		p.nslices++;
	}
	p.slices = revslices(p.slices);
	return p;
}

renderpie(lines: list of string, width: int): (ref Image, string)
{
	sl: list of ref PieSlice;
	p := parsepiechart(lines);
	if(p.nslices == 0)
		return rendererror("pie chart has no slices", width);

	# Layout
	pad := MARGIN;
	titleh := 0;
	if(p.title != "")
		titleh = mfont.height + 8;
	radius := (width - 2*pad) / 3;
	if(radius < 40) radius = 40;
	h := titleh + 2*radius + 2*pad + 4;
	leglineh := mfont.height + 4;
	legh := p.nslices * leglineh + 4;
	if(legh > h - 2*pad) h = legh + 2*pad;
	if(h < radius*2 + 2*pad + titleh + 8)
		h = radius*2 + 2*pad + titleh + 8;

	img := mdisp.newimage(Rect((0,0),(width,h)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil) return (nil, "cannot allocate image");
	img.draw(img.r, cbg, nil, (0,0));

	# Title
	ty := pad;
	if(p.title != "") {
		tw := mfont.width(p.title);
		img.text(Point(width/2 - tw/2, ty), ctext, Point(0,0), mfont, p.title);
		ty += titleh;
	}

	cx := pad + radius;
	cy := ty + radius;

	# Compute total (×1024)
	total := 0;
	for(sl = p.slices; sl != nil; sl = tl sl)
		total += (hd sl).value;
	if(total == 0)
		return rendererror("pie chart: all zero values", width);

	# Draw slices
	# Draw slices as polygons: 12 o'clock start, clockwise sweep.
	# The last slice is given the remainder so the arcs sum to exactly -360°,
	# eliminating the ~1° gap from integer-division truncation.
	startangle := 90;
	i := 0;
	for(sl = p.slices; sl != nil; sl = tl sl) {
		sv := (hd sl).value;
		phi: int;
		if(tl sl == nil) {
			# Last slice: -270 - startangle gives exactly one full clockwise rotation
			phi = -270 - startangle;
		} else {
			phi = -(sv * 360 / total);
			if(phi == 0) phi = -1;
		}
		piesector(img, cx, cy, radius, cpie[i%8], startangle, phi);
		startangle += phi;
		i++;
	}

	# Legend
	lx := cx + radius + 16;
	ly := ty + 4;
	i = 0;
	for(sl = p.slices; sl != nil; sl = tl sl) {
		sv := (hd sl).value;
		# Colour swatch
		img.draw(Rect((lx, ly+2), (lx+14, ly+14)), cpie[i%8], nil, (0,0));
		# Label
		lstr := (hd sl).label;
		if(p.showdata) {
			# Show percentage
			pct := sv * 100 / total;
			lstr += sys->sprint(" (%d%%)", pct);
		}
		img.text(Point(lx+18, ly), ctext, Point(0,0), mfont, lstr);
		ly += leglineh;
		i++;
	}

	return (img, nil);
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── SEQUENCE DIAGRAM ─────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

parseseq(lines: list of string): ref SeqDiag
{
	d := ref SeqDiag(nil, 0, nil, 0);
	for(l := lines; l != nil; l = tl l) {
		s := trimstr(hd l);
		if(s == "" || hasprefix(s, "%%")) continue;
		sl := tolower(s);
		if(hasprefix(sl, "sequencediagram") || hasprefix(sl, "title ") ||
				hasprefix(sl, "autonumber") || hasprefix(sl, "activate") ||
				hasprefix(sl, "deactivate"))
			continue;
		# participant
		if(hasprefix(sl, "participant ") || hasprefix(sl, "actor ")) {
			skip := 12;
			if(hasprefix(sl, "actor ")) skip = 6;
			rest := trimstr(s[skip:]);
			id := rest; alias := rest;
			# "Name as Alias"
			ai := findkw(rest, " as ");
			if(ai >= 0) {
				id = trimstr(rest[0:ai]);
				alias = trimstr(rest[ai+4:]);
			}
			addseqpart(d, id, alias);
			continue;
		}
		# Note over / Note left of / Note right of
		if(hasprefix(sl, "note ")) {
			rest := trimstr(s[5:]);
			# Find ":"
			ci := 0;
			for(; ci < len rest && rest[ci] != ':'; ci++)
				;
			if(ci < len rest) {
				text := trimstr(rest[ci+1:]);
				m := ref SeqMsg("", "", "", SM_SOLID, 1, text);
				d.msgs = m :: d.msgs;
				d.nmsgs++;
			}
			continue;
		}
		# Message: A ->> B : text  or  A -->> B : text
		ai := findkw(s, "->>");
		dai := findkw(s, "-->>");
		mtype := SM_SOLID;
		mlen := 3;
		mi := ai;
		if(dai >= 0 && (ai < 0 || dai < ai)) {
			mi = dai; mtype = SM_DASH; mlen = 4;
		}
		if(mi >= 0) {
			from := trimstr(s[0:mi]);
			rest := trimstr(s[mi+mlen:]);
			# Find ":"
			ci := 0;
			for(; ci < len rest && rest[ci] != ':'; ci++)
				;
			dst := trimstr(rest[0:ci]);
			text := "";
			if(ci < len rest)
				text = trimstr(rest[ci+1:]);
			# Auto-register participants
			addseqpart(d, from, from);
			addseqpart(d, dst, dst);
			m := ref SeqMsg(from, dst, text, mtype, 0, "");
			d.msgs = m :: d.msgs;
			d.nmsgs++;
		}
	}
	d.parts = revseqparts(d.parts);
	d.msgs = revseqmsgs(d.msgs);
	return d;
}

addseqpart(d: ref SeqDiag, id, alias: string)
{
	for(pl := d.parts; pl != nil; pl = tl pl)
		if((hd pl).id == id) return;
	p := ref SeqPart(id, alias, d.nparts);
	d.parts = p :: d.parts;
	d.nparts++;
}

seqpartidx(d: ref SeqDiag, id: string): int
{
	for(pl := d.parts; pl != nil; pl = tl pl)
		if((hd pl).id == id) return (hd pl).idx;
	return -1;
}

renderseq(lines: list of string, width: int): (ref Image, string)
{
	pl: list of ref SeqPart;
	d := parseseq(lines);
	if(d.nparts == 0)
		return rendererror("sequence diagram has no participants", width);

	pad := MARGIN;
	titleh := mfont.height + 6;

	# Image dimensions
	ncols := d.nparts;
	iw := ncols * SEQ_COLW + 2 * pad;
	if(iw < width) iw = width;
	msgsh := d.nmsgs * SEQ_ROWH + SEQ_ROWH;
	ih := 2*pad + 2*titleh + 2*SEQ_BOXH + msgsh;

	img := mdisp.newimage(Rect((0,0),(iw,ih)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil) return (nil, "cannot allocate image");
	img.draw(img.r, cbg, nil, (0,0));

	# Participant centres
	xcol := array[ncols] of int;
	i := 0;
	for(pl = d.parts; pl != nil; pl = tl pl) {
		xcol[i] = pad + i*SEQ_COLW + SEQ_COLW/2;
		i++;
	}

	topy := pad;
	boty := ih - pad - SEQ_BOXH;
	firstmegy := topy + SEQ_BOXH + 8;

	# Draw participant boxes (top and bottom)
	i = 0;
	for(pl = d.parts; pl != nil; pl = tl pl) {
		pt := hd pl;
		cx := xcol[i];
		alias := pt.alias;
		if(alias == "") alias = pt.id;
		# Top box
		bx := cx - SEQ_BOXW/2;
		drawparticipantbox(img, bx, topy, alias);
		# Bottom box
		drawparticipantbox(img, bx, boty, alias);
		# Lifeline (dashed vertical)
		dashedline(img, Point(cx, topy+SEQ_BOXH), Point(cx, boty), cgrid);
		i++;
	}

	# Draw messages
	my := firstmegy;
	for(ml := d.msgs; ml != nil; ml = tl ml) {
		m := hd ml;
		if(m.isnote) {
			# Draw note as a text strip
			nw := mfont.width(m.notetext) + 8;
			nx := iw/2 - nw/2;
			img.draw(Rect((nx-2, my-2), (nx+nw+2, my+mfont.height+2)), csect, nil, (0,0));
			img.text(Point(nx+4, my), ctext, Point(0,0), mfont, m.notetext);
		} else {
			fi := seqpartidx(d, m.from);
			ti := seqpartidx(d, m.dst);
			if(fi < 0 || ti < 0 || fi >= ncols || ti >= ncols) {
				my += SEQ_ROWH; continue;
			}
			x0 := xcol[fi];
			x1 := xcol[ti];
			drawseqmsg(img, x0, x1, my, m);
		}
		my += SEQ_ROWH;
	}

	return (img, nil);
}

drawparticipantbox(img: ref Image, bx, by: int, label: string)
{
	r := Rect((bx, by), (bx+SEQ_BOXW, by+SEQ_BOXH));
	img.draw(r, cnode, nil, (0,0));
	drawrectrect(img, r, cbord);
	lw := mfont.width(label);
	cx := bx + SEQ_BOXW/2;
	img.text(Point(cx-lw/2, by+(SEQ_BOXH-mfont.height)/2), ctext, Point(0,0), mfont, label);
}

drawseqmsg(img: ref Image, x0, x1, y: int, m: ref SeqMsg)
{
	col := cbord;
	if(m.mtype == SM_DASH) col = ctext2;

	if(x0 == x1) {
		# Self-message: right-angle loop
		loop := 24;
		drawedgeseg(img, Point(x0, y), Point(x0+loop, y), m.mtype, col, 0);
		drawedgeseg(img, Point(x0+loop, y), Point(x0+loop, y+SEQ_ROWH/2), m.mtype, col, 0);
		drawedgeseg(img, Point(x0+loop, y+SEQ_ROWH/2), Point(x0, y+SEQ_ROWH/2), m.mtype, col, 0);
		drawarrowhead(img, Point(x0, y+SEQ_ROWH/2), 3, col);
		if(m.text != "")
			img.text(Point(x0+loop+4, y-mfont.height), ctext, Point(0,0), mfont, m.text);
		return;
	}

	# Horizontal arrow
	img.line(Point(x0, y), Point(x1, y), Draw->Endsquare, Draw->Endsquare, 0, col, Point(0,0));
	if(x1 > x0)
		drawarrowhead(img, Point(x1, y), 1, col);
	else
		drawarrowhead(img, Point(x1, y), 3, col);
	# Label
	if(m.text != "") {
		mx := (x0 + x1) / 2;
		lw := mfont.width(m.text);
		img.text(Point(mx-lw/2, y-mfont.height-1), ctext, Point(0,0), mfont, m.text);
	}
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── GANTT CHART ──────────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

parsegantt(lines: list of string): ref GanttChart
{
	g := ref GanttChart("", nil, 0, 999999, 0);
	cursect := "Default";

	for(l := lines; l != nil; l = tl l) {
		s := trimstr(hd l);
		if(s == "" || hasprefix(s, "%%")) continue;
		sl := tolower(s);
		if(hasprefix(sl, "gantt"))  continue;
		if(hasprefix(sl, "title ")) { g.title = trimstr(s[6:]); continue; }
		if(hasprefix(sl, "dateformat ") || hasprefix(sl, "dateformat\t")) continue;
		if(hasprefix(sl, "axisformat ") || hasprefix(sl, "axisformat\t")) continue;
		if(hasprefix(sl, "excludes ")) continue;
		if(hasprefix(sl, "todaymarker")) continue;
		if(hasprefix(sl, "section ")) {
			cursect = trimstr(s[8:]);
			continue;
		}
		# Task line: label : [modifiers,] startdate, duration
		#   or: label :id, after id2, duration
		ci := 0;
		for(; ci < len s && s[ci] != ':'; ci++)
			;
		if(ci >= len s) continue;
		label := trimstr(s[0:ci]);
		rest := trimstr(s[ci+1:]);

		t := ref GTask(cursect, label, "", 0, 0, 0, "", 0, 1);
		parseganttrest(rest, t);
		g.tasks = t :: g.tasks;
		g.ntasks++;
	}
	g.tasks = revtasks(g.tasks);

	# Resolve "after" dependencies and compute date range
	ta := taskstoarray(g.tasks, g.ntasks);
	resolvetaskdeps(ta, g.ntasks);
	for(k := 0; k < g.ntasks; k++) {
		t := ta[k];
		if(t.startday < g.minday) g.minday = t.startday;
		endday := t.startday + t.durdays;
		if(endday > g.maxday) g.maxday = endday;
	}
	if(g.minday >= g.maxday) {
		g.minday = 0;
		g.maxday = 30;
	}
	return g;
}

parseganttrest(s: string, t: ref GTask)
{
	# Parse: [crit,] [active,] [done,] [id,] [after id,] startdate, duration
	# or: [id,] after othertask, duration
	parts := splittokens(s, ',');
	for(pl := parts; pl != nil; pl = tl pl) {
		tok := trimstr(hd pl);
		tl2 := tolower(tok);
		if(tl2 == "crit")   { t.crit = 1; continue; }
		if(tl2 == "active") { t.active = 1; continue; }
		if(tl2 == "done")   { t.done = 1; continue; }
		if(hasprefix(tl2, "after ")) { t.after = trimstr(tok[6:]); continue; }
		# If it looks like a date (YYYY-MM-DD)
		if(isdate(tok)) { t.startday = parsedate(tok); continue; }
		# If it looks like a duration (e.g. "7d", "2w")
		if(isduration(tok)) { t.durdays = parsedur(tok); continue; }
		# Else treat as ID
		if(t.id == "") t.id = tok;
	}
	if(t.durdays <= 0) t.durdays = 1;
}

resolvetaskdeps(ta: array of ref GTask, n: int)
{
	# Two passes to resolve chains
	for(pass := 0; pass < 2; pass++)
	for(i := 0; i < n; i++) {
		t := ta[i];
		if(t.after == "") continue;
		for(j := 0; j < n; j++) {
			if(ta[j].id == t.after || ta[j].label == t.after) {
				t.startday = ta[j].startday + ta[j].durdays;
				break;
			}
		}
	}
}

rendergantt(lines: list of string, width: int): (ref Image, string)
{
	g := parsegantt(lines);
	if(g.ntasks == 0)
		return rendererror("gantt chart has no tasks", width);

	pad := MARGIN;
	titleh := 0;
	if(g.title != "")
		titleh = mfont.height + 8;

	plotw := width - 2*pad - GNT_LBLW;
	if(plotw < 80) plotw = 80;

	ih := pad + titleh + GNT_HDRY + g.ntasks*GNT_ROWH + pad;

	# Count sections for extra section title rows
	cursect := "";
	nsects := 0;
	for(tl2 := g.tasks; tl2 != nil; tl2 = tl tl2) {
		t := hd tl2;
		if(t.section != cursect) { nsects++; cursect = t.section; }
	}
	ih += nsects * GNT_SECTH;

	img := mdisp.newimage(Rect((0,0),(width,ih)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil) return (nil, "cannot allocate image");
	img.draw(img.r, cbg, nil, (0,0));

	ty := pad;
	if(g.title != "") {
		tw := mfont.width(g.title);
		img.text(Point(width/2 - tw/2, ty), ctext, Point(0,0), mfont, g.title);
		ty += titleh;
	}

	# Date header
	dayrange := g.maxday - g.minday;
	if(dayrange <= 0) dayrange = 1;
	# Draw every N days as marker (choose N so markers are ≥40px apart)
	markevery := 1;
	while(markevery * plotw / dayrange < 40)
		markevery++;

	hdrr := Rect((pad + GNT_LBLW, ty), (pad + GNT_LBLW + plotw, ty + GNT_HDRY));
	img.draw(hdrr, csect, nil, (0,0));
	k := 0;
	while(k * markevery < dayrange) {
		dx := k * markevery * plotw / dayrange;
		mx := pad + GNT_LBLW + dx;
		# Tick
		img.draw(Rect((mx, ty+GNT_HDRY-4), (mx+1, ty+GNT_HDRY)), ctext, nil, (0,0));
		# Day number label
		lbl := sys->sprint("+%d", k*markevery);
		img.text(Point(mx+2, ty+4), ctext2, Point(0,0), mfont, lbl);
		k++;
	}
	ty += GNT_HDRY;

	# Tasks
	cursect = "";
	for(tl3 := g.tasks; tl3 != nil; tl3 = tl tl3) {
		t := hd tl3;
		# Section header
		if(t.section != cursect) {
			cursect = t.section;
			img.draw(Rect((pad, ty), (width-pad, ty+GNT_SECTH)), csect, nil, (0,0));
			img.text(Point(pad+4, ty+2), ctext, Point(0,0), mfont, cursect);
			ty += GNT_SECTH;
		}
		# Label column
		lbl := t.label;
		lw := mfont.width(lbl);
		if(lw > GNT_LBLW - 8) {
			# Truncate
			for(; len lbl > 0 && mfont.width(lbl+"…") > GNT_LBLW-8; )
				lbl = lbl[0:len lbl-1];
			lbl += "…";
		}
		img.text(Point(pad, ty+(GNT_ROWH-mfont.height)/2), ctext, Point(0,0), mfont, lbl);

		# Bar
		sd := t.startday - g.minday;
		ed := sd + t.durdays;
		bx := pad + GNT_LBLW + sd * plotw / dayrange;
		bw := (ed - sd) * plotw / dayrange;
		if(bw < 3) bw = 3;
		br := Rect((bx, ty+2), (bx+bw, ty+GNT_ROWH-2));
		barcol := cacc;
		if(t.crit) barcol = cred;
		else if(t.done) barcol = cgreen;
		else if(t.active) barcol = cyel;
		img.draw(br, barcol, nil, (0,0));

		# Grid line
		img.draw(Rect((pad+GNT_LBLW, ty+GNT_ROWH-1), (width-pad, ty+GNT_ROWH)), cgrid, nil, (0,0));
		ty += GNT_ROWH;
	}

	return (img, nil);
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── XY CHART ─────────────────────────────════════════════════════════════════
# ═══════════════════════════════════════════════════════════════════════════════

parsexychart(lines: list of string): ref XYChart
{
	pl: list of string;
	c := ref XYChart("", nil, 0, 0, 0, nil);
	c.ylower = 0; c.yupper = 1024;	# default range 0..1

	for(l := lines; l != nil; l = tl l) {
		s := trimstr(hd l);
		if(s == "" || hasprefix(s, "%%")) continue;
		sl := tolower(s);
		if(hasprefix(sl, "xychart")) continue;
		if(hasprefix(sl, "title ")) {
			# Strip surrounding quotes if present
			t := trimstr(s[6:]);
			if(len t >= 2 && t[0] == '"')
				t = t[1:len t-1];
			c.title = t;
			continue;
		}
		if(hasprefix(sl, "x-axis ") || hasprefix(sl, "x-axis[")) {
			# x-axis [Lab1, Lab2, ...]  or  x-axis --> N
			bi := 0;
			for(; bi < len s && s[bi] != '['; bi++)
				;
			if(bi < len s) {
				ei := bi+1;
				for(; ei < len s && s[ei] != ']'; ei++)
					;
				inner := s[bi+1:ei];
				parts := splittokens(inner, ',');
				n := 0;
				for(pl = parts; pl != nil; pl = tl pl)
					n++;
				c.xlabels = array[n] of string;
				c.nxlbl = n;
				k := 0;
				for(pl = parts; pl != nil; pl = tl pl) {
					c.xlabels[k] = trimstr(hd pl);
					if(len c.xlabels[k] >= 2 && c.xlabels[k][0] == '"')
						c.xlabels[k] = c.xlabels[k][1:len c.xlabels[k]-1];
					k++;
				}
			}
			continue;
		}
		if(hasprefix(sl, "y-axis ")) {
			# y-axis "label" lower --> upper
			rest := trimstr(s[7:]);
			# Strip quoted label
			if(len rest > 0 && rest[0] == '"') {
				j := 1;
				for(; j < len rest && rest[j] != '"'; j++)
					;
				rest = trimstr(rest[j+1:]);
			}
			# parse "lower --> upper"
			ai := findkw(rest, "-->");
			if(ai >= 0) {
				c.ylower = parsenum(trimstr(rest[0:ai]));
				c.yupper = parsenum(trimstr(rest[ai+3:]));
			}
			continue;
		}
		if(hasprefix(sl, "bar ") || hasprefix(sl, "bar[")) {
			ser := parsexyseries(s, 1);
			if(ser != nil) c.series = ser :: c.series;
			continue;
		}
		if(hasprefix(sl, "line ") || hasprefix(sl, "line[")) {
			ser := parsexyseries(s, 0);
			if(ser != nil) c.series = ser :: c.series;
			continue;
		}
	}
	c.series = revxyseries(c.series);
	return c;
}

parsexyseries(s: string, isbar: int): ref XYSeries
{
	pl: list of string;
	bi := 0;
	for(; bi < len s && s[bi] != '['; bi++)
		;
	if(bi >= len s) return nil;
	ei := bi+1;
	for(; ei < len s && s[ei] != ']'; ei++)
		;
	inner := s[bi+1:ei];
	parts := splittokens(inner, ',');
	n := 0;
	for(pl = parts; pl != nil; pl = tl pl)
		n++;
	if(n == 0) return nil;
	ser := ref XYSeries(isbar, array[n] of int, n);
	k := 0;
	for(pl = parts; pl != nil; pl = tl pl) {
		ser.vals[k] = parsenum(trimstr(hd pl));
		k++;
	}
	return ser;
}

renderxy(lines: list of string, width: int): (ref Image, string)
{
	sl: list of ref XYSeries;
	xi: int;
	c := parsexychart(lines);

	pad := MARGIN;
	titleh := 0;
	if(c.title != "")
		titleh = mfont.height + 8;

	plotw := width - 2*pad - XY_AXISW;
	if(plotw < 60) plotw = 60;
	ih := pad + titleh + XY_PLOTH + XY_AXISH + pad;

	img := mdisp.newimage(Rect((0,0),(width,ih)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil) return (nil, "cannot allocate image");
	img.draw(img.r, cbg, nil, (0,0));

	ty := pad;
	if(c.title != "") {
		tw := mfont.width(c.title);
		img.text(Point(width/2 - tw/2, ty), ctext, Point(0,0), mfont, c.title);
		ty += titleh;
	}

	plotx := pad + XY_AXISW;
	ploty := ty;
	plotboty := ploty + XY_PLOTH;

	# Y range (×1024)
	yrange := c.yupper - c.ylower;
	if(yrange <= 0) yrange = 1024;

	# Grid lines (5 horizontal)
	for(gi := 0; gi <= 4; gi++) {
		gy := ploty + gi * XY_PLOTH / 4;
		img.draw(Rect((plotx, gy), (plotx+plotw, gy+1)), cgrid, nil, (0,0));
		# Y axis label
		yval := c.yupper - gi * yrange / 4;
		lbl := sys->sprint("%d", yval / 1024);
		lw := mfont.width(lbl);
		img.text(Point(plotx - lw - 4, gy), ctext2, Point(0,0), mfont, lbl);
	}

	# Axes
	img.line(Point(plotx, ploty), Point(plotx, plotboty), Draw->Endsquare, Draw->Endsquare, 0, cbord, Point(0,0));
	img.line(Point(plotx, plotboty), Point(plotx+plotw, plotboty), Draw->Endsquare, Draw->Endsquare, 0, cbord, Point(0,0));

	ncols := c.nxlbl;
	if(ncols <= 0) {
		# Infer from first series
		for(sl = c.series; sl != nil; sl = tl sl)
			if((hd sl).nvals > ncols) ncols = (hd sl).nvals;
	}
	if(ncols <= 0) ncols = 1;

	colw := plotw / ncols;
	nser := 0;
	for(sl = c.series; sl != nil; sl = tl sl)
		nser++;

	# Draw series
	si := 0;
	for(sl = c.series; sl != nil; sl = tl sl) {
		ser := hd sl;
		col := cpie[si % 8];

		if(ser.isbar) {
			# Bars
			barw := colw * 7 / (8 * (nser + 1));
			if(barw < 2) barw = 2;
			for(xi = 0; xi < ser.nvals && xi < ncols; xi++) {
				v := ser.vals[xi];
				# ypix: top of bar relative to ploty
				ypix := XY_PLOTH - int(big(v - c.ylower) * big XY_PLOTH / big yrange);
				if(ypix < 0) ypix = 0;
				if(ypix > XY_PLOTH) ypix = XY_PLOTH;
				bx := plotx + xi*colw + si*barw + (colw - nser*barw)/2;
				br := Rect((bx, ploty+ypix), (bx+barw, plotboty));
				img.draw(br, col, nil, (0,0));
			}
		} else {
			# Line
			if(ser.nvals > 0) {
				pts := array[ser.nvals] of Point;
				for(xi = 0; xi < ser.nvals && xi < ncols; xi++) {
					v := ser.vals[xi];
					ypix := XY_PLOTH - int(big(v - c.ylower) * big XY_PLOTH / big yrange);
					if(ypix < 0) ypix = 0;
					if(ypix > XY_PLOTH) ypix = XY_PLOTH;
					pts[xi] = Point(plotx + xi*colw + colw/2, ploty+ypix);
				}
				img.poly(pts[0:ser.nvals], Draw->Enddisc, Draw->Enddisc, 1, col, Point(0,0));
				for(xi = 0; xi < ser.nvals; xi++) {
					img.fillellipse(pts[xi], 3, 3, col, Point(0,0));
				}
			}
		}
		si++;
	}

	# X axis labels
	for(xi = 0; xi < ncols; xi++) {
		lbl := "";
		if(xi < c.nxlbl) lbl = c.xlabels[xi];
		else lbl = sys->sprint("%d", xi+1);
		lw := mfont.width(lbl);
		cx := plotx + xi*colw + colw/2;
		img.text(Point(cx-lw/2, plotboty+4), ctext2, Point(0,0), mfont, lbl);
	}

	return (img, nil);
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── Drawing utilities ────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

# Arrowhead pointing in direction dir: 0=down, 1=right, 2=up, 3=left
drawarrowhead(img: ref Image, tip: Point, dir: int, col: ref Image)
{
	AW: con AHEADW;
	AH: con AHEADLEN;
	pts := array[3] of Point;
	case dir {
	0 =>	# down
		pts[0] = Point(tip.x,    tip.y);
		pts[1] = Point(tip.x-AW, tip.y-AH);
		pts[2] = Point(tip.x+AW, tip.y-AH);
	1 =>	# right
		pts[0] = Point(tip.x,    tip.y);
		pts[1] = Point(tip.x-AH, tip.y-AW);
		pts[2] = Point(tip.x-AH, tip.y+AW);
	2 =>	# up
		pts[0] = Point(tip.x,    tip.y);
		pts[1] = Point(tip.x-AW, tip.y+AH);
		pts[2] = Point(tip.x+AW, tip.y+AH);
	3 =>	# left
		pts[0] = Point(tip.x,    tip.y);
		pts[1] = Point(tip.x+AH, tip.y-AW);
		pts[2] = Point(tip.x+AH, tip.y+AW);
	}
	img.fillpoly(pts, ~0, col, Point(0,0));
}

# Simulated dashed line (8px on, 4px skip)
dashedline(img: ref Image, p0, p1: Point, col: ref Image)
{
	DASH: con 8;
	GAP:  con 4;
	dx := p1.x - p0.x;
	dy := p1.y - p0.y;
	dist := dx;
	if(dist < 0) dist = -dist;
	if(dy < 0 && -dy > dist) dist = -dy;
	else if(dy > dist) dist = dy;
	if(dist == 0) return;

	step := DASH + GAP;
	nstep := dist / step + 1;
	for(i := 0; i < nstep; i++) {
		t0 := i * step;
		t1 := t0 + DASH;
		if(t0 > dist) break;
		if(t1 > dist) t1 = dist;
		x0 := p0.x + dx * t0 / dist;
		y0 := p0.y + dy * t0 / dist;
		x1 := p0.x + dx * t1 / dist;
		y1 := p0.y + dy * t1 / dist;
		img.line(Point(x0,y0), Point(x1,y1), Draw->Endsquare, Draw->Endsquare, 0, col, Point(0,0));
	}
}

# Draw a 1px rectangle border
drawrectrect(img: ref Image, r: Rect, col: ref Image)
{
	img.draw(Rect(r.min, (r.max.x, r.min.y+1)), col, nil, (0,0));
	img.draw(Rect((r.min.x, r.max.y-1), r.max), col, nil, (0,0));
	img.draw(Rect(r.min, (r.min.x+1, r.max.y)), col, nil, (0,0));
	img.draw(Rect((r.max.x-1, r.min.y), r.max), col, nil, (0,0));
}

# Draw a rounded rectangle (fill + border)
drawroundrect(img: ref Image, r: Rect, col: ref Image)
{
	rad := 4;
	if(r.dy() < 2*rad+2) rad = r.dy()/2 - 1;
	if(rad < 1) rad = 1;
	# 4 corner ellipses to overdraw background on corners
	corners := array[4] of Point;
	corners[0] = Point(r.min.x+rad, r.min.y+rad);
	corners[1] = Point(r.max.x-rad-1, r.min.y+rad);
	corners[2] = Point(r.max.x-rad-1, r.max.y-rad-1);
	corners[3] = Point(r.min.x+rad, r.max.y-rad-1);
	for(i := 0; i < 4; i++)
		img.ellipse(corners[i], rad, rad, 0, col, Point(0,0));
	# Top and bottom horizontal bars
	img.draw(Rect((r.min.x+rad, r.min.y), (r.max.x-rad, r.min.y+1)), col, nil, (0,0));
	img.draw(Rect((r.min.x+rad, r.max.y-1), (r.max.x-rad, r.max.y)), col, nil, (0,0));
	# Left and right vertical bars
	img.draw(Rect((r.min.x, r.min.y+rad), (r.min.x+1, r.max.y-rad)), col, nil, (0,0));
	img.draw(Rect((r.max.x-1, r.min.y+rad), (r.max.x, r.max.y-rad)), col, nil, (0,0));
}

# Draw a diamond / rhombus shape
drawdiamond(img: ref Image, cx, cy, w, h: int, fill, border: ref Image)
{
	pts := array[4] of Point;
	pts[0] = Point(cx,    cy-h/2);	# top
	pts[1] = Point(cx+w/2, cy);	# right
	pts[2] = Point(cx,    cy+h/2);	# bottom
	pts[3] = Point(cx-w/2, cy);	# left
	img.fillpoly(pts, ~0, fill, Point(0,0));
	img.poly(pts, Draw->Endsquare, Draw->Endsquare, 0, border, Point(0,0));
	# close the outline
	img.line(pts[3], pts[0], Draw->Endsquare, Draw->Endsquare, 0, border, Point(0,0));
}

# Draw a hexagon
drawhex(img: ref Image, cx, cy, w, h: int, fill, border: ref Image)
{
	pts := array[6] of Point;
	qw := w / 4;
	hw := w / 2;
	hh := h / 2;
	pts[0] = Point(cx+qw, cy-hh);
	pts[1] = Point(cx+hw, cy);
	pts[2] = Point(cx+qw, cy+hh);
	pts[3] = Point(cx-qw, cy+hh);
	pts[4] = Point(cx-hw, cy);
	pts[5] = Point(cx-qw, cy-hh);
	img.fillpoly(pts, ~0, fill, Point(0,0));
	img.poly(pts, Draw->Endsquare, Draw->Endsquare, 0, border, Point(0,0));
	img.line(pts[5], pts[0], Draw->Endsquare, Draw->Endsquare, 0, border, Point(0,0));
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── Common FCGraph renderer (shared by flowchart and state diagram) ──────────
# ═══════════════════════════════════════════════════════════════════════════════

renderfcgraph(g: ref FCGraph, width: int): (ref Image, string)
{
	k: int;
	if(g.nnodes == 0)
		return rendererror("empty diagram", width);
	layoutflow(g, width);
	(iw, ih) := flowimgdims(g, width);
	img := mdisp.newimage(Rect((0,0),(iw,ih)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil)
		return (nil, "cannot allocate image");
	img.draw(img.r, cbg, nil, (0,0));
	na := nodestoarray(g.nodes, g.nnodes);
	ea := edgestoarray(g.edges, g.nedges);
	for(k = 0; k < g.nedges; k++) {
		e := ea[k];
		src := findnode(na, g.nnodes, e.src);
		dst := findnode(na, g.nnodes, e.dst);
		if(src == nil || dst == nil) continue;
		drawfcedge(img, src, dst, e, g.dir);
	}
	for(k = 0; k < g.nnodes; k++)
		drawfcnode(img, na[k]);
	return (img, nil);
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── stateDiagram-v2 ──────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

addstatenode(g: ref FCGraph, id: string)
{
	id = trimstr(id);
	if(id == "") return;
	for(nl := g.nodes; nl != nil; nl = tl nl)
		if((hd nl).id == id) return;
	n := ref FCNode;
	n.id = id;
	if(id == "__start__") n.label = "*";
	else if(id == "__end__") n.label = "[*]";
	else n.label = id;
	n.shape = SH_ROUND;
	n.layer = 0; n.col = 0;
	n.x = 0; n.y = 0; n.w = 0; n.h = 0;
	g.nodes = n :: g.nodes;
	g.nnodes++;
}

parsestate(lines: list of string): ref FCGraph
{
	s, rest, src, dst, lbl: string;
	p, q: int;
	g := ref FCGraph(DIRN_TD, "", nil, 0, nil, 0);
	for(l := lines; l != nil; l = tl l) {
		s = trimstr(hd l);
		if(s == "" || hasprefix(s, "%%")) continue;
		sl := tolower(s);
		if(sl == "statediagram-v2" || sl == "statediagram" || s == "}") continue;
		if(hasprefix(sl, "title ")) { g.title = trimstr(s[6:]); continue; }
		if(hasprefix(sl, "note ") || hasprefix(sl, "end note")) continue;
		p = findkw(s, "-->");
		if(p >= 0) {
			src = trimstr(s[0:p]);
			rest = trimstr(s[p+3:]);
			lbl = "";
			q = findkw(rest, ":");
			if(q >= 0) { lbl = trimstr(rest[q+1:]); rest = trimstr(rest[0:q]); }
			dst = trimstr(rest);
			if(src == "[*]") src = "__start__";
			if(dst == "[*]") dst = "__end__";
			addstatenode(g, src);
			addstatenode(g, dst);
			e := ref FCEdge;
			e.src = src; e.dst = dst; e.label = lbl;
			e.style = ES_SOLID; e.arrow = 1;
			g.edges = e :: g.edges;
			g.nedges++;
			continue;
		}
		if(hasprefix(sl, "state ")) {
			nm := trimstr(s[6:]);
			q = findkw(nm, " {");
			if(q >= 0) nm = trimstr(nm[0:q]);
			q = findkw(nm, "{");
			if(q >= 0) nm = trimstr(nm[0:q]);
			if(nm != "") addstatenode(g, nm);
			continue;
		}
	}
	g.nodes = revnodes(g.nodes);
	g.edges = revedges(g.edges);
	return g;
}

renderstate(lines: list of string, width: int): (ref Image, string)
{
	g := parsestate(lines);
	if(g.nnodes == 0)
		return rendererror("empty state diagram", width);
	return renderfcgraph(g, width);
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── classDiagram ─────────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

findclassnode(d: ref ClassDiag, id: string): ref ClassNode
{
	for(nl := d.nodes; nl != nil; nl = tl nl)
		if((hd nl).id == id) return hd nl;
	return nil;
}

addclassnode(d: ref ClassDiag, id: string)
{
	id = trimstr(id);
	if(id == "") return;
	if(findclassnode(d, id) != nil) return;
	n := ref ClassNode;
	n.id = id; n.label = id;
	n.members = nil; n.nmembers = 0;
	n.x = 0; n.y = 0; n.w = 0; n.h = 0;
	d.nodes = n :: d.nodes;
	d.nnodes++;
}

parseclassrel(s: string, d: ref ClassDiag): int
{
	src, dst, lbl, rest: string;
	p, q, rtype, mlen, found: int;
	found = 0; rtype = CR_ASSOC; mlen = 0; p = -1;
	if(!found) { p = findkw(s, "<|--"); if(p >= 0) { found=1; rtype = CR_INHERIT; mlen = 4; } }
	if(!found) { p = findkw(s, "--|>"); if(p >= 0) { found=1; rtype = CR_INHERIT; mlen = 4; } }
	if(!found) { p = findkw(s, "<|.."); if(p >= 0) { found=1; rtype = CR_REAL;    mlen = 4; } }
	if(!found) { p = findkw(s, "..|>"); if(p >= 0) { found=1; rtype = CR_REAL;    mlen = 4; } }
	if(!found) { p = findkw(s, "*--");  if(p >= 0) { found=1; rtype = CR_COMPOSE; mlen = 3; } }
	if(!found) { p = findkw(s, "--*");  if(p >= 0) { found=1; rtype = CR_COMPOSE; mlen = 3; } }
	if(!found) { p = findkw(s, "o--");  if(p >= 0) { found=1; rtype = CR_AGGR;    mlen = 3; } }
	if(!found) { p = findkw(s, "--o");  if(p >= 0) { found=1; rtype = CR_AGGR;    mlen = 3; } }
	if(!found) { p = findkw(s, "-->"); if(p >= 0) { found=1; rtype = CR_ASSOC;   mlen = 3; } }
	if(!found) { p = findkw(s, "<--"); if(p >= 0) { found=1; rtype = CR_ASSOC;   mlen = 3; } }
	if(!found) { p = findkw(s, "..>"); if(p >= 0) { found=1; rtype = CR_DEP;     mlen = 3; } }
	if(!found) { p = findkw(s, "<.."); if(p >= 0) { found=1; rtype = CR_DEP;     mlen = 3; } }
	if(!found) { p = findkw(s, "--");  if(p >= 0) { found=1; rtype = CR_ASSOC;   mlen = 2; } }
	if(!found) { p = findkw(s, "..");  if(p >= 0) { found=1; rtype = CR_DEP;     mlen = 2; } }
	if(!found || p < 0) return -1;
	src = trimstr(s[0:p]);
	rest = trimstr(s[p+mlen:]);
	q = findkw(rest, ":");
	if(q >= 0) { lbl = trimstr(rest[q+1:]); dst = trimstr(rest[0:q]); }
	else { lbl = ""; dst = rest; }
	dst = trimstr(dst);
	if(src == "" || dst == "") return -1;
	addclassnode(d, src);
	addclassnode(d, dst);
	r := ref ClassRel;
	r.src = src; r.dst = dst; r.label = lbl; r.rtype = rtype;
	d.rels = r :: d.rels;
	d.nrels++;
	return rtype;
}

parseclassdiag(lines: list of string): ref ClassDiag
{
	s, sl, nm, rest: string;
	p, q, inblock: int;
	d := ref ClassDiag("", nil, 0, nil, 0);
	curclass: string;
	inblock = 0; curclass = "";
	for(l := lines; l != nil; l = tl l) {
		s = trimstr(hd l);
		if(s == "" || hasprefix(s, "%%")) continue;
		sl = tolower(s);
		if(hasprefix(sl, "classdiagram")) continue;
		if(hasprefix(sl, "title ")) { d.title = trimstr(s[6:]); continue; }
		if(s == "}") { inblock = 0; curclass = ""; continue; }
		if(inblock) {
			mem := ref ClassMember;
			i := 0;
			if(i < len s && (s[i] == '+' || s[i] == '-' || s[i] == '#' || s[i] == '~'))
				{ mem.vis = s[i:i+1]; i++; }
			else
				mem.vis = "";
			rest = trimstr(s[i:]);
			if(len rest > 2 && rest[len rest - 2:] == "()") {
				mem.name = rest; mem.ismethod = 1;
			} else {
				mem.name = rest; mem.ismethod = 0;
			}
			if(mem.name != "") {
				nd := findclassnode(d, curclass);
				if(nd != nil) { nd.members = mem :: nd.members; nd.nmembers++; }
			}
			continue;
		}
		if(hasprefix(sl, "class ")) {
			nm = trimstr(s[6:]);
			p = findkw(nm, "{");
			if(p >= 0) { curclass = trimstr(nm[0:p]); inblock = 1; }
			else {
				q = findkw(nm, "[");
				if(q >= 0) nm = trimstr(nm[0:q]);
				q = findkw(nm, " ");
				if(q >= 0) nm = trimstr(nm[0:q]);
				curclass = trimstr(nm);
			}
			addclassnode(d, curclass);
			continue;
		}
		parseclassrel(s, d);
	}
	for(nl := d.nodes; nl != nil; nl = tl nl) {
		nd := hd nl;
		rl: list of ref ClassMember;
		for(ml := nd.members; ml != nil; ml = tl ml)
			rl = hd ml :: rl;
		nd.members = rl;
	}
	d.nodes = revclassnodes(d.nodes);
	d.rels = revclassrels(d.rels);
	return d;
}

renderclass(lines: list of string, width: int): (ref Image, string)
{
	i, j, k, ncols, nrows, iw, ih: int;
	cellw, cellh, fldh, meth_y, lx, ly: int;
	bx, by, bw: int;
	d := parseclassdiag(lines);
	if(d.nnodes == 0)
		return rendererror("empty class diagram", width);

	na := array[d.nnodes] of ref ClassNode;
	i = 0;
	for(nl := d.nodes; nl != nil; nl = tl nl)
		na[i++] = hd nl;

	# Compute per-node sizes
	hdr := mfont.height + 2*VPAD;
	for(i = 0; i < d.nnodes; i++) {
		nd := na[i];
		w := mfont.width(nd.label) + 2*HPAD;
		if(w < MINNODEW) w = MINNODEW;
		for(ml := nd.members; ml != nil; ml = tl ml) {
			m := hd ml;
			mw := mfont.width(m.vis + m.name) + 2*HPAD;
			if(mw > w) w = mw;
		}
		nd.w = w;
		nd.h = hdr + nd.nmembers * (mfont.height + 2);
		if(nd.h < MINNODEH) nd.h = MINNODEH;
	}

	# Grid layout
	ncols = 1;
	for(k = 2; k * k <= d.nnodes; k++)
		ncols = k;
	if(ncols < 1) ncols = 1;
	nrows = (d.nnodes + ncols - 1) / ncols;

	# Max cell size
	cellw = 0; cellh = 0;
	for(i = 0; i < d.nnodes; i++) {
		if(na[i].w > cellw) cellw = na[i].w;
		if(na[i].h > cellh) cellh = na[i].h;
	}
	cellw += HGAP; cellh += VGAP;

	iw = ncols * cellw + 2*MARGIN;
	if(iw < width) iw = width;
	ih = nrows * cellh + 2*MARGIN + mfont.height + VPAD;
	if(ih < 200) ih = 200;

	img := mdisp.newimage(Rect((0,0),(iw,ih)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil) return (nil, "cannot allocate image");
	img.draw(img.r, cbg, nil, (0,0));

	# Draw title
	if(d.title != "") {
		tw := mfont.width(d.title);
		img.text(Point(iw/2-tw/2, MARGIN/2), ctext, Point(0,0), mfont, d.title);
	}

	# Position and draw each class box
	for(i = 0; i < d.nnodes; i++) {
		nd := na[i];
		col := i % ncols;
		row := i / ncols;
		nd.x = MARGIN + col * cellw + cellw/2;
		nd.y = MARGIN + mfont.height + VPAD + row * cellh + nd.h/2;

		bx = nd.x - nd.w/2;
		by = nd.y - nd.h/2;
		bw = nd.w;
		boxr := Rect((bx, by), (bx+bw, by+nd.h));
		img.draw(boxr, cnode, nil, (0,0));
		drawrectrect(img, boxr, cbord);

		# Header stripe
		hdr = mfont.height + 2*VPAD;
		img.draw(Rect((bx, by), (bx+bw, by+hdr)), csect, nil, (0,0));
		img.draw(Rect((bx, by+hdr-1), (bx+bw, by+hdr+1)), cbord, nil, (0,0));
		lbl := nd.label;
		lx = bx + bw/2 - mfont.width(lbl)/2;
		img.text(Point(lx, by+VPAD), ctext, Point(0,0), mfont, lbl);

		# Members
		meth_y = by + hdr + 2;
		for(ml := nd.members; ml != nil; ml = tl ml) {
			m := hd ml;
			txt := m.vis + m.name;
			fldh = mfont.height + 2;
			lx = bx + HPAD;
			ly = meth_y;
			if(m.ismethod)
				img.text(Point(lx, ly), cacc, Point(0,0), mfont, txt);
			else
				img.text(Point(lx, ly), ctext2, Point(0,0), mfont, txt);
			meth_y += fldh;
		}
	}

	# Draw relationship lines
	ra := array[d.nrels] of ref ClassRel;
	j = 0;
	for(rl := d.rels; rl != nil; rl = tl rl)
		ra[j++] = hd rl;
	for(j = 0; j < d.nrels; j++) {
		r := ra[j];
		sn: ref ClassNode;
		dn: ref ClassNode;
		sn = nil; dn = nil;
		for(k = 0; k < d.nnodes; k++) {
			if(na[k].id == r.src) sn = na[k];
			if(na[k].id == r.dst) dn = na[k];
		}
		if(sn == nil || dn == nil) continue;
		drawclassrel(img, sn, dn, r);
	}

	return (img, nil);
}

drawclassrel(img: ref Image, sn: ref ClassNode, dn: ref ClassNode, r: ref ClassRel)
{
	p1 := Point(sn.x, sn.y);
	p2 := Point(dn.x, dn.y);
	col := cbord;
	case r.rtype {
	CR_INHERIT => col = cacc;
	CR_REAL    => col = cacc;
	CR_COMPOSE => col = cgreen;
	CR_AGGR    => col = cyel;
	}
	img.line(p1, p2, Draw->Endsquare, Draw->Endarrow, 1, col, Point(0,0));
	if(r.label != "") {
		mx := (p1.x + p2.x) / 2;
		my := (p1.y + p2.y) / 2;
		img.text(Point(mx, my), ctext2, Point(0,0), mfont, r.label);
	}
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── erDiagram ────────────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

findentity(d: ref ERDiag, id: string): ref EREntity
{
	for(el := d.entities; el != nil; el = tl el)
		if((hd el).id == id) return hd el;
	return nil;
}

addentity(d: ref ERDiag, id: string)
{
	id = trimstr(id);
	if(id == "") return;
	if(findentity(d, id) != nil) return;
	e := ref EREntity;
	e.id = id;
	e.attrs = nil; e.nattrs = 0;
	e.x = 0; e.y = 0; e.w = 0; e.h = 0;
	d.entities = e :: d.entities;
	d.nentities++;
}

parseerdiag(lines: list of string): ref ERDiag
{
	s, sl, nm, src, dst: string;
	p, q, inblock: int;
	d := ref ERDiag("", nil, 0, nil, 0);
	curent: string;
	inblock = 0; curent = "";
	for(l := lines; l != nil; l = tl l) {
		s = trimstr(hd l);
		if(s == "" || hasprefix(s, "%%")) continue;
		sl = tolower(s);
		if(hasprefix(sl, "erdiagram")) continue;
		if(hasprefix(sl, "title ")) { d.title = trimstr(s[6:]); continue; }
		if(s == "}") { inblock = 0; curent = ""; continue; }
		if(inblock) {
			# Attribute line: "type name [PK|FK|UK]"
			parts := splittokens(s, ' ');
			atype := "";
			aname := "";
			if(parts != nil) { atype = trimstr(hd parts); parts = tl parts; }
			if(parts != nil) { aname = trimstr(hd parts); }
			if(atype != "" && aname != "") {
				a := ref ERAttr;
				a.atype = atype; a.name = aname;
				ent := findentity(d, curent);
				if(ent != nil) { ent.attrs = a :: ent.attrs; ent.nattrs++; }
			}
			continue;
		}
		# Entity block: "ENTITY {" or relationship line
		p = findkw(s, "{");
		if(p >= 0) {
			nm = trimstr(s[0:p]);
			# skip keyword-like tokens
			if(findkw(nm, "|") < 0 && findkw(nm, "o") < 0) {
				curent = trimstr(nm);
				addentity(d, curent);
				inblock = 1;
			}
			continue;
		}
		# Relationship: "A ||--o{ B : label" etc.
		q = findkw(s, " : ");
		if(q < 0) q = findkw(s, ":");
		lbl := "";
		base := s;
		if(q >= 0) { lbl = trimstr(s[q+1:]); base = s[0:q]; }
		# Find relationship marker between entities
		p = -1;
		card := "";
		# Try each ER relationship marker in order
		p = findkw(base, "||--o{"); if(p >= 0) { card = "||--o{"; src = trimstr(base[0:p]); dst = trimstr(base[p+6:]); }
		if(p < 0) { p = findkw(base, "}o--||"); if(p >= 0) { card = "}o--||"; src = trimstr(base[0:p]); dst = trimstr(base[p+6:]); } }
		if(p < 0) { p = findkw(base, "||--||"); if(p >= 0) { card = "||--||"; src = trimstr(base[0:p]); dst = trimstr(base[p+6:]); } }
		if(p < 0) { p = findkw(base, "}|--||"); if(p >= 0) { card = "}|--||"; src = trimstr(base[0:p]); dst = trimstr(base[p+6:]); } }
		if(p < 0) { p = findkw(base, "||--|{"); if(p >= 0) { card = "||--|{"; src = trimstr(base[0:p]); dst = trimstr(base[p+6:]); } }
		if(p < 0) { p = findkw(base, "}|--|{"); if(p >= 0) { card = "}|--|{"; src = trimstr(base[0:p]); dst = trimstr(base[p+6:]); } }
		if(p < 0) { p = findkw(base, "}o--|{"); if(p >= 0) { card = "}o--|{"; src = trimstr(base[0:p]); dst = trimstr(base[p+6:]); } }
		if(p < 0) { p = findkw(base, "||--o|"); if(p >= 0) { card = "||--o|"; src = trimstr(base[0:p]); dst = trimstr(base[p+6:]); } }
		if(p < 0) { p = findkw(base, "|o--o{"); if(p >= 0) { card = "|o--o{"; src = trimstr(base[0:p]); dst = trimstr(base[p+6:]); } }
		if(p < 0) { p = findkw(base, "||..|{"); if(p >= 0) { card = "||..|{"; src = trimstr(base[0:p]); dst = trimstr(base[p+6:]); } }
		if(p < 0) { p = findkw(base, "}|..|{"); if(p >= 0) { card = "}|..|{"; src = trimstr(base[0:p]); dst = trimstr(base[p+6:]); } }
		if(p < 0) { p = findkw(base, "}o..o{"); if(p >= 0) { card = "}o..o{"; src = trimstr(base[0:p]); dst = trimstr(base[p+6:]); } }
		if(p < 0) { p = findkw(base, "||..o{"); if(p >= 0) { card = "||..o{"; src = trimstr(base[0:p]); dst = trimstr(base[p+6:]); } }
		if(p < 0) { p = findkw(base, "--");    if(p >= 0) { card = "--";     src = trimstr(base[0:p]); dst = trimstr(base[p+2:]); } }
		if(p < 0) { p = findkw(base, "..");    if(p >= 0) { card = "..";     src = trimstr(base[0:p]); dst = trimstr(base[p+2:]); } }
		if(p >= 0 && src != "" && dst != "") {
			addentity(d, src);
			addentity(d, dst);
			r := ref ERRel;
			r.src = src; r.dst = dst; r.label = lbl; r.card = card;
			d.rels = r :: d.rels;
			d.nrels++;
		}
	}
	# Reverse attr lists
	for(el := d.entities; el != nil; el = tl el) {
		ent := hd el;
		al: list of ref ERAttr;
		for(atl := ent.attrs; atl != nil; atl = tl atl)
			al = hd atl :: al;
		ent.attrs = al;
	}
	d.entities = reventities(d.entities);
	d.rels = reverrels(d.rels);
	return d;
}

renderer(lines: list of string, width: int): (ref Image, string)
{
	i, j, k, ncols, nrows, iw, ih: int;
	cellw, cellh, bx, by, bw, lx, ly, rowh: int;
	d := parseerdiag(lines);
	if(d.nentities == 0)
		return rendererror("empty ER diagram", width);

	ea := array[d.nentities] of ref EREntity;
	i = 0;
	for(el := d.entities; el != nil; el = tl el)
		ea[i++] = hd el;

	# Compute sizes
	hdr := mfont.height + 2*VPAD;
	rowh = mfont.height + 4;
	for(i = 0; i < d.nentities; i++) {
		ent := ea[i];
		w := mfont.width(ent.id) + 2*HPAD;
		if(w < MINNODEW) w = MINNODEW;
		for(atl := ent.attrs; atl != nil; atl = tl atl) {
			a := hd atl;
			aw := mfont.width(a.atype + " " + a.name) + 2*HPAD;
			if(aw > w) w = aw;
		}
		ent.w = w;
		ent.h = hdr + ent.nattrs * rowh + 4;
		if(ent.h < MINNODEH) ent.h = MINNODEH;
	}

	ncols = 1;
	for(k = 2; k * k <= d.nentities; k++)
		ncols = k;
	nrows = (d.nentities + ncols - 1) / ncols;
	cellw = 0; cellh = 0;
	for(i = 0; i < d.nentities; i++) {
		if(ea[i].w > cellw) cellw = ea[i].w;
		if(ea[i].h > cellh) cellh = ea[i].h;
	}
	cellw += HGAP; cellh += VGAP;
	iw = ncols * cellw + 2*MARGIN;
	if(iw < width) iw = width;
	ih = nrows * cellh + 2*MARGIN + mfont.height + VPAD;
	if(ih < 200) ih = 200;

	img := mdisp.newimage(Rect((0,0),(iw,ih)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil) return (nil, "cannot allocate image");
	img.draw(img.r, cbg, nil, (0,0));

	if(d.title != "") {
		tw := mfont.width(d.title);
		img.text(Point(iw/2-tw/2, MARGIN/2), ctext, Point(0,0), mfont, d.title);
	}

	for(i = 0; i < d.nentities; i++) {
		ent := ea[i];
		col := i % ncols;
		row := i / ncols;
		ent.x = MARGIN + col * cellw + cellw/2;
		ent.y = MARGIN + mfont.height + VPAD + row * cellh + ent.h/2;
		bx = ent.x - ent.w/2;
		by = ent.y - ent.h/2;
		bw = ent.w;
		boxr := Rect((bx, by), (bx+bw, by+ent.h));
		img.draw(boxr, cnode, nil, (0,0));
		drawrectrect(img, boxr, cbord);
		hdr = mfont.height + 2*VPAD;
		img.draw(Rect((bx, by), (bx+bw, by+hdr)), csect, nil, (0,0));
		img.draw(Rect((bx, by+hdr-1), (bx+bw, by+hdr+1)), cbord, nil, (0,0));
		lx = bx + bw/2 - mfont.width(ent.id)/2;
		img.text(Point(lx, by+VPAD), ctext, Point(0,0), mfont, ent.id);
		ly = by + hdr + 2;
		for(atl := ent.attrs; atl != nil; atl = tl atl) {
			a := hd atl;
			txt := a.atype + " " + a.name;
			img.text(Point(bx+HPAD, ly), ctext2, Point(0,0), mfont, txt);
			ly += rowh;
		}
	}

	# Relationship lines
	rra := array[d.nrels] of ref ERRel;
	j = 0;
	for(rl := d.rels; rl != nil; rl = tl rl)
		rra[j++] = hd rl;
	for(j = 0; j < d.nrels; j++) {
		r := rra[j];
		sn: ref EREntity;
		dn: ref EREntity;
		sn = nil; dn = nil;
		for(k = 0; k < d.nentities; k++) {
			if(ea[k].id == r.src) sn = ea[k];
			if(ea[k].id == r.dst) dn = ea[k];
		}
		if(sn == nil || dn == nil) continue;
		p1 := Point(sn.x, sn.y);
		p2 := Point(dn.x, dn.y);
		img.line(p1, p2, Draw->Endsquare, Draw->Endsquare, 0, cbord, Point(0,0));
		if(r.label != "") {
			mx := (p1.x + p2.x) / 2;
			my := (p1.y + p2.y) / 2;
			img.text(Point(mx, my), ctext2, Point(0,0), mfont, r.label);
		}
	}

	return (img, nil);
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── mindmap ──────────────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

parsemindmap(lines: list of string): (array of ref MMNode, int)
{
	nmax := 64;
	na := array[nmax] of ref MMNode;
	nn := 0;
	nodenum := 0;
	for(l := lines; l != nil; l = tl l) {
		s := hd l;
		sl := tolower(trimstr(s));
		if(sl == "" || sl == "mindmap" || hasprefix(sl, "%%")) continue;
		# Count leading spaces/tabs for depth
		depth := 0;
		for(i := 0; i < len s; i++) {
			if(s[i] == '\t') depth += 4;
			else if(s[i] == ' ') depth++;
			else break;
		}
		depth /= 2;
		lbl := trimstr(s);
		# Strip shape decorators: ((x)), (x), [x], {x}
		if(len lbl > 4 && lbl[0:2] == "((" && lbl[len lbl - 2:] == "))")
			lbl = lbl[2:len lbl-2];
		else if(len lbl > 2 && lbl[0] == '(' && lbl[len lbl-1] == ')')
			lbl = lbl[1:len lbl-1];
		else if(len lbl > 2 && lbl[0] == '[' && lbl[len lbl-1] == ']')
			lbl = lbl[1:len lbl-1];
		else if(len lbl > 2 && lbl[0] == '{' && lbl[len lbl-1] == '}')
			lbl = lbl[1:len lbl-1];
		lbl = trimstr(lbl);
		if(lbl == "") continue;
		if(nn >= nmax) break;
		n := ref MMNode;
		n.id = nodenum++;
		n.label = lbl;
		n.depth = depth;
		n.parent = -1;
		n.x = 0; n.y = 0; n.w = 0; n.h = 0;
		# Find parent (nearest node with depth-1)
		for(pi := nn-1; pi >= 0; pi--) {
			if(na[pi].depth == depth - 1) {
				n.parent = na[pi].id;
				break;
			}
			if(na[pi].depth < depth - 1) break;
		}
		na[nn++] = n;
	}
	return (na, nn);
}

rendermindmap(lines: list of string, width: int): (ref Image, string)
{
	i, j, iw, ih, maxdepth, ndepth: int;
	(na, nn) := parsemindmap(lines);
	if(nn == 0)
		return rendererror("empty mindmap", width);

	# Compute node sizes
	for(i = 0; i < nn; i++) {
		n := na[i];
		n.w = mfont.width(n.label) + 2*HPAD;
		n.h = mfont.height + 2*VPAD;
		if(n.w < MINNODEW) n.w = MINNODEW;
	}

	# Find max depth
	maxdepth = 0;
	for(i = 0; i < nn; i++)
		if(na[i].depth > maxdepth) maxdepth = na[i].depth;
	ndepth = maxdepth + 1;

	# Column width per depth level
	coldepw := 160;

	# Count children per parent
	childcount := array[nn] of {* => 0};
	for(i = 0; i < nn; i++) {
		pid := na[i].parent;
		if(pid >= 0) {
			for(j = 0; j < nn; j++)
				if(na[j].id == pid) { childcount[j]++; break; }
		}
	}

	# Simple layout: each node gets y = index * rowspacing
	rowh := mfont.height + VGAP;
	for(i = 0; i < nn; i++) {
		na[i].x = MARGIN + na[i].depth * coldepw;
		na[i].y = MARGIN + i * rowh;
	}

	iw = ndepth * coldepw + MARGIN*2 + 120;
	if(iw < width) iw = width;
	ih = nn * rowh + 2*MARGIN;
	if(ih < 100) ih = 100;

	img := mdisp.newimage(Rect((0,0),(iw,ih)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil) return (nil, "cannot allocate image");
	img.draw(img.r, cbg, nil, (0,0));

	# Draw edges from parent to child
	for(i = 0; i < nn; i++) {
		n := na[i];
		if(n.parent < 0) continue;
		for(j = 0; j < nn; j++) {
			if(na[j].id == n.parent) {
				p1 := Point(na[j].x + na[j].w/2, na[j].y + na[j].h/2);
				p2 := Point(n.x, n.y + n.h/2);
				img.line(p1, p2, Draw->Endsquare, Draw->Endsquare, 0, cbord, Point(0,0));
				break;
			}
		}
	}

	# Draw nodes
	for(i = 0; i < nn; i++) {
		n := na[i];
		r := Rect((n.x, n.y), (n.x+n.w, n.y+n.h));
		if(n.depth == 0) {
			img.draw(r, cacc, nil, (0,0));
			drawrectrect(img, r, cbord);
			img.text(Point(n.x+HPAD, n.y+VPAD), cbg, Point(0,0), mfont, n.label);
		} else {
			img.draw(r, cnode, nil, (0,0));
			drawroundrect(img, r, cbord);
			img.text(Point(n.x+HPAD, n.y+VPAD), ctext, Point(0,0), mfont, n.label);
		}
	}

	return (img, nil);
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── timeline ─────────────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

parsetimeline(lines: list of string): (list of ref TLPeriod, int, string)
{
	periods: list of ref TLPeriod;
	np := 0;
	title := "";
	curp: ref TLPeriod;
	curp = nil;
	for(l := lines; l != nil; l = tl l) {
		s := trimstr(hd l);
		if(s == "" || hasprefix(s, "%%")) continue;
		sl := tolower(s);
		if(sl == "timeline") continue;
		if(hasprefix(sl, "title ")) { title = trimstr(s[6:]); continue; }
		if(hasprefix(sl, "section ")) {
			if(curp != nil) {
				curp.events = revtlevents(curp.events);
				periods = curp :: periods;
				np++;
			}
			curp = ref TLPeriod;
			curp.label = trimstr(s[8:]);
			curp.events = nil;
			curp.nevents = 0;
			continue;
		}
		if(curp == nil) {
			curp = ref TLPeriod;
			curp.label = s;
			curp.events = nil;
			curp.nevents = 0;
			continue;
		}
		# Event line
		ev := ref TLEvent;
		ev.label = s;
		curp.events = ev :: curp.events;
		curp.nevents++;
	}
	if(curp != nil) {
		curp.events = revtlevents(curp.events);
		periods = curp :: periods;
		np++;
	}
	# Reverse
	rev: list of ref TLPeriod;
	for(; periods != nil; periods = tl periods)
		rev = hd periods :: rev;
	return (rev, np, title);
}

rendertimeline(lines: list of string, width: int): (ref Image, string)
{
	i, iw, ih, y, periodw, eventrx: int;
	pl: list of ref TLPeriod;
	(periods, np, title) := parsetimeline(lines);
	if(np == 0)
		return rendererror("empty timeline", width);

	periodw = 160;
	eventrx = width - MARGIN;
	rowh := mfont.height + VGAP/2;
	# Compute total height
	ih = 2*MARGIN + mfont.height + VPAD;
	for(pl = periods; pl != nil; pl = tl pl) {
		p := hd pl;
		ih += rowh;
		ih += p.nevents * rowh;
	}
	iw = width;
	if(iw < 400) iw = 400;

	img := mdisp.newimage(Rect((0,0),(iw,ih)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil) return (nil, "cannot allocate image");
	img.draw(img.r, cbg, nil, (0,0));

	y = MARGIN;
	if(title != "") {
		tw := mfont.width(title);
		img.text(Point(iw/2-tw/2, y), ctext, Point(0,0), mfont, title);
		y += mfont.height + VPAD;
	}

	i = 0;
	for(pl = periods; pl != nil; pl = tl pl) {
		p := hd pl;
		# Period bar
		col := cpie[i % 8];
		img.draw(Rect((MARGIN, y), (MARGIN+periodw, y+rowh-2)), col, nil, (0,0));
		lx := MARGIN + HPAD;
		img.text(Point(lx, y+2), cbg, Point(0,0), mfont, p.label);
		y += rowh;
		# Events
		for(el := p.events; el != nil; el = tl el) {
			ev := hd el;
			img.text(Point(MARGIN+periodw+HPAD, y+2), ctext, Point(0,0), mfont, ev.label);
			img.line(Point(MARGIN+periodw, y+rowh/2), Point(MARGIN+periodw+HPAD, y+rowh/2),
				Draw->Endsquare, Draw->Endsquare, 0, col, Point(0,0));
			y += rowh;
		}
		i++;
	}

	return (img, nil);
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── gitGraph ─────────────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

parsegitgraph(lines: list of string): (list of ref GitCommit, int, string)
{
	commits: list of ref GitCommit;
	nc := 0;
	title := "";
	curbranch := "main";
	lastcommit: string;
	lastcommit = "";
	for(l := lines; l != nil; l = tl l) {
		s := trimstr(hd l);
		if(s == "" || hasprefix(s, "%%")) continue;
		sl := tolower(s);
		if(hasprefix(sl, "gitgraph")) continue;
		if(hasprefix(sl, "title ")) { title = trimstr(s[6:]); continue; }
		if(hasprefix(sl, "branch ")) {
			curbranch = trimstr(s[7:]);
			continue;
		}
		if(hasprefix(sl, "checkout ")) {
			curbranch = trimstr(s[9:]);
			continue;
		}
		if(hasprefix(sl, "commit")) {
			c := ref GitCommit;
			c.branch = curbranch;
			c.parent = lastcommit;
			c.ismerge = 0;
			c.x = 0; c.y = 0;
			# Parse id: "id"
			p := findkw(s, "id:");
			if(p >= 0) {
				rest := trimstr(s[p+3:]);
				if(len rest > 0 && rest[0] == '"') {
					(id, ep) := readuntil(rest, 1, '"');
					c.id = id;
				} else {
					(id, ep2) := splitfirsttok(rest);
					c.id = id;
				}
			} else {
				c.id = sys->sprint("c%d", nc);
			}
			c.label = c.id;
			lastcommit = c.id;
			commits = c :: commits;
			nc++;
			continue;
		}
		if(hasprefix(sl, "merge ")) {
			c := ref GitCommit;
			c.branch = curbranch;
			c.parent = lastcommit;
			c.ismerge = 1;
			c.id = sys->sprint("m%d", nc);
			c.label = "merge";
			c.x = 0; c.y = 0;
			lastcommit = c.id;
			commits = c :: commits;
			nc++;
			continue;
		}
	}
	rev: list of ref GitCommit;
	for(; commits != nil; commits = tl commits)
		rev = hd commits :: rev;
	return (rev, nc, title);
}

rendergitgraph(lines: list of string, width: int): (ref Image, string)
{
	i, j, iw, ih, nbranches: int;
	(commits, nc, title) := parsegitgraph(lines);
	if(nc == 0)
		return rendererror("empty git graph", width);

	ca := array[nc] of ref GitCommit;
	i = 0;
	for(cl := commits; cl != nil; cl = tl cl)
		ca[i++] = hd cl;

	# Collect unique branches
	branches := array[16] of string;
	nbranches = 0;
	for(i = 0; i < nc; i++) {
		found := 0;
		for(j = 0; j < nbranches; j++)
			if(branches[j] == ca[i].branch) { found = 1; break; }
		if(!found && nbranches < 16)
			branches[nbranches++] = ca[i].branch;
	}

	# Layout: x = commit index * step, y = branch lane * laneH
	step := 60;
	laneH := 50;
	rad := 10;
	iw = nc * step + 2*MARGIN;
	if(iw < width) iw = width;
	ih = nbranches * laneH + 2*MARGIN + mfont.height + VPAD;
	if(ih < 100) ih = 100;

	img := mdisp.newimage(Rect((0,0),(iw,ih)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil) return (nil, "cannot allocate image");
	img.draw(img.r, cbg, nil, (0,0));

	y0 := MARGIN;
	if(title != "") {
		tw := mfont.width(title);
		img.text(Point(iw/2-tw/2, y0), ctext, Point(0,0), mfont, title);
		y0 += mfont.height + VPAD;
	}

	# Draw branch labels
	for(j = 0; j < nbranches; j++) {
		ly := y0 + j * laneH + laneH/2;
		img.text(Point(MARGIN, ly - mfont.height/2), ctext2, Point(0,0), mfont, branches[j]);
	}

	# Assign commit positions
	for(i = 0; i < nc; i++) {
		c := ca[i];
		lane := 0;
		for(j = 0; j < nbranches; j++)
			if(branches[j] == c.branch) { lane = j; break; }
		c.x = MARGIN + 80 + i * step;
		c.y = y0 + lane * laneH + laneH/2;
	}

	# Draw edges
	for(i = 0; i < nc; i++) {
		c := ca[i];
		if(c.parent == "") continue;
		for(j = 0; j < nc; j++) {
			if(ca[j].id == c.parent) {
				img.line(Point(ca[j].x, ca[j].y), Point(c.x, c.y),
					Draw->Endsquare, Draw->Endsquare, 1, cbord, Point(0,0));
				break;
			}
		}
	}

	# Draw commit circles
	for(i = 0; i < nc; i++) {
		c := ca[i];
		col := cpie[i % 8];
		if(c.ismerge) col = cyel;
		img.fillellipse(Point(c.x, c.y), rad, rad, col, Point(0,0));
		img.ellipse(Point(c.x, c.y), rad, rad, 0, cbord, Point(0,0));
		img.text(Point(c.x - mfont.width(c.label)/2, c.y + rad + 2), ctext2, Point(0,0), mfont, c.label);
	}

	return (img, nil);
}

# Helper for gitGraph parsing
splitfirsttok(s: string): (string, string)
{
	s = trimstr(s);
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t' || s[i] == '\n')
			return (s[0:i], trimstr(s[i:]));
	}
	return (s, "");
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── quadrantChart ────────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

parsequadrant(lines: list of string, width: int): (ref Image, string)
{
	title := "";
	xlbl := "x";
	ylbl := "y";
	qlabels := array[4] of string;
	qlabels[0] = "Q1"; qlabels[1] = "Q2";
	qlabels[2] = "Q3"; qlabels[3] = "Q4";
	points: list of ref QPoint;
	npoints := 0;
	for(l := lines; l != nil; l = tl l) {
		s := trimstr(hd l);
		if(s == "" || hasprefix(s, "%%")) continue;
		sl := tolower(s);
		if(hasprefix(sl, "quadrantchart")) continue;
		if(hasprefix(sl, "title ")) { title = trimstr(s[6:]); continue; }
		if(hasprefix(sl, "x-axis ")) {
			xlbl = trimstr(s[7:]);
			continue;
		}
		if(hasprefix(sl, "y-axis ")) {
			ylbl = trimstr(s[7:]);
			continue;
		}
		if(hasprefix(sl, "quadrant-1 ")) { qlabels[0] = trimstr(s[11:]); continue; }
		if(hasprefix(sl, "quadrant-2 ")) { qlabels[1] = trimstr(s[11:]); continue; }
		if(hasprefix(sl, "quadrant-3 ")) { qlabels[2] = trimstr(s[11:]); continue; }
		if(hasprefix(sl, "quadrant-4 ")) { qlabels[3] = trimstr(s[11:]); continue; }
		# Data point: "Label: [x, y]"
		p := findkw(s, ": [");
		if(p < 0) p = findkw(s, ":[");
		if(p >= 0) {
			lbl := trimstr(s[0:p]);
			rest := s[p+2:];
			if(len rest > 0 && rest[0] == '[') rest = rest[1:];
			q2 := findkw(rest, "]");
			if(q2 >= 0) rest = rest[0:q2];
			parts := splittokens(rest, ',');
			qx := 512; qy := 512;
			if(parts != nil) { qx = parsenum(hd parts); parts = tl parts; }
			if(parts != nil) { qy = parsenum(hd parts); }
			pt := ref QPoint;
			pt.label = lbl; pt.qx = qx; pt.qy = qy;
			points = pt :: points;
			npoints++;
		}
	}
	# Reverse points
	rev: list of ref QPoint;
	for(; points != nil; points = tl points)
		rev = hd points :: rev;

	# Render
	margin := MARGIN;
	axisw := 36;
	axish := 24;
	plotw := 400;
	ploth := 300;
	iw := plotw + axisw + 2*margin;
	ih := ploth + axish + 2*margin + mfont.height + VPAD;
	if(iw < width) iw = width;
	if(iw < 500) iw = 500;

	img := mdisp.newimage(Rect((0,0),(iw,ih)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil) return (nil, "cannot allocate image");
	img.draw(img.r, cbg, nil, (0,0));

	y0 := margin;
	if(title != "") {
		tw := mfont.width(title);
		img.text(Point(iw/2-tw/2, y0), ctext, Point(0,0), mfont, title);
		y0 += mfont.height + VPAD;
	}

	ox := margin + axisw;
	oy := y0;
	# Plot area
	img.draw(Rect((ox, oy), (ox+plotw, oy+ploth)), cnode, nil, (0,0));
	# Grid lines
	img.line(Point(ox+plotw/2, oy), Point(ox+plotw/2, oy+ploth), Draw->Endsquare, Draw->Endsquare, 0, cgrid, Point(0,0));
	img.line(Point(ox, oy+ploth/2), Point(ox+plotw, oy+ploth/2), Draw->Endsquare, Draw->Endsquare, 0, cgrid, Point(0,0));
	# Border
	drawrectrect(img, Rect((ox,oy),(ox+plotw,oy+ploth)), cbord);

	# Quadrant labels
	img.text(Point(ox+plotw/2+4, oy+4), ctext2, Point(0,0), mfont, qlabels[0]);
	img.text(Point(ox+4, oy+4), ctext2, Point(0,0), mfont, qlabels[1]);
	img.text(Point(ox+4, oy+ploth/2+4), ctext2, Point(0,0), mfont, qlabels[2]);
	img.text(Point(ox+plotw/2+4, oy+ploth/2+4), ctext2, Point(0,0), mfont, qlabels[3]);

	# Axis labels
	tw := mfont.width(xlbl);
	img.text(Point(ox+plotw/2-tw/2, oy+ploth+4), ctext2, Point(0,0), mfont, xlbl);
	img.text(Point(margin, oy+ploth/2), ctext2, Point(0,0), mfont, ylbl);

	# Data points
	for(pl := rev; pl != nil; pl = tl pl) {
		pt := hd pl;
		px := ox + pt.qx * plotw / 1024;
		py := oy + ploth - pt.qy * ploth / 1024;
		img.fillellipse(Point(px, py), 5, 5, cacc, Point(0,0));
		img.text(Point(px+7, py-mfont.height/2), ctext, Point(0,0), mfont, pt.label);
	}

	return (img, nil);
}

renderquadrant(lines: list of string, width: int): (ref Image, string)
{
	return parsequadrant(lines, width);
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── journey ──────────────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

parsejourney(lines: list of string): (list of ref JSection, int, string)
{
	sections: list of ref JSection;
	ns := 0;
	title := "";
	cursec: ref JSection;
	cursec = nil;
	for(l := lines; l != nil; l = tl l) {
		s := trimstr(hd l);
		if(s == "" || hasprefix(s, "%%")) continue;
		sl := tolower(s);
		if(sl == "journey") continue;
		if(hasprefix(sl, "title ")) { title = trimstr(s[6:]); continue; }
		if(hasprefix(sl, "section ")) {
			if(cursec != nil) {
				cursec.tasks = revjtasks(cursec.tasks);
				sections = cursec :: sections;
				ns++;
			}
			cursec = ref JSection;
			cursec.label = trimstr(s[8:]);
			cursec.tasks = nil;
			cursec.ntasks = 0;
			continue;
		}
		if(cursec == nil) continue;
		# Task line: "task: score: actors"
		p := findkw(s, ":");
		if(p < 0) continue;
		lbl := trimstr(s[0:p]);
		rest := trimstr(s[p+1:]);
		q := findkw(rest, ":");
		score := 3;
		actors := "";
		if(q >= 0) {
			score = parsenum(trimstr(rest[0:q])) / 1024;
			actors = trimstr(rest[q+1:]);
		} else {
			score = parsenum(trimstr(rest)) / 1024;
		}
		if(score < 1) score = 1;
		if(score > 5) score = 5;
		t := ref JTask;
		t.label = lbl; t.score = score; t.actors = actors;
		cursec.tasks = t :: cursec.tasks;
		cursec.ntasks++;
	}
	if(cursec != nil) {
		cursec.tasks = revjtasks(cursec.tasks);
		sections = cursec :: sections;
		ns++;
	}
	rev: list of ref JSection;
	for(; sections != nil; sections = tl sections)
		rev = hd sections :: rev;
	return (rev, ns, title);
}

renderjourney(lines: list of string, width: int): (ref Image, string)
{
	i, iw, ih, y, rowh: int;
	sl: list of ref JSection;
	(sections, ns, title) := parsejourney(lines);
	if(ns == 0)
		return rendererror("empty journey", width);

	rowh = mfont.height + VGAP/2;
	ih = 2*MARGIN + mfont.height + VPAD;
	for(sl = sections; sl != nil; sl = tl sl) {
		sec := hd sl;
		ih += rowh + sec.ntasks * rowh;
	}
	iw = width;
	if(iw < 400) iw = 400;

	img := mdisp.newimage(Rect((0,0),(iw,ih)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil) return (nil, "cannot allocate image");
	img.draw(img.r, cbg, nil, (0,0));

	y = MARGIN;
	if(title != "") {
		tw := mfont.width(title);
		img.text(Point(iw/2-tw/2, y), ctext, Point(0,0), mfont, title);
		y += mfont.height + VPAD;
	}

	i = 0;
	scorebarw := 100;
	for(sl = sections; sl != nil; sl = tl sl) {
		sec := hd sl;
		col := cpie[i % 8];
		# Section header
		img.draw(Rect((MARGIN, y), (iw-MARGIN, y+rowh-2)), csect, nil, (0,0));
		img.text(Point(MARGIN+HPAD, y+2), ctext, Point(0,0), mfont, sec.label);
		y += rowh;
		for(tl2 := sec.tasks; tl2 != nil; tl2 = tl tl2) {
			t := hd tl2;
			# Label
			img.text(Point(MARGIN+HPAD, y+2), ctext, Point(0,0), mfont, t.label);
			# Score bar
			bx := iw/2;
			bw := scorebarw * t.score / 5;
			img.draw(Rect((bx, y+2), (bx+bw, y+rowh-4)), col, nil, (0,0));
			# Score text
			stxt := sys->sprint("%d/5", t.score);
			img.text(Point(bx+bw+4, y+2), ctext2, Point(0,0), mfont, stxt);
			# Actors
			if(t.actors != "")
				img.text(Point(bx+scorebarw+HPAD+40, y+2), ctext2, Point(0,0), mfont, t.actors);
			y += rowh;
		}
		i++;
	}

	return (img, nil);
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── requirementDiagram ───────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

findreqnode(d: ref ReqDiag, id: string): ref ReqNode
{
	for(nl := d.nodes; nl != nil; nl = tl nl)
		if((hd nl).id == id) return hd nl;
	return nil;
}

addreqnode(d: ref ReqDiag, id: string, ntype: int)
{
	id = trimstr(id);
	if(id == "") return;
	if(findreqnode(d, id) != nil) return;
	n := ref ReqNode;
	n.id = id; n.name = id; n.ntype = ntype;
	n.rid = ""; n.text = ""; n.risk = ""; n.verify = ""; n.etype = "";
	n.x = 0; n.y = 0; n.w = 0; n.h = 0;
	d.nodes = n :: d.nodes;
	d.nnodes++;
}

parsereqdiag(lines: list of string): ref ReqDiag
{
	s, sl, nm, kw, val: string;
	p, q, inblock, blocktype: int;
	d := ref ReqDiag("", nil, 0, nil, 0);
	curnode: string;
	inblock = 0; blocktype = RN_REQ; curnode = "";
	for(l := lines; l != nil; l = tl l) {
		s = trimstr(hd l);
		if(s == "" || hasprefix(s, "%%")) continue;
		sl = tolower(s);
		if(hasprefix(sl, "requirementdiagram")) continue;
		if(s == "}") { inblock = 0; curnode = ""; continue; }
		if(inblock) {
			p = findkw(s, ":");
			if(p < 0) continue;
			kw = tolower(trimstr(s[0:p]));
			val = trimstr(s[p+1:]);
			nd := findreqnode(d, curnode);
			if(nd != nil) {
				if(kw == "id") nd.rid = val;
				else if(kw == "text") nd.text = val;
				else if(kw == "risk") nd.risk = val;
				else if(kw == "verifymethod") nd.verify = val;
				else if(kw == "type") nd.etype = val;
			}
			continue;
		}
		# Block start
		ntype := RN_REQ;
		if(hasprefix(sl, "requirement ") || hasprefix(sl, "functionalrequirement ") ||
				hasprefix(sl, "performancerequirement ") || hasprefix(sl, "interfacerequirement ") ||
				hasprefix(sl, "physicalrequirement ") || hasprefix(sl, "designconstraint "))
			ntype = RN_REQ;
		else if(hasprefix(sl, "element "))
			ntype = RN_ELEM;
		else {
			# Relationship line: "A - satisfies -> B" etc.
			p = findkw(s, " - ");
			q = findkw(s, " -> ");
			if(p >= 0 && q >= 0) {
				src := trimstr(s[0:p]);
				dst := trimstr(s[q+4:]);
				rtype := trimstr(s[p+3:q]);
				addreqnode(d, src, RN_REQ);
				addreqnode(d, dst, RN_REQ);
				r := ref ReqRel;
				r.src = src; r.dst = dst; r.rtype = rtype;
				d.rels = r :: d.rels;
				d.nrels++;
			}
			continue;
		}
		p = findkw(s, " ");
		if(p < 0) continue;
		nm = trimstr(s[p:]);
		q = findkw(nm, " {");
		if(q >= 0) nm = trimstr(nm[0:q]);
		q = findkw(nm, "{");
		if(q >= 0) nm = trimstr(nm[0:q]);
		nm = trimstr(nm);
		if(nm == "") continue;
		addreqnode(d, nm, ntype);
		nd2 := findreqnode(d, nm);
		if(nd2 != nil) nd2.ntype = ntype;
		p2 := findkw(s, "{");
		if(p2 >= 0) { inblock = 1; blocktype = ntype; curnode = nm; }
	}
	d.nodes = revreqnodes(d.nodes);
	d.rels = revreqrels(d.rels);
	return d;
}

renderreqmt(lines: list of string, width: int): (ref Image, string)
{
	i, j, k, ncols, nrows, iw, ih: int;
	cellw, cellh, bx, by, bw, lx, ly, rowh: int;
	d := parsereqdiag(lines);
	if(d.nnodes == 0)
		return rendererror("empty requirement diagram", width);

	na := array[d.nnodes] of ref ReqNode;
	i = 0;
	for(nl := d.nodes; nl != nil; nl = tl nl)
		na[i++] = hd nl;

	rowh = mfont.height + 4;
	for(i = 0; i < d.nnodes; i++) {
		nd := na[i];
		w := mfont.width(nd.name) + 2*HPAD;
		if(nd.rid != "") {
			tw := mfont.width("id: " + nd.rid) + 2*HPAD;
			if(tw > w) w = tw;
		}
		if(nd.text != "") {
			tw := mfont.width(nd.text) + 2*HPAD;
			if(tw > w) w = tw;
		}
		if(w < MINNODEW) w = MINNODEW;
		nd.w = w;
		nrows2 := 1;
		if(nd.rid != "") nrows2++;
		if(nd.text != "") nrows2++;
		if(nd.risk != "") nrows2++;
		if(nd.verify != "") nrows2++;
		if(nd.etype != "") nrows2++;
		nd.h = (mfont.height + 2*VPAD) + nrows2 * rowh + 4;
	}

	ncols = 1;
	for(k = 2; k * k <= d.nnodes; k++)
		ncols = k;
	nrows = (d.nnodes + ncols - 1) / ncols;
	cellw = 0; cellh = 0;
	for(i = 0; i < d.nnodes; i++) {
		if(na[i].w > cellw) cellw = na[i].w;
		if(na[i].h > cellh) cellh = na[i].h;
	}
	cellw += HGAP; cellh += VGAP;
	iw = ncols * cellw + 2*MARGIN;
	if(iw < width) iw = width;
	ih = nrows * cellh + 2*MARGIN;
	if(ih < 200) ih = 200;

	img := mdisp.newimage(Rect((0,0),(iw,ih)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil) return (nil, "cannot allocate image");
	img.draw(img.r, cbg, nil, (0,0));

	for(i = 0; i < d.nnodes; i++) {
		nd := na[i];
		col := i % ncols;
		row := i / ncols;
		nd.x = MARGIN + col * cellw + cellw/2;
		nd.y = MARGIN + row * cellh + nd.h/2;
		bx = nd.x - nd.w/2;
		by = nd.y - nd.h/2;
		bw = nd.w;
		hdr := mfont.height + 2*VPAD;
		boxr := Rect((bx, by), (bx+bw, by+nd.h));
		img.draw(boxr, cnode, nil, (0,0));
		drawrectrect(img, boxr, cbord);
		hdrcol := cacc;
		if(nd.ntype == RN_ELEM) hdrcol = csect;
		img.draw(Rect((bx, by), (bx+bw, by+hdr)), hdrcol, nil, (0,0));
		img.draw(Rect((bx, by+hdr-1), (bx+bw, by+hdr+1)), cbord, nil, (0,0));
		lx = bx + bw/2 - mfont.width(nd.name)/2;
		img.text(Point(lx, by+VPAD), cbg, Point(0,0), mfont, nd.name);
		ly = by + hdr + 2;
		if(nd.rid != "") {
			img.text(Point(bx+HPAD, ly), ctext2, Point(0,0), mfont, "id: "+nd.rid);
			ly += rowh;
		}
		if(nd.text != "") {
			img.text(Point(bx+HPAD, ly), ctext, Point(0,0), mfont, nd.text);
			ly += rowh;
		}
		if(nd.risk != "") {
			img.text(Point(bx+HPAD, ly), cyel, Point(0,0), mfont, "risk: "+nd.risk);
			ly += rowh;
		}
		if(nd.verify != "") {
			img.text(Point(bx+HPAD, ly), cgreen, Point(0,0), mfont, "verify: "+nd.verify);
			ly += rowh;
		}
		if(nd.etype != "") {
			img.text(Point(bx+HPAD, ly), ctext2, Point(0,0), mfont, "type: "+nd.etype);
			ly += rowh;
		}
	}

	# Relationship lines
	ra2 := array[d.nrels] of ref ReqRel;
	j = 0;
	for(rl := d.rels; rl != nil; rl = tl rl)
		ra2[j++] = hd rl;
	for(j = 0; j < d.nrels; j++) {
		r := ra2[j];
		sn: ref ReqNode;
		dn: ref ReqNode;
		sn = nil; dn = nil;
		for(k = 0; k < d.nnodes; k++) {
			if(na[k].id == r.src) sn = na[k];
			if(na[k].id == r.dst) dn = na[k];
		}
		if(sn == nil || dn == nil) continue;
		p1 := Point(sn.x, sn.y);
		p2 := Point(dn.x, dn.y);
		img.line(p1, p2, Draw->Endsquare, Draw->Endarrow, 1, cacc, Point(0,0));
		mx := (p1.x + p2.x) / 2;
		my := (p1.y + p2.y) / 2;
		img.text(Point(mx, my), ctext2, Point(0,0), mfont, r.rtype);
	}

	return (img, nil);
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── block-beta ───────────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

parseblockdiag(lines: list of string): (list of ref BlockNode, int, int, string)
{
	nodes: list of ref BlockNode;
	nn := 0;
	ncols := 3;
	title := "";
	for(l := lines; l != nil; l = tl l) {
		s := trimstr(hd l);
		if(s == "" || hasprefix(s, "%%")) continue;
		sl := tolower(s);
		if(hasprefix(sl, "block-beta")) continue;
		if(hasprefix(sl, "title ")) { title = trimstr(s[6:]); continue; }
		if(hasprefix(sl, "columns ")) {
			rest := trimstr(s[8:]);
			ncols = parsenum(rest) / 1024;
			if(ncols < 1) ncols = 1;
			continue;
		}
		# Parse blocks on this line
		# Format: A["Label"] B C["Another"]
		i := 0;
		n := len s;
		for(i = 0; i < n;) {
			for(; i < n && (s[i] == ' ' || s[i] == '\t'); i++) ;
			if(i >= n) break;
			# Read ID
			idstart := i;
			for(; i < n && s[i] != '[' && s[i] != ' ' && s[i] != '\t'; i++) ;
			id := s[idstart:i];
			if(id == "") break;
			lbl := id;
			# Check for ["label"]
			if(i < n && s[i] == '[') {
				i++;
				if(i < n && s[i] == '"') {
					i++;
					lstart := i;
					for(; i < n && s[i] != '"'; i++) ;
					lbl = s[lstart:i];
					if(i < n) i++; # skip "
				}
				if(i < n && s[i] == ']') i++;
			}
			b := ref BlockNode;
			b.id = id; b.label = lbl; b.cols = 1;
			b.x = 0; b.y = 0; b.w = 0; b.h = 0;
			nodes = b :: nodes;
			nn++;
		}
	}
	rev: list of ref BlockNode;
	for(; nodes != nil; nodes = tl nodes)
		rev = hd nodes :: rev;
	return (rev, nn, ncols, title);
}

renderblock(lines: list of string, width: int): (ref Image, string)
{
	i, iw, ih, nrows: int;
	cellw, cellh, bx, by: int;
	(nodes, nn, ncols, title) := parseblockdiag(lines);
	if(nn == 0)
		return rendererror("empty block diagram", width);

	na := array[nn] of ref BlockNode;
	i = 0;
	for(nl := nodes; nl != nil; nl = tl nl)
		na[i++] = hd nl;

	cellw = 0;
	for(i = 0; i < nn; i++) {
		w := mfont.width(na[i].label) + 2*HPAD;
		if(w < MINNODEW) w = MINNODEW;
		na[i].w = w;
		na[i].h = mfont.height + 2*VPAD;
		if(w > cellw) cellw = w;
	}
	cellh = mfont.height + 2*VPAD + VGAP;
	cellw += HGAP;
	nrows = (nn + ncols - 1) / ncols;
	iw = ncols * cellw + 2*MARGIN;
	if(iw < width) iw = width;
	ih = nrows * cellh + 2*MARGIN + mfont.height + VPAD;

	img := mdisp.newimage(Rect((0,0),(iw,ih)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil) return (nil, "cannot allocate image");
	img.draw(img.r, cbg, nil, (0,0));

	y0 := MARGIN;
	if(title != "") {
		tw := mfont.width(title);
		img.text(Point(iw/2-tw/2, y0), ctext, Point(0,0), mfont, title);
		y0 += mfont.height + VPAD;
	}

	for(i = 0; i < nn; i++) {
		b := na[i];
		col := i % ncols;
		row := i / ncols;
		bx = MARGIN + col * cellw;
		by = y0 + row * cellh;
		b.x = bx; b.y = by;
		b.w = cellw - HGAP; b.h = cellh - VGAP;
		boxr := Rect((bx, by), (bx+b.w, by+b.h));
		img.draw(boxr, cnode, nil, (0,0));
		drawrectrect(img, boxr, cbord);
		lx := bx + b.w/2 - mfont.width(b.label)/2;
		img.text(Point(lx, by+VPAD), ctext, Point(0,0), mfont, b.label);
	}

	return (img, nil);
}

# Error placeholder image
rendererror(msg: string, width: int): (ref Image, string)
{
	h := mfont.height + 2*MARGIN;
	img := mdisp.newimage(Rect((0,0),(width,h)), mdisp.image.chans, 0, Draw->Nofill);
	if(img == nil)
		return (nil, msg);
	img.draw(img.r, cbg, nil, (0,0));
	tw := mfont.width(msg);
	img.text(Point(width/2-tw/2, MARGIN), cred, Point(0,0), mfont, msg);
	return (img, nil);
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── String / parsing utilities ───────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

splitlines(s: string): list of string
{
	lines: list of string;
	i := 0; n := len s;
	start := 0;
	while(i < n) {
		if(s[i] == '\n') {
			lines = s[start:i] :: lines;
			start = i + 1;
		}
		i++;
	}
	if(start < n)
		lines = s[start:n] :: lines;
	rev: list of string;
	for(; lines != nil; lines = tl lines)
		rev = hd lines :: rev;
	return rev;
}

trimstr(s: string): string
{
	i := 0; n := len s;
	while(i < n && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r'))
		i++;
	while(n > i && (s[n-1] == ' ' || s[n-1] == '\t' || s[n-1] == '\r' || s[n-1] == '\n'))
		n--;
	if(i >= n) return "";
	return s[i:n];
}

tolower(s: string): string
{
	r := s;
	for(i := 0; i < len r; i++) {
		c := r[i];
		if(c >= 'A' && c <= 'Z')
			r[i] = c + ('a' - 'A');
	}
	return r;
}

hasprefix(s, pfx: string): int
{
	return len s >= len pfx && s[0:len pfx] == pfx;
}

# Read until stop character; return (content, new_i).
# i should point to first char of content (after opening delimiter).
readuntil(s: string, i: int, stop: int): (string, int)
{
	n := len s;
	start := i;
	while(i < n && s[i] != stop)
		i++;
	return (s[start:i], i);
}

# Find first occurrence of keyword kw in s; return index or -1
findkw(s, kw: string): int
{
	nl := len s - len kw;
	for(i := 0; i <= nl; i++)
		if(s[i:i+len kw] == kw) return i;
	return -1;
}

# Split s by delimiter ch; returns list of tokens
splittokens(s: string, ch: int): list of string
{
	toks: list of string;
	i := 0; n := len s;
	start := 0;
	while(i < n) {
		if(s[i] == ch) {
			toks = s[start:i] :: toks;
			start = i + 1;
		}
		i++;
	}
	toks = s[start:n] :: toks;
	rev: list of string;
	for(; toks != nil; toks = tl toks)
		rev = hd toks :: rev;
	return rev;
}

# Parse "3.14" or "42" as ×1024 fixed-point integer; integers only
parsenum(s: string): int
{
	i: int;
	s = trimstr(s);
	if(s == "") return 0;
	neg := 0;
	if(len s > 0 && s[0] == '-') { neg = 1; s = s[1:]; }
	dot := -1;
	for(i = 0; i < len s; i++)
		if(s[i] == '.') { dot = i; break; }
	result := 0;
	if(dot < 0) {
		for(i = 0; i < len s; i++) {
			c := s[i];
			if(c < '0' || c > '9') break;
			result = result * 10 + (c - '0');
		}
		result *= 1024;
	} else {
		for(i = 0; i < dot; i++) {
			c := s[i];
			if(c < '0' || c > '9') break;
			result = result * 10 + (c - '0');
		}
		result *= 1024;
		# Fractional part (up to 4 digits)
		scale := 1024;
		for(i = dot+1; i < len s && i <= dot+4; i++) {
			c := s[i];
			if(c < '0' || c > '9') break;
			scale = scale * 10;
			result = result * 10 + (c - '0') * 1024 / scale * scale / 1024;
		}
		# simpler fractional: just integer truncation
		frac := 0;
		fscale := 1;
		for(i = dot+1; i < len s && i-dot <= 4; i++) {
			c := s[i];
			if(c < '0' || c > '9') break;
			frac = frac * 10 + (c - '0');
			fscale *= 10;
		}
		result = (result / 1024) * 1024 + frac * 1024 / fscale;
	}
	if(neg) result = -result;
	return result;
}

# Parse YYYY-MM-DD → days since 2000-01-01
parsedate(s: string): int
{
	s = trimstr(s);
	if(len s < 10) return 0;
	y := intfrom(s, 0, 4);
	m := intfrom(s, 5, 7);
	d := intfrom(s, 8, 10);
	moff := array[13] of int;
	moff[0]=0; moff[1]=0; moff[2]=31; moff[3]=59; moff[4]=90;
	moff[5]=120; moff[6]=151; moff[7]=181; moff[8]=212;
	moff[9]=243; moff[10]=273; moff[11]=304; moff[12]=334;
	if(m < 1) m = 1;
	if(m > 12) m = 12;
	y -= 2000;
	leaps := y / 4;
	return y*365 + leaps + moff[m] + d - 1;
}

isdate(s: string): int
{
	s = trimstr(s);
	if(len s < 10) return 0;
	if(s[4] != '-' || s[7] != '-') return 0;
	for(i := 0; i < 4; i++)
		if(s[i] < '0' || s[i] > '9') return 0;
	return 1;
}

# Parse duration "7d", "2w", "1M" → days
parsedur(s: string): int
{
	s = trimstr(s);
	if(s == "") return 1;
	n := 0;
	i := 0;
	while(i < len s && s[i] >= '0' && s[i] <= '9') {
		n = n * 10 + (s[i] - '0');
		i++;
	}
	if(n == 0) n = 1;
	if(i < len s) {
		case s[i] {
		'w' or 'W' => n *= 7;
		'M'        => n *= 30;
		'y' or 'Y' => n *= 365;
		}
	}
	return n;
}

isduration(s: string): int
{
	s = trimstr(s);
	if(s == "") return 0;
	i := 0;
	while(i < len s && s[i] >= '0' && s[i] <= '9')
		i++;
	return i > 0 && i < len s && (s[i] == 'd' || s[i] == 'w' || s[i] == 'M' || s[i] == 'y' || s[i] == 'Y' || s[i] == 'W');
}

# Parse integer from s[a:b]
intfrom(s: string, a, b: int): int
{
	n := 0;
	for(i := a; i < b && i < len s; i++) {
		c := s[i];
		if(c < '0' || c > '9') break;
		n = n * 10 + (c - '0');
	}
	return n;
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── List/array conversion helpers ────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════

nodestoarray(l: list of ref FCNode, n: int): array of ref FCNode
{
	a := array[n] of ref FCNode;
	i := 0;
	for(; l != nil && i < n; l = tl l)
		a[i++] = hd l;
	return a;
}

edgestoarray(l: list of ref FCEdge, n: int): array of ref FCEdge
{
	a := array[n] of ref FCEdge;
	i := 0;
	for(; l != nil && i < n; l = tl l)
		a[i++] = hd l;
	return a;
}

taskstoarray(l: list of ref GTask, n: int): array of ref GTask
{
	a := array[n] of ref GTask;
	i := 0;
	for(; l != nil && i < n; l = tl l)
		a[i++] = hd l;
	return a;
}

findnode(na: array of ref FCNode, n: int, id: string): ref FCNode
{
	for(i := 0; i < n; i++)
		if(na[i].id == id) return na[i];
	return nil;
}

revnodes(l: list of ref FCNode): list of ref FCNode
{
	r: list of ref FCNode;
	for(; l != nil; l = tl l) r = hd l :: r;
	return r;
}

revedges(l: list of ref FCEdge): list of ref FCEdge
{
	r: list of ref FCEdge;
	for(; l != nil; l = tl l) r = hd l :: r;
	return r;
}

revslices(l: list of ref PieSlice): list of ref PieSlice
{
	r: list of ref PieSlice;
	for(; l != nil; l = tl l) r = hd l :: r;
	return r;
}

revseqparts(l: list of ref SeqPart): list of ref SeqPart
{
	r: list of ref SeqPart;
	for(; l != nil; l = tl l) r = hd l :: r;
	return r;
}

revseqmsgs(l: list of ref SeqMsg): list of ref SeqMsg
{
	r: list of ref SeqMsg;
	for(; l != nil; l = tl l) r = hd l :: r;
	return r;
}

revtasks(l: list of ref GTask): list of ref GTask
{
	r: list of ref GTask;
	for(; l != nil; l = tl l) r = hd l :: r;
	return r;
}

revxyseries(l: list of ref XYSeries): list of ref XYSeries
{
	r: list of ref XYSeries;
	for(; l != nil; l = tl l) r = hd l :: r;
	return r;
}

revclassnodes(l: list of ref ClassNode): list of ref ClassNode
{
	r: list of ref ClassNode;
	for(; l != nil; l = tl l) r = hd l :: r;
	return r;
}

revclassrels(l: list of ref ClassRel): list of ref ClassRel
{
	r: list of ref ClassRel;
	for(; l != nil; l = tl l) r = hd l :: r;
	return r;
}

reventities(l: list of ref EREntity): list of ref EREntity
{
	r: list of ref EREntity;
	for(; l != nil; l = tl l) r = hd l :: r;
	return r;
}

reverrels(l: list of ref ERRel): list of ref ERRel
{
	r: list of ref ERRel;
	for(; l != nil; l = tl l) r = hd l :: r;
	return r;
}

revtlevents(l: list of ref TLEvent): list of ref TLEvent
{
	r: list of ref TLEvent;
	for(; l != nil; l = tl l) r = hd l :: r;
	return r;
}

revjtasks(l: list of ref JTask): list of ref JTask
{
	r: list of ref JTask;
	for(; l != nil; l = tl l) r = hd l :: r;
	return r;
}

revreqnodes(l: list of ref ReqNode): list of ref ReqNode
{
	r: list of ref ReqNode;
	for(; l != nil; l = tl l) r = hd l :: r;
	return r;
}

revreqrels(l: list of ref ReqRel): list of ref ReqRel
{
	r: list of ref ReqRel;
	for(; l != nil; l = tl l) r = hd l :: r;
	return r;
}
