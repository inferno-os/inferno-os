package main

import "inferno/sys"

func main() {
	n := 10000
	iters := 100
	t0 := sys.Millisec()

	count := 0
	for iter := 0; iter < iters; iter++ {
		sieve := make([]int, n)
		for i := 0; i < n; i++ {
			sieve[i] = 0
		}

		for i := 2; i*i < n; i++ {
			if sieve[i] == 0 {
				for j := i * i; j < n; j += i {
					sieve[j] = 1
				}
			}
		}

		count = 0
		for i := 2; i < n; i++ {
			if sieve[i] == 0 {
				count++
			}
		}
	}

	t1 := sys.Millisec()
	println(count)
	println(t1 - t0)
}
