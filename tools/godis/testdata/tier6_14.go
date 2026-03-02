package main
func divide(a, b int) (result int, err string) {
    if b == 0 {
        err = "div by zero"
        return
    }
    result = a / b
    return
}
func main() {
    r, e := divide(10, 3)
    println(r)
    println(e)
    r2, e2 := divide(10, 0)
    println(r2)
    println(e2)
}
