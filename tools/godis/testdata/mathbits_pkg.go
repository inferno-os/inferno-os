package main

import "math/bits"

func main() {
	// OnesCount(7) = 3 (binary 111)
	println(bits.OnesCount(7))
	// Len(255) = 8
	println(bits.Len(255))
	// TrailingZeros(8) = 3 (binary 1000)
	println(bits.TrailingZeros(8))
}
