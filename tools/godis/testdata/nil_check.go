package main

func check(x interface{}) {
	if x == nil {
		println("nil")
	} else {
		println("not nil")
	}
}

func main() {
	check(nil)
	check(42)
}
