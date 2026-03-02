package main

var counter int

func increment() {
	counter = counter + 1
}

func main() {
	increment()
	increment()
	increment()
	println(counter)
}
