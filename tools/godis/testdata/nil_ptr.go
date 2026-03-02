package main

type Node struct {
	val  int
	next *Node
}

func check(n *Node) {
	if n == nil {
		println("nil")
	} else {
		println("not nil")
	}
}

func main() {
	check(nil)
	n := &Node{val: 42}
	check(n)
}
