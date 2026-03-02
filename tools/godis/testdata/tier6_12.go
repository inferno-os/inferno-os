package main
type Address struct{ City string; Zip int }
type Person struct{ Name string; Addr Address }
func main() {
    p := Person{Name: "Alice", Addr: Address{City: "NYC", Zip: 10001}}
    println(p.Name)
    println(p.Addr.City)
    println(p.Addr.Zip)
}
