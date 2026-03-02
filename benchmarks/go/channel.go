package main

import "inferno/sys"

func producer(ch chan int, n int) {
	i := 0
	for i < n {
		ch <- i
		i = i + 1
	}
	ch <- -1
}

func main() {
	t1 := sys.Millisec()
	iterations := 10
	total := 0
	for iter := 0; iter < iterations; iter++ {
		ch := make(chan int, 100)
		go producer(ch, 10000)
		sum := 0
		done2 := 0
		for done2 == 0 {
			v := <-ch
			if v == -1 {
				done2 = 1
			} else {
				sum = sum + v
			}
		}
		total = total + sum
	}
	t2 := sys.Millisec()
	println("BENCH channel", t2-t1, "ms", iterations, "iters", total)
}
