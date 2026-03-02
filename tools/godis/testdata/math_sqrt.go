package main

import "math"

func main() {
	// Sqrt(4.0) = 2.0
	s := math.Sqrt(4.0)
	// Truncate to int for deterministic output
	println(int(s))

	// Sqrt(9.0) = 3.0
	s = math.Sqrt(9.0)
	println(int(s))

	// Min/Max
	println(int(math.Min(3.0, 7.0)))
	println(int(math.Max(3.0, 7.0)))
}
