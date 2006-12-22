# only used by tetris currently. this interface will change.
Scoretable: module {
	PATH: con "/dis/lib/scoretable.dis";
	Score: adt {
		user: string;
		score: int;
		other: string;
	};
	init: fn(port: int, user, name: string, scorefile: string): (int, string);
	setscore: fn(score: int, other: string): int;
	scores: fn(): list of Score;
};
