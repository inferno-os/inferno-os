package main

import "inferno/sys"

func doLoop(n int) int {
	sum := 0
	for i := 0; i < n; i++ {
		sum += i
	}
	return sum
}

func main() {
	t0 := sys.Millisec()
	sum := doLoop(10000000)
	t1 := sys.Millisec()
	println(sum)
	println(t1 - t0)
}
