Utils : module {
	PATH : con "/dis/acme/util.dis";

	stderr : ref Sys->FD;

	Arg : adt {
		arg0 : string;
		av : list of string;
		p : string;
	};

	PNPROC, PNGROUP : con iota;

	init : fn(mods : ref Dat->Mods);
	arginit : fn(av : list of string) : ref Arg;
	argopt : fn(p : ref Arg) : int;
	argf : fn(p : ref Arg) : string;
	min : fn(a : int, b : int) : int;
	max : fn(a : int, b : int) : int;
	abs : fn(x : int) : int;
	error : fn(s : string);
	warning : fn(md : ref Dat->Mntdir, t : string);
	debuginit : fn();
	debug : fn(s : string);
	memdebug : fn(s : string);
	postnote : fn(t : int, this : int, pid : int, note : string) : int;
	exec: fn(c: string, args : list of string);
	getuser : fn() : string;
	gethome : fn(user : string) : string;
	access : fn(s : string) : int;
	isalnum : fn(c : int) : int;
	savemouse : fn(w : ref Windowm->Window);
	restoremouse : fn(w : ref Windowm->Window);
	clearmouse : fn();
	rgetc : fn(r : string, n : int) : int;
	tgetc : fn(t : ref Textm->Text, n : int) : int;
	reverse : fn(l : list of string) : list of string;
	stralloc : fn(n : int) : ref Dat->Astring;
	strfree :fn(s : ref Dat->Astring);
	strchr : fn(s : string, c : int) : int;
	strrchr: fn(s : string, c : int) : int;
	strncmp : fn(s, t : string, n : int) : int;
	getenv : fn(s : string) : string;
	setenv : fn(s, t : string);
	stob : fn(s : string, n : int) : array of byte;
	btos : fn(b : array of byte, s : ref Dat->Astring);
	findbl : fn(s : string, n : int) : (string, int);
	skipbl : fn(s : string, n : int) : (string, int);
	newwindow : fn(t : ref Textm->Text) : ref Windowm->Window;
	getexc: fn(): string;
	readexc : fn() : (int, string, string);
};