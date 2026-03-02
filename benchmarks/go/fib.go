package main

import "inferno/sys"

func fib(n int) int {
	if n <= 1 {
		return n
	}
	return fib(n-1) + fib(n-2)
}

func main() {
	t1 := sys.Millisec()
	result := 0
	iterations := 10
	for i := 0; i < iterations; i++ {
		result = fib(30)
	}
	t2 := sys.Millisec()
	println("BENCH fib", t2-t1, "ms", iterations, "iters", result)
}
