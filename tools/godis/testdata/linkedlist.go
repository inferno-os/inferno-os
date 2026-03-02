package main

type Node struct {
	val  int
	next *Node
}

func push(head *Node, val int) *Node {
	return &Node{val: val, next: head}
}

func length(head *Node) int {
	count := 0
	cur := head
	for cur != nil {
		count = count + 1
		cur = cur.next
	}
	return count
}

func printList(head *Node) {
	cur := head
	for cur != nil {
		println(cur.val)
		cur = cur.next
	}
}

func main() {
	var head *Node
	head = push(head, 1)
	head = push(head, 2)
	head = push(head, 3)
	head = push(head, 4)
	head = push(head, 5)
	printList(head)
}
