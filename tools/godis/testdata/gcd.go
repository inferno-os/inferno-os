package main

func gcd(a, b int) int {
	for b != 0 {
		t := b
		b = a - (a/b)*b
		a = t
	}
	return a
}

func main() {
	println(gcd(48, 18))
}
