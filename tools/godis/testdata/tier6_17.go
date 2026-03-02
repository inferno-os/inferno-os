package main
func foo() int {
    x := 1
    defer func() { println("deferred:", x) }()
    x = 2
    return x
}
func main() {
    println(foo())
}
