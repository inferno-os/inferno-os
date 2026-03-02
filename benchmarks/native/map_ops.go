package main

import (
	"fmt"
	"time"
)

func main() {
	// Pre-build keys to match Go-on-Dis version
	n := 100
	keys := make([]string, n)
	for i := 0; i < n; i++ {
		keys[i] = fmt.Sprintf("key%d", i)
	}

	t1 := time.Now()
	iterations := 100
	total := 0
	for iter := 0; iter < iterations; iter++ {
		m := make(map[string]int)
		for i := 0; i < n; i++ {
			m[keys[i]] = i
		}
		sum := 0
		for i := 0; i < n; i++ {
			if v, ok := m[keys[i]]; ok {
				sum += v
			}
		}
		total += sum
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH map_ops %d ms %d iters %d\n", elapsed, iterations, total)
}
