package main

type Point struct {
	X int
	Y int
}

func newPoint(x, y int) *Point {
	return &Point{X: x, Y: y}
}

func main() {
	p := newPoint(3, 4)
	println(p.X + p.Y)
}
