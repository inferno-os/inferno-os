package main

import (
	"fmt"
	"time"
)

func mandelbrot(size, maxIter int) int {
	sum := 0
	for y := 0; y < size; y++ {
		for x := 0; x < size; x++ {
			cr := 2.0*float64(x)/float64(size) - 1.5
			ci := 2.0*float64(y)/float64(size) - 1.0
			zr := 0.0
			zi := 0.0
			iter := 0
			for iter < maxIter {
				if zr*zr+zi*zi > 4.0 {
					break
				}
				tr := zr*zr - zi*zi + cr
				zi = 2.0*zr*zi + ci
				zr = tr
				iter++
			}
			sum += iter
		}
	}
	return sum
}

func main() {
	t1 := time.Now()
	iterations := 5
	total := 0
	for iter := 0; iter < iterations; iter++ {
		total += mandelbrot(200, 200)
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH mandelbrot %d ms %d iters %d\n", elapsed, iterations, total)
}
