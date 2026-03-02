package main

import "inferno/sys"

func mandelbrot(size int, maxIter int) int {
	sum := 0
	y := 0
	for y < size {
		x := 0
		for x < size {
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
				iter = iter + 1
			}
			sum = sum + iter
			x = x + 1
		}
		y = y + 1
	}
	return sum
}

func main() {
	t1 := sys.Millisec()
	iterations := 5
	total := 0
	for iter := 0; iter < iterations; iter++ {
		total = total + mandelbrot(200, 200)
	}
	t2 := sys.Millisec()
	println("BENCH mandelbrot", t2-t1, "ms", iterations, "iters", total)
}
