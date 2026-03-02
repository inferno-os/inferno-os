package main

import (
	"fmt"
	"math"
	"time"
)

func nbody(steps int) int {
	size := 5
	px := make([]float64, size)
	py := make([]float64, size)
	vx := make([]float64, size)
	vy := make([]float64, size)
	mass := make([]float64, size)

	px[0] = 0.0; py[0] = 0.0; vx[0] = 0.0; vy[0] = 0.0; mass[0] = 1000.0
	px[1] = 100.0; py[1] = 0.0; vx[1] = 0.0; vy[1] = 10.0; mass[1] = 1.0
	px[2] = 200.0; py[2] = 0.0; vx[2] = 0.0; vy[2] = 7.0; mass[2] = 1.0
	px[3] = 0.0; py[3] = 150.0; vx[3] = 8.0; vy[3] = 0.0; mass[3] = 1.0
	px[4] = 0.0; py[4] = 250.0; vx[4] = 6.0; vy[4] = 0.0; mass[4] = 1.0

	dt := 0.01

	for step := 0; step < steps; step++ {
		for i := 0; i < size; i++ {
			for j := i + 1; j < size; j++ {
				dx := px[j] - px[i]
				dy := py[j] - py[i]
				dist := math.Sqrt(dx*dx + dy*dy)
				if dist < 0.001 {
					dist = 0.001
				}
				force := mass[i] * mass[j] / (dist * dist)
				fx := force * dx / dist
				fy := force * dy / dist
				vx[i] += dt * fx / mass[i]
				vy[i] += dt * fy / mass[i]
				vx[j] -= dt * fx / mass[j]
				vy[j] -= dt * fy / mass[j]
			}
		}
		for i := 0; i < size; i++ {
			px[i] += dt * vx[i]
			py[i] += dt * vy[i]
		}
	}
	return int(px[0]*1000.0) + int(py[0]*1000.0) + int(px[1]*1000.0) + int(py[1]*1000.0)
}

func main() {
	t1 := time.Now()
	iterations := 10
	result := 0
	for iter := 0; iter < iterations; iter++ {
		result += nbody(5000)
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH nbody %d ms %d iters %d\n", elapsed, iterations, result)
}
