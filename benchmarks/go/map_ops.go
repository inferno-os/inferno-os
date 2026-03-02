package main

import (
	"fmt"
	"inferno/sys"
)

func main() {
	t1 := sys.Millisec()
	iterations := 100
	total := 0
	// Pre-build keys to reduce memory pressure
	n := 100
	keys := make([]string, n)
	i := 0
	for i < n {
		keys[i] = fmt.Sprintf("key%d", i)
		i = i + 1
	}

	for iter := 0; iter < iterations; iter++ {
		m := make(map[string]int)
		i = 0
		for i < n {
			m[keys[i]] = i
			i = i + 1
		}
		sum := 0
		i = 0
		for i < n {
			v, ok := m[keys[i]]
			if ok {
				sum = sum + v
			}
			i = i + 1
		}
		total = total + sum
	}
	t2 := sys.Millisec()
	println("BENCH map_ops", t2-t1, "ms", iterations, "iters", total)
}
