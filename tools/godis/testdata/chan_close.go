package main

func producer(ch chan int) {
	ch <- 1
	ch <- 2
	ch <- 3
	close(ch)
}

func main() {
	ch := make(chan int, 5)
	go producer(ch)
	// Spin to let producer finish (Dis schedules cooperatively)
	for i := 0; i < 100000; i++ {
	}
	sum := 0
	for v := range ch {
		sum = sum + v
	}
	println(sum)
}
