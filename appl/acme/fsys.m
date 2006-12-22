Fsys : module {
	PATH : con "/dis/acme/fsys.dis";

	init : fn(mods : ref Dat->Mods);

	messagesize: int;

	QID : fn(w, f : int) : int;
	FILE : fn(q : Sys->Qid) : int;
	WIN : fn(q : Sys->Qid) : int;

	fsysinit : fn();
	fsyscfd : fn() : int;
	fsysmount: fn(dir : string, ndir : int, incl : array of string, nincl : int) : ref Dat->Mntdir;
	fsysdelid : fn(idm : ref Dat->Mntdir);
	fsysclose: fn();
	respond : fn(x : ref Xfidm->Xfid, t : Dat->Smsg0, err : string) : ref Xfidm->Xfid;
};