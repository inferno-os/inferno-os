package main

import "inferno/sys"

func worker(ch chan int) {
	ch <- 1
}

func main() {
	t1 := sys.Millisec()
	iterations := 15
	total := 0
	for iter := 0; iter < iterations; iter++ {
		n := 1500
		ch := make(chan int, n)
		i := 0
		for i < n {
			go worker(ch)
			i = i + 1
		}
		sum := 0
		i = 0
		for i < n {
			sum = sum + <-ch
			i = i + 1
		}
		total = total + sum
	}
	t2 := sys.Millisec()
	println("BENCH spawn", t2-t1, "ms", iterations, "iters", total)
}
