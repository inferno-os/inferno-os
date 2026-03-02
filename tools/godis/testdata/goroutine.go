package main

func worker(id int, done chan int) {
	done <- id
}

func main() {
	done := make(chan int)
	go worker(1, done)
	println(<-done)
	go worker(2, done)
	println(<-done)
	go worker(3, done)
	println(<-done)
}
