package main
type Base struct{ Name string }
func (b Base) Hello() string { return "Hi " + b.Name }
type Derived struct{ Base; Age int }
func main() {
    d := Derived{Base: Base{Name: "Alice"}, Age: 30}
    println(d.Hello())
    println(d.Name)
    println(d.Age)
}
