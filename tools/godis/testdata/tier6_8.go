package main
import "strconv"
func main() {
    // int to string
    s := strconv.Itoa(42)
    println(s)
    // string to int with error
    n, err := strconv.Atoi("abc")
    if err != nil {
        println("error")
    }
    println(n)
}
