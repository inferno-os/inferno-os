package main

func main() {
	// Basic complex construction and extraction
	z := complex(3.0, 4.0)
	println(real(z))
	println(imag(z))

	// Complex arithmetic
	z2 := complex(1.0, 2.0)
	sum := z + z2
	println(real(sum))
	println(imag(sum))

	// Subtraction
	diff := z - z2
	println(real(diff))
	println(imag(diff))

	// Multiplication: (3+4i)(1+2i) = 3+6i+4i+8i² = 3+10i-8 = -5+10i
	prod := z * z2
	println(real(prod))
	println(imag(prod))

	// Division: (4+2i)/(1+1i) = (4+2+2-4i)/(1+1) = (6-2i)/2 = 3-1i
	z3 := complex(4.0, 2.0)
	z4 := complex(1.0, 1.0)
	quot := z3 / z4
	println(real(quot))
	println(imag(quot))

	// Equality
	z5 := complex(3.0, 4.0)
	if z == z5 {
		println("equal")
	}
	if z != z2 {
		println("not equal")
	}
}
