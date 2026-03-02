package main

type Adder struct{ base int }

func (a *Adder) Add(x int) int { return a.base + x }

func apply(f func(int) int, x int) int { return f(x) }

func main() {
	a := &Adder{base: 10}
	f := a.Add
	println(apply(f, 5))
	println(apply(f, 7))
}
