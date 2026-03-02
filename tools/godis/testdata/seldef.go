package main
func main() {
    ch := make(chan int, 1)
    ch <- 42
    select {
    case v := <-ch:
        println(v)
    default:
        println("default")
    }
    ch2 := make(chan int)
    select {
    case <-ch2:
        println("recv")
    default:
        println("empty")
    }
}
