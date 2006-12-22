Edit: module {
	#pragma	varargck	argpos	editerror	1

	PATH: con "/dis/acme/edit.dis";

	String: adt{
		n: int;
		r: string;
	};

	Addr: adt{
		typex: int;		# # (char addr), l (line addr), / ? . $ + - , ;
		num: int;
		next: cyclic ref Addr;		# or right side of , and ; 
		re: ref String;
		left: cyclic ref Addr;		# left side of , and ; 
	};

	Address: adt{
		r: Dat->Range;
		f: ref Filem->File;
	};

	Cmd: adt{
		addr: ref Addr;			# address (range of text)
		re: ref String;			# regular expression for e.g. 'x'
		next: cyclic ref Cmd;		# pointer to next element in {}
		num: int;
		flag: int;				# whatever
		cmdc: int;				# command character; 'x' etc.
		cmd: cyclic ref Cmd;			# target of x, g, {, etc.
		text: ref String;			# text of a, c, i; rhs of s
		mtaddr: ref Addr;		# address for m, t
	};

	Cmdt: adt{
		cmdc: int;			# command character
		text: int;			# takes a textual argument?
		regexp: int;		# takes a regular expression?
		addr: int;		# takes an address (m or t)?
		defcmd: int;		# default command; 0==>none
		defaddr: int;		# default address
		count: int;		# takes a count e.g. s2///
		token: string;		# takes text terminated by one of these
		fnc: int;			# function to call with parse tree
	};

	cmdtab: array of Cmdt;

	INCR: con 25;	# delta when growing list

	List: adt{
		nalloc: int;
		nused: int;
		pick{
			C => cmdptr: array of ref Cmd;
			S => stringptr: array of ref String;
			A => addrptr: array of ref Addr;
		}
	};

	aNo, aDot, aAll: con iota;	# default addresses

	ALLLOOPER, ALLTOFILE, ALLMATCHFILE, ALLFILECHECK, ALLELOGTERM, ALLEDITINIT, ALLUPDATE: con iota;

	C_nl, C_a, C_b, C_c, C_d, C_B, C_D, C_e, C_f, C_g, C_i, C_k, C_m, C_n, C_p, C_s, C_u, C_w, C_x, C_X, C_pipe, C_eq: con iota;

	editing: int;
	curtext: ref Textm->Text;

	init : fn(mods : ref Dat->Mods);

	allocstring: fn(a0: int): ref String;
	freestring: fn(a0: ref String);
	getregexp: fn(a0: int): ref String;
	newaddr: fn(): ref Addr;
	editcmd: fn(t: ref Textm->Text, r: string, n: int);
	editerror: fn(a0: string);
	cmdlookup: fn(a0: int): int;
	Straddc: fn(a0: ref String, a1: int);

	allelogterm: fn(w: ref Windowm->Window);
	alleditinit: fn(w: ref Windowm->Window);
	allupdate: fn(w: ref Windowm->Window);
};
