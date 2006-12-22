implement Engine;

include "sys.m";
	sys: Sys;
include "draw.m";
include "../spree.m";
	spree: Spree;
	Attributes, Range, Object, Clique, Member: import spree;

clique: ref Clique;

init(g: ref Clique, srvmod: Spree): string
{
	sys = load Sys Sys->PATH;
	clique = g;
	spree = srvmod;
	return nil;
}

join(nil: ref Member): string
{
	return nil;
}

leave(nil: ref Member)
{
}

number := 0;
currmember: ref Member;

obj(ext: int): ref Object
{
	o := currmember.obj(ext);
	if (o == nil)
		sys->raise("parse:bad object");
	return o;
}

Eusage: con "bad command usage";

assert(b: int, err: string)
{
	if (b == 0)
		sys->raise("parse:" + err);
}

command(member: ref Member, cmd: string): string
{
	e := ref Sys->Exception;
	if (sys->rescue("parse:*", e) == Sys->EXCEPTION) {
		sys->rescued(Sys->ONCE, nil);
		currmember = nil;
		return e.name[6:];
	}
	currmember = member;
	(nlines, lines) := sys->tokenize(cmd, "\n");
	assert(nlines > 0, "unknown command");
	(n, toks) := sys->tokenize(hd lines, " ");
	assert(n > 0, "unknown command");
	case hd toks {
	"new" =>			# new parent visibility\nvisibility attr val\nvisibility attr val...
		assert(n == 3, Eusage);
		setattrs(clique.newobject(obj(int hd tl toks), int hd tl tl toks), tl lines);
	"deck" =>
		stack := clique.newobject(nil, ~0);
		stack.setattr("type", "stack", ~0);
		for (i := 0; i < 6; i++) {
			o := clique.newobject(stack, ~0);
			o.setattr("face", "down", ~0);
			o.setattr("number", string number++, 0);
		}
	"flip" =>
		# flip objid start [end]
		assert(n == 2 || n == 3 || n == 4, Eusage);
		o := obj(int hd tl toks);
		if (n > 2) {
			start := int hd tl tl toks;
			end := start + 1;
			if (n == 4)
				end = int hd tl tl tl toks;
			assert(start >= 0 && start < len o.children &&
					end >= start && end >= 0 && end <= len o.children, "index out of range");
			for (; start < end; start++)
				flip(o.children[start]);
		} else
			flip(o);
		
	"set" =>			# set objid attr val
		assert(n == 4, Eusage);
		obj(int hd tl toks).setattr(hd tl tl toks, hd tl tl tl toks, ~0);
	"vis" =>			# vis objid flags
		assert(n == 3, Eusage);
		obj(int hd tl toks).setvisibility(int hd tl tl toks);
	"attrvis" =>		# attrvis objid attr flags
		assert(n == 4, Eusage);
		o := obj(int hd tl toks);
		name := hd tl tl toks;
		attr := o.attrs.get(name);
		assert(attr != nil, "attribute not found");
		o.setattrvisibility(name, int hd tl tl tl toks);
	"show" =>			# show [memberid]
		p: ref Member = nil;
		if (n == 2) {
			memberid := int hd tl toks;
			p = clique.member(memberid);
			assert(p != nil, "bad memberid");
		}
		clique.show(p);
	"del" or "delete" =>			# del obj
		assert(n == 2, Eusage);
		obj(int hd tl toks).delete();
	"tx" =>					# tx src from to dest [index]
		assert(n == 5 || n == 6, Eusage);
		src, dest: ref Object;
		r: Range;
		(src, toks) = (obj(int hd tl toks), tl tl toks);
		(r.start, toks) = (int hd toks, tl toks);
		(r.end, toks) = (int hd toks, tl toks);
		(dest, toks) = (obj(int hd toks), tl toks);
		index := len dest.children;
		if (n == 6)
			index = int hd toks;
		assert(r.start >= 0 && r.start < len src.children &&
				r.end >= 0 && r.end <= len src.children && r.end >= r.start,
				"bad range");
		src.transfer(r, dest, index);
	* =>
		assert(0, "bad command");
	}
	currmember = nil;
	return nil;
}


flip(o: ref Object)
{
	face := o.getattr("face");
	if (face == "down") {
		face = "up";
		o.setattrvisibility("number", ~0);
	} else {
		face = "down";
		o.setattrvisibility("number", 0);
	}
	o.setattr("face", face, ~0);
}

setattrs(o: ref Object, lines: list of string): string
{
	for (; lines != nil; lines = tl lines) {
		# attr val [visibility]
		(n, toks) := sys->tokenize(hd lines, " ");
		if (n != 2 && n != 3)
			return "bad attribute line";
		vis := 0;
		if (n == 3)
			vis = int hd tl tl toks;
		o.setattr(hd toks, hd tl toks, vis);
	}
	return nil;
}

