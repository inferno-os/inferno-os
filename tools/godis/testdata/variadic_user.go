package main
func sum(nums ...int) int {
    total := 0
    for _, n := range nums {
        total += n
    }
    return total
}
func main() {
    println(sum(1, 2, 3))
    println(sum(10, 20))
}
