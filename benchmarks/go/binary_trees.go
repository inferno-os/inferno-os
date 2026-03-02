package main

import "inferno/sys"

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
	t1 := sys.Millisec()
	depth := 18
	iterations := 5
	total := 0
	for iter := 0; iter < iterations; iter++ {
		tree := makeTree(depth)
		total = total + checkTree(tree)
	}
	t2 := sys.Millisec()
	println("BENCH binary_trees", t2-t1, "ms", iterations, "iters", total)
}
