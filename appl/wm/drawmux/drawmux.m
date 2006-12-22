Drawmux: module {
	PATH: con "/dis/lib/drawmux.dis";

	init: fn(): (string, ref Draw->Display);
	newviewer: fn(fd: ref Sys->FD);
};
