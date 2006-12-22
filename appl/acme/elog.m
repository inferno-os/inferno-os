Editlog: module {

	PATH: con "/dis/acme/elog.dis";

	Elog: adt{
		typex: int;		# Delete, Insert, Filename
		q0: int;		# location of change (unused in f)
		nd: int;		# number of deleted characters
		nr: int;		# runes in string or file name
		r: ref Dat->Astring;
	};

	init : fn(mods : ref Dat->Mods);

	elogterm: fn(a0: ref Filem->File);
	elogclose: fn(a0: ref Filem->File);
	eloginsert: fn(a0: ref Filem->File, a1: int, a2: string, a3: int);
	elogdelete: fn(a0: ref Filem->File, a1: int, a2: int);
	elogreplace: fn(a0: ref Filem->File, a1: int, a2: int, a3: string, a4: int);
	elogapply: fn(a0: ref Filem->File);

};

	