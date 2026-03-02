package main

// Test &^ (AND NOT / bit clear) operator
func main() {
	x := 0xFF
	y := 0x0F
	z := x &^ y // should be 0xF0 = 240
	println(z)

	// Test with variables
	a := 7  // 0b111
	b := 3  // 0b011
	c := a &^ b // should be 4 (0b100)
	println(c)
}
