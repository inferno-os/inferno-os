package main

type Shape interface {
	Area() int
	Name() string
}

type Rect struct {
	w, h int
}

func (r Rect) Area() int {
	return r.w * r.h
}

func (r Rect) Name() string {
	return "rect"
}

func describe(s Shape) {
	println(s.Name())
	println(s.Area())
}

func main() {
	r := Rect{w: 3, h: 4}
	describe(r)
}
