package main

func main() {
	// Test unsigned comparisons for uint
	var a uint = 10
	var b uint = 20

	// Basic unsigned comparisons (same as signed for small values)
	if a < b {
		println("a<b")
	}
	if b > a {
		println("b>a")
	}
	if a <= a {
		println("a<=a")
	}
	if a >= a {
		println("a>=a")
	}

	// Equality is sign-agnostic — should work
	if a != b {
		println("a!=b")
	}
}
