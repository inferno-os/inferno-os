package main

import (
	"fmt"
	"time"
)

func fannkuch(n int) int {
	perm := make([]int, n)
	perm1 := make([]int, n)
	count := make([]int, n)

	for i := 0; i < n; i++ {
		perm1[i] = i
		count[i] = 0
	}

	maxFlips := 0
	checksum := 0
	permCount := 0

	for {
		// Copy perm1 to perm
		copy(perm, perm1)

		// Count flips
		flips := 0
		k := perm[0]
		for k != 0 {
			for lo, hi := 0, k; lo < hi; lo, hi = lo+1, hi-1 {
				perm[lo], perm[hi] = perm[hi], perm[lo]
			}
			flips++
			k = perm[0]
		}

		if flips > maxFlips {
			maxFlips = flips
		}
		if permCount%2 == 0 {
			checksum += flips
		} else {
			checksum -= flips
		}
		permCount++

		// Generate next permutation (counting method)
		r := 1
		for r < n {
			perm0 := perm1[0]
			copy(perm1[:r], perm1[1:r+1])
			perm1[r] = perm0

			count[r]++
			if count[r] <= r {
				break
			}
			count[r] = 0
			r++
		}
		if r >= n {
			break
		}
	}
	return checksum
}

func main() {
	t1 := time.Now()
	iterations := 3
	total := 0
	for iter := 0; iter < iterations; iter++ {
		total += fannkuch(9)
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH fannkuch %d ms %d iters %d\n", elapsed, iterations, total)
}
