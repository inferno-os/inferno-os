#include "logfsos.h"
#include "logfs.h"
#include "local.h"

long
logfsfindfreeblock(LogfsLowLevel *ll, AllocReason reason)
{
	long b;
	long total;
	b = (*ll->findfreeblock)(ll, &total);
	if(b < 0)
		return b;
	switch(reason) {
	case AllocReasonReplace:
		break;
	case AllocReasonTransfer:
		if(total <= Replacements)
			return -1;
		break;
	case AllocReasonLogExtend:
		if(total <= Replacements + Transfers)
			return -1;
		break;
	case AllocReasonDataExtend:
		if(total <= Replacements + Transfers + LogSlack)
			return -1;
		break;
	}
//print("allocated free block %ld\n", b);
	return b;
}
