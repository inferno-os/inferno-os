package main

type Pair struct {
	First  int
	Second int
}

func getPair() Pair {
	return Pair{First: 10, Second: 20}
}

func main() {
	// *ssa.Field: extract field from struct value (not via pointer)
	p := getPair()
	println(p.First)
	println(p.Second)

	// Direct field access from return value
	sum := getPair().First + getPair().Second
	println(sum)
}
