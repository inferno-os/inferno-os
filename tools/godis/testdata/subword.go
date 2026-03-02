package main

func main() {
	// uint8 overflow: 200 + 100 = 300 → 44 (300 & 0xFF)
	var a uint8 = 200
	var b uint8 = 100
	c := a + b
	println(c)

	// int8 overflow: 100 + 50 = 150 → -106 (signed wrap)
	var d int8 = 100
	var e int8 = 50
	f := d + e
	println(f)

	// uint8 negation: -1 → 255
	var g uint8 = 1
	h := -g
	println(h)

	// int8 to int conversion preserves sign
	var i int8 = -42
	j := int(i)
	println(j)

	// uint16 overflow: 60000 + 10000 = 70000 → 4464
	var k uint16 = 60000
	var l uint16 = 10000
	m := k + l
	println(m)
}
