Regex: module {

	PATH:	con "/dis/lib/regex.dis";

# normally imported identifiers

	Re: type ref Arena;
	compile:	fn(nil:string,nil:int): (Re, string);
	execute:	fn(nil:Re, nil:string): array of (int, int);
	executese:	fn(nil:Re, nil:string, se: (int, int), bol: int, eol: int): array of (int, int);

# internal identifiers, not normally imported

	ALT, CAT, DOT, SET, HAT, DOL, NUL, PCLO, CLO, OPT, LPN, RPN : con (1<<16)+iota;

	refRex : type int;	# used instead of ref Rex to avoid circularity

	Set: adt {				# character class
		neg: int;			# 0 or 1
		ascii : array of int;		# ascii members, bit array
		unicode : list of (int,int);	# non-ascii char ranges
	};

	Rex: adt {		# node in parse of regex, or state of fsm
		kind : int;	# kind of node: char or ALT, CAT, etc
		left : refRex;	# left descendant
		right : refRex;	# right descendant, or next state
		set : ref Set;	# character class
		pno : int;
	};

	Arena: adt {		# free store from which nodes are allocated
		rex : array of Rex;		
		ptr : refRex;	# next available space
		start : refRex;	# root of parse, or start of fsm
		pno : int;
	};
};
