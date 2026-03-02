package geom

type Point struct {
	X, Y int
}

func New(x, y int) Point {
	return Point{X: x, Y: y}
}
