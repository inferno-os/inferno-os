implement BenchFannkuch;

include "sys.m";
	sys: Sys;

include "draw.m";

BenchFannkuch: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

fannkuch(n: int): int
{
	perm := array[n] of int;
	perm1 := array[n] of int;
	count := array[n] of int;

	for(i := 0; i < n; i++) {
		perm1[i] = i;
		count[i] = 0;
	}

	maxFlips := 0;
	checksum := 0;
	permCount := 0;

	done := 0;
	while(done == 0) {
		# Copy perm1 to perm
		for(i := 0; i < n; i++)
			perm[i] = perm1[i];

		# Count flips
		flips := 0;
		k := perm[0];
		while(k != 0) {
			lo := 0;
			hi := k;
			while(lo < hi) {
				tmp := perm[lo];
				perm[lo] = perm[hi];
				perm[hi] = tmp;
				lo++;
				hi--;
			}
			flips++;
			k = perm[0];
		}

		if(flips > maxFlips)
			maxFlips = flips;
		if(permCount % 2 == 0)
			checksum += flips;
		else
			checksum -= flips;
		permCount++;

		# Generate next permutation (counting method)
		r := 1;
		while(r < n) {
			perm0 := perm1[0];
			for(j := 0; j < r; j++)
				perm1[j] = perm1[j+1];
			perm1[r] = perm0;

			count[r]++;
			if(count[r] <= r)
				break;
			count[r] = 0;
			r++;
		}
		if(r >= n)
			done = 1;
	}
	return checksum;
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	t1 := sys->millisec();
	iterations := 3;
	total := 0;
	for(iter := 0; iter < iterations; iter++)
		total += fannkuch(9);
	t2 := sys->millisec();
	sys->print("BENCH fannkuch %d ms %d iters %d\n", t2-t1, iterations, total);
}
