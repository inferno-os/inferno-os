package main

import "inferno/sys"

func matmul(n int) int {
	a := make([]int, n*n)
	b := make([]int, n*n)
	c := make([]int, n*n)

	i := 0
	for i < n*n {
		a[i] = i + 1
		b[i] = i * 2
		i = i + 1
	}

	i = 0
	for i < n {
		j := 0
		for j < n {
			sum := 0
			k := 0
			for k < n {
				sum = sum + a[i*n+k]*b[k*n+j]
				k = k + 1
			}
			c[i*n+j] = sum
			j = j + 1
		}
		i = i + 1
	}
	return c[0] + c[n*n-1]
}

func main() {
	t1 := sys.Millisec()
	iterations := 10
	result := 0
	for iter := 0; iter < iterations; iter++ {
		result = result + matmul(120)
	}
	t2 := sys.Millisec()
	println("BENCH matrix", t2-t1, "ms", iterations, "iters", result)
}
