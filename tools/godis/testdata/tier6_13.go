package main
func main() {
    var s []string
    s = append(s, "a")
    s = append(s, "b")
    s = append(s, "c")
    for i := 0; i < len(s); i++ {
        println(s[i])
    }
}
