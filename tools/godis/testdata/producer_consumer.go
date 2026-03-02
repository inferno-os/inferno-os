package main

func produce(ch chan int, n int) {
	for i := 0; i < n; i++ {
		ch <- i * i
	}
	close(ch)
}

func main() {
	ch := make(chan int, 10)
	go produce(ch, 5)
	sum := 0
	for v := range ch {
		sum += v
	}
	println(sum)
}
