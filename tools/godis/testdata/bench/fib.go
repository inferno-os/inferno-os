package main

import "inferno/sys"

func fib(n int) int {
	if n < 2 {
		return n
	}
	return fib(n-1) + fib(n-2)
}

func main() {
	t0 := sys.Millisec()
	result := fib(35)
	t1 := sys.Millisec()
	println(result)
	println(t1 - t0)
}
