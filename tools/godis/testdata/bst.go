package main

type TreeNode struct {
	val   int
	left  *TreeNode
	right *TreeNode
}

func insert(root *TreeNode, val int) *TreeNode {
	if root == nil {
		return &TreeNode{val: val}
	}
	if val < root.val {
		root.left = insert(root.left, val)
	} else {
		root.right = insert(root.right, val)
	}
	return root
}

func inorder(root *TreeNode) {
	if root == nil {
		return
	}
	inorder(root.left)
	println(root.val)
	inorder(root.right)
}

func main() {
	var root *TreeNode
	root = insert(root, 5)
	root = insert(root, 3)
	root = insert(root, 7)
	root = insert(root, 1)
	root = insert(root, 4)
	root = insert(root, 6)
	root = insert(root, 8)
	inorder(root)
}
