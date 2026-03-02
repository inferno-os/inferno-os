package main

import (
	"fmt"
	"math"
	"time"
)

func evalA(i, j int) float64 {
	return 1.0 / float64((i+j)*(i+j+1)/2+i+1)
}

func multiplyAv(n int, v, av []float64) {
	for i := 0; i < n; i++ {
		sum := 0.0
		for j := 0; j < n; j++ {
			sum += evalA(i, j) * v[j]
		}
		av[i] = sum
	}
}

func multiplyAtv(n int, v, atv []float64) {
	for i := 0; i < n; i++ {
		sum := 0.0
		for j := 0; j < n; j++ {
			sum += evalA(j, i) * v[j]
		}
		atv[i] = sum
	}
}

func multiplyAtAv(n int, v, atav []float64) {
	u := make([]float64, n)
	multiplyAv(n, v, u)
	multiplyAtv(n, u, atav)
}

func spectralNorm(n int) int {
	u := make([]float64, n)
	for i := 0; i < n; i++ {
		u[i] = 1.0
	}
	v := make([]float64, n)

	for k := 0; k < 10; k++ {
		multiplyAtAv(n, u, v)
		multiplyAtAv(n, v, u)
	}

	vBv := 0.0
	vv := 0.0
	for i := 0; i < n; i++ {
		vBv += u[i] * v[i]
		vv += v[i] * v[i]
	}
	result := math.Sqrt(vBv / vv)
	return int(result * 1000000.0)
}

func main() {
	t1 := time.Now()
	iterations := 5
	total := 0
	for iter := 0; iter < iterations; iter++ {
		total += spectralNorm(300)
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH spectral_norm %d ms %d iters %d\n", elapsed, iterations, total)
}
