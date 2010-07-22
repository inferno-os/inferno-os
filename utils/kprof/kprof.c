#include <lib9.h>
#include <bio.h>
#include <mach.h>

enum {
	SpecialTotalTicks,
	SpecialOutsideTicks,
	SpecialMicroSecondsPerTick,
	SpecialSamples,
	SpecialSampleSize,
	SpecialSampleLogBucketSize,
	SpecialMax
};

int pcres = 8;
ulong uspertick;

struct COUNTER
{
	char 	*name;		/* function name */
	ulong	time;		/* ticks spent there */
};

void
error(int perr, char *s)
{
	fprint(2, "kprof: %s", s);
	if(perr)
		fprint(2, ": %r\n");
	else
		fprint(2, "\n");
	exits(s);
}

int
compar(void *va, void *vb)
{
	struct COUNTER *a, *b;

	a = (struct COUNTER *)va;
	b = (struct COUNTER *)vb;
	if(a->time < b->time)
		return -1;
	if(a->time == b->time)
		return 0;
	return 1;
}

ulong
tickstoms(ulong ticks)
{
	return ((vlong)ticks * uspertick) / 1000;
}

void
main(int argc, char *argv[])
{
	int fd;
	long i, j, k, n;
	Dir *d;
	char *name;
	ulong *data;
	ulong tbase, sum;
	long delta;
	Symbol s;
	Biobuf outbuf;
	Fhdr f;
	struct COUNTER *cp;

	if(argc != 3)
		error(0, "usage: kprof text data");
	/*
	 * Read symbol table
	 */
	fd = open(argv[1], OREAD);
	if(fd < 0)
		error(1, argv[1]);
	if (!crackhdr(fd, &f))
		error(1, "read text header");
	if (f.type == FNONE)
		error(0, "text file not an a.out");
	if (syminit(fd, &f) < 0)
		error(1, "syminit");
	close(fd);
	/*
	 * Read timing data
	 */
	fd = open(argv[2], OREAD);
	if(fd < 0)
		error(1, argv[2]);
	if((d = dirfstat(fd)) == nil)
		error(1, "stat");
	n = d->length/sizeof(data[0]);
	if(n < 2)
		error(0, "data file too short");
	data = malloc(d->length);
	if(data == 0)
		error(1, "malloc");
	if(read(fd, data, d->length) < 0)
		error(1, "text read");
	close(fd);
	free(d);
	for(i=0; i<n; i++)
		data[i] = beswal(data[i]);
	pcres = 1 << data[SpecialSampleLogBucketSize];
	uspertick = data[SpecialMicroSecondsPerTick];
	if (data[SpecialSampleSize] != sizeof(data[0]))
		error(0, "only sample size 4 supported\n");
	delta = data[SpecialTotalTicks] - data[SpecialOutsideTicks];
	print("total: %lud	in kernel text: %lud	outside kernel text: %lud\n",
		data[0], delta, data[1]);
	if(data[0] == 0)
		exits(0);
	if (!textsym(&s, 0))
		error(0, "no text symbols");
	tbase = s.value & ~(mach->pgsize-1);	/* align down to page */
	print("KTZERO %.8lux\n", tbase);
	/*
	 * Accumulate counts for each function
	 */
	cp = 0;
	k = 0;
	for (i = 0, j = (s.value-tbase)/pcres+SpecialMax; j < n; i++) {
		name = s.name;		/* save name */
		if (!textsym(&s, i))	/* get next symbol */
			break;
		sum = 0;
		while (j < n && j*pcres < s.value-tbase)
			sum += data[j++];
		if (sum) {
			cp = realloc(cp, (k+1)*sizeof(struct COUNTER));
			if (cp == 0)
				error(1, "realloc");
			cp[k].name = name;
			cp[k].time = sum;
			k++;
		}
	}
	if (!k)
		error(0, "no counts");
	cp[k].time = 0;			/* "etext" can take no time */
	/*
	 * Sort by time and print
	 */
	qsort(cp, k, sizeof(struct COUNTER), compar);
	Binit(&outbuf, 1, OWRITE);
	Bprint(&outbuf, "ms	  %%	sym\n");
	while(--k>=0)
		Bprint(&outbuf, "%lud\t%3lud.%ld\t%s\n",
				tickstoms(cp[k].time),
				100*cp[k].time/delta,
				(1000*cp[k].time/delta)%10,
				cp[k].name);
	exits(0);
}
