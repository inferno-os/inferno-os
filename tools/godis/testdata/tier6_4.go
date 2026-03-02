package main
type Animal interface{ Sound() string }
type Dog struct{}
func (d Dog) Sound() string { return "woof" }
type Cat struct{}
func (c Cat) Sound() string { return "meow" }
func describe(a Animal) {
    if d, ok := a.(Dog); ok {
        _ = d
        println("dog says " + a.Sound())
    } else {
        println("not a dog, says " + a.Sound())
    }
}
func main() {
    describe(Dog{})
    describe(Cat{})
}
