package main

import "inferno/sys"

func fannkuch(n int) int {
	perm := make([]int, n)
	perm1 := make([]int, n)
	count := make([]int, n)

	i := 0
	for i < n {
		perm1[i] = i
		count[i] = 0
		i = i + 1
	}

	maxFlips := 0
	checksum := 0
	permCount := 0

	done := 0
	for done == 0 {
		// Copy perm1 to perm
		i = 0
		for i < n {
			perm[i] = perm1[i]
			i = i + 1
		}

		// Count flips
		flips := 0
		k := perm[0]
		for k != 0 {
			lo := 0
			hi := k
			for lo < hi {
				tmp := perm[lo]
				perm[lo] = perm[hi]
				perm[hi] = tmp
				lo = lo + 1
				hi = hi - 1
			}
			flips = flips + 1
			k = perm[0]
		}

		if flips > maxFlips {
			maxFlips = flips
		}
		if permCount%2 == 0 {
			checksum = checksum + flips
		} else {
			checksum = checksum - flips
		}
		permCount = permCount + 1

		// Generate next permutation (counting method)
		r := 1
		for r < n {
			// Rotate perm1[0..r] left by 1
			perm0 := perm1[0]
			j := 0
			for j < r {
				perm1[j] = perm1[j+1]
				j = j + 1
			}
			perm1[r] = perm0

			count[r] = count[r] + 1
			if count[r] <= r {
				break
			}
			count[r] = 0
			r = r + 1
		}
		if r >= n {
			done = 1
		}
	}
	return checksum
}

func main() {
	t1 := sys.Millisec()
	iterations := 3
	total := 0
	for iter := 0; iter < iterations; iter++ {
		total = total + fannkuch(9)
	}
	t2 := sys.Millisec()
	println("BENCH fannkuch", t2-t1, "ms", iterations, "iters", total)
}
