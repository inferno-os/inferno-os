package main

import (
	"fmt"
	"time"
)

func main() {
	t1 := time.Now()
	iterations := 300
	totalLen := 0
	for iter := 0; iter < iterations; iter++ {
		s := ""
		for i := 0; i < 2000; i++ {
			s = s + "a"
		}
		totalLen += len(s)
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH strcat %d ms %d iters %d\n", elapsed, iterations, totalLen)
}
