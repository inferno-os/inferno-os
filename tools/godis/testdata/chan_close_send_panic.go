package main

func main() {
	ch := make(chan int, 1)
	close(ch)
	defer func() {
		r := recover()
		if r != nil {
			println("caught")
		}
	}()
	ch <- 42
}
