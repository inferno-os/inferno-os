FBrowse : module
{
	PATH: con	"/dis/grid/lib/fbrowse.dis";
	NOTHING: con	0;
	RUN: con		1;
	OPEN: con	2;
	WRITE: con	3;
	ERROR: con	-1;

	init : fn (ctxt : ref Draw->Context, title, root, currdir: string): string;
	readpath : fn (dir: Browser->File): (array of ref sys->Dir, int);
};

