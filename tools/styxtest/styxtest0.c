#include <lib9.h>
#include "styxserver.h"

int nq;
Styxserver *server;

void
myinit(Styxserver *s)
{
	styxaddfile(s, Qroot, 1, "fred", 0664, "inferno");
	styxaddfile(s, Qroot, 2, "joe", 0664, "inferno");
	styxadddir(s, Qroot, 3, "adir", 0775, "inferno");
	styxaddfile(s, 3, 4, "bill", 0664, "inferno");
	styxadddir(s, Qroot, 5, "new", 0775, "inferno");
	styxadddir(s, 5, 6, "cdir", 0775, "inferno");
	styxaddfile(s, 6, 7, "cfile", 0664, "inferno");
	nq = 8;
}

char *
mycreate(Qid *qid, char *name, int perm, int mode)
{
	int isdir;
	Styxfile *f;

	USED(mode);
	isdir = perm&DMDIR;
	if(isdir)
		f = styxadddir(server, qid->path, nq++, name , perm, "inferno");
	else
		f = styxaddfile(server, qid->path, nq++, name, perm, "inferno");
	if(f == nil)
		return Eexist;
	*qid = f->d.qid;
	return nil;
}

char *
myremove(Qid qid)
{
	Styxfile *f;

	f = styxfindfile(server, qid.path);
	if(f != nil && (f->d.qid.type&QTDIR) && f->child != nil)
		return "directory not empty";

	if(styxrmfile(server, qid.path) < 0)
		return Enonexist;	
	return nil;
}

char *
myread(Qid qid, char *d, ulong *n, vlong offset)
{
	if(qid.path != 1){
		*n = 0;
		return nil;
	}
	*n = styxreadstr(offset, d, *n, "abcdefghijklmn");
	return nil;
}

Styxops ops = {
	nil,			/* newclient */
	nil,			/* freeclient */

	nil,			/* attach */
	nil,			/* walk */
	nil,			/* open */
	mycreate,		/* create */
	myread,		/* read */
	nil,			/* write */
	nil,			/* close */
	myremove,	/* remove */
	nil,			/* stat */
	nil,			/* wstat */
};

main(int argc, char **argv)
{
	Styxserver s;

	USED(argc);
	USED(argv);
	server = &s;
	styxdebug();
	styxinit(&s, &ops, "6701", 0555, 0);
	myinit(&s);
	for(;;){
		styxwait(&s);
		styxprocess(&s);
	}
	return 0;
}

