package main
type Adder struct{ base int }
func (a Adder) Add(x int) int { return a.base + x }
func main() {
    a := Adder{base: 10}
    println(a.Add(5))
}
