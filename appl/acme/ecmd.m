Editcmd: module {

	PATH: con "/dis/acme/ecmd.dis";

	init : fn(mods : ref Dat->Mods);

	cmdexec: fn(a0: ref Textm->Text, a1: ref Edit->Cmd): int;
	resetxec: fn();
	cmdaddress: fn(a0: ref Edit->Addr, a1: Edit->Address, a2: int): Edit->Address;
	edittext: fn(f: ref Filem->File, q: int, r: string, nr: int): string;

	alllooper: fn(w: ref Windowm->Window, lp: ref Dat->Looper);
	alltofile: fn(w: ref Windowm->Window, tp: ref Dat->Tofile);
	allmatchfile: fn(w: ref Windowm->Window, tp: ref Dat->Tofile);
	allfilecheck: fn(w: ref Windowm->Window, fp: ref Dat->Filecheck);

	readloader: fn(f: ref Filem->File, q0: int, r: string, nr: int): int;
};