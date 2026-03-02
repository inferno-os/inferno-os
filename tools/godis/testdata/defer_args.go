package main

func printVal(x int) {
	println(x)
}

func main() {
	x := 10
	defer printVal(x) // should capture x=10 at defer-time
	x = 20
	println(x) // prints 20
	// deferred printVal(10) runs at return
}
