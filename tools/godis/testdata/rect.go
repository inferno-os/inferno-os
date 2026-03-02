package main

type Rect struct {
	X      int
	Y      int
	Width  int
	Height int
}

func area(r Rect) int {
	return r.Width * r.Height
}

func main() {
	var r Rect
	r.X = 10
	r.Y = 20
	r.Width = 30
	r.Height = 40
	println(area(r))
}
