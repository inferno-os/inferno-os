package main

import (
	"fmt"
	"time"
)

func binarySearch(a []int, target int) int {
	lo := 0
	hi := len(a) - 1
	for lo <= hi {
		mid := (lo + hi) / 2
		if a[mid] == target {
			return mid
		}
		if a[mid] < target {
			lo = mid + 1
		} else {
			hi = mid - 1
		}
	}
	return -1
}

func main() {
	n := 10000
	a := make([]int, n)
	for i := 0; i < n; i++ {
		a[i] = i * 2
	}

	t1 := time.Now()
	iterations := 100
	found := 0
	for iter := 0; iter < iterations; iter++ {
		for i := 0; i < n; i++ {
			idx := binarySearch(a, i*2)
			if idx >= 0 {
				found++
			}
		}
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH bsearch %d ms %d iters %d\n", elapsed, iterations, found)
}
