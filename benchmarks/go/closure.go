package main

import "inferno/sys"

func makeAdder(x int) func(int) int {
	return func(y int) int {
		return x + y
	}
}

func applyN(f func(int) int, n int, iterations int) int {
	result := 0
	i := 0
	for i < iterations {
		result = result + f(i)
		i = i + 1
	}
	return result
}

func main() {
	t1 := sys.Millisec()
	iterations := 500
	total := 0
	for iter := 0; iter < iterations; iter++ {
		add5 := makeAdder(5)
		add10 := makeAdder(10)
		total = total + applyN(add5, 0, 10000)
		total = total + applyN(add10, 0, 10000)
	}
	t2 := sys.Millisec()
	println("BENCH closure", t2-t1, "ms", iterations, "iters", total)
}
