Gamer: module
{
	PATH:	con "/dis/lib/gamer.dis";

	Game: adt {
		rf, wf: ref Sys->FD;
		opponent: string;
		player: int;

		In:	fn(g: self Game) : int;
		Out:	fn(g: self Game, i: int);
		Exit:	fn(g: self Game);
	};

	Join:	fn(game: string) : Game;
};
