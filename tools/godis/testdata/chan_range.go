package main

func main() {
	ch := make(chan int, 3)
	ch <- 10
	ch <- 20
	ch <- 30
	close(ch)
	sum := 0
	for v := range ch {
		sum = sum + v
	}
	println(sum)
}
