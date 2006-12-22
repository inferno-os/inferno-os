implement Gatherengine;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "sets.m";
	sets: Sets;
	Set, All, None, A, B: import sets;
include "../spree.m";
	spree: Spree;
	Attributes, Range, Object, Clique, Member: import spree;
include "../gather.m";

clique: ref Clique;

W, H: con 500;
INSET: con 20;
D: con 30;
BATLEN: con 100.0;
GOALSIZE: con 0.1;

MAXPLAYERS: con 32;
nmembers := 0;

Line: adt {
	p1, p2: Point;
	seg: fn(l: self Line, s1, s2: real): Line;
};

Dmember: adt {
	p:		ref Member;
	score:	int;
	bat:		ref Object;
};

Eusage: con "bad command usage";
colours := array[4] of {"blue", "orange", "yellow", "white"};
batpos: array of Line;
borderpos: array of Line;

members: array of Dmember;
arena: ref Object;
clienttype(): string
{
	return "bounce";
}

maxmembers(): int
{
	return 4;
}

readfile(nil: int, nil: big, nil: int): array of byte
{
	return nil;
}

init(srvmod: Spree, g: ref Clique, nil: list of string, nil: int): string
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	clique = g;
	spree = srvmod;

	sets = load Sets Sets->PATH;
	if (sets == nil) {
		sys->print("spit: cannot load %s: %r\n", Sets->PATH);
		return "bad module";
	}
	sets->init();

	r := Rect((0, 0), (W, H));
	walls := sides(r.inset(INSET));
	addlines(segs(walls, 0.0, 0.5 - GOALSIZE), nil);
	addlines(segs(walls, 0.5 + GOALSIZE, 1.0), nil);

	batpos = l2a(segs(sides(r.inset(INSET + 50)), 0.1, 0.9));
	borderpos = l2a(sides(r.inset(-1)));

	arena = clique.newobject(nil, All, "arena");
	arena.setattr("arenasize", string W + " " + string H, All);

	return nil;
}

propose(members: array of string): string
{
	if (len members < 2)
		return "need at least two members";
	if (len members > 4)
		return "too many members";
	return nil;
}

archive()
{
}		

start(pl: array of ref Member, archived: int)
{
	if (archived) {
	} else {
		members = array[len pl] of Dmember;
		for (i := 0; i < len pl; i++) {
			p := pl[i];
			bat := addline(batpos[i], nil);
			bat.setattr("pos", "10 " + string (10.0 + BATLEN), All);
			bat.setattr("owner", p.name, All);
			addline(borderpos[i], ("owner", p.name) :: nil);
			arena.setattr("member" + string i, p.name + " " + colours[i], All);
			members[i] = (p, 0, bat);
		}
		r := Rect((0, 0), (W, H)).inset(INSET + 1);
		goals := l2a(sides(r));
		for (i = len members; i < len batpos; i++) {
			addline(goals[i], nil);
			addline(borderpos[i], ("owner", pl[0].name) :: nil);
		}
	}
}

addline(lp: (Point, Point), attrs: list of (string, string)): ref Object
{
	(p1, p2) := lp;
	l := clique.newobject(nil, All, "line");
	l.setattr("coords", p2s(p1) + " " + p2s(p2), All);
	l.setattr("id", string l.id, All);
	for (; attrs != nil; attrs = tl attrs) {
		(attr, val) := hd attrs;
		l.setattr(attr, val, All);
	}
	return l;
}


p2s(p: Point): string
{
	return string p.x + " " + string p.y;
}

command(member: ref Member, cmd: string): string
{
	ord := order(member);
	sys->print("cmd: %s", cmd);
	{
		(n, toks) := sys->tokenize(cmd, " \n");
		assert(n > 0, "unknown command");
		case hd toks {
		"newball" =>
			# newball batid p.x p.y v.x v.y speed
			assert(n == 7, Eusage);
			bat := member.obj(int hd tl toks);
			assert(bat != nil, "no such bat");
			ball := clique.newobject(nil, All, "ball");
			ball.setattr("state", string bat.id +  " " + string ord +
				" " + concat(tl tl toks) + " " + string sys->millisec(), All);
		"lost" =>
			# lost ballid
			assert(n == 2, Eusage);
			o := member.obj(int hd tl toks);
			assert(o != nil, "bad object");
			assert(o.getattr("state") != nil, "can only lose balls");
			o.delete();
		"state" =>
			# state ballid lasthit owner p.x p.y v.x v.y s time
			assert(n == 10, Eusage);
			assert(ord >= 0, "you are not playing");
			o := member.obj(int hd tl toks);
			assert(o != nil, "object does not exist");
			o.setattr("state", concat(tl tl toks), All);
			members[ord].score++;
			arena.setattr("score" + string ord, string members[ord].score, All);
		"bat" =>
			# bat pos
			assert(n == 2, Eusage);
			s1 := real hd tl toks;
			members[ord].bat.setattr("pos", hd tl toks + " " + string (s1 + BATLEN), All);
		"time" =>
			# time millisec
			assert(n == 2, Eusage);
			tm := int hd tl toks;
			offset := sys->millisec() - tm;
			clique.action("time " + string offset + " " + string tm, nil, nil, None.add(member.id));
		* =>
			assert(0, "bad command");
		}
	} exception e {
	"parse:*" =>
		return e[6:];
	}
	return nil;
}

order(p: ref Member): int
{
	for (i := 0; i < len members; i++)
		if (members[i].p == p)
			return i;
	return -1;
}

assert(b: int, err: string)
{
	if (b == 0)
		raise "parse:" + err;
}

concat(v: list of string): string
{
	if (v == nil)
		return nil;
	s := hd v;
	for (v = tl v; v != nil; v = tl v)
		s += " " + hd v;
	return s;
}

Line.seg(l: self Line, s1, s2: real): Line
{
	(dx, dy) := (l.p2.x - l.p1.x, l.p2.y - l.p1.y);
	return (((l.p1.x + int (s1 * real dx)), l.p1.y + int (s1 * real dy)),
			((l.p1.x + int (s2 * real dx)), l.p1.y + int (s2 * real dy)));
}

sides(r: Rect): list of Line
{
	return ((r.min.x, r.min.y), (r.min.x, r.max.y)) ::
		((r.max.x, r.min.y), (r.max.x, r.max.y)) ::
		((r.min.x, r.min.y), (r.max.x, r.min.y)) ::
		((r.min.x, r.max.y), (r.max.x, r.max.y)) :: nil;
}

addlines(ll: list of Line, attrs: list of (string, string))
{
	for (; ll != nil; ll = tl ll)
		addline(hd ll, attrs);
}

segs(ll: list of Line, s1, s2: real): list of Line
{
	nll: list of Line;
	for (; ll != nil; ll = tl ll)
		nll = (hd ll).seg(s1, s2) :: nll;
	ll = nil;
	for (; nll != nil; nll = tl nll)
		ll = hd nll :: ll;
	return ll;
}

l2a(ll: list of Line): array of Line
{
	a := array[len ll] of Line;
	for (i := 0; ll != nil; ll = tl ll)
		a[i++] = hd ll;
	return a;
}
