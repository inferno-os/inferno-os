#include "lib9.h"
#include "logfs.h"
#include "local.h"

char *
logfsservertestcmd(LogfsServer *s, int argc, char **argv)
{
	if(argc == 1 && strcmp(argv[0], "dontfettledatablock") == 0)
		s->testflags |= LogfsTestDontFettleDataBlock;
	else
		return Ebadarg;
	return nil;
}
