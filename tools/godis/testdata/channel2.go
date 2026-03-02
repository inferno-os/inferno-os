package main

func producer(ch chan int, val int) {
	ch <- val
}

func main() {
	ch := make(chan int)
	go producer(ch, 10)
	go producer(ch, 20)
	go producer(ch, 30)
	a := <-ch
	b := <-ch
	c := <-ch
	println(a + b + c)
}
