package main

import "inferno/sys"

func sieve(limit int) int {
	s := make([]int, limit+1)
	count := 0
	i := 2
	for i <= limit {
		if s[i] == 0 {
			count = count + 1
			j := i + i
			for j <= limit {
				s[j] = 1
				j = j + i
			}
		}
		i = i + 1
	}
	return count
}

func main() {
	t1 := sys.Millisec()
	result := 0
	iterations := 50
	for i := 0; i < iterations; i++ {
		result = sieve(50000)
	}
	t2 := sys.Millisec()
	println("BENCH sieve", t2-t1, "ms", iterations, "iters", result)
}
