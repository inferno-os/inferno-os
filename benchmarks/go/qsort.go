package main

import "inferno/sys"

func partition(a []int, lo, hi int) int {
	pivot := a[hi]
	i := lo
	j := lo
	for j < hi {
		if a[j] < pivot {
			tmp := a[i]
			a[i] = a[j]
			a[j] = tmp
			i = i + 1
		}
		j = j + 1
	}
	tmp := a[i]
	a[i] = a[hi]
	a[hi] = tmp
	return i
}

func quicksort(a []int, lo, hi int) {
	if lo < hi {
		p := partition(a, lo, hi)
		quicksort(a, lo, p-1)
		quicksort(a, p+1, hi)
	}
}

func main() {
	n := 10000
	t1 := sys.Millisec()
	iterations := 50
	checksum := 0
	for iter := 0; iter < iterations; iter++ {
		a := make([]int, n)
		i := 0
		for i < n {
			a[i] = (n - i) * 7 % 1000
			i = i + 1
		}
		quicksort(a, 0, n-1)
		checksum = checksum + a[0] + a[n-1]
	}
	t2 := sys.Millisec()
	println("BENCH qsort", t2-t1, "ms", iterations, "iters", checksum)
}
