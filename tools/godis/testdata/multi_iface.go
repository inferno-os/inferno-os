package main

type Shape interface {
	Area() int
}

type Rect struct{ w, h int }
type Circle struct{ r int }

func (r Rect) Area() int   { return r.w * r.h }
func (c Circle) Area() int { return c.r * c.r * 3 }

func printArea(s Shape) {
	println(s.Area())
}

func main() {
	printArea(Rect{3, 4})
	printArea(Circle{5})
}
