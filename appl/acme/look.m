Look : module {
	PATH : con "/dis/acme/look.dis";

	init : fn(mods : ref Dat->Mods);

	isfilec: fn(r : int) : int;
	lookid : fn(n : int, b : int) : ref Windowm->Window;
	lookfile : fn(s : string, n : int) : ref Windowm->Window;
	dirname : fn(t : ref Textm->Text, r : string, n : int) : (string, int);
	cleanname : fn(s : string, n : int) : (string, int);
	new : fn(et, t, argt : ref Textm->Text, flag1, flag2 : int, arg : string, narg : int);
	expand : fn(t : ref Textm->Text, q0, q1 : int) : (int, Dat->Expand);
	search : fn(t : ref Textm->Text, r : string, n : int) : int;
	look3 : fn(t : ref Textm->Text, q0, q1, external : int);
	plumblook : fn(m : ref Plumbmsg->Msg);
	plumbshow : fn(m : ref Plumbmsg->Msg);
};
