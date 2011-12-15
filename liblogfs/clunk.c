#include "logfsos.h"
#include "logfs.h"
#include "fcall.h"
#include "local.h"

char *
logfsserverclunk(LogfsServer *server, u32int fid)
{
	Fid *f;
	if(server->trace > 1)
		print("logfsserverclunk(%ud)\n", fid);
	f = logfsfidmapfindentry(server->fidmap, fid);
	if(f == nil)
		return logfsebadfid;
	if(f->openmode >= 0 && (f->openmode & ORCLOSE) != 0)
		return logfsserverremove(server, fid);
	logfsfidmapclunk(server->fidmap, fid);
	return nil;
}
