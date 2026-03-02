package main
func classify(s string) string {
    switch s {
    case "a", "e", "i", "o", "u":
        return "vowel"
    default:
        return "consonant"
    }
}
func main() {
    println(classify("a"))
    println(classify("b"))
}
