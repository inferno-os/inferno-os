#include "lib9.h"
#include "logfs.h"
#include "local.h"
#include "mp.h"
#include "libsec.h"

char *
logfsformat(LogfsLowLevel *ll, long base, long limit, long bootsize, int trace)
{
	long bootblocksdone, logblocksdone;
	long u;
	long baseblock, limitblock, bootblocks, sizeinblocks;
	int magicfound;
	void *llsave;

	if(trace > 1)
		print("logfsformat: base %ld limit %ld bootsize %lud\n", base, limit, bootsize);

	if((*ll->getopenstatus)(ll))
		return Eperm;

	if(!(*ll->calcformat)(ll, base, limit, bootsize, &baseblock, &limitblock, &bootblocks))
		return Ebadarg;

	if(trace > 0)
		print("logfsformat: baseblock %ld limitblock %ld bootblocks %ld\n", baseblock, limitblock, bootblocks);

	bootblocksdone = 0;
	logblocksdone = 0;
	/*
	 * we need to create some fs blocks, and some boot blocks
	 * the number of boot blocks is fixed; the number of fs blocks
	 * occupies the remainder
	 * the layout is randomised to:
	 * 1) test the software
	 * 2) spread wear around if a lot of format commands are issued by
	 *     the bootloader
	 */

	sizeinblocks = limitblock - baseblock;

	for(u = 0; u < sizeinblocks; u++) {
		int r;
		uchar tag;
		long path;
		LogfsLowLevelReadResult e;
		char *errmsg;
		int markedbad;

		if(trace > 1)
			print("block %lud:", u);
		llsave = nil;
		errmsg = (*ll->getblockstatus)(ll, u + baseblock, &magicfound, &llsave, &e);
		if(errmsg)
			return errmsg;
		if(e == LogfsLowLevelReadResultBad) {
			if(trace > 1)
				print(" marked bad\n");
			continue;
		}
		errmsg = (*ll->eraseblock)(ll, u + baseblock, nil, &markedbad);
		if(errmsg)
			return errmsg;
		if(markedbad) {
			if(trace > 1)
				print(" marked bad\n");
			continue;
		}
		if(e != LogfsLowLevelReadResultHardError && magicfound) {
			if(trace > 1)
				print(" previously formatted");
		}
		r = rand() % (sizeinblocks - u);
		if(bootblocksdone < bootblocks && r < (bootblocks - bootblocksdone)) {
			tag = LogfsTboot;
			path = mkdatapath(bootblocksdone, 0);
		}
		else {
			tag = LogfsTnone;
			path = ~0;
		}
		if(trace > 1)
			print(" tag %s path %ld", logfstagname(tag), path);
		errmsg = (*ll->formatblock)(ll, u + baseblock, tag, path, baseblock, sizeinblocks, 1, &bootblocks, llsave, &markedbad);
		logfsfreemem(llsave);
		if(errmsg)
			return errmsg;
		if(markedbad) {
			if(trace > 1)
				print(" marked bad\n");
			continue;
		}
		switch(tag) {
		case LogfsTboot:
			bootblocksdone++;
			break;
		case LogfsTnone:
			logblocksdone++;
			break;
		}
		if(trace > 1)
			print("\n");
	}
	if(bootblocksdone < bootblocks)
		return "not enough capacity left for boot";
	if(trace > 0)
		print("log blocks %lud\n", logblocksdone);
	return nil;
}
