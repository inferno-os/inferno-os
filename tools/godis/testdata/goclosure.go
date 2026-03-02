package main
func main() {
    ch := make(chan int, 5)
    for i := 0; i < 5; i++ {
        go func(n int) {
            ch <- n * n
        }(i)
    }
    sum := 0
    for i := 0; i < 5; i++ {
        sum += <-ch
    }
    println(sum)
}
