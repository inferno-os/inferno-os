package main

type Inner struct{ X, Y int }
type Outer struct {
	A Inner
	B int
}

func main() {
	o := &Outer{A: Inner{X: 3, Y: 4}, B: 5}
	println(o.A.X + o.A.Y + o.B)
}
