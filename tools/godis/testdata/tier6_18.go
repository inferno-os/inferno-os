package main
func sender(ch chan<- int) {
    ch <- 42
}
func receiver(ch <-chan int) int {
    return <-ch
}
func main() {
    ch := make(chan int)
    go sender(ch)
    println(receiver(ch))
}
