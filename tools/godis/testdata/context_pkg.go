package main

import "context"

func main() {
	ctx := context.Background()
	_ = ctx
	ctx2 := context.TODO()
	_ = ctx2
	println("context ok")
}
