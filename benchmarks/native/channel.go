package main

import (
	"fmt"
	"time"
)

func producer(ch chan int, n int) {
	for i := 0; i < n; i++ {
		ch <- i
	}
	close(ch)
}

func main() {
	t1 := time.Now()
	iterations := 10
	total := 0
	for iter := 0; iter < iterations; iter++ {
		ch := make(chan int, 100)
		go producer(ch, 10000)
		sum := 0
		for v := range ch {
			sum += v
		}
		total += sum
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH channel %d ms %d iters %d\n", elapsed, iterations, total)
}
