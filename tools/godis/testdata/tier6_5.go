package main
type Point struct{ X, Y int }
func main() {
    points := []Point{{1, 2}, {3, 4}, {5, 6}}
    sum := 0
    for i := 0; i < len(points); i++ {
        sum += points[i].X + points[i].Y
    }
    println(sum)
}
