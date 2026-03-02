package main

import (
	"inferno/sys"
	"math"
)

func nbody(steps int) int {
	size := 5
	px := make([]float64, size)
	py := make([]float64, size)
	vx := make([]float64, size)
	vy := make([]float64, size)
	mass := make([]float64, size)

	px[0] = 0.0
	py[0] = 0.0
	vx[0] = 0.0
	vy[0] = 0.0
	mass[0] = 1000.0

	px[1] = 100.0
	py[1] = 0.0
	vx[1] = 0.0
	vy[1] = 10.0
	mass[1] = 1.0

	px[2] = 200.0
	py[2] = 0.0
	vx[2] = 0.0
	vy[2] = 7.0
	mass[2] = 1.0

	px[3] = 0.0
	py[3] = 150.0
	vx[3] = 8.0
	vy[3] = 0.0
	mass[3] = 1.0

	px[4] = 0.0
	py[4] = 250.0
	vx[4] = 6.0
	vy[4] = 0.0
	mass[4] = 1.0

	dt := 0.01

	step := 0
	for step < steps {
		i := 0
		for i < size {
			j := i + 1
			for j < size {
				dx := px[j] - px[i]
				dy := py[j] - py[i]
				dist := math.Sqrt(dx*dx + dy*dy)
				if dist < 0.001 {
					dist = 0.001
				}
				force := mass[i] * mass[j] / (dist * dist)
				fx := force * dx / dist
				fy := force * dy / dist
				vx[i] = vx[i] + dt*fx/mass[i]
				vy[i] = vy[i] + dt*fy/mass[i]
				vx[j] = vx[j] - dt*fx/mass[j]
				vy[j] = vy[j] - dt*fy/mass[j]
				j = j + 1
			}
			i = i + 1
		}
		k := 0
		for k < size {
			px[k] = px[k] + dt*vx[k]
			py[k] = py[k] + dt*vy[k]
			k = k + 1
		}
		step = step + 1
	}
	return int(px[0]*1000.0) + int(py[0]*1000.0) + int(px[1]*1000.0) + int(py[1]*1000.0)
}

func main() {
	t1 := sys.Millisec()
	iterations := 10
	result := 0
	for iter := 0; iter < iterations; iter++ {
		result = result + nbody(5000)
	}
	t2 := sys.Millisec()
	println("BENCH nbody", t2-t1, "ms", iterations, "iters", result)
}
