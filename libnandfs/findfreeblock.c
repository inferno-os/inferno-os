#include "lib9.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

long
nandfsfindfreeblock(Nandfs *nandfs, long *freeblocksp)
{
	long bestnewblock;
	long bestnerase;
	long i;

	if (freeblocksp)
		*freeblocksp = 0;
	for (i = 0, bestnewblock = -1, bestnerase = 0x7fffffff; i < nandfs->ll.blocks; i++) {
		long nerase;
		if (nandfsgettag(nandfs, i) == LogfsTnone) {
			if (freeblocksp) {
				(*freeblocksp)++;
			}
			if ((nerase = nandfsgetnerase(nandfs, i)) < bestnerase) {
				bestnewblock = i;
				bestnerase = nerase;
			}
		}
	}
	return bestnewblock;
}
