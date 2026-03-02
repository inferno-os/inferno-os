package main

import (
	"fmt"
	"time"
)

func fib(n int) int {
	if n <= 1 {
		return n
	}
	return fib(n-1) + fib(n-2)
}

func main() {
	t1 := time.Now()
	result := 0
	iterations := 10
	for i := 0; i < iterations; i++ {
		result = fib(30)
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH fib %d ms %d iters %d\n", elapsed, iterations, result)
}
