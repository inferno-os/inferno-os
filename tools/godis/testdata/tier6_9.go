package main
import "sync"
func main() {
    var wg sync.WaitGroup
    results := make(chan int, 5)
    for i := 0; i < 5; i++ {
        wg.Add(1)
        go func(n int) {
            results <- n * n
            wg.Done()
        }(i)
    }
    go func() {
        wg.Wait()
        close(results)
    }()
    sum := 0
    for v := range results {
        sum += v
    }
    println(sum)
}
