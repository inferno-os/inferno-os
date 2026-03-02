package main

type Point struct{ X, Y int }

func main() {
	pts := make([]Point, 3)
	pts[0] = Point{1, 2}
	pts[1] = Point{3, 4}
	pts[2] = Point{5, 6}
	sum := 0
	for i := 0; i < 3; i++ {
		sum = sum + pts[i].X + pts[i].Y
	}
	println(sum)
}
