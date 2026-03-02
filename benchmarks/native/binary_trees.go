package main

import (
	"fmt"
	"time"
)

type TreeNode struct {
	left  *TreeNode
	right *TreeNode
}

func makeTree(depth int) *TreeNode {
	if depth == 0 {
		return &TreeNode{}
	}
	return &TreeNode{
		left:  makeTree(depth - 1),
		right: makeTree(depth - 1),
	}
}

func checkTree(node *TreeNode) int {
	if node.left == nil {
		return 1
	}
	return 1 + checkTree(node.left) + checkTree(node.right)
}

func main() {
	t1 := time.Now()
	depth := 18
	iterations := 5
	total := 0
	for iter := 0; iter < iterations; iter++ {
		tree := makeTree(depth)
		total += checkTree(tree)
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH binary_trees %d ms %d iters %d\n", elapsed, iterations, total)
}
