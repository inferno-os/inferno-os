package main

import (
	"fmt"
	"time"
)

func sieve(limit int) int {
	s := make([]int, limit+1)
	count := 0
	for i := 2; i <= limit; i++ {
		if s[i] == 0 {
			count++
			for j := i + i; j <= limit; j += i {
				s[j] = 1
			}
		}
	}
	return count
}

func main() {
	t1 := time.Now()
	result := 0
	iterations := 50
	for i := 0; i < iterations; i++ {
		result = sieve(50000)
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH sieve %d ms %d iters %d\n", elapsed, iterations, result)
}
