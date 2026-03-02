package main

import (
	"inferno/sys"
	"math"
)

func evalA(i, j int) float64 {
	return 1.0 / float64((i+j)*(i+j+1)/2+i+1)
}

func multiplyAv(n int, v []float64, av []float64) {
	i := 0
	for i < n {
		sum := 0.0
		j := 0
		for j < n {
			sum = sum + evalA(i, j)*v[j]
			j = j + 1
		}
		av[i] = sum
		i = i + 1
	}
}

func multiplyAtv(n int, v []float64, atv []float64) {
	i := 0
	for i < n {
		sum := 0.0
		j := 0
		for j < n {
			sum = sum + evalA(j, i)*v[j]
			j = j + 1
		}
		atv[i] = sum
		i = i + 1
	}
}

func multiplyAtAv(n int, v []float64, atav []float64) {
	u := make([]float64, n)
	multiplyAv(n, v, u)
	multiplyAtv(n, u, atav)
}

func spectralNorm(n int) int {
	u := make([]float64, n)
	i := 0
	for i < n {
		u[i] = 1.0
		i = i + 1
	}
	v := make([]float64, n)

	k := 0
	for k < 10 {
		multiplyAtAv(n, u, v)
		multiplyAtAv(n, v, u)
		k = k + 1
	}

	vBv := 0.0
	vv := 0.0
	i = 0
	for i < n {
		vBv = vBv + u[i]*v[i]
		vv = vv + v[i]*v[i]
		i = i + 1
	}
	result := math.Sqrt(vBv / vv)
	return int(result * 1000000.0)
}

func main() {
	t1 := sys.Millisec()
	iterations := 5
	total := 0
	for iter := 0; iter < iterations; iter++ {
		total = total + spectralNorm(300)
	}
	t2 := sys.Millisec()
	println("BENCH spectral_norm", t2-t1, "ms", iterations, "iters", total)
}
