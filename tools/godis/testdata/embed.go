package main

type Point struct {
	X int
	Y int
}

type Circle struct {
	Point
	Radius int
}

func main() {
	c := Circle{Point{3, 4}, 10}
	println(c.X)
	println(c.Y)
	println(c.Radius)
}
