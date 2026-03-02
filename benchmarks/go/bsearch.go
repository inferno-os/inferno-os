package main

import "inferno/sys"

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
	i := 0
	for i < n {
		a[i] = i * 2
		i = i + 1
	}

	t1 := sys.Millisec()
	iterations := 100
	found := 0
	for iter := 0; iter < iterations; iter++ {
		i = 0
		for i < n {
			idx := binarySearch(a, i*2)
			if idx >= 0 {
				found = found + 1
			}
			i = i + 1
		}
	}
	t2 := sys.Millisec()
	println("BENCH bsearch", t2-t1, "ms", iterations, "iters", found)
}
