package main

import "fmt"

func main() {
	for i := 1; i <= 15; i++ {
		if i%15 == 0 {
			println("FizzBuzz")
		} else if i%3 == 0 {
			println("Fizz")
		} else if i%5 == 0 {
			println("Buzz")
		} else {
			println(fmt.Sprintf("%d", i))
		}
	}
}
