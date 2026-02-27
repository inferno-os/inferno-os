package main

import "inferno/sys"

func qsort(a []int, lo, hi int) {
	if lo >= hi {
		return
	}
	pivot := a[lo]
	i := lo + 1
	j := hi
	for i <= j {
		for i <= hi && a[i] <= pivot {
			i++
		}
		for j > lo && a[j] > pivot {
			j--
		}
		if i < j {
			a[i], a[j] = a[j], a[i]
		}
	}
	a[lo], a[j] = a[j], a[lo]
	qsort(a, lo, j-1)
	qsort(a, j+1, hi)
}

func main() {
	n := 10000
	t0 := sys.Millisec()

	// Generate pseudo-random array using simple LCG
	a := make([]int, n)
	x := 12345
	for i := 0; i < n; i++ {
		x = x*1103515245 + 12345
		// Mask to positive 31 bits
		v := x
		if v < 0 {
			v = -v
		}
		a[i] = v % 100000
	}

	qsort(a, 0, n-1)

	// Verify sorted
	sorted := 1
	for i := 1; i < n; i++ {
		if a[i] < a[i-1] {
			sorted = 0
		}
	}

	t1 := sys.Millisec()
	println(sorted)
	println(t1 - t0)
}
