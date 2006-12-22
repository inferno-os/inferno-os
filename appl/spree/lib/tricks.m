Tricks: module {
	PATH:		con "/dis/spree/lib/tricks.dis";
	init:			fn(mod: Spree, g: ref Clique, cardlibmod: Cardlib);

	Trick: adt {
		trumps:	int;
		startcard:	Cardlib->Card;
		highcard:	Cardlib->Card;
		winner:	int;
		pile:		ref Object;
		hands:	array of ref Object;
		rank:		array of int;

		new:		fn(pile: ref Object, trumps: int,
					hands: array of ref Object, rank: array of int): ref Trick;
		play:		fn(t: self ref Trick, ord, idx: int): string;
		archive:	fn(t: self ref Trick, archiveobj: ref Object, name: string);
		unarchive:	fn(archiveobj: ref Object, name: string): ref Trick;
	};

};
