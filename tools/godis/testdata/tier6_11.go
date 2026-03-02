package main
func printAny(v interface{}) {
    switch v.(type) {
    case int:
        println("int")
    case string:
        println("string")
    default:
        println("other")
    }
}
func main() {
    printAny(42)
    printAny("hello")
}
