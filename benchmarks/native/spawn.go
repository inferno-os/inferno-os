package main

import (
	"fmt"
	"time"
)

func worker(ch chan int) {
	ch <- 1
}

func main() {
	t1 := time.Now()
	iterations := 15
	total := 0
	for iter := 0; iter < iterations; iter++ {
		n := 1500
		ch := make(chan int, n)
		for i := 0; i < n; i++ {
			go worker(ch)
		}
		sum := 0
		for i := 0; i < n; i++ {
			sum += <-ch
		}
		total += sum
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH spawn %d ms %d iters %d\n", elapsed, iterations, total)
}
