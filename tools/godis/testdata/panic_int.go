package main

func main() {
	defer func() {
		r := recover()
		if r != nil {
			println("recovered")
		}
	}()
	panic(42)
}
