package main

import "inferno/sys"

type Shape interface {
	Area() int
}

type Rect struct {
	W, H int
}

func (r Rect) Area() int {
	return r.W * r.H
}

type Circle struct {
	R int
}

func (c Circle) Area() int {
	return c.R * c.R * 3
}

func computeArea(s Shape) int {
	return s.Area()
}

func main() {
	t1 := sys.Millisec()
	iterations := 1000
	total := 0
	for iter := 0; iter < iterations; iter++ {
		sum := 0
		i := 0
		for i < 2000 {
			var a int
			if i%2 == 0 {
				r := Rect{W: i, H: i + 1}
				a = computeArea(r)
			} else {
				c := Circle{R: i}
				a = computeArea(c)
			}
			sum = sum + a
			i = i + 1
		}
		total = total + sum
	}
	t2 := sys.Millisec()
	println("BENCH interface", t2-t1, "ms", iterations, "iters", total)
}
