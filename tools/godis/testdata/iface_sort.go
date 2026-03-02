package main

type Stringer interface {
	String() string
}

type Person struct {
	Name string
	Age  int
}

func (p Person) String() string {
	return p.Name
}

type City struct {
	Name string
}

func (c City) String() string {
	return c.Name
}

func printIt(s Stringer) {
	println(s.String())
}

func main() {
	printIt(Person{Name: "Alice", Age: 30})
	printIt(City{Name: "Boston"})
}
