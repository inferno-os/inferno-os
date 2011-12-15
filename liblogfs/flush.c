#include "logfsos.h"
#include "logfs.h"
#include "fcall.h"
#include "local.h"

char *
logfsserverflush(LogfsServer *server)
{
	char *errmsg = logfslogsegmentflush(server, 1);
	if(errmsg == nil)
		errmsg = logfslogsegmentflush(server, 0);
	if(errmsg == nil)
		errmsg = (*server->ll->sync)(server->ll);
	if(server->trace > 1)
		print("logfsserverflush\n");
	return errmsg;
}
