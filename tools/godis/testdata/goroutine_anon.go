package main

func main() {
	ch := make(chan int)
	x := 40
	go func() {
		ch <- x + 2
	}()
	println(<-ch)
}
