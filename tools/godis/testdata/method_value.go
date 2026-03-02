package main

type Adder struct{ base int }

func (a *Adder) Add(x int) int { return a.base + x }

func main() {
	a := &Adder{base: 10}
	f := a.Add
	println(f(5))
	println(f(7))
}
