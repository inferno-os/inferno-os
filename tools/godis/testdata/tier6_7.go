package main
type Tree struct {
    Val   int
    Left  *Tree
    Right *Tree
}
func sum(t *Tree) int {
    if t == nil { return 0 }
    return t.Val + sum(t.Left) + sum(t.Right)
}
func main() {
    t := &Tree{Val: 1,
        Left:  &Tree{Val: 2, Left: &Tree{Val: 4}, Right: &Tree{Val: 5}},
        Right: &Tree{Val: 3},
    }
    println(sum(t))
}
