package main

type Point struct {
	X int
	Y int
}

func main() {
	var p Point
	p.X = 3
	p.Y = 4
	println(p.X + p.Y)
}
