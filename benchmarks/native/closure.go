package main

import (
	"fmt"
	"time"
)

func makeAdder(x int) func(int) int {
	return func(y int) int {
		return x + y
	}
}

func applyN(f func(int) int, n int, iterations int) int {
	result := 0
	for i := 0; i < iterations; i++ {
		result += f(i)
	}
	return result
}

func main() {
	t1 := time.Now()
	iterations := 500
	total := 0
	for iter := 0; iter < iterations; iter++ {
		add5 := makeAdder(5)
		add10 := makeAdder(10)
		total += applyN(add5, 0, 10000)
		total += applyN(add10, 0, 10000)
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH closure %d ms %d iters %d\n", elapsed, iterations, total)
}
