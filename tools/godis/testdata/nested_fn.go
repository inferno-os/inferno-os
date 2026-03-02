package main
func adder(x int) func(int) int {
    return func(y int) int {
        return x + y
    }
}
func main() {
    add5 := adder(5)
    println(add5(3))
}
