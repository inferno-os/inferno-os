package main

func divide(a, b int) (result int, ok bool) {
	if b == 0 {
		return 0, false
	}
	result = a / b
	ok = true
	return
}

func main() {
	r, ok := divide(10, 3)
	println(r)
	if ok {
		println("ok")
	}
	r2, ok2 := divide(5, 0)
	println(r2)
	if !ok2 {
		println("zero")
	}
}
