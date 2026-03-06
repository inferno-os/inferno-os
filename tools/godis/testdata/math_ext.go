package main

import "math"

func main() {
	// Floor
	f := math.Floor(3.7)
	if f == 3.0 {
		println("floor ok")
	}
	// Ceil
	c := math.Ceil(3.2)
	if c == 4.0 {
		println("ceil ok")
	}
	// Trunc
	tr := math.Trunc(3.9)
	if tr == 3.0 {
		println("trunc ok")
	}
	// Pow
	p := math.Pow(2.0, 10.0)
	if p == 1024.0 {
		println("pow ok")
	}
	// IsNaN
	nan := math.NaN()
	if math.IsNaN(nan) {
		println("nan ok")
	}
}
