implement Sort;
include "sort.m";

sort[S, T](s: S, a: array of T)
	for{
	S =>
		gt: fn(s: self S, x, y: T): int;
	}
{
	mergesort(s, a, array[len a] of T);
}

mergesort[S, T](s: S, a, b: array of T)
	for{
	S =>
		gt: fn(s: self S, x, y: T): int;
	}
{
	r := len a;
	if (r > 1) {
		m := (r-1)/2 + 1;
		mergesort(s, a[0:m], b[0:m]);
		mergesort(s, a[m:], b[m:]);
		b[0:] = a;
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if(s.gt(b[i], b[j]))
				a[k] = b[j++];
			else
				a[k] = b[i++];
		}
		if (i < m)
			a[k:] = b[i:m];
		else if (j < r)
			a[k:] = b[j:r];
	}
}
