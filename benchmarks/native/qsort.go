package main

import (
	"fmt"
	"time"
)

func partition(a []int, lo, hi int) int {
	pivot := a[hi]
	i := lo
	for j := lo; j < hi; j++ {
		if a[j] < pivot {
			a[i], a[j] = a[j], a[i]
			i++
		}
	}
	a[i], a[hi] = a[hi], a[i]
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
	t1 := time.Now()
	iterations := 50
	checksum := 0
	for iter := 0; iter < iterations; iter++ {
		a := make([]int, n)
		for i := 0; i < n; i++ {
			a[i] = (n - i) * 7 % 1000
		}
		quicksort(a, 0, n-1)
		checksum += a[0] + a[n-1]
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH qsort %d ms %d iters %d\n", elapsed, iterations, checksum)
}
