Regx : module {
	PATH : con "/dis/acme/regx.dis";

	init : fn(mods : ref Dat->Mods);

	rxinit : fn();
	rxcompile: fn(r : string) : int;
	rxexecute: fn(t : ref Textm->Text, r: string, startp : int, eof : int) : (int, Dat->Rangeset);
	rxbexecute: fn(t : ref Textm->Text, startp : int) : (int, Dat->Rangeset);
	isaddrc : fn(r : int) : int;
	isregexc : fn(r : int) : int;
	address : fn(md: ref Dat->Mntdir, t : ref Textm->Text, lim : Dat->Range, ar : Dat->Range, a0 : ref Textm->Text, a1 : string, q0 : int, q1 : int, eval : int) : (int, int, Dat->Range);
};