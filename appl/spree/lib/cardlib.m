Cardlib: module {
	PATH:		con "/dis/spree/lib/cardlib.dis";

	Layout: adt {
		lay:			ref Spree->Object;		# the actual layout object
	};

	Stackspec: adt {
		style:	string;
		maxcards:	int;
		conceal:	int;
		title:		string;
	};

	Card: adt {
		suit:		int;
		number:	int;
		face:		int;
	};

	# a member currently playing
	Cmember: adt {
		ord:		int;
		id:		int;
		p:		ref Spree->Member;
		obj:		ref Spree->Object;
		layout:	ref Layout;
		sel:		ref Selection;

		join:		fn(p: ref Spree->Member, ord: int): ref Cmember;
		index:	fn(ord: int): ref Cmember;
		find:		fn(p: ref Spree->Member): ref Cmember;
		findid:	fn(id: int): ref Cmember;
		leave:	fn(cp: self ref Cmember);
		next:		fn(cp: self ref Cmember, fwd: int): ref Cmember;
		prev:		fn(cp: self ref Cmember, fwd: int): ref Cmember;
	};

	Selection: adt {
		stack:	ref Spree->Object;
		ownerid:	int;
		isrange:	int;
		r:		Range;
		idxl:		list of int;

		set:		fn(sel: self ref Selection, stack: ref Spree->Object);
		setexcl:	fn(sel: self ref Selection, stack: ref Spree->Object): int;
		setrange:	fn(sel: self ref Selection, r: Range);
		addindex:	fn(sel: self ref Selection, i: int);
		delindex:	fn(sel: self ref Selection, i: int);
		isempty:	fn(sel: self ref Selection): int;
		isset:		fn(sel: self ref Selection, index: int): int;
		transfer:	fn(sel: self ref Selection, dst: ref Spree->Object, index: int);
		owner:	fn(sel: self ref Selection): ref Cmember;
	};

	selection:	fn(stack: ref Spree->Object): ref Selection;

	# pack and facing directions (clockwise by face direction)
	dTOP, dLEFT, dBOTTOM, dRIGHT: con iota;
	dMASK: con 7;
	dSHIFT: con 0;
	
	# anchor positions
	aSHIFT: con 4;
	aMASK: con 16rf0;
	aCENTRE, aUPPERCENTRE, aUPPERLEFT, aCENTRELEFT,
		aLOWERLEFT, aLOWERCENTRE, aLOWERRIGHT,
		aCENTRERIGHT, aUPPERRIGHT: con iota << aSHIFT;
	
	# orientations
	oMASK: con 16rf00;
	oSHIFT: con 8;
	oRIGHT, oUP, oLEFT, oDOWN: con iota << oSHIFT;

	EXPAND: con 16r1000;

	FILLSHIFT: con 13;
	FILLX, FILLY: con 1 << (FILLSHIFT + iota);
	FILLMASK: con FILLX|FILLY;

	CLUBS, DIAMONDS, HEARTS, SPADES: con iota;

	init:			fn(spree: Spree, clique: ref Spree->Clique);

	addlayframe:	fn(name: string, parent: string, layout: ref Layout, packopts: int, facing: int);
	addlayobj:	fn(name: string, parent: string, layout: ref Layout, packopts: int, obj: ref Spree->Object);
	dellay:		fn(name: string, layout: ref Layout);

	newstack:		fn(parent: ref Spree->Object, p: ref Spree->Member, spec: Stackspec): ref Spree->Object;

	archive:		fn(): ref Spree->Object;
	unarchive:	fn(): ref Spree->Object;
	setarchivename: fn(o: ref Spree->Object, name: string);
	getarchiveobj:	fn(name: string): ref Spree->Object;
	archivearray:	fn(a: array of ref Spree->Object, name: string);
	getarchivearray: fn(name: string): array of ref Spree->Object;

	newlayout:	fn(parent: ref Spree->Object, vis: Sets->Set): ref Layout;
	makecards:	fn(stack: ref Spree->Object, r: Range, rear: string);
	maketable:	fn(parent: string);
	deal:			fn(stack: ref Spree->Object, n: int, stacks: array of ref Spree->Object, first: int);
	shuffle:		fn(stack: ref Spree->Object);
	sort:			fn(stack: ref Spree->Object, rank, suitrank: array of int);

	getcard:		fn(card: ref Spree->Object): Card;
	getcards:		fn(stack: ref Spree->Object): array of Card;
	discard:		fn(stk, pile: ref Spree->Object, facedown: int);
	setface:		fn(card: ref Spree->Object, face: int);

	flip:			fn(stack: ref Spree->Object);

	nmembers:		fn(): int;
};
