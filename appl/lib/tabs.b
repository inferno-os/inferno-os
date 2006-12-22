implement Tabs;

# pseudo-widget for folder tab selections

#
# Copyright © 1996-1999 Lucent Technologies Inc.  All rights reserved.
# Revisions Copyright © 2000-2002 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "tk.m";
	tk: Tk;

include "string.m";
	str: String;		# could load on demand

include "tabs.m";

TABSXdelta : con 2;
TABSXslant : con 5;
TABSXoff : con 5;
TABSYheight : con 35;
TABSYtop : con 10;
TABSBord : con 3;

init()
{
	sys = load Sys Sys->PATH;
	tk = load Tk Tk->PATH;
	str = load String String->PATH;
}

mktabs(t: ref Tk->Toplevel, dot: string, tabs: array of (string, string), dflt: int): chan of string
{
	lab, widg: string;
	cmd(t, "canvas "+dot+" -height "+string TABSYheight);
	cmd(t, "pack propagate "+dot+" 0");
	c := chan of string;
	tk->namechan(t, c, dot[1:]);
	xpos := 2*TABSXdelta;
	top := 10;
	ypos := TABSYheight - 3;
	back := cmd(t, dot+" cget -background");
	dark := "#999999";
	light := "#ffffff";
	w := 20;
	h := 30;
	last := "";
	for(i := 0; i < len tabs; i++){
		(lab, widg) = tabs[i];
		tag := "tag" + string i;
		sel := "sel" + string i;
		xs := xpos;
		xpos += TABSXslant + TABSXoff;
		v := cmd(t, dot+" create text "+string xpos+" "+string ypos+" -text "+tk->quote(lab)+" -anchor sw -tags "+tag);
		bbox := tk->cmd(t, dot+" bbox "+tag);
		if(bbox[0] == '!')
			break;
		(r, nil) := parserect(bbox);
		r.max.x += TABSXoff;
		x1 := " "+string xs;
		x2 := " "+string(xs + TABSXslant);
		x3 := " "+string r.max.x;
		x4 := " "+string(r.max.x + TABSXslant);
		y1 := " "+string(TABSYheight - 2);
		y2 := " "+string TABSYtop;
		cmd(t, dot+" create polygon " + x1+y1 + x2+y2 + x3+y2 + x4+y1 +
			" -fill "+back+" -tags "+tag);
		cmd(t, dot+" create line " + x3+y2 + x4+y1 +
			" -fill "+dark+" -width 3 -tags "+tag);
		cmd(t, dot+" create line " + x1+y1 + x2+y2 + x3+y2 +
			" -fill "+light+" -width 3 -tags "+tag);

		x1 = " "+string(xs+2);
		x4 = " "+string(r.max.x + TABSXslant - 2);
		y1 = " "+string(TABSYheight);
		cmd(t, dot+" create line " + x1+y1 + x4+y1 +
			" -fill "+back+" -width 5 -tags "+sel);

		cmd(t, dot+" raise "+v);
		cmd(t, dot+" bind "+tag+" <ButtonRelease-1> 'send "+
			dot[1:]+" "+string i);

		cmd(t, dot+" lower "+tag+" "+last);
		last = tag;

		xpos = r.max.x;
		ww := int cmd(t, widg+" cget -width");
		wh := int cmd(t, widg+" cget -height");
		if(wh > h)
			h = wh;
		if(ww > w)
			w = ww;
	}
	xpos += 4*TABSXslant;
	if(w < xpos)
		w = xpos;

	for(i = 0; i < len tabs; i++){
		(nil, widg) = tabs[i];
		cmd(t, "pack propagate "+widg+" 0");
		cmd(t, widg+" configure -width "+string w+" -height "+string h);
	}

	w += 2*TABSBord;
	h += 2*TABSBord + TABSYheight;

	cmd(t, dot+" create line 0 "+string TABSYheight+
		" "+string w+" "+string TABSYheight+" -width 3 -fill "+light);
	cmd(t, dot+" create line 1 "+string TABSYheight+
		" 1 "+string(h-1)+" -width 3 -fill "+light);
	cmd(t, dot+" create line  0 "+string(h-1)+
		" "+string w+" "+string(h-1)+" -width 3 -fill "+dark);
	cmd(t, dot+" create line "+string(w-1)+" "+string TABSYheight+
		" "+string(w-1)+" "+string(h-1)+" -width 3 -fill "+dark);

	cmd(t, dot+" configure -width "+string w+" -height "+string h);
	cmd(t, dot+" configure -scrollregion {0 0 "+string w+" "+string h+"}");
	tabsctl(t, dot, tabs, -1, string dflt);
	return c;
}

tabsctl(t: ref Tk->Toplevel,
	dot: string,
	tabs: array of (string, string),
	id: int,
	s: string): int
{
	lab, widg: string;

	nid := int s;
	if(id == nid)
		return id;
	if(id >= 0){
		(lab, widg) = tabs[id];
		tag := "tag" + string id;
		cmd(t, dot+" lower sel" + string id);
		pos := cmd(t, dot+" coords " + tag);
		if(len pos >= 1 && pos[0] != '!'){
			(p, nil) := parsept(pos);
			cmd(t, dot+" coords "+tag+" "+string(p.x+1)+
				" "+string(p.y+1));
		}
		if(id > 0)
			cmd(t, dot+" lower "+ tag + " tag"+string (id - 1));
		cmd(t, dot+" delete win" + string id);
	}
	id = nid;
	(lab, widg) = tabs[id];
	pos := tk->cmd(t, dot+" coords tag" + string id);
	if(len pos >= 1 && pos[0] != '!'){
		(p, nli) := parsept(pos);
		cmd(t, dot+" coords tag"+string id+" "+string(p.x-1)+" "+string(p.y-1));
	}
	cmd(t, dot+" raise tag"+string id);
	cmd(t, dot+" raise sel"+string id);
	cmd(t, dot+" create window "+string TABSBord+" "+
		string(TABSYheight+TABSBord)+" -window "+widg+" -anchor nw -tags win"+string id);
	cmd(t, "update");
	return id;
}

parsept(s: string): (Draw->Point, string)
{
	p: Draw->Point;

	(p.x, s) = str->toint(s, 10);
	(p.y, s) = str->toint(s, 10);
	return (p, s);
}

parserect(s: string): (Draw->Rect, string)
{
	r: Draw->Rect;

	(r.min, s) = parsept(s);
	(r.max, s) = parsept(s);
	return (r, s);
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "%s: tk error %s on [%s]\n", PATH, e, s);
	return e;
}
