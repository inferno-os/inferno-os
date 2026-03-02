package main

import (
	"fmt"
	"time"
)

func matmul(n int) int {
	a := make([]int, n*n)
	b := make([]int, n*n)
	c := make([]int, n*n)

	for i := 0; i < n*n; i++ {
		a[i] = i + 1
		b[i] = i * 2
	}

	for i := 0; i < n; i++ {
		for j := 0; j < n; j++ {
			sum := 0
			for k := 0; k < n; k++ {
				sum += a[i*n+k] * b[k*n+j]
			}
			c[i*n+j] = sum
		}
	}
	return c[0] + c[n*n-1]
}

func main() {
	t1 := time.Now()
	iterations := 10
	result := 0
	for iter := 0; iter < iterations; iter++ {
		result += matmul(120)
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH matrix %d ms %d iters %d\n", elapsed, iterations, result)
}
