implement Gatherengine;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sets.m";
	All, None: import Sets;
include "../spree.m";
	spree: Spree;
	Attributes, Range, Object, Clique, Member: import spree;
include "objstore.m";
	objstore: Objstore;
include "../gather.m";

clique: ref Clique;

Black, White, Nocolour: con iota;		# first two must be 0 and 1.
N: con 8;

boardobj: ref Object;
board:	array of array of int;
pieces:	array of int;
turn		:= Nocolour;
members	:= array[2] of ref Member;			# member ids of those playing

Point: adt {
	x, y: int;
	add: fn(p: self Point, p1: Point): Point;
	inboard: fn(p: self Point): int;
};

clienttype(): string
{
	return "othello";
}

init(srvmod: Spree, g: ref Clique, nil: list of string, nil: int): string
{
	sys = load Sys Sys->PATH;
	clique = g;
	spree = srvmod;

	objstore = load Objstore Objstore->PATH;
	if (objstore == nil) {
		sys->print("othello: cannot load %s: %r", Objstore->PATH);
		return "bad module";
	}
	objstore->init(srvmod, g);

	return nil;
}

maxmembers(): int
{
	return 2;
}

readfile(nil: int, nil: big, nil: int): array of byte
{
	return nil;
}

propose(members: array of string): string
{
	if (len members != 2)
		return "need exactly two members";
	return nil;
}

archive()
{
	objstore->setname(boardobj, "board");
}		

start(pl: array of ref Member, archived: int)
{
	members = pl;
	board = array[N] of {* => array[N] of {* => Nocolour}};
	pieces = array[2] of {* => 0};
	if (archived) {
		objstore->unarchive();
		boardobj = objstore->get("board");
		for (i := 0; i < N; i++) {
			for (j := 0; j < N; j++) {
				a := boardobj.getattr(pt2attr((j, i)));
				if (a != nil) {
					piece := int a;
					board[j][i] = piece;
					if (piece != Nocolour)
						pieces[piece]++;
				}
			}
		}
		turn = int boardobj.getattr("turn");
	} else {
		boardobj = clique.newobject(nil, All, nil);
		boardobj.setattr("members", string members[Black].name + " " + string members[White].name, All);
		for (ps := (Black, (3, 3)) :: (Black, (4, 4)) :: (White, (3, 4)) :: (White, Point(4, 3)) :: nil;
				ps != nil;
				ps = tl ps) {
			(colour, p) := hd ps;
			setpiece(colour, p);
		}
		turn = Black;
		boardobj.setattr("turn", string Black, All);
	}
}

cliqueover()
{
	turn = Nocolour;
	boardobj.setattr("winner", string winner(), All);
	boardobj.setattr("turn", string turn, All);
}

command(member: ref Member, cmd: string): string
{
	{
		(n, toks) := sys->tokenize(cmd, " \n");
		assert(n > 0, "unknown command");
	
		case hd toks {
		"move" =>
			assert(n == 3, "bad command usage");
			assert(turn != Nocolour, "clique has finished");
			assert(member == members[White] || member == members[Black], "you are not playing");
			assert(member == members[turn], "it is not your turn");
			p := Point(int hd tl toks, int hd tl tl toks);
			assert(p.x >= 0 && p.x < N && p.y >= 0 && p.y < N, "invalid move position");
			assert(board[p.x][p.y] == Nocolour, "position is already occupied");
			assert(newmove(turn, p, 1), "cannot move there");
	
			turn = reverse(turn);
			if (!canplay()) {
				turn = reverse(turn);
				if (!canplay())
					cliqueover();
			}
			boardobj.setattr("turn", string turn, All);
			return nil;
		}
		sys->print("othello: unknown client command '%s'\n", hd toks);
		return "who knows";
	} exception e {
	"parse:*" =>
		return e[6:];
	}
}

Directions := array[] of {Point(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)};

setpiece(colour: int, p: Point)
{
	v := board[p.x][p.y];
	if (v != Nocolour)
		pieces[v]--;
	board[p.x][p.y] = colour;
	pieces[colour]++;
	boardobj.setattr(pt2attr(p), string colour, All);
}

pt2attr(pt: Point): string
{
	s := "  ";
	s[0] = pt.x + 'a';
	s[1] = pt.y + 'a';
	return  s;
}

# member colour has tried to place a piece at mp.
# return -1 if it's an illegal move, 0 otherwise.
# (in which case appropriate updates are sent out all round).
# if update is 0, just check for the move's validity
# (no change to the board, no updates sent)
newmove(colour: int, mp: Point, update: int): int
{
	totchanged := 0;
	for (i := 0; i < len Directions; i++) {
		d := Directions[i];
		n := 0;
		for (p := mp.add(d); p.inboard(); p = p.add(d)) {
			n++;
			if (board[p.x][p.y] == colour || board[p.x][p.y] == Nocolour)
				break;
		}
		if (p.inboard() && board[p.x][p.y] == colour && n > 1) {
			if (!update)
				return 1;
			totchanged += n - 1;
			for (p = mp.add(d); --n > 0; p = p.add(d))
				setpiece(reverse(board[p.x][p.y]), p);
		}
	}
	if (totchanged > 0) {
		setpiece(colour, mp);
		return 1;
	}
	return 0;
}

# who has most pieces?
winner(): int
{
	if (pieces[White] > pieces[Black])
		return White;
	else if (pieces[Black] > pieces[White])
		return Black;
	return Nocolour;
}

# is there any possible legal move?
canplay(): int
{
	for (y := 0; y < N; y++)
		for (x := 0; x < N; x++)
			if (board[x][y] == Nocolour && newmove(turn, (x, y), 0))
				return 1;
	return 0;
}

reverse(colour: int): int
{
	if (colour == Nocolour)
		return Nocolour;
	return !colour;
}

Point.add(p: self Point, p1: Point): Point
{
	return (p.x + p1.x, p.y + p1.y);
}

Point.inboard(p: self Point): int
{
	return p.x >= 0 && p.x < N && p.y >= 0 && p.y < N;
}

assert(b: int, err: string)
{
	if (b == 0)
		raise "parse:" + err;
}
