#include "logfsos.h"
#include "logfs.h"
#include "local.h"

char *
logfstagname(uchar tag)
{
	switch(tag) {
	case LogfsTboot:
		return "boot";
	case LogfsTnone:
		return "free";
	case LogfsTlog:
		return "log";
	case LogfsTdata:
		return "data";
	}
	return "???";
}

