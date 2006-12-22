#include "lib9.h"
#include "logfs.h"
#include "local.h"

char logfsebadfid[] = "fid not in use";
char logfsefidnotopen[] = "fid is not open for I/O";
char logfsefidopen[] = "fid is open for I/O";
char logfsenotadir[]  = "fid not a dir";
char logfsefidinuse[] = "fid in use";
char logfseopen[] = "fid not open";
char logfseaccess[] = "fid open in wrong mode";
char logfselogfull[] = "log filled";
char logfselogmsgtoobig[] = "message too big for log";
char logfseinternal[] = "internal error";
char logfsenotempty[] = "directory not empty";
char logfsefullreplacing[] = "out of space trying to replace block";
char logfseunknownpath[] = "unknown path";
